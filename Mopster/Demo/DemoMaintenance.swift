import Foundation
import MopsterCore

/// Never runs a process: every task succeeds except one that reports a failure with sample output.
struct DemoMaintenanceRunner: MaintenanceRunning {
    static let failingID = "rebuildLaunchServices"
    var delay: Duration = .milliseconds(1500)

    func run(_ tasks: [MaintenanceTask]) async -> [String: MaintenanceOutcome] {
        try? await Task.sleep(for: delay)
        return Self.outcomes(for: tasks)
    }

    static func outcomes(for tasks: [MaintenanceTask]) -> [String: MaintenanceOutcome] {
        Dictionary(
            uniqueKeysWithValues: tasks.map { task in
                switch task.id {
                case failingID: (task.id, .failed("lsregister: could not open the Launch Services database (error -10811).\n"))
                case "verifyStartupDisk":
                    (task.id, .succeeded("Verifying file system\nChecking the container superblock\nChecking the space manager\nThe volume Macintosh HD appears to be OK\n"))
                default: (task.id, .succeeded(""))
                }
            })
    }

    static func history(now: Date = .now) -> InMemoryMaintenanceHistory {
        InMemoryMaintenanceHistory([
            "freeRAM": now.addingTimeInterval(-3 * 86_400),
            "flushDNS": now.addingTimeInterval(-9 * 86_400),
            "verifyStartupDisk": now.addingTimeInterval(-32 * 86_400),
        ])
    }
}
