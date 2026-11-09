import Darwin
import Foundation

public enum SafetyRefusal: Equatable, Sendable {
    case outsideAllowedRoots, protectedSystemPath, insideAppBundle, structuralFolder, secretStore, mopsterItself
    /// Symlinks could not be resolved (for example an unreadable parent), so the path cannot be judged.
    case unresolvable
}

public enum SafetyVerdict: Equatable, Sendable {
    case allowed
    case refused(SafetyRefusal)
}

/// Judges whether a path may be removed. Paths are compared as NFC-normalized, lowercased components, both
/// literally and with symlinks resolved; a refusal from either comparison wins.
public struct SafetyGuard: Sendable {
    private let home: URL
    private let appBundle: URL
    private let extraRoots: [URL]

    public init(home: URL, appBundle: URL, extraRoots: [URL] = []) {
        self.home = home
        self.appBundle = appBundle
        let honored = extraRoots.filter { Self.isHonored($0, home: home) }
        self.extraRoots = honored
    }

    public func adding(root: URL) -> SafetyGuard {
        SafetyGuard(home: home, appBundle: appBundle, extraRoots: extraRoots + [root])
    }

    public func check(_ url: URL) -> SafetyVerdict {
        // References are rebuilt per check so symlinks created after init are honored, and every extra root
        // must still pass the honoring rule (a root swapped for a symlink to a system folder is dropped).
        let roots = extraRoots.filter { Self.isHonored($0, home: home) }
        let literal = References(home: home, appBundle: appBundle, extraRoots: roots, resolve: false)
        let resolved = References(home: home, appBundle: appBundle, extraRoots: roots, resolve: true)
        let resolvedRefusal: SafetyRefusal? =
            PathComponents.resolved(url).map { resolved.refusal(for: $0) } ?? .unresolvable
        let refusals = [literal.refusal(for: PathComponents.literal(url)), resolvedRefusal].compactMap { $0 }
        guard let strongest = refusals.min(by: { Self.rank($0) < Self.rank($1) }) else { return .allowed }
        return .refused(strongest)
    }

    private static func rank(_ refusal: SafetyRefusal) -> Int {
        switch refusal {
        case .protectedSystemPath: 0
        case .unresolvable: 1
        case .mopsterItself: 2
        case .secretStore: 3
        case .insideAppBundle: 4
        case .outsideAllowedRoots: 5
        case .structuralFolder: 6
        }
    }

    /// An extra root counts only when it resolves strictly inside home, or to `/Volumes/<name>` or below.
    private static func isHonored(_ root: URL, home: URL) -> Bool {
        guard let comps = PathComponents.resolved(root), let homeComps = PathComponents.resolved(home) else {
            return false
        }
        if comps.count > homeComps.count, comps.starts(with: homeComps) { return true }
        return comps.count >= 2 && comps[0] == "volumes"
    }
}

private struct References: Sendable {
    let home: [String]
    let appBundle: [String]
    let roots: [[String]]
    let protectedSystem: [[String]]
    let secretStores: [[String]]
    let structural: [[String]]

    init(home homeURL: URL, appBundle: URL, extraRoots: [URL], resolve: Bool) {
        let convert: (URL) -> [String] = resolve
            ? { PathComponents.resolved($0) ?? PathComponents.literal($0) } : PathComponents.literal
        let fromPath: (String) -> [String] = { convert(URL(fileURLWithPath: $0)) }
        let homeComponents = convert(homeURL)
        home = homeComponents
        self.appBundle = convert(appBundle)
        let systemRoots = ProtectedPaths.systemAllowedRoots.map(fromPath)
        roots = [homeComponents] + systemRoots + extraRoots.map(convert)
        protectedSystem = ProtectedPaths.protectedSystem.map(fromPath)
        let inHome: (String) -> [[String]] = { name in
            let nominal = homeComponents + PathComponents.split(name)
            return resolve ? [nominal, convert(homeURL.appendingPathComponent(name))] : [nominal]
        }
        secretStores = ProtectedPaths.secretStores.flatMap(inHome)
        structural = [homeComponents] + systemRoots + extraRoots.map(convert)
            + ProtectedPaths.standardHomeFolders.flatMap(inHome)
    }

    func refusal(for path: [String]) -> SafetyRefusal? {
        if path.isEmpty || protectedSystem.contains(where: { path.starts(with: $0) }) {
            return .protectedSystemPath
        }
        if path.starts(with: appBundle) { return .mopsterItself }
        if secretStores.contains(where: { path.starts(with: $0) }) { return .secretStore }
        if path.dropLast().contains(where: { $0.hasSuffix(".app") }) { return .insideAppBundle }
        guard roots.contains(where: { path.starts(with: $0) }) else { return .outsideAllowedRoots }
        if structural.contains(path) { return .structuralFolder }
        if path.count == home.count + 2, path.starts(with: home), path[home.count] == "library" {
            return .structuralFolder
        }
        if path.count < appBundle.count, appBundle.starts(with: path) { return .mopsterItself }
        if secretStores.contains(where: { path.count < $0.count && $0.starts(with: path) }) { return .secretStore }
        return nil
    }
}

enum PathComponents {
    static func normalize(_ component: String) -> String {
        component.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func split(_ path: String) -> [String] {
        path.split(separator: "/").map { normalize(String($0)) }
    }

    /// Lexical standardization (`.` and `..` folded) without touching the disk.
    /// The firmlinked `/tmp`, `/var` and `/etc` are spelled with their `/private` prefix, so a path and a
    /// reference spelled differently still compare equal.
    static func literal(_ url: URL) -> [String] {
        let folded = fold(rawComponents(url))
        guard let first = folded.first, ["tmp", "var", "etc"].contains(first) else { return folded }
        return ["private"] + folded
    }

    /// Symlinks resolved on the longest existing prefix; the non-existent remainder is folded lexically.
    /// Returns nil when resolution fails for any reason other than a missing component.
    static func resolved(_ url: URL) -> [String]? {
        let raw = rawComponents(url)
        for end in stride(from: raw.count, through: 0, by: -1) {
            let prefix = "/" + raw[..<end].joined(separator: "/")
            let (real, code) = realPath(prefix)
            if let real { return fold(real.split(separator: "/").map(String.init) + raw[end...]) }
            guard code == ENOENT else { return nil }
        }
        return fold(raw)
    }

    private static func rawComponents(_ url: URL) -> [String] {
        URL(fileURLWithPath: url.path).path.split(separator: "/").map(String.init)
    }

    private static func fold(_ components: [String]) -> [String] {
        var result: [String] = []
        for component in components {
            switch component {
            case ".": continue
            case "..": _ = result.popLast()
            default: result.append(normalize(component))
            }
        }
        return result
    }

    private static func realPath(_ path: String) -> (String?, Int32) {
        guard let buffer = realpath(path, nil) else { return (nil, errno) }
        defer { free(buffer) }
        return (String(cString: buffer), 0)
    }
}
