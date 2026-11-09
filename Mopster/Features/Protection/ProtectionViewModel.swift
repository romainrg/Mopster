import AppKit
import Foundation
import MopsterCore
import Observation

struct ProtectionResult: Sendable {
    var checks: [SecurityCheck]
    var items: [InspectedLaunchItem]
}

@MainActor @Observable
final class ProtectionViewModel {
    enum PendingAction: Identifiable {
        case disable(InspectedLaunchItem)
        case remove(InspectedLaunchItem)

        var id: String {
            switch self {
            case .disable(let item): "disable:\(item.id)"
            case .remove(let item): "remove:\(item.id)"
            }
        }

        var item: InspectedLaunchItem {
            switch self {
            case .disable(let item), .remove(let item): item
            }
        }
    }

    let flow: ScanFlow<ProtectionResult>
    private(set) var checks: [SecurityCheck] = []
    private(set) var items: [InspectedLaunchItem] = []
    private(set) var busyItemID: String?
    var pending: PendingAction?
    var actionError: String?
    private(set) var isCheckingSystemUpdates = false
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private let systemUpdates: (@Sendable () async -> [SystemUpdate]?)?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    convenience init(env: AppEnvironment) {
        let security = env.security
        let launchItems = env.launchItems
        self.init(env: env, systemUpdates: env.systemUpdates) { _ in
            async let checks = security.run()
            async let items = launchItems.items()
            return await ProtectionResult(checks: Self.applying(system: nil, to: checks), items: items)
        }
    }

    /// Fills the "Pending macOS updates" row: warning with a count, ok at zero, unknown when the check failed.
    nonisolated static func applying(system: [SystemUpdate]?, to checks: [SecurityCheck]) -> [SecurityCheck] {
        let pending: SecurityCheck
        switch system?.count {
        case nil: pending = SecurityCheck(id: .pendingMacOSUpdates, status: .unknown)
        case 0?: pending = SecurityCheck(id: .pendingMacOSUpdates, status: .ok)
        case let count?:
            pending = SecurityCheck(
                id: .pendingMacOSUpdates, status: .warning, detail: String(localized: "\(count) pending"))
        }
        return checks.map { $0.id == .pendingMacOSUpdates ? pending : $0 }
    }

    /// Internal entry point for previews and screenshot scenes.
    init(
        env: AppEnvironment, initialPhase: ScanFlow<ProtectionResult>.Phase = .intro,
        checkingSystemUpdates: Bool = false,
        systemUpdates: (@Sendable () async -> [SystemUpdate]?)? = nil,
        scan: @escaping ScanFlow<ProtectionResult>.Scan
    ) {
        self.env = env
        self.systemUpdates = systemUpdates
        isCheckingSystemUpdates = checkingSystemUpdates
        let box = WeakBox()
        flow = ScanFlow(initialPhase: initialPhase) { progress in
            let result = try await scan(progress)
            await box.model?.adopt(result)
            return result
        }
        box.model = self
        if case .results(let result) = initialPhase { adopt(result) }
    }

    @MainActor private final class WeakBox {
        weak var model: ProtectionViewModel?
    }

    var itemsToReview: Int { items.filter { !$0.flags.isEmpty }.count }

    func refresh() { flow.start() }

    /// The checks and launch items show at once; `softwareupdate` can take minutes, so its row fills in later.
    private func adopt(_ result: ProtectionResult) {
        checks = result.checks
        items = result.items
        updatesTask?.cancel()
        guard let systemUpdates else { return }
        isCheckingSystemUpdates = true
        updatesTask = Task { [weak self] in
            let system = await systemUpdates()
            guard !Task.isCancelled, let self else { return }
            self.checks = Self.applying(system: system, to: self.checks)
            self.isCheckingSystemUpdates = false
        }
    }

    func reveal(_ item: InspectedLaunchItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.item.plist])
    }

    func canToggle(_ item: InspectedLaunchItem) -> Bool {
        item.item.domain == .userAgents && item.item.label != nil
    }

    /// Disabling asks first; enabling is harmless and runs at once.
    func requestToggle(_ item: InspectedLaunchItem) {
        if item.isDisabled { toggleDisabled(item) } else { pending = .disable(item) }
    }

    func requestRemove(_ item: InspectedLaunchItem) { pending = .remove(item) }

    func confirm(_ action: PendingAction) {
        pending = nil
        switch action {
        case .disable(let item): toggleDisabled(item)
        case .remove(let item): remove(item)
        }
    }

    func toggleDisabled(_ item: InspectedLaunchItem) {
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
        }
    }

    func remove(_ item: InspectedLaunchItem) {
        guard busyItemID == nil else { return }
        busyItemID = item.id
        let remover = env.remover
        Task {
            let report = await remover.remove([item.item.plist])
            if let failure = report.failures.first {
                actionError = String(localized: FeatureDone.phrase(for: failure.reason))
            }
            await reloadItems()
        }
    }

    private func reloadItems() async {
        items = await env.launchItems.items()
        busyItemID = nil
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
