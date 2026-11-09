import Foundation
import MopsterCore
import Observation

@MainActor @Observable
final class OptimizationViewModel {
    enum SortKey { case cpu, memory }

    enum PendingAction: Identifiable {
        case quit(ProcessSample)
        case forceQuit(ProcessSample)
        case disable(InspectedLaunchItem)

        var id: String {
            switch self {
            case .quit(let process): "quit:\(process.pid)"
            case .forceQuit(let process): "forceQuit:\(process.pid)"
            case .disable(let item): "disable:\(item.id)"
            }
        }
    }

    static let visibleCount = 25
    static let interval: Duration = .seconds(2)

    private(set) var processes: [ProcessSample] = []
    private(set) var load = SystemLoad(memoryPressure: .normal, cpuLoad: 0)
    private(set) var backgroundItems: [InspectedLaunchItem] = []
    private(set) var busyItemID: String?
    var sort: SortKey = .cpu
    var pending: PendingAction?
    var actionError: String?
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var loadedItems = false

    init(env: AppEnvironment) { self.env = env }

    var topProcesses: [ProcessSample] {
        let sorted: [ProcessSample]
        switch sort {
        case .cpu: sorted = processes.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memory: sorted = processes.sorted { $0.memoryBytes > $1.memoryBytes }
        }
        return Array(sorted.prefix(Self.visibleCount))
    }

    /// Samples every 2 s until `stop()`; the view calls these on appear and disappear.
    func start() {
        if !loadedItems { loadBackgroundItems() }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sampleOnce()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func sampleOnce() async {
        let result = await env.processSampling.sample()
        guard !Task.isCancelled else { return }
        processes = result.processes
        load = result.load
    }

    func loadBackgroundItems() {
        loadedItems = true
        Task { await reloadItems() }
    }

    private func reloadItems() async {
        let items = await env.launchItems.items()
        backgroundItems = items.sorted { lhs, rhs in
            let lhsUser = lhs.item.domain == .userAgents
            if lhsUser != (rhs.item.domain == .userAgents) { return lhsUser }
            return Self.name(of: lhs).localizedCaseInsensitiveCompare(Self.name(of: rhs)) == .orderedAscending
        }
    }

    static func name(of item: InspectedLaunchItem) -> String {
        item.item.label ?? item.item.plist.deletingPathExtension().lastPathComponent
    }

    // MARK: Processes

    func canQuit(_ process: ProcessSample) -> Bool {
        ProcessControlPolicy.canQuit(process, currentUID: getuid(), ownPID: getpid())
    }

    func confirm(_ action: PendingAction) {
        pending = nil
        switch action {
        case .quit(let process): perform(process, force: false)
        case .forceQuit(let process): perform(process, force: true)
        case .disable(let item): toggleDisabled(item)
        }
    }

    private func perform(_ process: ProcessSample, force: Bool) {
        let control = env.processControl
        let done = force ? control.forceQuit(process) : control.quit(process)
        if !done { actionError = String(localized: "“\(process.name)” couldn't be quit.") }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            await sampleOnce()
        }
    }

    // MARK: Background items

    func canToggle(_ item: InspectedLaunchItem) -> Bool {
        item.item.domain == .userAgents && item.item.label != nil
    }

    /// Disabling asks first; enabling is harmless and runs at once.
    func requestToggle(_ item: InspectedLaunchItem) {
        if item.isDisabled { toggleDisabled(item) } else { pending = .disable(item) }
    }

    private func toggleDisabled(_ item: InspectedLaunchItem) {
        guard busyItemID == nil, canToggle(item) else { return }
        busyItemID = item.id
        let control = env.launchControl
        Task {
            do {
                if item.isDisabled { try await control.enable(item) } else { try await control.disable(item) }
            } catch {
                actionError = Self.message(for: error)
            }
            await reloadItems()
            busyItemID = nil
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? LaunchControlError {
        case .notAllowed?: String(localized: "Only your own agents can be disabled or enabled.")
        case .missingLabel?: String(localized: "This item has no label.")
        case .commandFailed(let text)?: String(localized: "Failed: \(text)")
        case nil: String(localized: "Failed: \(error.localizedDescription)")
        }
    }
}
