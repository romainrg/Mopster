import XCTest

@testable import MopsterCore

final class DiskUsageTests: XCTestCase {
    func testAllocatedSizeSumsFiles() throws {
        let root = try makeTemporaryTree(["a.bin": 100_000, "sub/b.bin": 200_000])
        let size = DiskUsage.allocatedSize(of: root)
        XCTAssertGreaterThanOrEqual(size, 300_000)
        XCTAssertLessThan(size, 300_000 + 64 * 1024)
    }

    func testMissingPathIsZero() {
        XCTAssertEqual(DiskUsage.allocatedSize(of: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")), 0)
    }

    func testAllocatedSizeCountsSymlinkAsLinkNotTarget() throws {
        let outside = try makeTemporaryTree(["big.bin": 5_000_000])
        let dir = try makeTemporaryTree(["small.txt": 10])
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.appendingPathComponent("big.bin"))
        XCTAssertLessThan(DiskUsage.allocatedSize(of: dir), 64 * 1024)
        XCTAssertLessThan(DiskUsage.allocatedSize(of: link), 64 * 1024)
    }

    func testAllocatedSizeSkipsUnreadableSubfolder() throws {
        let root = try makeTemporaryTree(["ok/a.bin": 100_000, "locked/b.bin": 5_000_000])
        let locked = root.appendingPathComponent("locked")
        XCTAssertEqual(chmod(locked.path, 0o000), 0)
        let size = DiskUsage.allocatedSize(of: root)
        XCTAssertGreaterThanOrEqual(size, 100_000)
        XCTAssertLessThan(size, 100_000 + 64 * 1024)
    }
}
