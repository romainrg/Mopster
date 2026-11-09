import Foundation

public struct ScanProgress: Sendable, Equatable {
    public var location: String?
    /// `nil` when the total is unknown (indeterminate progress).
    public var fraction: Double?
    public var itemsFound: Int

    public init(location: String? = nil, fraction: Double? = nil, itemsFound: Int = 0) {
        self.location = location
        self.fraction = fraction
        self.itemsFound = itemsFound
    }
}
