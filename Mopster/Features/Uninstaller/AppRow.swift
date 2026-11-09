import AppKit
import MopsterCore
import SwiftUI

struct AppIcon: View {
    let url: URL
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .frame(width: size, height: size)
    }

    private var icon: NSImage {
        FileManager.default.fileExists(atPath: url.path)
            ? NSWorkspace.shared.icon(forFile: url.path)
            : NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

struct AppRow: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 10) {
            AppIcon(url: app.url)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: app.name).lineLimit(1)
                Text("\(app.version) · \(source) · \(lastUsed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if app.isLocked {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    .accessibilityLabel(Text("macOS protects this app."))
            }
            Text(Formatting.bytes(app.size)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
        .opacity(app.isLocked ? 0.5 : 1)
        .help(app.isLocked ? String(localized: "macOS protects this app.") : "")
    }

    private var source: String {
        app.isAppStore ? String(localized: "App Store") : String(localized: "Other source")
    }

    private var lastUsed: String {
        guard let date = app.lastUsed else { return String(localized: "Last used unknown") }
        let relative = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
        return String(localized: "Last used \(relative)")
    }
}
