import XCTest
@testable import MopsterCore

final class LeftoverFinderTests: XCTestCase {
    private func app(_ id: String = "com.foo.Bar", name: String = "Bar Pro", path: String? = nil) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: path ?? "/Applications/\(name).app"), bundleID: id, name: name, version: "1",
            build: "1", isAppStore: false, sparkleFeed: nil, minimumSystemVersion: nil, isLocked: false,
            size: 0, lastUsed: nil)
    }

    func testMatchesAllForms() throws {
        let home = try makeTemporaryTree([
            "Library/Preferences/com.foo.Bar.plist": 5,
            "Library/Preferences/ByHost/com.foo.Bar.ABC.plist": 5,
            "Library/Caches/com.foo.Bar/data": 100,
            "Library/Application Support/Bar Pro/x": 5,
            "Library/Application Support/Bar/x": 5,
            "Library/Group Containers/ABCDE12345.com.foo.Bar/x": 5,
            "Library/Group Containers/group.com.foo.Bar/x": 5,
            "Library/Group Containers/ABCDE1234.com.foo.Bar/x": 5,
            "Library/Group Containers/ABCDE123456.com.foo.Bar/x": 5,
            "Library/Group Containers/ABCDE12345.group.com.foo.Bar.shared/x": 5,
            "Library/Containers/com.foo.Bar.helper/x": 5,
            "Library/Saved Application State/com.foo.Bar.savedState/x": 5,
            "Library/Cookies/com.foo.Bar.binarycookies": 5,
            "Library/Caches/com.foo.Barista/x": 5,
        ])
        let sys = try makeTemporaryTree(["Library/LaunchDaemons/com.foo.Bar.helper.plist": 5])
        let items = LeftoverFinder(home: home, systemRoot: sys).leftovers(for: app(), among: [])
        let names = Set(items.map(\.name))
        XCTAssertEqual(
            names,
            [
                "com.foo.Bar.plist", "com.foo.Bar.ABC.plist", "com.foo.Bar", "Bar Pro",
                "ABCDE12345.com.foo.Bar", "group.com.foo.Bar", "ABCDE12345.group.com.foo.Bar.shared", "com.foo.Bar.helper",
                "com.foo.Bar.savedState", "com.foo.Bar.binarycookies", "com.foo.Bar.helper.plist",
            ])
        for item in items {
            let nameOnly = item.name == "Bar Pro"
            XCTAssertEqual(item.risk, nameOnly ? .review : .safe, item.name)
            XCTAssertEqual(item.isSelectedByDefault, !nameOnly, item.name)
        }
        let cache = try XCTUnwrap(items.first { $0.name == "com.foo.Bar" })
        XCTAssertEqual(cache.detail, "~/Library/Caches")
        XCTAssertGreaterThan(cache.size, 0)
        XCTAssertEqual(items.map(\.size), items.map(\.size).sorted(by: >))
        let sysItem = try XCTUnwrap(items.first { $0.name == "com.foo.Bar.helper.plist" })
        XCTAssertEqual(sysItem.url.standardizedFileURL.path, sys.appendingPathComponent("Library/LaunchDaemons/com.foo.Bar.helper.plist").standardizedFileURL.path)
    }

    func testShortNameMatchesOnlyByBundleID() throws {
        let home = try makeTemporaryTree([
            "Library/Application Support/Foo/x": 5, "Library/Caches/com.foo.Bar/x": 5,
        ])
        let items = LeftoverFinder(home: home, systemRoot: home).leftovers(for: app(name: "Foo"), among: [])
        XCTAssertEqual(items.map(\.name), ["com.foo.Bar"])
    }

    func testNameMatchIsCaseInsensitive() throws {
        let home = try makeTemporaryTree(["Library/Application Support/bar pro/x": 5])
        XCTAssertEqual(LeftoverFinder(home: home, systemRoot: home).leftovers(for: app(), among: []).count, 1)
    }

    func testNeverReturnsLocationAndSkipsMissing() throws {
        let home = try makeTemporaryTree(["Library/Application Support/": 0])
        XCTAssertTrue(LeftoverFinder(home: home, systemRoot: home).leftovers(for: app(name: "Application Support"), among: []).isEmpty)
    }

    func testUnreadableLocationSkipped() throws {
        let home = try makeTemporaryTree(["Library/Caches/com.foo.Bar/x": 5, "Library/Logs/com.foo.Bar/x": 5])
        let logs = home.appendingPathComponent("Library/Logs")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: logs.path)
        let items = LeftoverFinder(home: home, systemRoot: home).leftovers(for: app(), among: [])
        XCTAssertEqual(items.count, 1)
    }

    func testXcodeExtra() throws {
        let home = try makeTemporaryTree(["Library/Developer/Xcode/DerivedData/x": 50])
        let xcode = app("com.apple.dt.Xcode", name: "Xcode")
        let items = LeftoverFinder(home: home, systemRoot: home).leftovers(for: xcode, among: [])
        XCTAssertEqual(items.map(\.name), ["Xcode"])
        XCTAssertEqual(items.first?.detail, "~/Library/Developer")
        XCTAssertEqual(items.first?.risk, .review)
        XCTAssertEqual(items.first?.isSelectedByDefault, false)
        XCTAssertEqual(items.first?.url.lastPathComponent, "Xcode")
    }

    func testOtherAppWithLongerIDClaimsItsEntries() throws {
        let home = try makeTemporaryTree([
            "Library/Preferences/com.foo.Bar.plist": 5, "Library/Preferences/com.foo.Bar.Pro.plist": 5,
            "Library/Containers/com.foo.Bar.Pro/x": 5, "Library/Containers/com.foo.Bar/x": 5,
            "Library/Group Containers/ABCDE12345.com.foo.Bar.Pro/x": 5,
        ])
        let bar = app("com.foo.Bar", name: "Bar", path: "/Applications/Bar.app")
        let pro = app("com.foo.Bar.Pro", name: "Bar Professional", path: "/Applications/BarPro.app")
        let items = LeftoverFinder(home: home, systemRoot: home).leftovers(for: bar, among: [bar, pro])
        XCTAssertEqual(Set(items.map(\.name)), ["com.foo.Bar.plist", "com.foo.Bar"])
    }

    func testTwoCopiesOfSameBundleIDOfferNothing() throws {
        let home = try makeTemporaryTree([
            "Library/Caches/com.apple.dt.Xcode/x": 5, "Library/Developer/Xcode/x": 5,
        ])
        let a = app("com.apple.dt.Xcode", name: "Xcode", path: "/Applications/Xcode.app")
        let b = app("com.apple.dt.Xcode", name: "Xcode-beta", path: "/Applications/Xcode-beta.app")
        XCTAssertTrue(LeftoverFinder(home: home, systemRoot: home).leftovers(for: a, among: [a, b]).isEmpty)
        XCTAssertEqual(LeftoverFinder(home: home, systemRoot: home).leftovers(for: a, among: [a]).count, 2)
    }

    func testSameNameOtherAppBlocksNameOnlyMatch() throws {
        let home = try makeTemporaryTree(["Library/Application Support/Slack/x": 5])
        let web = app("com.safari.WebApp.Slack", name: "Slack", path: "/Users/x/Applications/Slack.app")
        let desktop = app("com.tinyspeck.slackmacgap", name: "Slack", path: "/Applications/Slack.app")
        let finder = LeftoverFinder(home: home, systemRoot: home)
        XCTAssertTrue(finder.leftovers(for: web, among: [web, desktop]).isEmpty)
        XCTAssertEqual(finder.leftovers(for: desktop, among: [web, desktop]).count, 0)
        XCTAssertEqual(finder.leftovers(for: desktop, among: [desktop]).map(\.name), ["Slack"])
    }

    func testNameOnlyMatchIsReviewAndUnselected() throws {
        let home = try makeTemporaryTree(["Library/Application Support/Bar Pro/x": 5])
        let item = try XCTUnwrap(LeftoverFinder(home: home, systemRoot: home).leftovers(for: app(), among: []).first)
        XCTAssertEqual(item.risk, .review)
        XCTAssertFalse(item.isSelectedByDefault)
    }
}
