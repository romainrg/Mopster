import Foundation
import MopsterCore
import Observation

@MainActor @Observable
final class SystemJunkViewModel {
    let flow: ScanFlow<JunkScanResult>
    var selection = Selection(defaultsFrom: [])
    private(set) var groups: [CleanupGroup] = []
    private(set) var skipped: [URL] = []
    private(set) var trashSize: Int64?
    @ObservationIgnored private let env: AppEnvironment

    convenience init(env: AppEnvironment) {
        let scanner = env.junk
        let ignore = env.ignoreList
        self.init(env: env) { progress in
            let list = await ignore.list
            return try await scanner(list).scan(progress: progress)
        }
    }

    /// Internal entry point for previews and screenshot scenes.
    init(
        env: AppEnvironment, initialPhase: ScanFlow<JunkScanResult>.Phase = .intro,
        scan: @escaping ScanFlow<JunkScanResult>.Scan
    ) {
        self.env = env
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
        weak var model: SystemJunkViewModel?
    }

    /// The skipped folders with the home abbreviated to `~`.
    var skippedPaths: [String] {
        let home = env.isDemo ? DemoData.demoHome : env.home.standardizedFileURL.path
        return skipped.map { url in
            let path = url.standardizedFileURL.path
            if path == home { return "~" }
            return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        }
    }

    var totalFound: Int64 { groups.reduce(0) { $0 + $1.totalSize } }

    func start() { flow.start() }

    /// Runs inside the scan, before the flow publishes `.results`, so groups and selection are always consistent with it.
    private func adopt(_ result: JunkScanResult) {
        groups = result.groups
        skipped = result.skipped
        trashSize = result.trashSize
        selection = Selection(defaultsFrom: groups)
    }

    func clean() {
        flow.remove(selection.urls(in: groups), using: env.remover)
    }

    func ignore(_ url: URL) {
        env.ignoreList.add(url)
        let prefix = url.standardizedFileURL.path
        let removed = Set(
            groups.flatMap(\.items).map(\.id).filter { $0 == prefix || $0.hasPrefix(prefix + "/") })
        groups = groups.compactMap { group in
            var group = group
            group.items.removeAll { removed.contains($0.id) }
            return group.items.isEmpty ? nil : group
        }
        var kept = Selection(defaultsFrom: [])
        for group in groups { for item in group.items where selection.contains(item.id) { kept.toggle(item.id) } }
        selection = kept
    }
}
