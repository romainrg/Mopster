import Foundation

public struct InstalledApp: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let bundleID: String
    public let name: String
    public let version: String
    public let build: String
    public let isAppStore: Bool
    public let sparkleFeed: URL?
    public let minimumSystemVersion: String?
    public let isLocked: Bool
    public let size: Int64
    public let lastUsed: Date?

    public init(
        url: URL, bundleID: String, name: String, version: String, build: String, isAppStore: Bool,
        sparkleFeed: URL?, minimumSystemVersion: String?, isLocked: Bool, size: Int64, lastUsed: Date?
    ) {
        self.url = url
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.build = build
        self.isAppStore = isAppStore
        self.sparkleFeed = sparkleFeed
        self.minimumSystemVersion = minimumSystemVersion
        self.isLocked = isLocked
        self.size = size
        self.lastUsed = lastUsed
    }
}
