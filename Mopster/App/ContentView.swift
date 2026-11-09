import SwiftUI

struct ContentView: View {
    @Environment(\.appEnvironment) private var env
    @Environment(FullDiskAccess.self) private var fullDiskAccess
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var selection: SidebarSection?
    @State private var showOnboarding = false

    @State private var models: FeatureModels?

    /// `models` lets previews and screenshot scenes start a screen in a given phase.
    init(initialSection: SidebarSection = .smartSweep, models: FeatureModels? = nil) {
        _models = State(initialValue: models)
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarGroup.allCases) { group in
                    if let title = group.title {
                        Section(title) { rows(for: group) }
                    } else {
                        Section { rows(for: group) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { accessFooter }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.ground.ignoresSafeArea())
        }
        .toolbar {
            if env.isDemo {
                ToolbarItem { Text("Demo").font(.caption.bold()).foregroundStyle(.orange) }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                hasSeenOnboarding = true
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            if models == nil {
                let selection = $selection
                models = FeatureModels(env: env, navigate: { selection.wrappedValue = $0 })
            }
            showOnboarding = !env.isDemo && !hasSeenOnboarding
        }
        .onChange(of: hasSeenOnboarding) { _, seen in
            if !seen && !env.isDemo { showOnboarding = true }
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .smartSweep:
            if let models { SmartSweepView(model: models.smartSweep) }
        case .systemJunk:
            if let models { SystemJunkView(model: models.systemJunk) }
        case .protection:
            if let models { ProtectionView(model: models.protection) }
        case .optimization:
            if let models { OptimizationView(model: models.optimization) }
        case .maintenance:
            if let models { MaintenanceView(model: models.maintenance) }
        case .uninstaller:
            if let models { UninstallerView(model: models.uninstaller) }
        case .updater:
            if let models { UpdaterView(model: models.updater) }
        case .telescope:
            if let models { TelescopeView(model: models.telescope) }
        case .largeFiles:
            if let models { LargeFilesView(model: models.largeFiles) }
        case .duplicates:
            if let models { DuplicatesView(model: models.duplicates) }
        case let selection?:
            Text(selection.title)
                .font(.largeTitle)
        case nil:
            EmptyView()
        }
    }

    private var accessFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                Circle()
                    .fill(fullDiskAccess.isGranted ? ModuleTint.junk.gradient : ModuleTint.updater.gradient)
                    .frame(width: 8, height: 8)
                Text(fullDiskAccess.isGranted ? "Full Disk Access: Granted" : "Full Disk Access: Not granted")
                    .font(.caption)
                Spacer()
            }
            if !fullDiskAccess.isGranted {
                Button("Grant access") { SystemSettings.open(.fullDiskAccess) }
                    .controlSize(.small)
            }
        }
        .padding([.horizontal, .bottom], 12)
    }

    private func rows(for group: SidebarGroup) -> some View {
        ForEach(group.sections) { section in
            HStack(spacing: 10) {
                ModuleIcon(symbol: section.symbol, tint: section.tint)
                Text(section.title)
            }
            .tag(section)
        }
    }
}
