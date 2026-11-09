import MopsterCore
import SwiftUI

struct MaintenanceView: View {
    @Bindable var model: MaintenanceViewModel

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(.maintenance)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.tasks) { task in
                        MaintenanceRow(
                        task: task,
                        isSelected: Binding(get: { model.isSelected(task) }, set: { model.setSelected(task, $0) }),
                        lastRun: model.lastRuns[task.id], status: model.statuses[task.id], output: model.output(for: task),
                            isEnabled: !model.isRunning)
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .themePanel()
            footer
        }
    }

    private var footer: some View {
        ModuleFooter {
            Text("Administrator tasks ask for your password once.")
                .font(.caption).foregroundStyle(.secondary)
        } actions: {
            Button("Run selected") { Task { await model.runSelected() } }
                .buttonStyle(.gradient(.maintenance))
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canRun)
        }
    }
}

private struct MaintenanceRow: View {
    let task: MaintenanceTask
    @Binding var isSelected: Bool
    let lastRun: Date?
    let status: MaintenanceViewModel.Status?
    let output: String?
    let isEnabled: Bool
    @State private var userExpanded: Bool?

    private var isFailed: Bool {
        if case .finished(.failed)? = status { return true }
        return false
    }

    private var expanded: Bool { userExpanded ?? isFailed }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: $isSelected) { Text(task.title) }
                .labelsHidden()
                .disabled(!isEnabled)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(task.title).fontWeight(.medium)
                    if task.needsAdmin { Chip(text: "Administrator") }
                    if task.restartAdvised { Chip(text: "Restart advised") }
                }
                Text(task.explanation).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                lastRunText.font(.caption).foregroundStyle(.tertiary)
                if let output {
                    Button {
                        userExpanded = !(userExpanded ?? isFailed)
                    } label: {
                        Label("Output", systemImage: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    if expanded {
                        Text(verbatim: output)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Spacer(minLength: 8)
            statusView.frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var lastRunText: Text {
        if let lastRun, abs(lastRun.timeIntervalSinceNow) < 60 { return Text("Last run just now") }
        if let lastRun {
            let relative = lastRun.formatted(.relative(presentation: .numeric))
            return Text("Last run \(relative)")
        }
        return Text("Never run")
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .running?:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Running").font(.caption).foregroundStyle(.secondary)
            }
        case .finished(.succeeded)?:
            Label("Succeeded", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .finished(.failed)?:
            Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
        case .finished(.cancelled)?:
            Label("Cancelled", systemImage: "slash.circle").foregroundStyle(.secondary).font(.caption)
        case nil:
            EmptyView()
        }
    }
}
