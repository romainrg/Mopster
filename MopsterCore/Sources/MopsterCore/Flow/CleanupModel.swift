import Foundation

public enum Risk: Sendable { case safe, review }

public struct CleanupItem: Identifiable, Sendable, Hashable {
    /// Standardized path.
    public let id: String
    public let url: URL
    public let name: String
    public let detail: String?
    public let size: Int64
    public let risk: Risk
    public let isSelectedByDefault: Bool

    public init(
        url: URL, name: String, detail: String? = nil, size: Int64, risk: Risk = .safe,
        isSelectedByDefault: Bool = true
    ) {
        self.id = url.standardizedFileURL.path
        self.url = url
        self.name = name
        self.detail = detail
        self.size = size
        self.risk = risk
        self.isSelectedByDefault = isSelectedByDefault
    }
}

public struct CleanupGroup: Identifiable, Sendable {
    public let id: String
    public let title: LocalizedStringResource
    public let explanation: LocalizedStringResource?
    public let symbol: String
    public let risk: Risk
    public var items: [CleanupItem]

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    public init(
        id: String, title: LocalizedStringResource, explanation: LocalizedStringResource? = nil,
        symbol: String, risk: Risk = .safe, items: [CleanupItem]
    ) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.symbol = symbol
        self.risk = risk
        self.items = items
    }
}
