import Foundation
import MopsterCore

/// Fictional updates for apps of the demo inventory; touches no network.
struct DemoUpdateChecker: UpdateChecking {
    func check(apps: [InstalledApp]) async -> UpdateCheckResult {
        try? await Task.sleep(for: .seconds(1))
        return Self.result
    }

    static let systemUpdates = [
        SystemUpdate(
            label: "macOS 27.1-27B100", title: "macOS 27.1", version: "27.1", recommended: true, restart: true)
    ]

    private static func app(_ bundleID: String) -> InstalledApp {
        DemoAppInventory.apps.first { $0.bundleID == bundleID }!
    }

    static let result = UpdateCheckResult(
        updates: [
            AppUpdate(app: app("com.example.pixelstudio"), available: "4.3.0", source: .sparkle),
            AppUpdate(app: app("com.example.notebook"), available: "3.0", source: .appStore(trackID: 1_000_000_001)),
            AppUpdate(app: app("com.example.codeforge"), available: "1.89.1", source: .sparkle),
            AppUpdate(app: app("com.example.sketchpad"), available: "6.1.2", source: .appStore(trackID: 1_000_000_002)),
        ],
        unknown: [app("com.example.photovault")],
        system: systemUpdates)
}
