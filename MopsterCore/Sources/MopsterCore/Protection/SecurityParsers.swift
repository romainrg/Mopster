import Foundation

public struct CheckOutcome: Sendable, Equatable {
    public let status: CheckStatus
    public let detail: String?

    public init(_ status: CheckStatus, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }
}

/// Pure parsers for the output of the system's security tools; unrecognized input is always `.unknown`.
public enum SecurityParsers {
    public static func parseSIP(csrutilStatus: String) -> CheckStatus {
        let text = csrutilStatus.lowercased()
        guard text.contains("system integrity protection status") else { return .unknown }
        if text.contains("custom configuration") || text.contains("disabled") { return .warning }
        if text.contains("enabled") { return .ok }
        return .unknown
    }

    public static func parseGatekeeper(spctlStatus: String) -> CheckStatus {
        let text = spctlStatus.lowercased()
        if text.contains("assessments disabled") { return .warning }
        if text.contains("assessments enabled") { return .ok }
        return .unknown
    }

    public static func parseFileVault(fdesetupStatus: String) -> CheckStatus {
        let first = fdesetupStatus.split(separator: "\n").first.map { $0.lowercased() } ?? ""
        if first.hasPrefix("filevault is on") || first.hasPrefix("encryption in progress") { return .ok }
        if first.hasPrefix("filevault is off") { return .warning }
        return .unknown
    }

    public static func parseFirewall(socketfilterfw: String) -> CheckStatus {
        let text = socketfilterfw.lowercased()
        guard text.contains("firewall is") else { return .unknown }
        if let range = text.range(of: #"state = (\d)"#, options: .regularExpression) {
            return text[range].hasSuffix("0") ? .warning : .ok
        }
        if text.contains("disabled") { return .warning }
        if text.contains("enabled") { return .ok }
        return .unknown
    }

    /// `Version: 5371 Installed: 2026-11-04 03:56:18 +0000` gives the detail `5371 · 2026-11-04`.
    public static func parseXProtect(versionOutput: String) -> CheckOutcome {
        guard
            let match = versionOutput.range(of: #"Version:\s*(\S+)"#, options: .regularExpression)
        else { return CheckOutcome(.unknown) }
        let version = versionOutput[match].replacingOccurrences(of: "Version:", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let date = versionOutput.range(of: #"Installed:\s*\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            let day = versionOutput[date].suffix(10)
            return CheckOutcome(.ok, detail: "\(version) · \(day)")
        }
        return CheckOutcome(.ok, detail: version)
    }

    /// macOS 14 has no `xprotect` tool: the bundle's version and modification date stand in.
    public static func xprotectBundle(version: String?, modified: Date?) -> CheckOutcome {
        guard let version, !version.isEmpty else { return CheckOutcome(.unknown) }
        guard let modified else { return CheckOutcome(.ok, detail: version) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return CheckOutcome(.ok, detail: "\(version) · \(formatter.string(from: modified))")
    }

    /// Reads `CriticalUpdateInstall` and `ConfigDataInstall` from `com.apple.SoftwareUpdate`.
    public static func parseAutoUpdates(defaults: [String: Any]) -> CheckStatus {
        let values = ["CriticalUpdateInstall", "ConfigDataInstall"].compactMap { key in defaults[key].map(isOn) }
        if values.contains(where: { $0 == false }) { return .warning }
        if values.contains(where: { $0 == nil }) || values.isEmpty { return .unknown }
        return .ok
    }

    private static func isOn(_ value: Any) -> Bool? {
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let text = value as? String {
            switch text.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }
}
