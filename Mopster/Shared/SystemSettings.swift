import AppKit

enum SystemSettings {
    enum Pane {
        case fullDiskAccess, loginItems, softwareUpdate, firewall, fileVault, privacySecurity, automation
    }

    static func open(_ pane: Pane) {
        for candidate in urls(for: pane) {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Modern URL first, legacy `com.apple.preference.security` form as fallback.
    static func urls(for pane: Pane, osMajor: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> [String] {
        let privacy = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        let legacy = "x-apple.systempreferences:com.apple.preference.security"
        switch pane {
        case .fullDiskAccess: return ["\(privacy)?Privacy_AllFiles", "\(legacy)?Privacy_AllFiles"]
        case .automation: return ["\(privacy)?Privacy_Automation", "\(legacy)?Privacy_Automation"]
        case .fileVault: return ["\(privacy)?FileVault", "\(legacy)?FDE"]
        case .privacySecurity: return [privacy, legacy]
        case .loginItems:
            return ["x-apple.systempreferences:com.apple.LoginItems-Settings.extension"]
        case .softwareUpdate:
            return ["x-apple.systempreferences:com.apple.Software-Update-Settings.extension",
                    "x-apple.systempreferences:com.apple.preferences.softwareupdate"]
        case .firewall:
            return osMajor >= 15
                ? ["x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall",
                   "x-apple.systempreferences:com.apple.preference.security?Firewall"]
                : ["x-apple.systempreferences:com.apple.preference.security?Firewall"]
        }
    }
}
