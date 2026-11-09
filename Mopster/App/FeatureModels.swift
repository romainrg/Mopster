import Observation

/// Holds every module's view model so state survives sidebar navigation; each module adds its model here.
@MainActor @Observable
final class FeatureModels {
    let systemJunk: SystemJunkViewModel
    let protection: ProtectionViewModel
    let optimization: OptimizationViewModel
    let maintenance: MaintenanceViewModel
    let uninstaller: UninstallerViewModel
    let updater: UpdaterViewModel
    let telescope: TelescopeViewModel
    let largeFiles: LargeFilesViewModel
    let duplicates: DuplicatesViewModel
    let smartSweep: SmartSweepViewModel

    init(env: AppEnvironment, systemJunk: SystemJunkViewModel? = nil, protection: ProtectionViewModel? = nil,
         optimization: OptimizationViewModel? = nil, maintenance: MaintenanceViewModel? = nil,
         uninstaller: UninstallerViewModel? = nil, updater: UpdaterViewModel? = nil,
         telescope: TelescopeViewModel? = nil, largeFiles: LargeFilesViewModel? = nil,
         duplicates: DuplicatesViewModel? = nil, smartSweep: SmartSweepViewModel? = nil,
         navigate: @escaping (SidebarSection) -> Void = { _ in }) {
        self.systemJunk = systemJunk ?? SystemJunkViewModel(env: env)
        self.protection = protection ?? ProtectionViewModel(env: env)
        self.optimization = optimization ?? OptimizationViewModel(env: env)
        self.maintenance = maintenance ?? MaintenanceViewModel(env: env)
        self.uninstaller = uninstaller ?? UninstallerViewModel(env: env)
        self.updater = updater ?? UpdaterViewModel(env: env)
        self.telescope = telescope ?? TelescopeViewModel(env: env)
        self.largeFiles = largeFiles ?? LargeFilesViewModel(env: env)
        self.duplicates = duplicates ?? DuplicatesViewModel(env: env)
        self.smartSweep = smartSweep ?? SmartSweepViewModel(env: env, navigate: navigate)
    }
}
