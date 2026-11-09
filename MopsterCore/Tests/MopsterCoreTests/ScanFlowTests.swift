import XCTest
@testable import MopsterCore

@MainActor
final class ScanFlowTests: XCTestCase {
    private struct Boom: LocalizedError { var errorDescription: String? { "boom" } }

    private struct FakeRemover: ItemRemover {
        let report: RemovalReport
        func remove(_ urls: [URL]) async -> RemovalReport { report }
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func set() { lock.lock(); value = true; lock.unlock() }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
        func increment() { lock.lock(); value += 1; lock.unlock() }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    func testInitialPhaseIsReportedAndStartWorksFromIt() async {
        let flow = ScanFlow<Int>(initialPhase: .results(1)) { _ in 2 }
        guard case .results(1) = flow.phase else { return XCTFail("expected initial results") }
        flow.start()
        await waitUntil { if case .results(2) = flow.phase { true } else { false } }
    }

    func testStartReachesResults() async {
        let flow = ScanFlow<Int> { _ in 42 }
        flow.start()
        await waitUntil { if case .results(42) = flow.phase { true } else { false } }
    }

    func testCancelReturnsToIntroAndCancelsTask() async {
        let cancelled = Flag()
        let flow = ScanFlow<Int> { _ in
            do { try await Task.sleep(for: .seconds(30)) } catch { cancelled.set(); throw error }
            return 1
        }
        flow.start()
        try? await Task.sleep(for: .milliseconds(20))
        flow.cancel()
        guard case .intro = flow.phase else { return XCTFail("expected intro") }
        await waitUntil { cancelled.isSet }
        try? await Task.sleep(for: .milliseconds(50))
        guard case .intro = flow.phase else { return XCTFail("cancellation overwrote intro") }
    }

    func testScanFinishingAfterCancelDoesNotOverwriteIntro() async {
        let flow = ScanFlow<Int> { _ in
            await withCheckedContinuation { c in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { c.resume() }
            }
            return 7
        }
        flow.start()
        flow.cancel()
        try? await Task.sleep(for: .milliseconds(250))
        guard case .intro = flow.phase else { return XCTFail("late result overwrote intro") }
    }

    func testThrowingScanFails() async {
        let flow = ScanFlow<Int> { _ in throw Boom() }
        flow.start()
        await waitUntil { if case .failed("boom") = flow.phase { true } else { false } }
    }

    func testRemoveEndsInDoneWithReport() async {
        let flow = ScanFlow<Int> { _ in 1 }
        let report = RemovalReport(
            trashed: [TrashedItem(url: URL(fileURLWithPath: "/tmp/x"), size: 5)], trashedBytes: 5)
        flow.remove([URL(fileURLWithPath: "/tmp/x")], using: FakeRemover(report: report))
        await waitUntil { if case .done(let r) = flow.phase { r == report } else { false } }
    }

    func testProgressIsCoalescedAndLatestWins() async {
        let flow = ScanFlow<Int> { progress in
            for i in 1...5000 { progress(ScanProgress(itemsFound: i)) }
            try await Task.sleep(for: .milliseconds(600))
            return 1
        }
        var seen: [Int] = []
        flow.start()
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if case .scanning(let p) = flow.phase, seen.last != p.itemsFound { seen.append(p.itemsFound) }
            if case .results = flow.phase { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertLessThanOrEqual(seen.count, 8)
        XCTAssertEqual(seen.last, 5000)
    }

    func testStartWhileScanningIsIgnored() async {
        let runs = Counter()
        let flow = ScanFlow<Int> { _ in
            runs.increment()
            try await Task.sleep(for: .milliseconds(100))
            return 1
        }
        flow.start()
        flow.start()
        await waitUntil { if case .results = flow.phase { true } else { false } }
        XCTAssertEqual(runs.count, 1)
    }
}
