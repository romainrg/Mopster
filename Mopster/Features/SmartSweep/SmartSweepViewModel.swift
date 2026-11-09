import Foundation
import MopsterCore
import Observation

enum CardState<Value> {
    case loading
    case ready(Value)
    case failed

    var value: Value? {
        if case .ready(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct JunkSummary {
    var safeBytes: Int64
    var safeURLs: [URL]
    var reviewBytes: Int64
}

struct ProtectionSummary {
    var warnings: Int
    var flaggedItems: Int
    var total: Int { warnings + flaggedItems }
}

struct PerformanceSummary {
    var memoryPressure: MemoryPressure
    var topProcessName: String?
    var topProcessCPU: Double
    var brokenItems: Int
}

struct UpdatesSummary {
    var appUpdates: Int
    var macOSUpdates: Int
    var total: Int { appUpdates + macOSUpdates }
}

struct LargeFilesSummary {
    var count: Int
    var bytes: Int64
}

@MainActor @Observable
final class SmartSweepViewModel {
    enum Phase {
        case intro
        case sweeping
        case results
        case removing
        case done(RemovalReport)
    }

    /// Files at least this big that were not opened for a year; a builder's default, recorded in the README.
    nonisolated static let largeFileMinSize: Int64 = 50_000_000
    nonisolated static let largeFileAge: TimeInterval = 365 * 86_400

    private(set) var phase: Phase
    private(set) var junk: CardState<JunkSummary> = .loading
    private(set) var protection: CardState<ProtectionSummary> = .loading
    private(set) var performance: CardState<PerformanceSummary> = .loading
    private(set) var updates: CardState<UpdatesSummary> = .loading
    private(set) var largeFiles: CardState<LargeFilesSummary> = .loading
    var confirmingRun = false
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let navigate: (SidebarSection) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(env: AppEnvironment, initialPhase: Phase = .intro, navigate: @escaping (SidebarSection) -> Void) {
        self.env = env
        self.phase = initialPhase
        self.navigate = navigate
    }

    /// Internal entry point for screenshot scenes: cards start in the given states.
    convenience init(
        env: AppEnvironment, phase: Phase, junk: CardState<JunkSummary>, protection: CardState<ProtectionSummary>,
        performance: CardState<PerformanceSummary>, updates: CardState<UpdatesSummary>,
        largeFiles: CardState<LargeFilesSummary>
    ) {
        self.init(env: env, initialPhase: phase, navigate: { _ in })
        self.junk = junk
        self.protection = protection
        self.performance = performance
        self.updates = updates
        self.largeFiles = largeFiles
    }

    var isSettled: Bool {
        !junk.isLoading && !protection.isLoading && !performance.isLoading && !updates.isLoading
            && !largeFiles.isLoading
    }

    /// Run is offered only when the junk card is ready with something safe to clean.
    var canRun: Bool {
        switch phase {
        case .sweeping, .results: return !(junk.value?.safeURLs.isEmpty ?? true)
        case .intro, .removing, .done: return false
        }
    }

    func review(_ section: SidebarSection) { navigate(section) }

    // MARK: Sweep

    func start() {
        switch phase {
        case .sweeping, .removing: return
        case .intro, .results, .done: break
        }
        generation += 1
        let current = generation
        junk = .loading
        protection = .loading
        performance = .loading
        updates = .loading
        largeFiles = .loading
        phase = .sweeping
        task?.cancel()
        let launchItems = env.launchItems
        let sharedItems = Task { await launchItems.items() }
        task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self?.sweepJunk(current) }
                group.addTask { await self?.sweepProtection(current, items: sharedItems) }
                group.addTask { await self?.sweepPerformance(current, items: sharedItems) }
                group.addTask { await self?.sweepUpdates(current) }
                group.addTask { await self?.sweepLargeFiles(current) }
            }
            self?.finish(current)
        }
    }

    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        phase = .intro
    }

    private func finish(_ current: Int) {
        guard generation == current, case .sweeping = phase else { return }
        phase = .results
    }

    private func sweepJunk(_ current: Int) async {
        let scanner = env.junk(env.ignoreList.list)
        let state: CardState<JunkSummary>
        do {
            let result = try await scanner.scan(progress: { _ in })
            state = .ready(Self.junkSummary(of: result.groups))
        } catch {
            state = .failed
        }
        guard generation == current, !Task.isCancelled else { return }
        junk = state
    }

    nonisolated static func junkSummary(of groups: [CleanupGroup]) -> JunkSummary {
        let selection = Selection(defaultsFrom: groups)
        let items = groups.flatMap(\.items)
        let safe = items.filter { selection.contains($0.id) && $0.risk == .safe }
        let safeIDs = Set(safe.map(\.id))
        let review = items.filter { !safeIDs.contains($0.id) }
        return JunkSummary(
            safeBytes: safe.reduce(0) { $0 + $1.size }, safeURLs: safe.map(\.url),
            reviewBytes: review.reduce(0) { $0 + $1.size })
    }

    private func sweepProtection(_ current: Int, items: Task<[InspectedLaunchItem], Never>) async {
        let resolvedChecks = await env.security.run()
        let resolvedItems = await items.value
        guard generation == current, !Task.isCancelled else { return }
        protection = .ready(Self.protectionSummary(checks: resolvedChecks, items: resolvedItems))
    }

    /// Pending macOS updates are left to the Updates card.
    nonisolated static func protectionSummary(checks: [SecurityCheck], items: [InspectedLaunchItem])
        -> ProtectionSummary
    {
        ProtectionSummary(
            warnings: checks.filter { $0.status == .warning && $0.id != .pendingMacOSUpdates }.count,
            flaggedItems: items.filter { !$0.flags.isEmpty }.count)
    }

    private func sweepPerformance(_ current: Int, items: Task<[InspectedLaunchItem], Never>) async {
        let sampling = env.processSampling
        _ = await sampling.sample()
        try? await Task.sleep(for: .seconds(1))
        let second = await sampling.sample()
        let resolvedItems = await items.value
        guard generation == current, !Task.isCancelled else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let top = second.processes.filter { $0.pid != ownPID }.max { $0.cpuPercent < $1.cpuPercent }
        performance = .ready(
            PerformanceSummary(
                memoryPressure: second.load.memoryPressure, topProcessName: top?.name,
                topProcessCPU: top?.cpuPercent ?? 0,
                brokenItems: resolvedItems.filter { $0.flags.contains(.programMissing) }.count))
    }

    private func sweepUpdates(_ current: Int) async {
        let result = await env.updates.check(apps: await env.apps.apps())
        guard generation == current, !Task.isCancelled else { return }
        if result.system == nil && result.updates.isEmpty {
            updates = .failed
        } else {
            updates = .ready(
                UpdatesSummary(appUpdates: result.updates.count, macOSUpdates: result.system?.count ?? 0))
        }
    }

    private func sweepLargeFiles(_ current: Int) async {
        let finder = env.largeFiles(env.ignoreList.list)
        let query = LargeFileQuery(minSize: Self.largeFileMinSize, olderThan: Self.largeFileAge)
        let state: CardState<LargeFilesSummary>
        do {
            let files = try await finder.find(query, progress: { _ in })
            state = .ready(LargeFilesSummary(count: files.count, bytes: files.reduce(0) { $0 + $1.size }))
        } catch {
            state = .failed
        }
        guard generation == current, !Task.isCancelled else { return }
        largeFiles = state
    }

    // MARK: Run

    func requestRun() {
        guard canRun else { return }
        confirmingRun = true
    }

    /// Moves exactly the safe, pre-selected junk found by this sweep to the Trash.
    func run() {
        guard canRun, let urls = junk.value?.safeURLs else { return }
        generation += 1
        let current = generation
        task?.cancel()
        phase = .removing
        let remover = env.remover
        task = Task { [weak self] in
            let report = await remover.remove(urls)
            guard let self, self.generation == current else { return }
            self.phase = .done(report)
        }
    }
}
