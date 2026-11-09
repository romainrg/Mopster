import AppKit
import Foundation
import MopsterCore
import Observation

struct UninstallerInventory: Sendable {
    var apps: [InstalledApp]
    var orphans: [CleanupGroup]
}

/// Refreshes the inventory cache around a removal so leftovers and orphans never reflect a stale app list.
private struct RefreshingRemover: ItemRemover {
    let base: any ItemRemover
    let apps: any AppInventoryProviding

    func remove(_ urls: [URL]) async -> RemovalReport {
        _ = await apps.apps()
        let report = await base.remove(urls)
        _ = await apps.apps()
        return report
    }
}

@MainActor @Observable
final class UninstallerViewModel {
    enum Tab: Hashable { case applications, leftovers }
    enum SortKey: Hashable { case name, size, lastUsed }
    enum PendingAction: Equatable { case uninstall, reset, removeOrphans }

    let flow: ScanFlow<UninstallerInventory>
    var tab: Tab = .applications
    var search = ""
    var sort: SortKey = .name
    var pending: PendingAction?
    @ObservationIgnored private var pendingAppID: String?
    var leftoverSelection = Selection(defaultsFrom: [])
    var orphanSelection = Selection(defaultsFrom: [])
    private(set) var apps: [InstalledApp] = []
    private(set) var orphans: [CleanupGroup] = []
    private(set) var selectedApp: InstalledApp?
    private(set) var leftovers: [CleanupGroup] = []
    private(set) var isLoadingLeftovers = false
    private(set) var selectedAppIsRunning = false
    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private var leftoversTask: Task<Void, Never>?
    @ObservationIgnored private var runningWatch: Task<Void, Never>?

    convenience init(env: AppEnvironment) {
        let inventory = env.apps
        self.init(env: env) { progress in
            progress(ScanProgress(location: "/Applications"))
            let apps = await inventory.apps()
            progress(ScanProgress(location: "~/Library", itemsFound: apps.count))
            return UninstallerInventory(apps: apps, orphans: await inventory.orphans())
        }
    }

    /// Internal entry point for previews and screenshot scenes; `preselected` opens an app with its leftovers.
    init(
        env: AppEnvironment, initialPhase: ScanFlow<UninstallerInventory>.Phase = .intro,
        initialTab: Tab = .applications, preselected: (app: InstalledApp, leftovers: [CleanupItem])? = nil,
        scan: @escaping ScanFlow<UninstallerInventory>.Scan
    ) {
        self.env = env
        tab = initialTab
        let box = WeakBox()
        flow = ScanFlow(initialPhase: initialPhase) { progress in
            let result = try await scan(progress)
            await box.model?.adopt(result)
            return result
        }
        box.model = self
        if case .results(let inventory) = initialPhase { adopt(inventory) }
        if let preselected {
            selectedApp = preselected.app
            adoptLeftovers(preselected.leftovers)
            selectedAppIsRunning = env.isAppRunning(preselected.app.bundleID)
        }
    }

    @MainActor private final class WeakBox {
        weak var model: UninstallerViewModel?
    }

    // MARK: Applications

    var visibleApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty
            ? apps
            : apps.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
        switch sort {
        case .name: return matching
        case .size: return matching.sorted { $0.size > $1.size }
        case .lastUsed: return matching.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
        }
    }

    var totalOrphanSize: Int64 { orphans.reduce(0) { $0 + $1.totalSize } }
    var selectedLeftoverURLs: [URL] { leftoverSelection.urls(in: leftovers) }
    var canAct: Bool { selectedApp.map { !$0.isLocked } == true && !selectedAppIsRunning && !isLoadingLeftovers }
    var canReset: Bool { canAct && !selectedLeftoverURLs.isEmpty }

    func start() { flow.start() }

    /// Runs inside the scan, before the flow publishes `.results`, so lists and selections are consistent with it.
    private func adopt(_ inventory: UninstallerInventory) {
        apps = inventory.apps
        orphans = inventory.orphans
        orphanSelection = Selection(defaultsFrom: orphans)
        select(selectedApp?.id)
    }

    func select(_ id: String?) {
        leftoversTask?.cancel()
        runningWatch?.cancel()
        leftovers = []
        leftoverSelection = Selection(defaultsFrom: [])
        guard let app = apps.first(where: { $0.id == id }) else {
            selectedApp = nil
            selectedAppIsRunning = false
            isLoadingLeftovers = false
            return
        }
        selectedApp = app
        refreshRunning()
        guard !app.isLocked else {
            isLoadingLeftovers = false
            return
        }
        isLoadingLeftovers = true
        let inventory = env.apps
        leftoversTask = Task { [weak self] in
            let items = await inventory.leftovers(for: app)
            guard !Task.isCancelled, let self, self.selectedApp?.id == app.id else { return }
            self.adoptLeftovers(items)
        }
    }

    private func adoptLeftovers(_ items: [CleanupItem]) {
        leftovers = Dictionary(grouping: items, by: { $0.detail ?? "" }).map { folder, items in
            CleanupGroup(
                id: folder, title: LocalizedStringResource(stringLiteral: folder), symbol: "folder",
                risk: items.contains { $0.risk == .review } ? .review : .safe,
                items: items.sorted { $0.size > $1.size })
        }.sorted { ($0.totalSize, $1.id) > ($1.totalSize, $0.id) }
        leftoverSelection = Selection(defaultsFrom: leftovers)
        isLoadingLeftovers = false
    }

    // MARK: Running check

    func refreshRunning() {
        selectedAppIsRunning = selectedApp.map { env.isAppRunning($0.bundleID) } ?? false
    }

    func quitSelectedApp() {
        guard let app = selectedApp else { return }
        env.terminateApp(app.bundleID)
        runningWatch?.cancel()
        runningWatch = Task { [weak self] in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled, let self else { return }
                self.refreshRunning()
                if !self.selectedAppIsRunning { return }
            }
        }
    }

    // MARK: Removal

    func request(_ action: PendingAction) {
        refreshRunning()
        switch action {
        case .uninstall: guard canAct else { return }
        case .reset: guard canReset else { return }
        case .removeOrphans: guard !orphanSelection.urls(in: orphans).isEmpty else { return }
        }
        pendingAppID = selectedApp?.id
        pending = action
    }

    func confirm(_ action: PendingAction) {
        pending = nil
        let appID = pendingAppID
        pendingAppID = nil
        if action != .removeOrphans {
            guard let app = selectedApp, app.id == appID else { return }
            refreshRunning()
            guard !selectedAppIsRunning else { return }
        }
        let remover = RefreshingRemover(base: env.remover, apps: env.apps)
        switch action {
        case .uninstall:
            guard canAct, let app = selectedApp else { return }
            flow.remove([app.url] + selectedLeftoverURLs, using: remover)
        case .reset:
            guard canReset else { return }
            flow.remove(selectedLeftoverURLs, using: remover)
        case .removeOrphans:
            let urls = orphanSelection.urls(in: orphans)
            guard !urls.isEmpty else { return }
            flow.remove(urls, using: remover)
        }
    }

    /// After a removal the inventory is scanned again, so the list shows what is really left.
    func finish() { flow.start() }
}
