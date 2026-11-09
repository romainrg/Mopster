import Foundation
import MopsterCore

struct DemoSecurityChecker: SecurityChecking {
    func run() async -> [SecurityCheck] { Self.checks }

    static let checks = [
            SecurityCheck(id: .sip, status: .ok),
            SecurityCheck(id: .gatekeeper, status: .ok),
            SecurityCheck(id: .fileVault, status: .ok),
            SecurityCheck(id: .firewall, status: .warning),
            SecurityCheck(id: .xprotect, status: .ok, detail: "5371 · 2026-11-04"),
            SecurityCheck(id: .autoSecurityUpdates, status: .ok),
            SecurityCheck(id: .pendingMacOSUpdates, status: .warning, detail: String(localized: "\(1) pending")),
        ]
}

/// In-memory launch item state shared by the demo provider, control and remover.
final class DemoLaunchState: @unchecked Sendable {
    private let lock = NSLock()
    private var disabled: Set<String> = ["com.example.backup-helper"]
    private var removed: Set<String> = []

    func isDisabled(_ label: String?) -> Bool { lock.withLock { label.map(disabled.contains) ?? false } }
    func set(_ label: String?, disabled value: Bool) {
        guard let label else { return }
        lock.withLock { if value { disabled.insert(label) } else { disabled.remove(label) } }
    }
    func remove(_ paths: [String]) { lock.withLock { removed.formUnion(paths) } }
    func isRemoved(_ path: String) -> Bool { lock.withLock { removed.contains(path) } }
}

struct DemoLaunchItems: LaunchItemProviding {
    let state: DemoLaunchState

    private static func item(
        _ label: String, _ domain: LaunchDomain, program: String?, _ signature: CodeSignature,
        flags: [PersistenceFlag] = []
    ) -> (LaunchItem, CodeSignature, [PersistenceFlag]) {
        let directory: String
        switch domain {
        case .userAgents: directory = "\(DemoData.demoHome)/Library/LaunchAgents"
        case .systemAgents: directory = "/Library/LaunchAgents"
        case .systemDaemons: directory = "/Library/LaunchDaemons"
        }
        let plist = URL(fileURLWithPath: "\(directory)/\(label).plist")
        return (LaunchItem(plist: plist, label: label, program: program, domain: domain, isUnreadable: false), signature, flags)
    }

    private static let samples = [
        item("com.example.sync", .userAgents, program: "/Applications/Example Sync.app/Contents/MacOS/ExampleSync", .developerID(team: "ABCDE12345")),
        item("com.example.backup-helper", .userAgents, program: "/Applications/Example Backup.app/Contents/MacOS/BackupHelper", .developerID(team: "FGHIJ67890")),
        item("com.acme.updater", .userAgents, program: "/Users/demo/Tools/acme-updater", .unsigned, flags: [.unsignedOrAdHoc]),
        item(
            "com.example.cache-warmer", .userAgents, program: "/Users/demo/.local/share/warmer/run", .adHoc,
            flags: [.unsignedOrAdHoc, .hiddenOrTemporaryLocation]),
        item(
            "com.example.legacy-agent", .userAgents, program: "/Applications/Legacy Tool.app/Contents/MacOS/LegacyTool", .missing,
            flags: [.programMissing]),
        item("com.apple.AirPlayXPCHelper", .systemAgents, program: "/System/Library/CoreServices/AirPlayXPCHelper", .apple),
        item("com.example.vpn-helper", .systemAgents, program: "/Applications/Example VPN.app/Contents/MacOS/VPNHelper", .developerID(team: "KLMNO12345")),
        item("com.example.vpn.daemon", .systemDaemons, program: "/Library/PrivilegedHelperTools/com.example.vpn.daemon", .developerID(team: "KLMNO12345")),
        item("com.apple.mdmclient.daemon", .systemDaemons, program: "/usr/libexec/mdmclient", .apple),
    ]

    func items() async -> [InspectedLaunchItem] { inspected() }

    func inspected() -> [InspectedLaunchItem] {
        Self.samples.filter { !state.isRemoved($0.0.plist.path) }.map { sample in
            InspectedLaunchItem(
                item: sample.0, signature: sample.1, flags: sample.2, isDisabled: state.isDisabled(sample.0.label))
        }
    }
}

struct DemoLaunchControl: LaunchAgentControlling {
    let state: DemoLaunchState

    func disable(_ item: InspectedLaunchItem) async throws {
        try? await Task.sleep(for: .milliseconds(300))
        state.set(item.item.label, disabled: true)
    }

    func enable(_ item: InspectedLaunchItem) async throws {
        try? await Task.sleep(for: .milliseconds(300))
        state.set(item.item.label, disabled: false)
    }
}

struct DemoLaunchRemover: ItemRemover {
    let base: any ItemRemover
    let state: DemoLaunchState

    func remove(_ urls: [URL]) async -> RemovalReport {
        state.remove(urls.map(\.path))
        return await base.remove(urls)
    }
}
