import Foundation

public struct JunkRule: Identifiable, Sendable {
    public let id: String
    public let title: LocalizedStringResource
    public let explanation: LocalizedStringResource
    public let symbol: String
    public let locations: [String]
    public let exclusions: [String]
    public let minAge: TimeInterval?
    public let extensions: Set<String>?
    public let needsFullDiskAccess: Bool
    public let risk: Risk

    public init(
        id: String, title: LocalizedStringResource, explanation: LocalizedStringResource, symbol: String,
        locations: [String], exclusions: [String] = [], minAge: TimeInterval? = nil,
        extensions: Set<String>? = nil, needsFullDiskAccess: Bool = false, risk: Risk
    ) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.symbol = symbol
        self.locations = locations
        self.exclusions = exclusions
        self.minAge = minAge
        self.extensions = extensions
        self.needsFullDiskAccess = needsFullDiskAccess
        self.risk = risk
    }
}
