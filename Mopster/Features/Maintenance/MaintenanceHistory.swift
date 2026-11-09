import Foundation

protocol MaintenanceHistory: Sendable {
    func lastRun(of id: String) -> Date?
    func recordSuccess(of id: String, at date: Date)
}

struct UserDefaultsMaintenanceHistory: MaintenanceHistory, @unchecked Sendable {
    var defaults: UserDefaults = .standard

    func lastRun(of id: String) -> Date? { defaults.object(forKey: "maintenance.lastRun.\(id)") as? Date }

    func recordSuccess(of id: String, at date: Date) { defaults.set(date, forKey: "maintenance.lastRun.\(id)") }
}

/// Demo history: lives in memory and never touches `UserDefaults`.
final class InMemoryMaintenanceHistory: MaintenanceHistory, @unchecked Sendable {
    private let lock = NSLock()
    private var dates: [String: Date]

    init(_ dates: [String: Date] = [:]) { self.dates = dates }

    func lastRun(of id: String) -> Date? { lock.withLock { dates[id] } }

    func recordSuccess(of id: String, at date: Date) { lock.withLock { dates[id] = date } }
}
