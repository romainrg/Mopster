import MopsterCore
import SwiftUI

struct UninstallerView: View {
    @Bindable var model: UninstallerViewModel

    @ViewBuilder var body: some View {
        switch model.flow.phase {
        case .intro:
            FeatureIntro(
                symbol: "xmark.app", tint: .uninstaller, title: "Uninstaller",
                promise: "Remove apps together with everything they leave behind.",
                scope: "Lists the apps in /Applications and ~/Applications, then looks for their files in your Library folders.",
                action: model.start)
        case .scanning(let progress):
            FeatureScanning(progress: progress, tint: .uninstaller, cancel: model.flow.cancel)
        case .results:
            results
        case .removing:
            ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let report):
            FeatureDone(report: report, onDone: model.finish)
        case .failed(let message):
            FeatureFailed(message: message, retry: model.start)
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            ModuleHeader(.uninstaller) {
                Picker("View", selection: $model.tab) {
                    Text("Applications").tag(UninstallerViewModel.Tab.applications)
                    Text("Leftovers").tag(UninstallerViewModel.Tab.leftovers)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
            }
            switch model.tab {
            case .applications: ApplicationsTab(model: model)
            case .leftovers: LeftoversTab(model: model)
            }
        }
        .onAppear { model.refreshRunning() }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
            titleVisibility: .visible, presenting: model.pending
        ) { action in
            Button("Move to Trash", role: .destructive) { model.confirm(action) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You can restore them from the Trash until you empty it.")
        }
    }

    private var dialogTitle: Text {
        let count = model.selectedLeftoverURLs.count
        switch model.pending {
        case .uninstall?:
            let name = model.selectedApp?.name ?? ""
            return count == 0
                ? Text("Move “\(name)” to the Trash?")
                : Text("Move “\(name)” and its leftovers (\(count)) to the Trash?")
        case .reset?:
            return Text("Move the leftovers of “\(model.selectedApp?.name ?? "")” (\(count)) to the Trash?")
        case .removeOrphans?:
            return Text("Move \(model.orphanSelection.urls(in: model.orphans).count) items to the Trash?")
        case nil:
            return Text(verbatim: "")
        }
    }
}

private struct ApplicationsTab: View {
    @Bindable var model: UninstallerViewModel

    var body: some View {
        HStack(spacing: 14) {
            appList
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
                .themeCard()
            Group {
                if let app = model.selectedApp {
                    AppDetail(model: model, app: app)
                } else {
                    Text("Select an app to see its leftovers.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .themeCard()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search apps", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                Picker("Sort by", selection: $model.sort) {
                    Text("Name").tag(UninstallerViewModel.SortKey.name)
                    Text("Size").tag(UninstallerViewModel.SortKey.size)
                    Text("Last used").tag(UninstallerViewModel.SortKey.lastUsed)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(10)
            List(
                selection: Binding(get: { model.selectedApp?.id }, set: { model.select($0) })
            ) {
                ForEach(model.visibleApps) { app in
                    AppRow(app: app)
                        .tag(app.id)
                        .selectionDisabled(app.isLocked)
                }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct AppDetail: View {
    @Environment(\.appEnvironment) private var env
    @Bindable var model: UninstallerViewModel
    let app: InstalledApp

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.selectedAppIsRunning { runningBanner }
            Divider()
            leftoverList
            Divider()
            actionBar
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIcon(url: app.url, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: app.name).font(.title2.bold()).lineLimit(1)
                Text(verbatim: app.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(verbatim: displayPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(Formatting.bytes(app.size)).font(.title3).monospacedDigit()
        }
        .padding(12)
    }

    private var displayPath: String {
        let home = env.home.standardizedFileURL.path
        return app.url.path.hasPrefix(home + "/") ? "~" + app.url.path.dropFirst(home.count) : app.url.path
    }

    private var runningBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Quit \(app.name) first")
            Spacer()
            Button("Quit", action: model.quitSelectedApp)
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }

    @ViewBuilder private var leftoverList: some View {
        if model.isLoadingLeftovers {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.leftovers.isEmpty {
            Text("No leftovers found.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            CleanupList(groups: model.leftovers, selection: $model.leftoverSelection)
                .scrollContentBackground(.hidden)
        }
    }

    private var actionBar: some View {
        HStack {
            Text("\(Formatting.bytes(model.leftoverSelection.totalSize(in: model.leftovers))) of leftovers selected")
                .monospacedDigit()
            Spacer()
            Button("Reset") { model.request(.reset) }
                .buttonStyle(.soft)
                .disabled(!model.canReset)
                .help("Move only the selected leftovers to the Trash and keep the app.")
            Button("Uninstall") { model.request(.uninstall) }
                .buttonStyle(.gradient)
                .disabled(!model.canAct)
                .help("Move the app and the selected leftovers to the Trash.")
        }
        .padding(12)
    }
}

private struct LeftoversTab: View {
    @Bindable var model: UninstallerViewModel

    var body: some View {
        if model.orphans.isEmpty {
            VStack(spacing: 10) {
                ModuleIcon(symbol: "checkmark", tint: .junk, size: 56)
                Text("No leftovers found").font(.title3.bold())
                Text("Every app folder in your Library belongs to an installed app.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Formatting.bytes(model.totalOrphanSize)) found").font(.headline).monospacedDigit()
                    Text("Files left by apps that are no longer installed. Nothing is selected: review each group first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                CleanupResultsView(
                    groups: model.orphans, selection: $model.orphanSelection,
                    onRemove: { model.request(.removeOrphans) }, showsNotes: true)
            }
        }
    }
}
