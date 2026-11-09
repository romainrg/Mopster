import AppKit
import SwiftUI

struct ItemContextMenu: ViewModifier {
    let url: URL
    let onIgnore: (() -> Void)?

    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Quick Look") { QuickLook.shared.preview(url) }
            if let onIgnore {
                Divider()
                Button("Always ignore", action: onIgnore)
            }
        }
    }
}

extension View {
    func itemContextMenu(url: URL, onIgnore: (() -> Void)? = nil) -> some View {
        modifier(ItemContextMenu(url: url, onIgnore: onIgnore))
    }
}
