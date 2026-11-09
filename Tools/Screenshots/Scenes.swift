import MopsterCore
import SwiftUI

struct ScreenshotScene {
    let name: String
    let size: CGSize
    let make: @MainActor () -> AnyView
}

enum ScreenshotScenes {
    @MainActor
    static var all: [ScreenshotScene] {
        let sections = SidebarSection.allCases.filter { $0 != .smartSweep && $0 != .maintenance && $0 != .telescope && $0 != .largeFiles && $0 != .duplicates }.map { section in
            ScreenshotScene(
                name: section.rawValue,
                size: CGSize(width: 1100, height: section == .optimization ? 1100 : 720)
            ) {
                AnyView(
                    ContentView(initialSection: section)
                        .environment(\.appEnvironment, AppEnvironment.demo())
                        .environment(FullDiskAccess(isDemo: true)))
            }
        }
        return sections + smartSweepScenes + systemJunkScenes + protectionScenes + maintenanceScenes + uninstallerScenes + updaterScenes + telescopeScenes + largeFilesScenes + duplicatesScenes
            + [ScreenshotScene(name: "onboarding", size: CGSize(width: 780, height: 480)) { AnyView(OnboardingView(onContinue: {})) }]
    }

    @MainActor
    private static var smartSweepScenes: [ScreenshotScene] {
        func scene(_ name: String, settled: Bool) -> ScreenshotScene {
            ScreenshotScene(name: name, size: CGSize(width: 1100, height: 720)) {
                let env = AppEnvironment.demo()
                let now = Date.now
                let old = DemoLargeFileFinder.files(now: now).filter {
                    $0.size >= SmartSweepViewModel.largeFileMinSize
                        && now.timeIntervalSince($0.lastAccess) >= SmartSweepViewModel.largeFileAge
                }
                let junkResult = DemoJunkScanner.result()
                let junk = SmartSweepViewModel.junkSummary(of: junkResult.groups, trashSize: junkResult.trashSize)
                let protection = SmartSweepViewModel.protectionSummary(
                    checks: DemoSecurityChecker.checks, items: DemoLaunchItems(state: DemoLaunchState()).inspected())
                let updates = DemoUpdateChecker.result
                let model = SmartSweepViewModel(
                    env: env, phase: settled ? .results : .sweeping, junk: .ready(junk), protection: .ready(protection),
                    performance: settled
                        ? .ready(
                            PerformanceSummary(
                                memoryPressure: .normal, topProcessName: "Video Converter", topProcessCPU: 96,
                                brokenItems: 1)) : .loading,
                    updates: settled
                        ? .ready(
                            UpdatesSummary(appUpdates: updates.updates.count, macOSUpdates: updates.system?.count ?? 0))
                        : .loading,
                    largeFiles: settled
                        ? .ready(LargeFilesSummary(count: old.count, bytes: old.reduce(0) { $0 + $1.size })) : .loading)
                return AnyView(
                    ContentView(initialSection: .smartSweep, models: FeatureModels(env: env, smartSweep: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            }
        }
        return [scene("smartSweep-results", settled: true), scene("smartSweep-sweeping", settled: false)]
    }

    @MainActor
    private static var systemJunkScenes: [ScreenshotScene] {
        let result = DemoJunkScanner.result()
        let demoReport = RemovalReport(
            trashed: result.groups.filter { $0.risk == .safe }.flatMap(\.items).map {
                TrashedItem(url: $0.url, size: $0.size)
            },
            trashedBytes: result.groups.filter { $0.risk == .safe }.reduce(0) { $0 + $1.totalSize })
        func scene(_ name: String, _ phase: ScanFlow<JunkScanResult>.Phase) -> ScreenshotScene {
            ScreenshotScene(name: name, size: CGSize(width: 1100, height: 720)) {
                let env = AppEnvironment.demo()
                let model = SystemJunkViewModel(env: env, initialPhase: phase) { _ in result }
                return AnyView(
                    ContentView(initialSection: .systemJunk, models: FeatureModels(env: env, systemJunk: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            }
        }
        return [scene("systemJunk-results", .results(result)), scene("systemJunk-done", .done(demoReport))]
    }

    @MainActor
    private static var protectionScenes: [ScreenshotScene] {
        [
            ScreenshotScene(name: "protection-results", size: CGSize(width: 1100, height: 960)) {
                let env = AppEnvironment.demo()
                let result = ProtectionResult(
                    checks: DemoSecurityChecker.checks, items: DemoLaunchItems(state: DemoLaunchState()).inspected())
                let model = ProtectionViewModel(env: env, initialPhase: .results(result)) { _ in result }
                return AnyView(
                    ContentView(initialSection: .protection, models: FeatureModels(env: env, protection: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            },
            ScreenshotScene(name: "protection-checking", size: CGSize(width: 1100, height: 900)) {
                let env = AppEnvironment.demo()
                let result = ProtectionResult(
                    checks: DemoSecurityChecker.checks, items: DemoLaunchItems(state: DemoLaunchState()).inspected())
                let model = ProtectionViewModel(
                    env: env, initialPhase: .results(result), checkingSystemUpdates: true) { _ in result }
                return AnyView(
                    ContentView(initialSection: .protection, models: FeatureModels(env: env, protection: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            },
        ]
    }

    @MainActor
    private static var maintenanceScenes: [ScreenshotScene] {
        func scene(_ name: String, selection: Set<String>, ran: Bool) -> ScreenshotScene {
            ScreenshotScene(name: name, size: CGSize(width: 1100, height: 900)) {
                let env = AppEnvironment.demo()
                let selected = MaintenanceCatalog.tasks.filter { selection.contains($0.id) }
                let model = MaintenanceViewModel(
                    env: env, initialSelection: selection,
                    initialOutcomes: ran ? DemoMaintenanceRunner.outcomes(for: selected) : [:])
                return AnyView(
                    ContentView(initialSection: .maintenance, models: FeatureModels(env: env, maintenance: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            }
        }
        let picked: Set<String> = ["freeRAM", "flushDNS", "rebuildLaunchServices", "verifyStartupDisk"]
        return [
            scene("maintenance", selection: [], ran: false),
            scene("maintenance-done", selection: picked, ran: true),
        ]
    }

    @MainActor
    private static var uninstallerScenes: [ScreenshotScene] {
        let inventory = UninstallerInventory(apps: DemoAppInventory.apps, orphans: DemoAppInventory.orphanGroups)
        func scene(_ name: String, tab: UninstallerViewModel.Tab, openApp: String? = nil) -> ScreenshotScene {
            ScreenshotScene(name: name, size: CGSize(width: 1100, height: 720)) {
                let env = AppEnvironment.demo()
                let preselected = openApp.flatMap { id in
                    inventory.apps.first { $0.bundleID == id }.map {
                        (app: $0, leftovers: DemoAppInventory.leftovers(forBundleID: id))
                    }
                }
                let model = UninstallerViewModel(
                    env: env, initialPhase: .results(inventory), initialTab: tab, preselected: preselected
                ) { _ in inventory }
                return AnyView(
                    ContentView(initialSection: .uninstaller, models: FeatureModels(env: env, uninstaller: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            }
        }
        return [
            scene("uninstaller-apps", tab: .applications, openApp: "com.example.pixelstudio"),
            scene("uninstaller-leftovers", tab: .leftovers),
        ]
    }

    @MainActor
    private static var updaterScenes: [ScreenshotScene] {
        [
            ScreenshotScene(name: "updater-results", size: CGSize(width: 1100, height: 720)) {
                let env = AppEnvironment.demo()
                let result = DemoUpdateChecker.result
                let model = UpdaterViewModel(env: env, initialPhase: .results(result)) { _ in result }
                return AnyView(
                    ContentView(initialSection: .updater, models: FeatureModels(env: env, updater: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            }
        ]
    }

    @MainActor
    private static var telescopeScenes: [ScreenshotScene] {
        func scene(_ name: String, dive: [String], selected: String) -> ScreenshotScene {
            ScreenshotScene(name: name, size: CGSize(width: 1100, height: 720)) {
                let env = AppEnvironment.demo()
                let result = SizeTreeResult(root: DemoSizeTree.tree(), skipped: [])
                let model = TelescopeViewModel(
                    env: env, initialPhase: .results(result), initialDive: dive, initialSelection: [selected]
                ) { _, _ in result }
                return AnyView(
                    ContentView(initialSection: .telescope, models: FeatureModels(env: env, telescope: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            }
        }
        return [
            scene("telescope", dive: [], selected: "/Users/demo/Projects"),
            scene("telescope-dive", dive: ["Projects"], selected: "/Users/demo/Projects/ml-experiments"),
        ]
    }

    @MainActor
    private static var largeFilesScenes: [ScreenshotScene] {
        [
            ScreenshotScene(name: "largeFiles", size: CGSize(width: 1100, height: 720)) {
                let env = AppEnvironment.demo()
                let files = DemoLargeFileFinder.files().sorted { $0.size > $1.size }
                let selected = Set(files.filter { $0.url.lastPathComponent.hasSuffix(".iso") || $0.url.lastPathComponent.hasPrefix("Family") }.map(\.id))
                let model = LargeFilesViewModel(env: env, initialPhase: .results(files), initialSelection: selected) { _, _ in files }
                return AnyView(
                    ContentView(initialSection: .largeFiles, models: FeatureModels(env: env, largeFiles: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            }
        ]
    }

    @MainActor
    private static var duplicatesScenes: [ScreenshotScene] {
        [
            ScreenshotScene(name: "duplicates", size: CGSize(width: 1100, height: 720)) {
                let env = AppEnvironment.demo()
                let groups = DemoDuplicateFinder.groups().sorted { $0.wastedSpace > $1.wastedSpace }
                let model = DuplicatesViewModel(
                    env: env, initialPhase: .results(groups), initialSelection: DuplicateSelection.autoSelect(groups),
                    initialRefusal: groups[2].id, initialSkippedCloudOnly: 3) { _, _, _ in
                        DuplicateScan(groups: groups, skippedCloudOnly: 3)
                    }
                return AnyView(
                    ContentView(initialSection: .duplicates, models: FeatureModels(env: env, duplicates: model))
                        .environment(\.appEnvironment, env)
                        .environment(FullDiskAccess(isDemo: true)))
            }
        ]
    }
}
