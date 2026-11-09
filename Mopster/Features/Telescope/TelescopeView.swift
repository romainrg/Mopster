import MopsterCore
import SwiftUI

struct TelescopeView: View {
    @Bindable var model: TelescopeViewModel

    @ViewBuilder var body: some View {
        switch model.flow.phase {
        case .intro:
            VStack(spacing: 0) {
                header(canRescan: false)
                Divider()
                FeatureIntro(
                    symbol: "scope", title: "Telescope",
                    promise: "See what takes up your disk space.",
                    scope: "Scans a folder or volume and draws a map you can dive into. Nothing is changed until you move items to the Trash.",
                    action: model.scan)
            }
        case .scanning(let progress):
            FeatureScanning(progress: progress, cancel: model.flow.cancel)
        case .results:
            map
        case .removing:
            ProgressView("Moving to the Trash…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .done(let report):
            if model.showsReport {
                FeatureDone(report: report, onDone: model.dismissReport)
            } else {
                map
            }
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.orange)
                Text("The scan failed").font(.title2.bold())
                Text(message).foregroundStyle(.secondary)
                Button("Retry", action: model.scan).buttonStyle(.borderedProminent)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(canRescan: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive").foregroundStyle(.secondary)
            Text(verbatim: (model.displayedRoot.path as NSString).abbreviatingWithTildeInPath)
                .font(.callout.monospaced())
                .lineLimit(1).truncationMode(.middle)
            Button("Choose…", action: model.choose).controlSize(.small)
            Spacer(minLength: 8)
            if !model.skipped.isEmpty {
                Label("Some folders couldn't be read.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help(model.skipped.prefix(20).map(\.path).joined(separator: "\n"))
            }
            if canRescan { Button("Rescan", action: model.scan).controlSize(.small) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var map: some View {
        let items = model.items
        return VStack(spacing: 0) {
            header(canRescan: true)
            Divider()
            breadcrumb
            HStack(spacing: 0) {
                TreemapView(
                    items: items, selection: model.selection, hoveredID: $model.hoveredID, onTap: tap,
                    onIgnore: model.ignore
                )
                .padding(10)
                Divider()
                sideList(items).frame(width: 320)
            }
            Divider()
            footer
        }
        .confirmationDialog(confirmationTitle, isPresented: $model.confirmingRemoval, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive, action: model.moveToTrash)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore them from the Trash until you empty it.")
        }
    }

    private func tap(_ item: TelescopeItem) {
        if item.isDiveable { model.dive(into: item) } else { model.toggle(item) }
    }

    private var confirmationTitle: LocalizedStringKey {
        let nodes = model.selectedNodes
        if nodes.count == 1, let node = nodes.first { return "Move “\(TelescopeViewModel.displayName(node))” to the Trash?" }
        return "Move \(nodes.count) items to the Trash?"
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.path.enumerated()), id: \.offset) { index, node in
                if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                if index == model.path.count - 1 {
                    Text(verbatim: node.name).font(.callout.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                } else {
                    Button { model.climb(to: index) } label: {
                        Text(verbatim: node.name).lineLimit(1).truncationMode(.middle)
                    }
                    .buttonStyle(.link)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: Formatting.bytes(model.currentSize)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func sideList(_ items: [TelescopeItem]) -> some View {
        let largest = max(1, items.first?.size ?? 1)
        return List(items) { item in
            TelescopeRow(
                item: item, fraction: Double(item.size) / Double(largest),
                isOn: Binding(get: { model.selection.contains(item.id) }, set: { _ in model.toggle(item) }),
                onDive: { model.dive(into: item) })
                .telescopeContextMenu(item: item, onIgnore: model.ignore)
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            if model.selectedNodes.isEmpty {
                Text("Nothing selected").foregroundStyle(.secondary)
            } else {
                Text("\(Formatting.bytes(model.selectedSize)) selected").monospacedDigit()
            }
            Spacer()
            Button("Reveal in Finder", action: model.reveal).disabled(model.selectedNodes.isEmpty)
            Button("Move to Trash", action: model.requestRemoval)
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedNodes.isEmpty)
        }
        .padding(12)
    }
}

private struct TelescopeRow: View {
    let item: TelescopeItem
    let fraction: Double
    @Binding var isOn: Bool
    let onDive: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isOn) { Text(verbatim: item.name) }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!item.isSelectable)
                .help(item.isProtected ? Text("Mopster won’t move this folder to the Trash.") : Text(verbatim: ""))
            Image(systemName: item.kind.symbol).foregroundStyle(item.kind.color).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.name).lineLimit(1).truncationMode(.middle)
                GeometryReader { proxy in
                    Capsule().fill(item.kind.color.opacity(0.6))
                        .frame(width: max(2, proxy.size.width * fraction))
                }
                .frame(height: 4)
            }
            Text(verbatim: Formatting.bytes(item.size)).foregroundStyle(.secondary).monospacedDigit()
                .frame(minWidth: 62, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { if item.isDiveable { onDive() } }
    }
}
