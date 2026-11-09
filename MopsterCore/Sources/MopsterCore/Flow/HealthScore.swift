import Foundation

/// Smart Sweep's calm 0–100 score. Each finding costs a few points, capped per area so one area never
/// dominates; an area that couldn't be checked (`nil`) costs nothing.
public struct HealthScore: Equatable, Sendable {
    public enum Level: Sendable { case good, fair, poor }

    public let value: Int

    public var level: Level {
        switch value {
        case 75...: .good
        case 50...: .fair
        default: .poor
        }
    }

    public init(
        safeJunkBytes: Int64? = nil, securityWarnings: Int? = nil, flaggedItems: Int? = nil,
        memoryPressure: MemoryPressure? = nil, brokenItems: Int? = nil, pendingUpdates: Int? = nil,
        diskUsedFraction: Double? = nil
    ) {
        func capped(_ count: Int?, each: Int, max limit: Int) -> Int {
            min(limit, Swift.max(0, count ?? 0) * each)
        }

        var penalty = 0
        switch safeJunkBytes ?? 0 {
        case 5_000_000_001...: penalty += 6
        case 1_000_000_001...: penalty += 3
        default: break
        }
        penalty += capped(securityWarnings, each: 6, max: 18)
        penalty += capped(flaggedItems, each: 1, max: 5)
        switch memoryPressure {
        case .warning?: penalty += 10
        case .critical?: penalty += 25
        case .normal?, nil: break
        }
        penalty += capped(brokenItems, each: 1, max: 3)
        penalty += capped(pendingUpdates, each: 1, max: 5)
        switch diskUsedFraction ?? 0 {
        case 0.9...: penalty += 10
        case 0.8...: penalty += 3
        default: break
        }
        value = Swift.max(0, 100 - penalty)
    }
}
