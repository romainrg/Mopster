import XCTest

@testable import MopsterCore

final class LargeFileFinderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func find(
        _ home: URL, _ query: LargeFileQuery, ignore: IgnoreList = IgnoreList()
    ) async throws -> [LargeFile] {
        try await LargeFileFinder(home: home, ignore: ignore, now: now).find(query, progress: { _ in })
    }

    private func names(_ files: [LargeFile]) -> [String] { files.map(\.url.lastPathComponent) }

    private func setDates(_ url: URL, access: Date, modification: Date) throws {
        var values = URLResourceValues()
        values.contentAccessDate = access
        values.contentModificationDate = modification
        var mutable = url
        try mutable.setResourceValues(values)
    }

    func testThresholdAndKinds() async throws {
        let home = try makeTemporaryTree([
            "Movies/clip.mov": 300_000, "Movies/small.mov": 10_000, "Downloads/backup.zip": 200_000,
            "Downloads/installer.dmg": 400_000, "Music/song.mp3": 250_000, "Documents/report.pdf": 150_000,
            "Documents/blob.xyzunknown": 120_000,
        ])
        let all = try await find(home, LargeFileQuery(minSize: 100_000))
        XCTAssertEqual(
            names(all), ["installer.dmg", "clip.mov", "song.mp3", "backup.zip", "report.pdf", "blob.xyzunknown"])
        XCTAssertEqual(all.map(\.size), all.map(\.size).sorted(by: >))
        let kinds = Dictionary(uniqueKeysWithValues: all.map { ($0.url.lastPathComponent, $0.kind) })
        XCTAssertEqual(kinds["clip.mov"], .video)
        XCTAssertEqual(kinds["song.mp3"], .audio)
        XCTAssertEqual(kinds["backup.zip"], .archive)
        XCTAssertEqual(kinds["installer.dmg"], .diskImage)
        XCTAssertEqual(kinds["report.pdf"], .document)
        XCTAssertEqual(kinds["blob.xyzunknown"], .other)

        let videosAndArchives = try await find(home, LargeFileQuery(minSize: 100_000, kinds: [.video, .archive]))
        XCTAssertEqual(names(videosAndArchives), ["clip.mov", "backup.zip"])
        let big = try await find(home, LargeFileQuery(minSize: 280_000))
        XCTAssertEqual(names(big), ["installer.dmg", "clip.mov"])
    }

    func testAgeUsesAccessDateThenModification() async throws {
        let home = try makeTemporaryTree(["a/stale.bin": 60_000, "a/fresh.bin": 60_000, "a/readOld.bin": 60_000])
        let stale = home.appendingPathComponent("a/stale.bin")
        let fresh = home.appendingPathComponent("a/fresh.bin")
        let readOld = home.appendingPathComponent("a/readOld.bin")
        try setDates(stale, access: now.addingTimeInterval(-400 * day), modification: now.addingTimeInterval(-400 * day))
        try setDates(fresh, access: now.addingTimeInterval(-1 * day), modification: now.addingTimeInterval(-400 * day))
        try setDates(readOld, access: now.addingTimeInterval(-400 * day), modification: now.addingTimeInterval(-1 * day))

        let old = try await find(home, LargeFileQuery(minSize: 1, olderThan: 365 * day))
        XCTAssertEqual(Set(names(old)), ["stale.bin", "readOld.bin"])
        let any = try await find(home, LargeFileQuery(minSize: 1))
        XCTAssertEqual(any.count, 3)
        let lastAccess = try XCTUnwrap(any.first { $0.url.lastPathComponent == "fresh.bin" }).lastAccess
        XCTAssertEqual(lastAccess.timeIntervalSince1970, now.addingTimeInterval(-day).timeIntervalSince1970, accuracy: 1)
    }

    func testLibraryAndHiddenExcludedByDefault() async throws {
        let home = try makeTemporaryTree([
            "Library/Caches/cache.bin": 100_000, ".hidden/secret.bin": 100_000, ".dotfile.bin": 100_000,
            "Documents/Library/nested.bin": 100_000, "Documents/visible.bin": 100_000,
        ])
        let byDefault = try await find(home, LargeFileQuery(minSize: 50_000))
        XCTAssertEqual(Set(names(byDefault)), ["nested.bin", "visible.bin"])
        let everything = try await find(home, LargeFileQuery(minSize: 50_000, includeLibraryAndHidden: true))
        XCTAssertEqual(
            Set(names(everything)), ["nested.bin", "visible.bin", "cache.bin", "secret.bin", ".dotfile.bin"])
    }

    func testIgnoredPathsExcluded() async throws {
        let home = try makeTemporaryTree(["Keep/a.bin": 100_000, "Skip/b.bin": 100_000, "Documents/c.bin": 100_000])
        let ignore = IgnoreList(paths: [
            home.appendingPathComponent("Skip").path, home.appendingPathComponent("Documents/c.bin").path,
        ])
        let result = try await find(home, LargeFileQuery(minSize: 50_000), ignore: ignore)
        XCTAssertEqual(names(result), ["a.bin"])
    }

    func testPackageCountedAsOneItem() async throws {
        let home = try makeTemporaryTree([
            "Notes.rtfd/part1.bin": 150_000, "Notes.rtfd/part2.bin": 150_000, "Apps/Tool.app/Contents/big.bin": 900_000,
        ])
        let result = try await find(home, LargeFileQuery(minSize: 100_000))
        XCTAssertEqual(names(result), ["Notes.rtfd"])
        let package = try XCTUnwrap(result.first)
        XCTAssertEqual(package.size, DiskUsage.allocatedSize(of: home.appendingPathComponent("Notes.rtfd")))
        XCTAssertEqual(package.kind, .other)
    }

    func testSymlinksSkipped() async throws {
        let outside = try makeTemporaryTree(["big.bin": 500_000])
        let home = try makeTemporaryTree(["Documents/x.txt": 10])
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Documents/link.bin"),
            withDestinationURL: outside.appendingPathComponent("big.bin"))
        let result = try await find(home, LargeFileQuery(minSize: 50_000))
        XCTAssertTrue(result.isEmpty)
    }

    func testCancellationThrows() async throws {
        let home = try makeTemporaryTree(["a.bin": 100_000])
        let task = Task { () -> [LargeFile] in
            try await Task.sleep(for: .milliseconds(200))
            return try await find(home, LargeFileQuery(minSize: 1))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
    }
}
