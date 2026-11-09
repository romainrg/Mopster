import Foundation

public enum LeftoverLocations {
    public static let user = [
        "Library/Application Support", "Library/Caches", "Library/Preferences",
        "Library/Preferences/ByHost", "Library/Containers", "Library/Group Containers",
        "Library/Saved Application State", "Library/HTTPStorages", "Library/WebKit", "Library/Logs",
        "Library/Cookies", "Library/LaunchAgents", "Library/Application Scripts",
    ]
    public static let system = [
        "Library/Application Support", "Library/LaunchAgents", "Library/LaunchDaemons",
        "Library/PrivilegedHelperTools",
    ]
    public static let extras = ["com.apple.dt.Xcode": ["~/Library/Developer/Xcode"]]

    static let groupContainers = "Library/Group Containers"
    static let byHost = "Library/Preferences/ByHost"
    static let strippedSuffixes = [".plist", ".savedState", ".binarycookies"]

    static func normalized(_ name: String) -> String {
        for suffix in strippedSuffixes where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    static func isTeamID(_ text: Substring) -> Bool {
        text.count == 10 && text.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
    }

    /// The text after a leading `<TEAMID>.` (the whole first component is exactly 10 uppercase alphanumerics).
    static func droppingTeamID(_ text: String) -> String? {
        guard let dot = text.firstIndex(of: "."), isTeamID(text[..<dot]), text.index(after: dot) < text.endIndex
        else { return nil }
        return String(text[text.index(after: dot)...])
    }

    static func entries(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    static func abbreviated(_ path: String, home: URL) -> String {
        let homePath = home.standardizedFileURL.path
        guard path == homePath || path.hasPrefix(homePath + "/") else { return path }
        return "~" + path.dropFirst(homePath.count)
    }
}

public struct LeftoverFinder: Sendable {
    private let home: URL
    private let systemRoot: URL

    public init(home: URL, systemRoot: URL = URL(fileURLWithPath: "/")) {
        self.home = home
        self.systemRoot = systemRoot
    }

    /// `installed` is every installed app; entries another app claims at least as precisely are not offered.
    public func leftovers(for app: InstalledApp, among installed: [InstalledApp]) -> [CleanupItem] {
        let id = app.bundleID.lowercased()
        let name = app.name.lowercased()
        let canMatchName = app.name.count >= 4
        let others = installed.filter { $0.url.standardizedFileURL != app.url.standardizedFileURL }
        let sameIDCopyInstalled = others.contains { $0.bundleID.lowercased() == id }
        let sameNameInstalled = others.contains { $0.name.lowercased() == name }
        let longerIDs = others.map { $0.bundleID.lowercased() }.filter { $0.count > id.count }

        var found: [CleanupItem] = []
        func scan(_ folder: URL, relativeLocation: String) {
            guard !sameIDCopyInstalled else { return }
            for entry in LeftoverLocations.entries(in: folder) {
                let entryName = entry.lastPathComponent
                let byID = Self.matches(entryName, id: id, location: relativeLocation)
                let byName = canMatchName && entryName.lowercased() == name
                guard byID || byName else { continue }
                if longerIDs.contains(where: { Self.matches(entryName, id: $0, location: relativeLocation) }) { continue }
                if !byID && sameNameInstalled { continue }
                found.append(item(for: entry, in: folder, byID: byID))
            }
        }
        for location in LeftoverLocations.user {
            scan(home.appendingPathComponent(location, isDirectory: true), relativeLocation: location)
        }
        for location in LeftoverLocations.system {
            scan(systemRoot.appendingPathComponent(location, isDirectory: true), relativeLocation: "system/" + location)
        }
        if !sameIDCopyInstalled {
            for extra in LeftoverLocations.extras[app.bundleID] ?? [] {
                let url = expand(extra)
                if FileManager.default.fileExists(atPath: url.path) {
                    found.append(item(for: url, in: url.deletingLastPathComponent(), byID: false))
                }
            }
        }

        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }.sorted { $0.size > $1.size }
    }

    private static func matches(_ entry: String, id: String, location: String) -> Bool {
        func idForm(_ text: String) -> Bool { text == id || text.hasPrefix(id + ".") }
        let normalized = LeftoverLocations.normalized(entry).lowercased()
        if idForm(normalized) { return true }
        guard location == LeftoverLocations.groupContainers else { return false }
        func groupForm(_ text: String) -> Bool { idForm(text) || idForm(String(text.dropFirst("group.".count))) && text.hasPrefix("group.") }
        if groupForm(normalized) { return true }
        guard let rest = LeftoverLocations.droppingTeamID(LeftoverLocations.normalized(entry)) else { return false }
        return groupForm(rest.lowercased())
    }

    private func expand(_ path: String) -> URL {
        guard path.hasPrefix("~/") else { return URL(fileURLWithPath: path) }
        return home.appendingPathComponent(String(path.dropFirst(2)))
    }

    private func item(for url: URL, in folder: URL, byID: Bool) -> CleanupItem {
        CleanupItem(
            url: url, name: url.lastPathComponent,
            detail: LeftoverLocations.abbreviated(folder.standardizedFileURL.path, home: home),
            size: DiskUsage.allocatedSize(of: url), risk: byID ? .safe : .review, isSelectedByDefault: byID)
    }
}
