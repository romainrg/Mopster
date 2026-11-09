import Foundation

/// Runs non-admin tasks one by one and every admin task in a single `osascript` call, so macOS asks for the password once.
public struct LiveMaintenanceRunner: MaintenanceRunning {
    private static let longRunning: Set<String> = ["verifyStartupDisk", "reindexSpotlight"]
    private static let adminTimeout: TimeInterval = 900

    public init() {}

    public func run(_ tasks: [MaintenanceTask]) async -> [String: MaintenanceOutcome] {
        var results: [String: MaintenanceOutcome] = [:]
        let admin = tasks.filter(\.needsAdmin)
        if !admin.isEmpty { results.merge(await runAdmin(admin)) { $1 } }
        for task in tasks where !task.needsAdmin { results[task.id] = await runSteps(of: task) }
        return results
    }

    private func runSteps(of task: MaintenanceTask) async -> MaintenanceOutcome {
        let timeout: TimeInterval = Self.longRunning.contains(task.id) ? 600 : 120
        var parts: [String] = []
        for step in task.steps {
            do {
                let result = try await ProcessRunner.run(step[0], Array(step.dropFirst()), timeout: timeout)
                parts.append(Self.combined(result.stdout, result.stderr))
                if result.status != 0 { return .failed(Self.joined(parts)) }
            } catch {
                return .failed(Self.joined(parts + [Self.message(for: error)]))
            }
        }
        return .succeeded(Self.joined(parts))
    }

    private func runAdmin(_ tasks: [MaintenanceTask]) async -> [String: MaintenanceOutcome] {
        let script = MaintenanceBatch.adminScript(for: tasks)
        let source = "do shell script \(AppleScriptQuoting.literal(script)) with administrator privileges"
        let stdout: String
        let stderr: String
        do {
            let result = try await ProcessRunner.run("/usr/bin/osascript", ["-e", source], timeout: Self.adminTimeout)
            stdout = result.stdout
            stderr = result.stderr
            if result.status != 0 && stderr.contains("(-128)") {
                return Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, MaintenanceOutcome.cancelled) })
            }
        } catch {
            return Dictionary(
                uniqueKeysWithValues: tasks.map { ($0.id, MaintenanceOutcome.failed(Self.message(for: error))) })
        }
        let codes = MaintenanceBatch.parseResults(stdout)
        let output = Self.combined(MaintenanceBatch.withoutResultLines(stdout), stderr)
        return Dictionary(
            uniqueKeysWithValues: tasks.map {
                ($0.id, MaintenanceBatch.succeeded($0, in: codes) ? .succeeded(output) : .failed(output))
            })
    }

    private static func combined(_ stdout: String, _ stderr: String) -> String {
        joined([stdout, stderr])
    }

    private static func joined(_ parts: [String]) -> String {
        parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func message(for error: Error) -> String {
        switch error as? ProcessRunnerError {
        case .timedOut?: String(localized: L("maintenance.error.timedOut", "The command took too long and was stopped."))
        default: String(localized: L("maintenance.error.notFound", "The command is not available on this Mac."))
        }
    }
}
