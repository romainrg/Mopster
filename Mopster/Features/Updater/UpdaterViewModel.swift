import Foundation
import MopsterCore
import Observation

@MainActor @Observable
final class UpdaterViewModel {
    let flow: ScanFlow<UpdateCheckResult>
    private(set) var result: UpdateCheckResult?
    var unknownExpanded = false
    @ObservationIgnored private let env: AppEnvironment

    convenience init(env: AppEnvironment) {
        let inventory = env.apps
        let updates = env.updates
        self.init(env: env) { _ in await updates.check(apps: await inventory.apps()) }
    }

    /// Internal entry point for previews and screenshot scenes.
    init(
        env: AppEnvironment, initialPhase: ScanFlow<UpdateCheckResult>.Phase = .intro,
        scan: @escaping ScanFlow<UpdateCheckResult>.Scan
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
        weak var model: UpdaterViewModel?
    }

    var updateCount: Int { result?.updates.count ?? 0 }

    func check() { flow.start() }

    private func adopt(_ result: UpdateCheckResult) { self.result = result }

    func openSystemSettings() {
        guard !env.isDemo else { return }
        SystemSettings.open(.softwareUpdate)
    }

    func update(_ update: AppUpdate) {
        switch update.source {
        case .appStore(let trackID):
            if let url = URL(string: "macappstore://apps.apple.com/app/id\(trackID)") { env.openURL(url) }
        case .sparkle:
            env.openApp(update.app.url)
        }
    }
}
