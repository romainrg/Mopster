import Darwin
import Foundation

/// Only `*`, `?` and `[...]` (fnmatch, no escaping, one path component) are wildcards.
/// A component taken from `home`, or a pattern component without any of them, is always compared literally
/// (after Unicode normalization). A catalog pattern therefore cannot name a literal `[`, `*` or `?`.
public enum PathPattern {
    private enum Component {
        case literal(String)
        case glob(String)
    }

    /// Expands `~`-relative or absolute patterns to existing entries, sorted by path.
    /// With `followingSymlinkedFolders` false, a symlink standing for a folder below the home folder (not the
    /// last component) is not entered, so nothing outside the home folder is listed through it.
    public static func expand(_ pattern: String, home: URL, followingSymlinkedFolders: Bool = true) -> [URL] {
        var current = ["/"]
        let parts = components(of: pattern, home: home)
        let homeDepth = pattern == "~" || pattern.hasPrefix("~/") ? home.standardizedFileURL.pathComponents.count - 1 : 0
        for (index, component) in parts.enumerated() {
            current = current.flatMap { children(of: $0, matching: component) }
            if !followingSymlinkedFolders, index >= homeDepth, index < parts.count - 1 {
                current = current.filter { !isSymbolicLink($0) }
            }
            if current.isEmpty { return [] }
        }
        return current.sorted().map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    /// True when the URL's path matches the pattern component by component.
    public static func matches(_ url: URL, pattern: String, home: URL) -> Bool {
        let patternParts = components(of: pattern, home: home)
        let pathParts = url.standardizedFileURL.path.split(separator: "/").map(String.init)
        guard patternParts.count == pathParts.count else { return false }
        return zip(patternParts, pathParts).allSatisfy { nameMatches($1, $0) }
    }

    private static func components(of pattern: String, home: URL) -> [Component] {
        var rest = Substring(pattern)
        var result: [Component] = []
        if rest == "~" || rest.hasPrefix("~/") {
            result = home.standardizedFileURL.path.split(separator: "/").map { .literal(String($0)) }
            rest = rest.dropFirst()
        }
        for part in rest.split(separator: "/") {
            let name = String(part)
            result.append(name.contains { "*?[".contains($0) } ? .glob(name) : .literal(name))
        }
        return result
    }

    private static func normalized(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
    }

    private static func nameMatches(_ name: String, _ component: Component) -> Bool {
        switch component {
        case .literal(let literal):
            return normalized(name) == normalized(literal)
        case .glob(let pattern):
            return fnmatch(normalized(pattern), normalized(name), FNM_PERIOD | FNM_NOESCAPE) == 0
        }
    }

    private static func isSymbolicLink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK
    }

    private static func join(_ directory: String, _ name: String) -> String {
        directory == "/" ? "/" + name : directory + "/" + name
    }

    private static func children(of directory: String, matching component: Component) -> [String] {
        if case .literal(let name) = component {
            var info = stat()
            let direct = join(directory, name)
            if lstat(direct, &info) == 0 { return [direct] }
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return names.filter { nameMatches($0, component) }.map { join(directory, $0) }
    }
}
