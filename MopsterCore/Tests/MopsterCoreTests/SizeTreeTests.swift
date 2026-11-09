import XCTest

@testable import MopsterCore

final class SizeTreeTests: XCTestCase {
    private func build(_ root: URL, keep: Int = 20) throws -> SizeTreeResult {
        try SizeTreeBuilder(root: root, keepFilesPerDirectory: keep).build(progress: { _ in })
    }

    func testDirectorySizesSumChildren() throws {
        let root = try makeTemporaryTree(["a.bin": 100_000, "sub/b.bin": 200_000, "sub/deep/c.bin": 300_000])
        let tree = try build(root).root
        let sub = try XCTUnwrap(tree.children.first { $0.name == "sub" })
        let deep = try XCTUnwrap(sub.children.first { $0.name == "deep" })
        XCTAssertTrue(sub.isDirectory)
        XCTAssertEqual(tree.size, tree.children.reduce(0) { $0 + $1.size } + ownSize(root))
        XCTAssertEqual(sub.size, sub.children.reduce(0) { $0 + $1.size } + ownSize(root.appendingPathComponent("sub")))
        XCTAssertGreaterThanOrEqual(deep.size, 300_000)
        XCTAssertEqual(tree.size, DiskUsage.allocatedSize(of: root))
        XCTAssertEqual(tree.children.map(\.size), tree.children.map(\.size).sorted(by: >))
    }

    func testOnlyTopFilesKeptRestAggregated() throws {
        var spec: [String: Int] = [:]
        for index in 0..<25 { spec[String(format: "f%02d.bin", index)] = 10_000 + index * 8192 }
        let root = try makeTemporaryTree(spec)
        let tree = try build(root, keep: 20).root
        let files = tree.children.filter { !$0.isDirectory && !$0.isAggregate }
        let aggregate = try XCTUnwrap(tree.children.first { $0.isAggregate })
        XCTAssertEqual(files.count, 20)
        XCTAssertEqual(aggregate.name, SizeNode.otherFilesName)
        XCTAssertEqual(aggregate.url, root)
        XCTAssertFalse(aggregate.isDirectory)
        let smallest5 = (0..<5).reduce(Int64(0)) { $0 + allocated(root.appendingPathComponent(String(format: "f%02d.bin", $1))) }
        XCTAssertEqual(aggregate.size, smallest5)
        XCTAssertGreaterThanOrEqual(files.map(\.size).min() ?? 0, aggregate.size / 5)
    }

    func testNoAggregateWhenNothingLeftOver() throws {
        let root = try makeTemporaryTree(["a.bin": 5000, "b.bin": 6000])
        XCTAssertNil(try build(root).root.children.first { $0.isAggregate })
    }

    func testSymlinkNotFollowedAndLoopSafe() throws {
        let outside = try makeTemporaryTree(["big.bin": 5_000_000])
        let root = try makeTemporaryTree(["a/x.txt": 10])
        let a = root.appendingPathComponent("a")
        try FileManager.default.createSymbolicLink(at: a.appendingPathComponent("loop"), withDestinationURL: root)
        try FileManager.default.createSymbolicLink(
            at: a.appendingPathComponent("big"), withDestinationURL: outside.appendingPathComponent("big.bin"))
        let node = try XCTUnwrap(try build(root).root.children.first { $0.name == "a" })
        XCTAssertLessThan(node.size, 64 * 1024)
    }

    func testUnreadableSubdirectorySkippedAndListed() throws {
        let root = try makeTemporaryTree(["ok/a.bin": 100_000, "locked/b.bin": 5_000_000])
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        let result = try build(root)
        XCTAssertEqual(result.skipped.map(\.lastPathComponent), ["locked"])
        let lockedNode = try XCTUnwrap(result.root.children.first { $0.name == "locked" })
        XCTAssertTrue(lockedNode.children.isEmpty)
        XCTAssertLessThan(lockedNode.size, 64 * 1024)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(result.root.children.first { $0.name == "ok" }).size, 100_000)
    }

    func testCancellationThrows() async throws {
        var spec: [String: Int] = [:]
        for index in 0..<2000 { spec["f\(index).txt"] = 1 }
        let root = try makeTemporaryTree(spec)
        let task = Task { () throws -> SizeTreeResult in
            withUnsafeCurrentTask { $0?.cancel() }
            return try SizeTreeBuilder(root: root).build(progress: { _ in })
        }
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
    }

    func testAsyncWrapperPropagatesCancellation() async throws {
        var spec: [String: Int] = [:]
        for index in 0..<8000 { spec["f\(index).txt"] = 1 }
        let root = try makeTemporaryTree(spec)
        let start = Date()
        let task = Task {
            try await FtsSizeTreeBuilder().build(root: root, progress: { _ in Thread.sleep(forTimeInterval: 0.5) })
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
    }

    func testSymlinkedRootIsResolvedAndFileRootIsLeaf() throws {
        let real = try makeTemporaryTree(["d/a.bin": 100_000])
        let holder = try makeTemporaryTree([:])
        let link = holder.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real.appendingPathComponent("d"))
        let viaLink = try build(link).root
        XCTAssertTrue(viaLink.isDirectory)
        XCTAssertGreaterThanOrEqual(viaLink.size, 100_000)
        let file = try build(real.appendingPathComponent("d/a.bin")).root
        XCTAssertFalse(file.isDirectory)
        XCTAssertTrue(file.children.isEmpty)
        XCTAssertGreaterThanOrEqual(file.size, 100_000)
    }

    func testProgressReported() throws {
        var spec: [String: Int] = [:]
        for index in 0..<2500 { spec["f\(index).txt"] = 1 }
        let root = try makeTemporaryTree(spec)
        let seen = LockedBox<[ScanProgress]>([])
        _ = try SizeTreeBuilder(root: root).build(progress: { p in seen.mutate { $0.append(p) } })
        XCTAssertFalse(seen.value.isEmpty)
        XCTAssertNil(seen.value[0].fraction)
    }

    private func allocated(_ url: URL) -> Int64 { DiskUsage.allocatedSize(of: url) }
    private func ownSize(_ url: URL) -> Int64 {
        var st = stat()
        return lstat(url.path, &st) == 0 ? Int64(st.st_blocks) * 512 : 0
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); defer { lock.unlock() }; body(&stored) }
}
