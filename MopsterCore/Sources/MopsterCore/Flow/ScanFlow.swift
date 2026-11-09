import Foundation
import Observation

/// Drives the Intro → Scanning → Results → Done flow shared by every feature.
@MainActor @Observable
public final class ScanFlow<Result: Sendable> {
    public enum Phase {
        case intro
        case scanning(ScanProgress)
        case results(Result)
        case removing
        case done(RemovalReport)
        case failed(String)
    }

    public typealias Scan = @Sendable (@escaping @Sendable (ScanProgress) -> Void) async throws -> Result

    public private(set) var phase: Phase

    @ObservationIgnored private let scan: Scan
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private static var progressInterval: TimeInterval { 0.1 }

    public init(initialPhase: Phase = .intro, scan: @escaping Scan) {
        phase = initialPhase
        self.scan = scan
    }

    public func start() {
        switch phase {
        case .scanning, .removing: return
        case .intro, .results, .done, .failed: break
        }
        generation += 1
        let current = generation
        phase = .scanning(ScanProgress())
        let throttle = ProgressThrottle(interval: Self.progressInterval) { [weak self] progress in
            guard let self, self.generation == current, case .scanning = self.phase else { return }
            self.phase = .scanning(progress)
        }
        let scan = scan
        task = Task { [weak self] in
            do {
                let result = try await scan { throttle.submit($0) }
                self?.finishScan(current, .results(result))
            } catch is CancellationError {
                return
            } catch {
                self?.finishScan(current, .failed(error.localizedDescription))
            }
        }
    }

    public func cancel() {
        guard case .scanning = phase else { return }
        generation += 1
        task?.cancel()
        task = nil
        phase = .intro
    }

    public func remove(_ urls: [URL], using remover: any ItemRemover) {
        switch phase {
        case .scanning, .removing: return
        case .intro, .results, .done, .failed: break
        }
        generation += 1
        let current = generation
        phase = .removing
        task = Task { [weak self] in
            let report = await remover.remove(urls)
            self?.finishScan(current, .done(report))
        }
    }

    public func reset() {
        generation += 1
        task?.cancel()
        task = nil
        phase = .intro
    }

    private func finishScan(_ current: Int, _ next: Phase) {
        guard generation == current else { return }
        task = nil
        phase = next
    }
}

/// Coalesces progress updates from any thread: at most one delivery per interval on the main actor, latest wins.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: TimeInterval
    private let deliver: @MainActor (ScanProgress) -> Void
    private var latest: ScanProgress?
    private var scheduled = false
    private var lastDelivery = Date.distantPast

    init(interval: TimeInterval, deliver: @escaping @MainActor (ScanProgress) -> Void) {
        self.interval = interval
        self.deliver = deliver
    }

    func submit(_ progress: ScanProgress) {
        lock.lock()
        latest = progress
        guard !scheduled else {
            lock.unlock()
            return
        }
        scheduled = true
        let delay = max(0, interval - Date().timeIntervalSince(lastDelivery))
        lock.unlock()
        Task { @MainActor [self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            drain()
        }
    }

    @MainActor private func drain() {
        lock.lock()
        let progress = latest
        latest = nil
        scheduled = false
        lastDelivery = Date()
        lock.unlock()
        if let progress { deliver(progress) }
    }
}
