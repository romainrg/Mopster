import Foundation

/// Size and free space of a volume, as Finder reports them (purgeable space counts as available).
public struct VolumeCapacity: Equatable, Sendable {
    public let total: Int64
    public let available: Int64

    public init(total: Int64, available: Int64) {
        self.total = total
        self.available = available
    }

    public var used: Int64 { max(0, total - available) }

    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    /// The volume holding `url`, or nil when the path is missing or macOS can't tell.
    public static func of(_ url: URL) -> VolumeCapacity? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys), let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return VolumeCapacity(total: Int64(total), available: available)
    }
}
