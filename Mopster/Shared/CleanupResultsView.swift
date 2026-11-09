import MopsterCore
import SwiftUI

struct CleanupResultsView: View {
    let groups: [CleanupGroup]
    @Binding var selection: Selection
    let onRemove: () -> Void
    var onIgnore: ((CleanupItem) -> Void)?
    /// Shows each group's explanation as a note under its header, not only as a tooltip.
    var showsNotes = false

    var body: some View {
        VStack(spacing: 0) {
            CleanupList(groups: groups, selection: $selection, onIgnore: onIgnore, showsNotes: showsNotes)
            Divider()
            HStack {
                Text("\(Formatting.bytes(selection.totalSize(in: groups))) selected")
                    .monospacedDigit()
                Spacer()
                Button("Move to Trash", action: onRemove)
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.urls(in: groups).isEmpty)
            }
            .padding(12)
        }
    }
}

/// The grouped checklist alone, for screens that bring their own action bar.
struct CleanupList: View {
    let groups: [CleanupGroup]
    @Binding var selection: Selection
    var onIgnore: ((CleanupItem) -> Void)?
    var showsNotes = false

    var body: some View {
        List {
            ForEach(groups) { group in
                Section {
                    if showsNotes, let note = group.explanation {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(group.items) { item in
                        ItemRow(item: item, isOn: itemBinding(item))
                            .itemContextMenu(url: item.url, onIgnore: onIgnore.map { handler in { handler(item) } })
                    }
                } header: {
                    GroupHeader(group: group, state: selection.state(of: group)) { on in
                        selection.setAll(in: group, on)
                    }
                }
            }
        }
    }

    private func itemBinding(_ item: CleanupItem) -> Binding<Bool> {
        Binding(
            get: { selection.contains(item.id) },
            set: { _ in selection.toggle(item.id) })
    }
}

private struct GroupHeader: View {
    let group: CleanupGroup
    let state: GroupState
    let setAll: (Bool) -> Void

    var body: some View {
        HStack {
            Button {
                setAll(state != .all)
            } label: {
                Image(systemName: symbolName)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(group.title))
            Image(systemName: group.symbol).foregroundStyle(.tint)
            Text(group.title).font(.headline).foregroundStyle(.primary)
            if group.risk == .review {
                Text("Review")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text(Formatting.bytes(group.totalSize)).foregroundStyle(.secondary).monospacedDigit()
        }
        .help(group.explanation.map { String(localized: $0) } ?? "")
    }

    private var symbolName: String {
        switch state {
        case .none: "square"
        case .some: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }
}

private struct ItemRow: View {
    let item: CleanupItem
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack {
                VStack(alignment: .leading) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if let detail = item.detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Text(Formatting.bytes(item.size)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .toggleStyle(.checkbox)
        .padding(.leading, 20)
    }
}

#Preview("Results") {
    @Previewable @State var selection: Selection = {
        Selection(defaultsFrom: sampleGroups)
    }()
    CleanupResultsView(groups: sampleGroups, selection: $selection, onRemove: {})
        .frame(width: 560, height: 400)
}

private let sampleGroups: [CleanupGroup] = [
    CleanupGroup(
        id: "caches", title: L("App caches", "App caches"),
        explanation: L("Safe to rebuild", "Safe to rebuild"), symbol: "internaldrive",
        items: [
            CleanupItem(url: URL(fileURLWithPath: "/tmp/a"), name: "Cache A", detail: "~/Library/Caches", size: 5_000_000),
            CleanupItem(url: URL(fileURLWithPath: "/tmp/b"), name: "Cache B", size: 9_000_000),
        ]),
    CleanupGroup(
        id: "dl", title: L("Installers", "Installers"), symbol: "shippingbox", risk: .review,
        items: [
            CleanupItem(
                url: URL(fileURLWithPath: "/tmp/c.dmg"), name: "c.dmg", size: 80_000_000, risk: .review,
                isSelectedByDefault: false)
        ]),
]
