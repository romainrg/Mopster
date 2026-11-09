import CoreServices
import Foundation

public struct AppInventory: Sendable {
    private let roots: [URL]
    private let systemPrefix: String

    public init(roots: [URL], systemPrefix: String = "/System/") {
        self.roots = roots
        self.systemPrefix = systemPrefix
    }

    public func apps() -> [InstalledApp] {
        roots.flatMap(bundleURLs).compactMap(app(at:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func entries(of folder: URL) -> [URL] {
        // No `.skipsHiddenFiles`: Safari's symlink in /Applications carries the `hidden` flag.
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    private func bundleURLs(in root: URL) -> [URL] {
        var bundles: [URL] = []
        for entry in entries(of: root) {
            if entry.pathExtension == "app" {
                bundles.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                bundles += entries(of: entry).filter { $0.pathExtension == "app" }
            }
        }
        return bundles
    }

    private func app(at url: URL) -> InstalledApp? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty
        else { return nil }
        let resolved = Self.realPath(url)
        let name =
            (info["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(
            url: url,
            bundleID: bundleID,
            name: name,
            version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            isAppStore: FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path),
            sparkleFeed: (info["SUFeedURL"] as? String).flatMap(URL.init(string:)),
            minimumSystemVersion: info["LSMinimumSystemVersion"] as? String,
            isLocked: resolved.hasPrefix(systemPrefix),
            size: DiskUsage.allocatedSize(of: URL(fileURLWithPath: resolved)),
            lastUsed: Self.lastUsed(of: url))
    }

    static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func lastUsed(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
