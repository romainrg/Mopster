import Darwin
import Foundation

public struct JunkScanResult: Sendable {
    public var groups: [CleanupGroup]
    public var skipped: [URL]
    public var trashSize: Int64?

    public init(groups: [CleanupGroup], skipped: [URL], trashSize: Int64?) {
        self.groups = groups
        self.skipped = skipped
        self.trashSize = trashSize
    }
}

public protocol JunkScanning: Sendable {
    func scan(progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> JunkScanResult
}

public struct JunkScanner: JunkScanning {
    private let rules: [JunkRule]
    private let home: URL
    private let ignore: IgnoreList
    private let now: Date

    public init(rules: [JunkRule] = JunkCatalog.rules, home: URL, ignore: IgnoreList, now: Date = .now) {
        self.rules = rules
        self.home = home.standardizedFileURL
        self.ignore = ignore
        self.now = now
    }

    public func scan(progress: @escaping @Sendable (ScanProgress) -> Void) async throws -> JunkScanResult {
        var state = State(claimed: ignore.paths.map { Self.components(URL(fileURLWithPath: $0)) })
        var groups: [CleanupGroup] = []
        var found = 0

        for (index, rule) in rules.enumerated() {
            try Task.checkCancellation()
            progress(
                ScanProgress(
                    location: rule.locations.first, fraction: Double(index) / Double(rules.count), itemsFound: found))
            noteUnreadableLocations(of: rule, state: &state)

            var items: [CleanupItem] = []
            for candidate in expand(rule) {
                try Task.checkCancellation()
                for piece in subtract(candidate, state: &state) {
                    state.claimed.append(Self.components(piece))
                    items.append(makeItem(piece, rule: rule))
                }
            }
            guard !items.isEmpty else { continue }
            found += items.count
            items.sort { ($0.size, $1.id) > ($1.size, $0.id) }
            groups.append(
                CleanupGroup(
                    id: rule.id, title: rule.title, explanation: rule.explanation, symbol: rule.symbol,
                    risk: rule.risk, items: items))
        }
        return JunkScanResult(groups: groups, skipped: state.skipped, trashSize: trashSize())
    }

    private struct State {
        var claimed: [[String]]
        var skipped: [URL] = []
        var skippedPaths: Set<String> = []
        var probed: Set<String> = []

        /// Records an unreadable folder once and claims it, so no general rule lists it as a whole.
        mutating func markUnreadable(_ url: URL) {
            guard skippedPaths.insert(url.path).inserted else { return }
            skipped.append(url)
            claimed.append(JunkScanner.components(url))
        }
    }

    private static func components(_ url: URL) -> [String] {
        PathComponents.literal(url.standardizedFileURL)
    }

    // MARK: Expansion and filters

    private func expand(_ rule: JunkRule) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for location in rule.locations {
            for url in PathPattern.expand(location, home: home, followingSymlinkedFolders: false) where seen.insert(url.path).inserted {
                if isFilteredOut(url, by: rule) { continue }
                result.append(url)
            }
        }
        return result
    }

    private func isFilteredOut(_ url: URL, by rule: JunkRule) -> Bool {
        if rule.exclusions.contains(where: { PathPattern.matches(url, pattern: $0, home: home) }) { return true }
        if let extensions = rule.extensions, !extensions.contains(url.pathExtension.lowercased()) { return true }
        if let minAge = rule.minAge,
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            now.timeIntervalSince(modified) < minAge
        {
            return true
        }
        return false
    }

    // MARK: Overlap resolution

    private func subtract(_ item: URL, state: inout State) -> [URL] {
        let path = Self.components(item)
        if state.claimed.contains(where: { path.starts(with: $0) }) { return [] }
        if !state.claimed.contains(where: { $0.count > path.count && $0.starts(with: path) }) { return [item] }
        return children(of: item, state: &state).flatMap { subtract($0, state: &state) }
    }

    private func children(of directory: URL, state: inout State) -> [URL] {
        var info = stat()
        guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return [] }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            state.markUnreadable(directory)
            return []
        }
        return names.sorted().map { directory.appendingPathComponent($0) }
    }

    // MARK: Unreadable locations

    private func noteUnreadableLocations(of rule: JunkRule, state: inout State) {
        for location in rule.locations {
            guard let directory = literalPrefix(of: location), state.probed.insert(directory.path).inserted
            else { continue }
            if let blocked = unreadableAncestor(of: directory) { state.markUnreadable(blocked) }
        }
    }

    /// The deepest existing folder on the way to `directory` that cannot be searched or listed.
    /// A missing component (ENOENT/ENOTDIR) means the location is simply absent.
    private func unreadableAncestor(of directory: URL) -> URL? {
        var current = URL(fileURLWithPath: "/")
        for name in directory.pathComponents.dropFirst() {
            let next = current.appendingPathComponent(name)
            var info = stat()
            if stat(next.path, &info) != 0 {
                return errno == ENOENT || errno == ENOTDIR ? nil : current
            }
            guard (info.st_mode & S_IFMT) == S_IFDIR else { return nil }
            current = next
        }
        return (try? FileManager.default.contentsOfDirectory(atPath: current.path)) == nil ? current : nil
    }

    private func literalPrefix(of pattern: String) -> URL? {
        var parts = pattern.split(separator: "/").map(String.init)
        var base = home
        if pattern == "~" || pattern.hasPrefix("~/") {
            parts.removeFirst()
        } else {
            base = URL(fileURLWithPath: "/")
        }
        let literal = parts.prefix { !$0.contains { "*?[".contains($0) } }
        let directoryParts = literal.count == parts.count ? literal.dropLast() : literal
        return directoryParts.reduce(base) { $0.appendingPathComponent($1) }.standardizedFileURL
    }

    // MARK: Items

    private func makeItem(_ url: URL, rule: JunkRule) -> CleanupItem {
        CleanupItem(
            url: url, name: url.lastPathComponent, detail: displayPath(url.deletingLastPathComponent()),
            size: DiskUsage.allocatedSize(of: url), risk: rule.risk, isSelectedByDefault: rule.risk == .safe)
    }

    private func displayPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path == home.path { return "~" }
        if path.hasPrefix(home.path + "/") { return "~" + path.dropFirst(home.path.count) }
        return path
    }

    private func trashSize() -> Int64? {
        let trash = home.appendingPathComponent(".Trash")
        guard (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) != nil else { return nil }
        return DiskUsage.allocatedSize(of: trash)
    }
}
