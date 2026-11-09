import XCTest
@testable import MopsterCore

final class JunkScannerTests: XCTestCase {
    private let mb = 1_000_000
    private let mb64: Int64 = 1_000_000

    private func scan(
        _ home: URL, rules: [JunkRule] = JunkCatalog.rules, ignore: [String] = [], now: Date = .now
    ) async throws -> JunkScanResult {
        try await JunkScanner(rules: rules, home: home, ignore: IgnoreList(paths: ignore), now: now)
            .scan { _ in }
    }

    private func group(_ id: String, in result: JunkScanResult) -> CleanupGroup? {
        result.groups.first { $0.id == id }
    }

    private func rule(
        _ id: String = "test", locations: [String], minAge: TimeInterval? = nil, extensions: Set<String>? = nil,
        risk: Risk = .safe
    ) -> JunkRule {
        JunkRule(
            id: id, title: L("test.title", "Test"), explanation: L("test.explanation", "Test"),
            symbol: "doc", locations: locations, minAge: minAge, extensions: extensions, risk: risk)
    }

    func testSpecificRuleClaimsBeforeGeneral() async throws {
        let home = try makeTemporaryTree([
            "Library/Caches/Google/Chrome/Default/data": 3 * mb,
            "Library/Caches/Google/Updater/data": 1 * mb,
        ])
        let result = try await scan(home)
        let browser = try XCTUnwrap(group("browserCaches", in: result))
        let apps = try XCTUnwrap(group("appCaches", in: result))
        XCTAssertEqual(browser.items.map(\.name), ["Default"])
        XCTAssertEqual(apps.items.map(\.name), ["Updater"])
        XCTAssertEqual(browser.items[0].size, DiskUsage.allocatedSize(of: browser.items[0].url))
        XCTAssertEqual(
            result.groups.flatMap(\.items).reduce(0) { $0 + $1.size },
            DiskUsage.allocatedSize(of: home.appendingPathComponent("Library/Caches/Google/Chrome/Default"))
                + DiskUsage.allocatedSize(of: home.appendingPathComponent("Library/Caches/Google/Updater")))
        XCTAssertGreaterThanOrEqual(browser.items[0].size, 3 * mb64)
        XCTAssertGreaterThanOrEqual(apps.items[0].size, 1 * mb64)
        XCTAssertLessThan(apps.items[0].size, 2 * mb64)
    }

    func testExclusionsAreNotListed() async throws {
        let home = try makeTemporaryTree([
            "Library/Caches/com.apple.bird/x": 10, "Library/Caches/com.example.app/x": 10,
        ])
        let items = try await scan(home).groups.flatMap(\.items).map(\.name)
        XCTAssertEqual(items, ["com.example.app"])
    }

    func testExtensionFilter() async throws {
        let home = try makeTemporaryTree([
            "Downloads/a.dmg": 10, "Downloads/b.pkg": 10, "Downloads/c.pkg/inner": 10, "Downloads/notes.txt": 10,
        ])
        let names = try await scan(home).groups.flatMap(\.items).map(\.name).sorted()
        XCTAssertEqual(names, ["a.dmg", "b.pkg", "c.pkg"])
    }

