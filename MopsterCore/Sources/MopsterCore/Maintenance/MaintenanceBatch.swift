import Foundation

public enum MaintenanceBatch {
    public static func adminScript(for tasks: [MaintenanceTask]) -> String {
        var lines = ["#!/bin/sh"]
        for task in tasks where task.needsAdmin {
            let steps = task.steps.map { $0.map(quoted).joined(separator: " ") }.joined(separator: " && ")
            lines.append("(\(steps))")
            lines.append("printf '\\nMOPSTER_RESULT %s %d\\n' \(task.id) $?")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func parseResults(_ output: String) -> [String: Int32] {
        var codes: [String: Int32] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count == 3, parts[0] == "MOPSTER_RESULT", let code = Int32(parts[2]) else { continue }
            codes[String(parts[1])] = code
        }
        return codes
    }

    public static func withoutResultLines(_ output: String) -> String {
        output.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("MOPSTER_RESULT ") }.joined(separator: "\n")
    }

    /// A task with no result line counts as failed.
    public static func succeeded(_ task: MaintenanceTask, in codes: [String: Int32]) -> Bool {
        codes[task.id] == 0
    }

    private static func quoted(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
