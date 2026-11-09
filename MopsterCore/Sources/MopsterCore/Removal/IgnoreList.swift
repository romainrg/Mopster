import Foundation

public struct IgnoreList: Codable, Sendable {
    public var paths: [String]

    public init(paths: [String] = []) {
        self.paths = paths
    }

    /// True when the URL is an entry or located below one (standardized, case and normalization insensitive).
    public func contains(_ url: URL) -> Bool {
        let candidate = PathComponents.literal(url)
        return paths.contains { entry in
            let entryComponents = PathComponents.literal(URL(fileURLWithPath: entry))
            return !entryComponents.isEmpty && candidate.starts(with: entryComponents)
        }
    }
}
