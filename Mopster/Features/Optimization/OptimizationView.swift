import AppKit
import MopsterCore
import SwiftUI

struct OptimizationView: View {
    @Bindable var model: OptimizationViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                Section {
                    ForEach(model.topProcesses) { process in
                        ProcessRow(
                            process: process, canQuit: model.canQuit(process),
                            quit: { model.pending = .quit(process) },
                            forceQuit: { model.pending = .forceQuit(process) })
                    }
                } header: {
                    processesHeader
                }
                Section {
                    ForEach(model.backgroundItems) { item in
                        BackgroundItemRow(
                            item: item, isBusy: model.busyItemID == item.id, canToggle: model.canToggle(item),
                            toggle: { model.requestToggle(item) })
                    }
                } header: {
                    HStack {
                        Text("Background items")
                        Spacer()
                        Button("Refresh", action: model.loadBackgroundItems).controlSize(.small)
                    }
                } footer: {
                    HStack {
                        Text("Apps that open at login are managed by macOS.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Login Items…") { SystemSettings.open(.loginItems) }.controlSize(.small)
                    }
                    .padding(.top, 6)
                }
            }
            .themePanel()
            .padding(.bottom, 24)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .confirmationDialog(
            dialogTitle, isPresented: Binding(get: { model.pending != nil }, set: { if !$0 { model.pending = nil } }),
            titleVisibility: .visible, presenting: model.pending
        ) { action in
            switch action {
            case .quit: Button("Quit") { model.confirm(action) }
            case .forceQuit: Button("Force Quit", role: .destructive) { model.confirm(action) }
            case .disable: Button("Disable") { model.confirm(action) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            switch action {
            case .quit: Text("The app is asked to close and can offer to save your work.")
            case .forceQuit: Text("Unsaved changes in this process will be lost.")
            case .disable: Text("It stops running now and stays off until you enable it again.")
            }
        }
        .alert(
            "That didn't work",
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
        ) {
            Button("OK") { model.actionError = nil }
        } message: {
            Text(verbatim: model.actionError ?? "")
        }
    }

    private var dialogTitle: Text {
        switch model.pending {
        case .quit(let process)?: Text("Quit “\(process.name)”?")
        case .forceQuit(let process)?: Text("Force quit “\(process.name)”?")
        case .disable(let item)?: Text("Disable “\(OptimizationViewModel.name(of: item))”?")
        case nil: Text(verbatim: "")
        }
    }

    private var header: some View {
        ModuleHeader(.optimization) {
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory pressure").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Circle().fill(pressureColor).frame(width: 10, height: 10)
                        Text(pressureText).font(.title3.weight(.semibold))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU load").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(model.load.cpuLoad, format: .percent.precision(.fractionLength(0)))
                            .font(.title3.weight(.semibold)).monospacedDigit()
                        ProgressView(value: min(max(model.load.cpuLoad, 0), 1))
                            .tint(ModuleTint.optimization.end)
                            .frame(width: 120)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var pressureText: LocalizedStringKey {
        switch model.load.memoryPressure {
        case .normal: "Normal"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }

    private var pressureColor: LinearGradient {
        switch model.load.memoryPressure {
        case .normal: ModuleTint.junk.gradient
        case .warning, .critical: ModuleTint.updater.gradient
        }
    }

    private var processesHeader: some View {
        HStack(spacing: 10) {
            Text("Processes")
            Spacer()
            Picker("Sort by", selection: $model.sort) {
                Text("CPU").tag(OptimizationViewModel.SortKey.cpu)
                Text("Memory").tag(OptimizationViewModel.SortKey.memory)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
        }
    }
}

private struct ProcessRow: View {
    let process: ProcessSample
    let canQuit: Bool
    let quit: () -> Void
    let forceQuit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 22, height: 22)
            Text(process.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(process.cpuPercent / 100, format: .percent.precision(.fractionLength(1)))
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)
            Text(Formatting.bytes(Int64(clamping: process.memoryBytes)))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            HStack(spacing: 6) {
                if canQuit {
                    Button("Quit", action: quit)
                    Button("Force Quit", action: forceQuit)
                }
            }
            .controlSize(.small)
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, 1)
        .help(process.path ?? process.name)
    }

    @ViewBuilder private var icon: some View {
        if let url = process.bundleURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
        } else {
            Image(systemName: "gearshape").foregroundStyle(.secondary)
        }
    }
}

private struct BackgroundItemRow: View {
    let item: InspectedLaunchItem
    let isBusy: Bool
    let canToggle: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(OptimizationViewModel.name(of: item)).lineLimit(1).truncationMode(.middle)
                    if item.isDisabled { Chip(text: "Disabled") }
                }
                Text(domainTitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView().controlSize(.small)
            } else if canToggle {
                Button(item.isDisabled ? "Enable" : "Disable", action: toggle).controlSize(.small)
            }
        }
        .padding(.vertical, 1)
        .help(item.item.plist.path)
    }

    private var domainTitle: LocalizedStringKey {
        switch item.item.domain {
        case .userAgents: "Your agents"
        case .systemAgents: "All users' agents"
        case .systemDaemons: "System daemons"
        }
    }
}