    func testMinAgeFilter() async throws {
        let home = try makeTemporaryTree(["Stuff/fresh": 10, "Stuff/old": 10])
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-30 * 86_400)],
            ofItemAtPath: home.appendingPathComponent("Stuff/old").path)
        let rules = [rule(locations: ["~/Stuff/*"], minAge: 7 * 86_400)]
        let names = try await scan(home, rules: rules, now: now).groups.flatMap(\.items).map(\.name)
        XCTAssertEqual(names, ["old"])
    }

    func testReviewRulesAreNotPreselected() async throws {
        let home = try makeTemporaryTree(["Library/Saved Application State/a": 10, "Library/Logs/b": 10])
        let result = try await scan(home)
        XCTAssertEqual(try XCTUnwrap(group("savedAppState", in: result)).items.map(\.isSelectedByDefault), [false])
        XCTAssertEqual(try XCTUnwrap(group("logs", in: result)).items.map(\.isSelectedByDefault), [true])
        XCTAssertEqual(try XCTUnwrap(group("savedAppState", in: result)).items[0].risk, .review)
    }

    func testIgnoredPathsAreHidden() async throws {
        let home = try makeTemporaryTree([
            "Library/Caches/keep/x": 10, "Library/Caches/other/x": 10, "Library/Caches/mixed/hide/x": 10,
            "Library/Caches/mixed/show/x": 10,
        ])
        let ignore = [
            home.appendingPathComponent("Library/Caches/keep").path,
            home.appendingPathComponent("Library/Caches/mixed/hide").path,
        ]
        let items = try await scan(home, ignore: ignore).groups.flatMap(\.items)
        XCTAssertEqual(items.map(\.name).sorted(), ["other", "show"])
    }

    func testUnreadableLocationIsSkippedAndReported() async throws {
        let home = try makeTemporaryTree(["Library/Logs/a": 10, "Library/Caches/app/x": 10])
        let logs = home.appendingPathComponent("Library/Logs")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: logs.path)
        let result = try await scan(home)
        XCTAssertEqual(result.skipped.map { $0.standardizedFileURL.path }, [logs.standardizedFileURL.path])
        XCTAssertNotNil(group("appCaches", in: result))
        XCTAssertNil(group("logs", in: result))
    }

    func testSkippedFolderIsNotSwallowedByGeneralRule() async throws {
        let home = try makeTemporaryTree([
            "Library/Caches/Google/Chrome/Default/data": 10, "Library/Caches/Google/Updater/data": 10,
        ])
        let chrome = home.appendingPathComponent("Library/Caches/Google/Chrome")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: chrome.path)
        let result = try await scan(home)
        XCTAssertEqual(result.skipped.map { $0.standardizedFileURL.path }, [chrome.standardizedFileURL.path])
        XCTAssertEqual(try XCTUnwrap(group("appCaches", in: result)).items.map(\.name), ["Updater"])
        XCTAssertNil(group("browserCaches", in: result))
    }

    func testUnreadableParentIsReported() async throws {
        let home = try makeTemporaryTree([
            "Library/Containers/com.apple.mail/Data/Library/Mail Downloads/a": 10, "Library/Caches/app/x": 10,
        ])
        let mail = home.appendingPathComponent("Library/Containers/com.apple.mail")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: mail.path)
        let result = try await scan(home)
        XCTAssertEqual(result.skipped.map { $0.standardizedFileURL.path }, [mail.standardizedFileURL.path])
        XCTAssertNil(group("mailDownloads", in: result))
        XCTAssertNotNil(group("appCaches", in: result))
    }

    func testSymlinkedIntermediateFolderIsNotTraversed() async throws {
        let home = try makeTemporaryTree(["Library/Caches/app/x": 10])
        let elsewhere = try makeTemporaryTree(["npm/_cacache/blob": 5 * mb])
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent(".npm"), withDestinationURL: elsewhere.appendingPathComponent("npm"))
        let result = try await scan(home, rules: [rule(locations: ["~/.npm/_cacache/*"])])
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertTrue(PathPattern.expand("~/.npm/_cacache/*", home: home).count == 1)
    }

    func testMissingLocationIsNotSkipped() async throws {
        let home = try makeTemporaryTree(["Library/Caches/app/x": 10])
        let result = try await scan(home)
        XCTAssertTrue(result.skipped.isEmpty)
        XCTAssertNil(result.trashSize)
    }

    func testTrashSize() async throws {
        let home = try makeTemporaryTree([".Trash/big": 2 * mb])
        let size = try await scan(home).trashSize
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(size), 2 * mb64)
    }

    func testProgressReportsOncePerRule() async throws {
        let home = try makeTemporaryTree(["Library/Caches/app/x": 10])
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var values: [ScanProgress] = []
        }
        let box = Box()
        _ = try await JunkScanner(home: home, ignore: IgnoreList()).scan {
            box.lock.lock(); box.values.append($0); box.lock.unlock()
        }
        XCTAssertEqual(box.values.count, JunkCatalog.rules.count)
        XCTAssertEqual(box.values.first?.fraction, 0)
        XCTAssertEqual(box.values.first?.location, JunkCatalog.rules[0].locations[0])
    }

    func testCancellationThrows() async throws {
        let home = try makeTemporaryTree(["Library/Caches/app/x": 10])
        let task = Task { try await self.scan(home) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
    }
}
