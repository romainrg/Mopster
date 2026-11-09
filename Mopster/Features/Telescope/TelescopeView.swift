import MopsterCore
import SwiftUI

struct TelescopeView: View {
    @Bindable var model: TelescopeViewModel

    @ViewBuilder var body: some View {
        switch model.flow.phase {
        case .intro:
            VStack(spacing: 0) {
                pathRow
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                FeatureIntro(
                symbol: "scope", tint: .telescope, title: "Telescope",
                    promise: "See what takes up your disk space.",
                    scope: "Scans a folder or volume and draws a map you can dive into. Nothing is changed until you move items to the Trash.",
                    action: model.scan)
            }
        case .scanning(let progress):
            FeatureScanning(progress: progress, tint: .telescope, cancel: model.flow.cancel)
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
            FeatureFailed(message: message, retry: model.scan)
        }
    }

    private var rootPath: String {
        (model.displayedRoot.path as NSString).abbreviatingWithTildeInPath
    }

    private var pathRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive").foregroundStyle(.secondary)
            Text(verbatim: rootPath)
                .font(.callout.monospaced())
                .lineLimit(1).truncationMode(.middle)
            Button("Choose…", action: model.choose).buttonStyle(.soft).controlSize(.small)
            Spacer(minLength: 8)
        }
    }

    private var header: some View {
        ModuleHeader(.telescope, subtitle: Text(verbatim: rootPath)) {
            if !model.skipped.isEmpty {
                Label("Some folders couldn't be read.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help(model.skipped.prefix(20).map(\.path).joined(separator: "\n"))
            }
            Button("Choose…", action: model.choose).buttonStyle(.soft)
            Button("Rescan", action: model.scan).buttonStyle(.soft)
        }
    }

    private var map: some View {
        let items = model.items
        return VStack(spacing: 0) {
            header
            breadcrumb
            HStack(spacing: 14) {
                TreemapView(
                    items: items, selection: model.selection, hoveredID: $model.hoveredID, onTap: tap,
                    onIgnore: model.ignore
                )
                .padding(10)
                .themeCard()
                sideList(items)
                    .scrollContentBackground(.hidden)
                    .themeCard()
                    .frame(width: 320)
            }
            .padding(.horizontal, 24)
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
        .padding(.horizontal, 24).padding(.bottom, 10)
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
        ModuleFooter {
            if model.selectedNodes.isEmpty {
                Text("Nothing selected").foregroundStyle(.secondary)
            } else {
                Text("\(Formatting.bytes(model.selectedSize)) selected").monospacedDigit()
            }
        } actions: {
            Button("Reveal in Finder", action: model.reveal).buttonStyle(.soft).disabled(model.selectedNodes.isEmpty)
            Button("Move to Trash", action: model.requestRemoval)
                .buttonStyle(.gradient)
                .disabled(model.selectedNodes.isEmpty)
        }
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
