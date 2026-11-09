import XCTest

@testable import MopsterCore

final class DuplicateFinderTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MopsterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { TestSupport.destroyTree(root) }
        return root
    }

    @discardableResult
    private func write(_ data: Data, _ root: URL, _ path: String, created: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        if let created {
            try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        }
        return url
    }

    private func bytes(_ byte: UInt8, _ count: Int) -> Data { Data(repeating: byte, count: count) }

    private func find(
        _ folders: [URL], minSize: Int64 = 1_000, ignore: IgnoreList = IgnoreList()
    ) async throws -> [DuplicateGroup] {
        try await DuplicateFinder(ignore: ignore).find(in: folders, minSize: minSize, progress: { _ in })
    }

    private func names(_ group: DuplicateGroup) -> [String] { group.files.map(\.url.lastPathComponent) }

    func testIdenticalFilesGroupedDifferentNot() async throws {
        let root = try makeRoot()
        try write(bytes(1, 5_000), root, "a/one.bin")
        try write(bytes(1, 5_000), root, "b/two.bin")
        try write(bytes(1, 5_000), root, "c/three.bin")
        try write(bytes(2, 5_000), root, "d/other.bin")
        try write(bytes(3, 7_000), root, "d/unique.bin")
        let groups = try await find([root])
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(Set(names(group)), ["one.bin", "two.bin", "three.bin"])
        XCTAssertEqual(group.size, 5_000)
        XCTAssertEqual(group.id.count, 64)
    }

    func testSameSizeSameFirstBlockDifferentTailNotGrouped() async throws {
        let root = try makeRoot()
        var first = bytes(7, 10_000)
        var second = first
        first[9_999] = 1
        second[9_999] = 2
        try write(first, root, "a.bin")
        try write(second, root, "b.bin")
        let groups = try await find([root])
        XCTAssertTrue(groups.isEmpty)
    }

    func testBelowMinSizeIgnored() async throws {
        let root = try makeRoot()
        try write(bytes(1, 500), root, "small1.bin")
        try write(bytes(1, 500), root, "small2.bin")
        let none = try await find([root], minSize: 1_000)
        XCTAssertTrue(none.isEmpty)
        let some = try await find([root], minSize: 100)
        XCTAssertEqual(some.count, 1)
    }

    func testHardLinksAreNotDuplicates() async throws {
        let root = try makeRoot()
        let original = try write(bytes(4, 5_000), root, "original.bin")
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("hardlink.bin"))
        let groups = try await find([root])
        XCTAssertTrue(groups.isEmpty)
        try write(bytes(4, 5_000), root, "real-copy.bin")
        let withCopy = try await find([root])
        XCTAssertEqual(withCopy.count, 1)
        XCTAssertEqual(withCopy.first?.files.count, 2)
    }

    func testSymlinkNotOffered() async throws {
        let root = try makeRoot()
        let target = try write(bytes(5, 5_000), root, "real.bin")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.bin"), withDestinationURL: target)
        let groups = try await find([root])
        XCTAssertTrue(groups.isEmpty)
    }

    func testFileInSymlinkedFolderNotFollowed() async throws {
        let root = try makeRoot()
        let outside = try makeRoot()
        try write(bytes(6, 5_000), root, "mine.bin")
        try write(bytes(6, 5_000), outside, "elsewhere.bin")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        let groups = try await find([root])
        XCTAssertTrue(groups.isEmpty)
    }

    func testPackagesSkipped() async throws {
        let root = try makeRoot()
        try write(bytes(8, 5_000), root, "Photos.photoslibrary/originals/a.bin")
        try write(bytes(8, 5_000), root, "Photos.photoslibrary/originals/b.bin")
        try write(bytes(8, 5_000), root, "loose.bin")
        let groups = try await find([root])
        XCTAssertTrue(groups.isEmpty)
    }

    func testHiddenAndIgnoredSkipped() async throws {
        let root = try makeRoot()
        try write(bytes(9, 5_000), root, "visible.bin")
        try write(bytes(9, 5_000), root, ".hidden.bin")
        try write(bytes(9, 5_000), root, ".cache/inside.bin")
        try write(bytes(9, 5_000), root, "Skip/ignored.bin")
        let ignore = IgnoreList(paths: [root.appendingPathComponent("Skip").path])
        let groups = try await find([root], ignore: ignore)
        XCTAssertTrue(groups.isEmpty)
    }

    func testOverlappingFoldersListFileOnce() async throws {
        let root = try makeRoot()
        try write(bytes(1, 5_000), root, "Documents/Sub/a.bin")
        try write(bytes(1, 5_000), root, "Documents/b.bin")
        let documents = root.appendingPathComponent("Documents")
        let groups = try await find([documents, documents.appendingPathComponent("Sub")])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(names(try XCTUnwrap(groups.first))), ["a.bin", "b.bin"])
        XCTAssertEqual(groups.first?.files.count, 2)
    }

    func testResultsUseCallerSpellingAndSortOrder() async throws {
        let root = try makeRoot()
        let old = Date(timeIntervalSince1970: 1_500_000_000)
        let new = Date(timeIntervalSince1970: 1_600_000_000)
        try write(bytes(1, 5_000), root, "small-new.bin", created: new)
        try write(bytes(1, 5_000), root, "small-old.bin", created: old)
        for index in 1...3 { try write(bytes(2, 8_000), root, "big\(index).bin", created: old) }
        let groups = try await find([root])
        XCTAssertEqual(groups.map(\.size), [8_000, 5_000])
        XCTAssertEqual(groups.map(\.wastedSpace), [16_000, 5_000])
        XCTAssertEqual(names(groups[1]), ["small-old.bin", "small-new.bin"])
        XCTAssertEqual(names(groups[0]), ["big1.bin", "big2.bin", "big3.bin"])
        XCTAssertTrue(groups.flatMap(\.files).allSatisfy { $0.url.path.hasPrefix(root.path) })
    }

    func testCloudOnlyFilesAreSkippedAndCounted() async throws {
        let root = try makeRoot()
        try write(bytes(1, 5_000), root, "a/one.bin")
        try write(bytes(1, 5_000), root, "b/two.bin")
        try write(bytes(1, 5_000), root, "c/cloud.bin")
        let finder = DuplicateFinder(statFlags: { $0.hasSuffix("/cloud.bin") ? DuplicateFinder.datalessFlag : 0 })
        let scan = try await finder.scan(in: [root], minSize: 1_000, progress: { _ in })
        XCTAssertEqual(scan.skippedCloudOnly, 1)
        XCTAssertEqual(scan.groups.count, 1)
        XCTAssertEqual(Set(names(try XCTUnwrap(scan.groups.first))), ["one.bin", "two.bin"])
    }

    func testCancellationThrows() async throws {
        let root = try makeRoot()
        try write(bytes(1, 5_000), root, "a.bin")
        try write(bytes(1, 5_000), root, "b.bin")
        let task = Task { () -> [DuplicateGroup] in
            try await Task.sleep(for: .milliseconds(200))
            return try await find([root])
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
    }

    // MARK: Selection

    private func file(_ path: String, created: Date?) -> DuplicateFile {
        DuplicateFile(url: URL(fileURLWithPath: path), created: created)
    }

    func testAutoSelectKeepsOldest() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let dated = DuplicateGroup(
            id: "g1", size: 10,
            files: [file("/a/new", created: new), file("/b/old", created: old), file("/c/newer", created: new)])
        let undated = DuplicateGroup(
            id: "g2", size: 10, files: [file("/z/second", created: nil), file("/y/first", created: nil)])
        let selection = DuplicateSelection.autoSelect([dated, undated])
        XCTAssertEqual(selection, ["/a/new", "/c/newer", "/z/second"])
        XCTAssertTrue(DuplicateSelection.allows(selection, in: [dated, undated]))
    }

    func testAllowsRefusesWholeGroup() {
        let group = DuplicateGroup(id: "g", size: 10, files: [file("/a", created: nil), file("/b", created: nil)])
        let other = DuplicateGroup(id: "h", size: 10, files: [file("/c", created: nil), file("/d", created: nil)])
        XCTAssertTrue(DuplicateSelection.allows([], in: [group, other]))
        XCTAssertTrue(DuplicateSelection.allows(["/a", "/c"], in: [group, other]))
        XCTAssertFalse(DuplicateSelection.allows(["/a", "/b"], in: [group, other]))
        XCTAssertFalse(DuplicateSelection.allows(["/a", "/c", "/d"], in: [group, other]))
    }

    func testRepairedDeselectsNewOldestWhenKeeperRemoved() {
        let old = Date(timeIntervalSince1970: 1_000)
        let mid = Date(timeIntervalSince1970: 2_000)
        let new = Date(timeIntervalSince1970: 3_000)
        // The group {A, B, C} was auto-selected as {B, C}; A (the keeper) is then ignored.
        let shrunk = DuplicateGroup(id: "g", size: 10, files: [file("/b", created: mid), file("/c", created: new)])
        let other = DuplicateGroup(id: "h", size: 10, files: [file("/d", created: old), file("/e", created: new)])
        let repaired = DuplicateSelection.repaired(["/b", "/c", "/e"], in: [shrunk, other])
        XCTAssertEqual(repaired, ["/c", "/e"])
        XCTAssertTrue(DuplicateSelection.allows(repaired, in: [shrunk, other]))
    }

    func testRepairedClearsSelectionOfDroppedGroups() {
        let single = DuplicateGroup(id: "g", size: 10, files: [file("/only", created: nil)])
        let intact = DuplicateGroup(id: "h", size: 10, files: [file("/x", created: nil), file("/y", created: nil)])
        XCTAssertEqual(DuplicateSelection.repaired(["/only", "/y", "/gone"], in: [single, intact]), ["/y"])
    }
}
