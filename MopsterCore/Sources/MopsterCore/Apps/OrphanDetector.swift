import Foundation

public struct OrphanDetector: Sendable {
    private let home: URL
    private let installed: [String]
    private let installedApps: [(bundleID: String, name: String)]
    private let isKnownToLaunchServices: @Sendable (String) -> Bool

    private static let bundleIDPattern = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+){2,}$"#)
    private static let uuidOrHex = try! NSRegularExpression(
        pattern: #"^([0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}|[0-9A-Fa-f]{12,})$"#)
    /// Prefixes of ids that are never an app's leftovers; extendable. `homebrew.` names brew services agents
    /// (non-app tooling), the others are owned by the system.
    public static var systemPrefixes: [String] { ["com.apple.", "is.workflow.", "homebrew."] }
    private static let containerPrefixes = ["group.", "groups.", "systemgroup."]
    /// Second-level prefixes where two components say nothing about the developer.
    private static let hostingNamespaces: Set<String> = [
        "com.github", "io.github", "com.gitlab", "io.gitlab", "org.sourceforge", "net.sourceforge",
    ]
    private static let logsLocation = "Library/Logs"
    private static let ownID = "io.github.romainrg.Mopster"

    public init(
        home: URL, installedApps: [(bundleID: String, name: String)],
        isKnownToLaunchServices: @escaping @Sendable (String) -> Bool
    ) {
        self.home = home
        self.installedApps = installedApps
        self.installed = installedApps.map { $0.bundleID.lowercased() }
        self.isKnownToLaunchServices = isKnownToLaunchServices
    }

    public func orphans() -> [CleanupGroup] {
        var byID: [String: (id: String, items: [CleanupItem])] = [:]
        for location in LeftoverLocations.user {
            let folder = home.appendingPathComponent(location, isDirectory: true)
            let detail = LeftoverLocations.abbreviated(folder.standardizedFileURL.path, home: home)
            for entry in LeftoverLocations.entries(in: folder).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let id = candidateID(entry.lastPathComponent, location: location), !isClaimed(id) else { continue }
                let item = CleanupItem(
                    url: entry, name: entry.lastPathComponent, detail: detail,
                    size: DiskUsage.allocatedSize(of: entry), risk: .review, isSelectedByDefault: false)
                byID[id.lowercased(), default: (id, [])].items.append(item)
            }
        }
        return byID.values.map { group in
            CleanupGroup(
                id: group.id, title: LocalizedStringResource(stringLiteral: group.id),
                explanation: sharedVendorNote(for: group.id),
                symbol: "questionmark.app", risk: .review, items: group.items.sorted { $0.size > $1.size })
        }.sorted { ($0.totalSize, $1.id) > ($1.totalSize, $0.id) }
    }

    private func isLogNoise(_ entry: String) -> Bool {
        let parts = entry.split(separator: ".")
        return parts.contains("log") || parts.count > 1 && parts.last.map { $0.allSatisfy(\.isNumber) } == true
    }

    private func candidateID(_ entry: String, location: String) -> String? {
        if location == Self.logsLocation, isLogNoise(entry) { return nil }
        var id = LeftoverLocations.normalized(entry)
        if location == LeftoverLocations.byHost, let dot = id.lastIndex(of: ".") {
            let tail = String(id[id.index(after: dot)...])
            if matches(Self.uuidOrHex, tail) { id = String(id[..<dot]) }
        }
        var changed = true
        while changed {
            changed = false
            if let rest = LeftoverLocations.droppingTeamID(id) {
                id = rest
                changed = true
            }
            if let prefix = Self.containerPrefixes.first(where: { id.hasPrefix($0) }) {
                id.removeFirst(prefix.count)
                changed = true
            }
        }
        guard matches(Self.bundleIDPattern, id) else { return nil }
        let lower = id.lowercased()
        if Self.systemPrefixes.contains(where: { lower.hasPrefix($0.lowercased()) }) { return nil }
        if lower == Self.ownID.lowercased() || lower.hasPrefix(Self.ownID.lowercased() + ".") { return nil }
        return id
    }

    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func sharedVendorNote(for id: String) -> LocalizedStringResource? {
        guard let vendor = vendorPrefix(id), !Self.hostingNamespaces.contains(vendor),
            let app = installedApps.first(where: { vendorPrefix($0.bundleID) == vendor })
        else { return nil }
        return Self.sharedVendorNote(appName: app.name)
    }

    public static func sharedVendorNote(appName: String) -> LocalizedStringResource {
        L("orphans.sharedVendor", "Another app from the same developer is installed: \(appName). Check before removing.")
    }

    private func vendorPrefix(_ id: String) -> String? {
        let parts = id.lowercased().split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 ? parts.prefix(2).joined(separator: ".") : nil
    }

    private func isClaimed(_ id: String) -> Bool {
        let lower = id.lowercased()
        for app in installed where app == lower || lower.hasPrefix(app + ".") || app.hasPrefix(lower + ".") {
            return true
        }
        return isKnownToLaunchServices(id)
    }
}
