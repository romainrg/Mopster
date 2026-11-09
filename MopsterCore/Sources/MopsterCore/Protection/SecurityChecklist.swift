import Foundation

public enum CheckStatus: Sendable, Equatable { case ok, warning, unknown }

public enum SecurityCheckID: String, Sendable, CaseIterable {
    case sip, gatekeeper, fileVault, firewall, xprotect, autoSecurityUpdates, pendingMacOSUpdates
}

public struct SecurityCheck: Identifiable, Sendable, Equatable {
    public let id: SecurityCheckID
    public let status: CheckStatus
    public let detail: String?

    public init(id: SecurityCheckID, status: CheckStatus, detail: String? = nil) {
        self.id = id
        self.status = status
        self.detail = detail
    }
}

public protocol SecurityChecking: Sendable {
    func run() async -> [SecurityCheck]
}

/// Runs the system's own security tools; anything missing or unreadable is `.unknown`.
public struct LiveSecurityChecker: SecurityChecking {
    /// Returns the tool's output, or nil when it could not run.
    public typealias Run = @Sendable (String, [String]) async -> String?

    private let osMajor: Int
    private let softwareUpdateDefaults: @Sendable () -> [String: Any]
    private let xprotectBundle: @Sendable () -> (version: String?, modified: Date?)
    private let run: Run

    public init() {
        self.init(
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            softwareUpdateDefaults: { Self.readSoftwareUpdateDefaults() },
            xprotectBundle: { Self.readXProtectBundle() },
            run: { await Self.runTool($0, $1) })
    }

    init(
        osMajor: Int, softwareUpdateDefaults: @escaping @Sendable () -> [String: Any],
        xprotectBundle: @escaping @Sendable () -> (version: String?, modified: Date?), run: @escaping Run
    ) {
        self.osMajor = osMajor
        self.softwareUpdateDefaults = softwareUpdateDefaults
        self.xprotectBundle = xprotectBundle
        self.run = run
    }

    public func run() async -> [SecurityCheck] {
        async let sip = run("/usr/bin/csrutil", ["status"])
        async let gatekeeper = run("/usr/sbin/spctl", ["--status"])
        async let fileVault = run("/usr/bin/fdesetup", ["status"])
        async let firewall = run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        async let xprotect = xprotectOutcome()
        let autoUpdates = SecurityParsers.parseAutoUpdates(defaults: softwareUpdateDefaults())
        let xprotectResult = await xprotect
        return [
            SecurityCheck(id: .sip, status: await sip.map { SecurityParsers.parseSIP(csrutilStatus: $0) } ?? .unknown),
            SecurityCheck(
                id: .gatekeeper,
                status: await gatekeeper.map { SecurityParsers.parseGatekeeper(spctlStatus: $0) } ?? .unknown),
            SecurityCheck(
                id: .fileVault,
                status: await fileVault.map { SecurityParsers.parseFileVault(fdesetupStatus: $0) } ?? .unknown),
            SecurityCheck(
                id: .firewall,
                status: await firewall.map { SecurityParsers.parseFirewall(socketfilterfw: $0) } ?? .unknown),
            SecurityCheck(id: .xprotect, status: xprotectResult.status, detail: xprotectResult.detail),
            SecurityCheck(id: .autoSecurityUpdates, status: autoUpdates),
            SecurityCheck(id: .pendingMacOSUpdates, status: .unknown),
        ]
    }

    private func xprotectOutcome() async -> CheckOutcome {
        if osMajor >= 15, let output = await run("/usr/bin/xprotect", ["version"]) {
            let outcome = SecurityParsers.parseXProtect(versionOutput: output)
            if outcome.status != .unknown { return outcome }
        }
        let bundle = xprotectBundle()
        return SecurityParsers.xprotectBundle(version: bundle.version, modified: bundle.modified)
    }

    /// `spctl --status` exits 1 when assessments are disabled, so the output matters more than the exit code.
    private static func runTool(_ exe: String, _ args: [String]) async -> String? {
        guard let result = try? await ProcessRunner.run(exe, args, timeout: 10) else { return nil }
        return result.stdout.isEmpty ? result.stderr : result.stdout
    }

    private static func readSoftwareUpdateDefaults() -> [String: Any] {
        NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.SoftwareUpdate.plist") as? [String: Any] ?? [:]
    }

    private static func readXProtectBundle() -> (version: String?, modified: Date?) {
        let path = "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist"
        let info = NSDictionary(contentsOfFile: path)
        let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return (info?["CFBundleShortVersionString"] as? String, modified)
    }
}
