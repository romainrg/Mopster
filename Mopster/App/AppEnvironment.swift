import AppKit
import MopsterCore
import SwiftUI

// Injection pattern: `AppEnvironment` is a value placed in the SwiftUI environment through a custom key.
// MopsterApp does `.environment(\.appEnvironment, AppEnvironment.current())` once; views read it with
// `@Environment(\.appEnvironment) private var env`. Each module task adds its service as a property here
// and sets it in both `live()` and `demo()`.

struct AppEnvironment {
    let isDemo: Bool
    let home: URL
    var guardian: SafetyGuard
    var remover: any ItemRemover
    var makeRemover: @Sendable ([URL]) -> any ItemRemover
    var sizeTree: any SizeTreeBuilding
    var ignoreList: IgnoreListStore
    var junk: @Sendable (IgnoreList) -> any JunkScanning
    var largeFiles: @Sendable (IgnoreList) -> any LargeFileFinding
    var duplicates: @Sendable (IgnoreList) -> any DuplicateFinding
    var security: any SecurityChecking
    var launchItems: any LaunchItemProviding
    var launchControl: any LaunchAgentControlling
    var processSampling: any ProcessSampling
    var processControl: any ProcessControlling
    var maintenance: any MaintenanceRunning
    var maintenanceHistory: any MaintenanceHistory
    var apps: any AppInventoryProviding
    var isAppRunning: @MainActor (String) -> Bool
    var terminateApp: @MainActor (String) -> Void
    var updates: any UpdateChecking
    var systemUpdates: @Sendable () async -> [SystemUpdate]?
    var diskCapacity: @Sendable () -> VolumeCapacity?
    var openURL: @MainActor (URL) -> Void
    var openApp: @MainActor (URL) -> Void

    @MainActor
    static func live() -> AppEnvironment {
        let home = realHome()
        let guardian = SafetyGuard(home: home, appBundle: Bundle.main.bundleURL)
        return AppEnvironment(
            isDemo: false,
            home: home,
            guardian: guardian,
            remover: TrashRemover(guard: guardian, primary: FileManagerTrash(), fallback: FinderTrash()),
            makeRemover: { roots in
                TrashRemover(
                    guard: roots.reduce(guardian) { $0.adding(root: $1) }, primary: FileManagerTrash(),
                    fallback: FinderTrash())
            },
            sizeTree: FtsSizeTreeBuilder(),
            ignoreList: IgnoreListStore(),
            junk: { JunkScanner(home: home, ignore: $0) },
            largeFiles: { LargeFileFinder(home: home, ignore: $0) },
            duplicates: { DuplicateFinder(ignore: $0) },
            security: LiveSecurityChecker(),
            launchItems: LiveLaunchItemProvider(home: home),
            launchControl: LiveLaunchAgentControl(),
            processSampling: LiveProcessSampling(),
            processControl: LiveProcessControl(),
            maintenance: LiveMaintenanceRunner(),
            maintenanceHistory: UserDefaultsMaintenanceHistory(),
            apps: LiveAppInventory(
                home: home, systemRoot: URL(fileURLWithPath: "/"),
                isKnownToLaunchServices: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }),
            isAppRunning: { id in NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id } },
            terminateApp: { id in
                NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { _ = $0.terminate() }
            },
            updates: UpdateChecker(http: URLSessionHTTPClient()),
            systemUpdates: UpdateChecker.softwareUpdateList,
            diskCapacity: { VolumeCapacity.of(home) },
            openURL: { _ = NSWorkspace.shared.open($0) },
            openApp: { NSWorkspace.shared.openApplication(at: $0, configuration: NSWorkspace.OpenConfiguration()) })
    }

    @MainActor
    static func demo() -> AppEnvironment {
        let home = realHome()
        let launchState = DemoLaunchState()
        let demoProcesses = DemoProcessSampling()
        return AppEnvironment(
            isDemo: true,
            home: home,
            guardian: SafetyGuard(home: URL(fileURLWithPath: DemoData.demoHome), appBundle: Bundle.main.bundleURL),
            remover: DemoLaunchRemover(base: DemoEnvironment.remover, state: launchState),
            makeRemover: { _ in DemoEnvironment.remover },
            sizeTree: DemoSizeTree(),
            ignoreList: IgnoreListStore(persistence: nil),
            junk: { _ in DemoJunkScanner() },
            largeFiles: { _ in DemoLargeFileFinder() },
            duplicates: { _ in DemoDuplicateFinder() },
            security: DemoSecurityChecker(),
            launchItems: DemoLaunchItems(state: launchState),
            launchControl: DemoLaunchControl(state: launchState),
            processSampling: demoProcesses,
            processControl: DemoProcessControl(sampling: demoProcesses),
            maintenance: DemoMaintenanceRunner(),
            maintenanceHistory: DemoMaintenanceRunner.history(),
            apps: DemoAppInventory(),
            isAppRunning: { _ in false },
            terminateApp: { _ in },
            updates: DemoUpdateChecker(),
            systemUpdates: { DemoUpdateChecker.systemUpdates },
            diskCapacity: { DemoData.diskCapacity },
            openURL: { _ in },
            openApp: { _ in })
    }

    @MainActor
    static func current() -> AppEnvironment {
        CommandLine.arguments.contains("--demo") ? demo() : live()
    }

    private static func realHome() -> URL {
        #if DEBUG
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--fixture-home"), arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

private struct AppEnvironmentKey: EnvironmentKey {
    @MainActor static var defaultValue: AppEnvironment { AppEnvironment.demo() }
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}

@MainActor @Observable
final class IgnoreListStore {
    private static let key = "ignoreList"
    private let defaults: UserDefaults?
    private(set) var list: IgnoreList

    /// `nil` keeps the list in memory only (demo mode never touches the real defaults).
    init(persistence defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        list = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(IgnoreList.self, from: $0) }
            ?? IgnoreList()
    }

    func add(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !list.paths.contains(path) else { return }
        list.paths.append(path)
        save()
    }

    func remove(_ path: String) {
        list.paths.removeAll { $0 == path }
        save()
    }

    private func save() {
        defaults?.set(try? JSONEncoder().encode(list), forKey: Self.key)
    }
}
