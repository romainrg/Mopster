import XCTest

@testable import MopsterCore

private final class FakeTrash: TrashOperation, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []
    let directory: URL
    let error: Error?

    init(directory: URL, error: Error? = nil) {
        self.directory = directory
        self.error = error
    }

    var calls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func trash(_ url: URL) throws -> URL? {
        lock.lock()
        recorded.append(url)
        lock.unlock()
        if let error { throw error }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

final class TrashRemoverTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = try makeTemporaryTree(["Projects/": 0])
    }

    private func makeGuard() -> SafetyGuard {
        SafetyGuard(home: home, appBundle: home.appendingPathComponent("Applications/Mopster.app"))
    }

    private func file(_ relative: String, size: Int = 50_000) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: size).write(to: url)
        return url
    }

    private func trashDirectory() -> URL { home.appendingPathComponent("FakeTrash") }

    func testTrashesAllowedItemAndCountsBytes() async throws {
        let item = try file("Projects/big.bin", size: 100_000)
        let expected = DiskUsage.allocatedSize(of: item)
        let fake = FakeTrash(directory: trashDirectory())
        let report = await TrashRemover(guard: makeGuard(), primary: fake, fallback: nil).remove([item])
        XCTAssertEqual(report.trashed, [TrashedItem(url: item, size: expected)])
        XCTAssertEqual(report.trashedBytes, expected)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
    }

    func testRefusedItemNeverReachesTrash() async throws {
        let secret = try file(".ssh/id_ed25519")
        let fake = FakeTrash(directory: trashDirectory())
        let report = await TrashRemover(guard: makeGuard(), primary: fake, fallback: fake).remove([secret])
        XCTAssertEqual(report.failures, [RemovalFailure(url: secret, reason: .refused(.secretStore))])
        XCTAssertTrue(report.trashed.isEmpty)
        XCTAssertEqual(report.trashedBytes, 0)
        XCTAssertTrue(fake.calls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: secret.path))
    }

    func testVanishedItemIsAlreadyGone() async throws {
        let item = try file("Projects/gone.bin")
        try FileManager.default.removeItem(at: item)
        let fake = FakeTrash(directory: trashDirectory())
        let report = await TrashRemover(guard: makeGuard(), primary: fake, fallback: nil).remove([item])
        XCTAssertEqual(report.failures, [RemovalFailure(url: item, reason: .alreadyGone)])
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testDanglingSymlinkIsNotGone() async throws {
        let link = home.appendingPathComponent("Projects/dangling")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        let fake = FakeTrash(directory: trashDirectory())
        let report = await TrashRemover(guard: makeGuard(), primary: fake, fallback: nil).remove([link])
        XCTAssertEqual(report.trashed.map(\.url), [link])
        XCTAssertTrue(report.failures.isEmpty)
    }

    func testItemSwappedForSymlinkToProtectedPathIsRefused() async throws {
        let item = try file("Projects/victim")
        try FileManager.default.removeItem(at: item)
        try FileManager.default.createSymbolicLink(at: item, withDestinationURL: URL(fileURLWithPath: "/System/Library"))
        let fake = FakeTrash(directory: trashDirectory())
        let report = await TrashRemover(guard: makeGuard(), primary: fake, fallback: fake).remove([item])
        XCTAssertEqual(report.failures, [RemovalFailure(url: item, reason: .refused(.protectedSystemPath))])
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testNestedSelectionCountsBytesOnce() async throws {
        _ = try file("Projects/a/b", size: 100_000)
        _ = try file("Projects/a/c", size: 100_000)
        let folder = home.appendingPathComponent("Projects/a")
        let inner = folder.appendingPathComponent("b")
        let expected = DiskUsage.allocatedSize(of: folder)
        let fake = FakeTrash(directory: trashDirectory())
        let report = await TrashRemover(guard: makeGuard(), primary: fake, fallback: nil).remove([inner, folder])
        XCTAssertEqual(report.trashed, [TrashedItem(url: folder, size: expected)])
        XCTAssertEqual(report.trashedBytes, expected)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertEqual(fake.calls, [folder])
    }

    func testPermissionDeniedUsesFallback() async throws {
        let item = try file("Projects/rootowned.bin")
        let primary = FakeTrash(directory: trashDirectory(), error: CocoaError(.fileWriteNoPermission))
        let fallback = FakeTrash(directory: trashDirectory())
        let report = await TrashRemover(guard: makeGuard(), primary: primary, fallback: fallback).remove([item])
        XCTAssertEqual(primary.calls, [item])
        XCTAssertEqual(fallback.calls, [item])
        XCTAssertEqual(report.trashed.map(\.url), [item])
        XCTAssertTrue(report.failures.isEmpty)
    }

    func testUnderlyingPosixPermissionErrorUsesFallback() async throws {
        let item = try file("Projects/locked.bin")
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteUnknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: posix])
        let primary = FakeTrash(directory: trashDirectory(), error: wrapped)
        let fallback = FakeTrash(directory: trashDirectory())
        let report = await TrashRemover(guard: makeGuard(), primary: primary, fallback: fallback).remove([item])
        XCTAssertEqual(fallback.calls, [item])
        XCTAssertEqual(report.trashed.map(\.url), [item])
    }

    func testPermissionDeniedWithoutFallbackIsFailure() async throws {
        let item = try file("Projects/rootowned.bin")
        let primary = FakeTrash(directory: trashDirectory(), error: CocoaError(.fileWriteNoPermission))
        let report = await TrashRemover(guard: makeGuard(), primary: primary, fallback: nil).remove([item])
        XCTAssertEqual(report.failures.count, 1)
        guard case .failed = report.failures[0].reason else { return XCTFail("expected .failed") }
    }

    func testOtherErrorIsReportedNotRetried() async throws {
        let item = try file("Projects/odd.bin")
        let primary = FakeTrash(directory: trashDirectory(), error: CocoaError(.fileWriteOutOfSpace))
        let fallback = FakeTrash(directory: trashDirectory())
        let report = await TrashRemover(guard: makeGuard(), primary: primary, fallback: fallback).remove([item])
        XCTAssertEqual(primary.calls.count, 1)
        XCTAssertTrue(fallback.calls.isEmpty)
        XCTAssertEqual(report.failures.count, 1)
        XCTAssertEqual(
            report.failures[0].reason, .failed(CocoaError(.fileWriteOutOfSpace).localizedDescription))
        XCTAssertTrue(report.trashed.isEmpty)
    }

    func testProcessesInInputOrder() async throws {
        let first = try file("Projects/1.bin")
        let second = try file("Projects/2.bin")
        let fake = FakeTrash(directory: trashDirectory())
        _ = await TrashRemover(guard: makeGuard(), primary: fake, fallback: nil).remove([second, first])
        XCTAssertEqual(fake.calls, [second, first])
    }
}
