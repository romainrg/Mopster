import MopsterCore
import SwiftUI

extension TelescopeItem.Kind {
    var color: Color {
        switch self {
        case .folder: Color(nsColor: .systemBlue)
        case .media: Color(nsColor: .systemPurple)
        case .archive: Color(nsColor: .systemOrange)
        case .application: Color(nsColor: .systemGreen)
        case .file: Color(nsColor: .systemTeal)
        case .aggregate, .smaller: Color(nsColor: .systemGray)
        }
    }

    var symbol: String {
        switch self {
        case .folder: "folder.fill"
        case .media: "play.rectangle.fill"
        case .archive: "archivebox.fill"
        case .application: "app.fill"
        case .file: "doc.fill"
        case .aggregate: "doc.on.doc.fill"
        case .smaller: "square.grid.3x3.fill"
        }
    }
}

struct TreemapView: View {
    let items: [TelescopeItem]
    let selection: Set<String>
    @Binding var hoveredID: String?
    let onTap: (TelescopeItem) -> Void
    let onIgnore: (TelescopeItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let rects = Treemap.squarify(items.map { Double($0.size) }, in: bounds)
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let rect = rects[index].insetBy(dx: 0.75, dy: 0.75)
                    if rect.width >= 2, rect.height >= 2 {
                        Tile(item: item, size: rect.size, isSelected: selection.contains(item.id))
                            .offset(x: rect.minX, y: rect.minY)
                            .onHover { inside in
                                if inside { hoveredID = item.id } else if hoveredID == item.id { hoveredID = nil }
                            }
                            .onTapGesture { onTap(item) }
                            .telescopeContextMenu(item: item, onIgnore: onIgnore)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .overlay(alignment: .bottomLeading) {
                if let hovered = items.first(where: { $0.id == hoveredID }) {
                    HoverDetails(item: hovered).padding(8).allowsHitTesting(false)
                }
            }
        }
    }
}

private struct Tile: View {
    let item: TelescopeItem
    let size: CGSize
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(item.kind.color.opacity(item.kind == .smaller || item.kind == .aggregate ? 0.22 : 0.34))
            shape.strokeBorder(item.kind.color.opacity(0.7), lineWidth: 0.75)
            if size.width >= 60, size.height >= 30 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.name).font(.caption.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    Text(verbatim: Formatting.bytes(item.size)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
                .frame(width: size.width, alignment: .leading)
            }
            if isSelected {
                shape.strokeBorder(Color.accentColor, lineWidth: 3)
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(4)
                    .frame(width: size.width, height: size.height, alignment: .bottomTrailing)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(shape)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.name), \(Formatting.bytes(item.size))"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct HoverDetails: View {
    let item: TelescopeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: item.name).font(.callout.weight(.semibold)).lineLimit(1)
            Text(verbatim: Formatting.bytes(item.size)).font(.caption).monospacedDigit()
            if let url = item.url {
                Text(verbatim: (url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(8)
        .frame(maxWidth: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
    }
}

extension View {
    @ViewBuilder func telescopeContextMenu(item: TelescopeItem, onIgnore: @escaping (TelescopeItem) -> Void) -> some View {
        if let url = item.url, item.isSelectable {
            itemContextMenu(url: url, onIgnore: { onIgnore(item) })
        } else {
            self
        }
    }
}
