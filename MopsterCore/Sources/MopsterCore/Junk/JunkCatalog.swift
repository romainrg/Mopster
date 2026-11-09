import Foundation

/// Ordered most specific first: the order is both the claim order and the display order.
public enum JunkCatalog {
    public static let rules: [JunkRule] = [
        JunkRule(
            id: "browserCaches",
            title: L("junk.browserCaches.title", "Browser caches"),
            explanation: L(
                "junk.browserCaches.explanation",
                "Files browsers keep to load pages faster. They are rebuilt automatically when needed."),
            symbol: "globe",
            locations: [
                "~/Library/Caches/com.apple.Safari/*",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/*",
                "~/Library/Caches/Google/Chrome/*",
                "~/Library/Caches/BraveSoftware/Brave-Browser/*",
                "~/Library/Caches/Microsoft Edge/*",
                "~/Library/Caches/company.thebrowser.Browser/*",
                "~/Library/Caches/Firefox/Profiles/*",
                "~/Library/Caches/com.operasoftware.Opera/*",
                "~/Library/Caches/Vivaldi/*",
            ],
            needsFullDiskAccess: true, risk: .safe),
        JunkRule(
            id: "xcodeCaches",
            title: L("junk.xcodeCaches.title", "Xcode build caches"),
            explanation: L(
                "junk.xcodeCaches.explanation",
                "Intermediate files from building projects and running simulators. Xcode recreates them on the next build."
            ),
            symbol: "hammer",
            locations: [
                "~/Library/Developer/Xcode/DerivedData/*",
                "~/Library/Developer/CoreSimulator/Caches/*",
            ],
            risk: .safe),
        JunkRule(
            id: "xcodeArchives",
            title: L("junk.xcodeArchives.title", "Xcode archives and device support"),
            explanation: L(
                "junk.xcodeArchives.explanation",
                "Old app archives and debug symbols for devices you have connected. Check them first: an archive can't be rebuilt exactly as it was."
            ),
            symbol: "archivebox",
            locations: [
                "~/Library/Developer/Xcode/iOS DeviceSupport/*",
                "~/Library/Developer/Xcode/Archives/*",
            ],
            risk: .review),
        JunkRule(
            id: "developerCaches",
            title: L("junk.developerCaches.title", "Developer caches"),
            explanation: L(
                "junk.developerCaches.explanation",
                "Packages and build outputs kept by developer tools. They are downloaded or built again when needed."
            ),
            symbol: "shippingbox",
            locations: [
                "~/.npm/_cacache/*",
                "~/Library/pnpm/store/*",
                "~/Library/Caches/Yarn/*",
                "~/Library/Caches/pip/*",
                "~/Library/Caches/Homebrew/downloads/*",
                "~/Library/Caches/CocoaPods/*",
                "~/.gradle/caches/*",
                "~/Library/Caches/go-build/*",
                "~/.cargo/registry/cache/*",
                "~/Library/Caches/composer/*",
            ],
            risk: .safe),
        JunkRule(
            id: "mavenRepository",
            title: L("junk.mavenRepository.title", "Maven repository"),
            explanation: L(
                "junk.mavenRepository.explanation",
                "Libraries downloaded by Maven for your Java projects. They are fetched again on the next build, which needs a connection."
            ),
            symbol: "shippingbox",
            locations: ["~/.m2/repository/*"],
            risk: .review),
        JunkRule(
            id: "mailDownloads",
            title: L("junk.mailDownloads.title", "Mail downloads"),
            explanation: L(
                "junk.mailDownloads.explanation",
                "Copies of attachments you opened from Mail."),
            symbol: "envelope",
            locations: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/*"],
            needsFullDiskAccess: true, risk: .safe),
        JunkRule(
            id: "crashReports",
            title: L("junk.crashReports.title", "Crash reports"),
            explanation: L(
                "junk.crashReports.explanation",
                "Reports macOS writes when an app crashes. They only help to diagnose problems."),
            symbol: "exclamationmark.triangle",
            locations: ["~/Library/Logs/DiagnosticReports/*"],
            risk: .safe),
        JunkRule(
            id: "logs",
            title: L("junk.logs.title", "Logs"),
            explanation: L(
                "junk.logs.explanation",
                "Text logs written by apps and services. New ones are created when needed."),
            symbol: "doc.text",
            locations: ["~/Library/Logs/*"],
            exclusions: ["~/Library/Logs/DiagnosticReports"],
            risk: .safe),
        JunkRule(
            id: "appCaches",
            title: L("junk.appCaches.title", "App caches"),
            explanation: L(
                "junk.appCaches.explanation",
                "Files apps keep to load faster. They are rebuilt automatically when needed."),
            symbol: "internaldrive",
            locations: ["~/Library/Caches/*"],
            exclusions: [
                "~/Library/Caches/com.apple.bird",
                "~/Library/Caches/CloudKit",
                "~/Library/Caches/com.apple.cloudd",
                "~/Library/Caches/com.apple.akd",
                "~/Library/Caches/com.apple.findmy.fmipcore",
                "~/Library/Caches/com.apple.icloud.fmfd",
                "~/Library/Caches/io.github.romainrg.Mopster",
            ],
            risk: .safe),
        JunkRule(
            id: "savedAppState",
            title: L("junk.savedAppState.title", "Saved app state"),
            explanation: L(
                "junk.savedAppState.explanation",
                "Windows and documents apps reopen after a restart. Without them, apps start fresh."),
            symbol: "clock.arrow.circlepath",
            locations: ["~/Library/Saved Application State/*"],
            risk: .review),
        JunkRule(
            id: "installers",
            title: L("junk.installers.title", "Installers in Downloads"),
            explanation: L(
                "junk.installers.explanation",
                "Disk images and packages you may have already used to install an app. Download them again if needed."
            ),
            symbol: "arrow.down.circle",
            locations: ["~/Downloads/*"],
            extensions: ["dmg", "pkg", "mpkg", "xip"],
            risk: .review),
        JunkRule(
            id: "deviceBackups",
            title: L("junk.deviceBackups.title", "iPhone and iPad backups"),
            explanation: L(
                "junk.deviceBackups.explanation",
                "Local backups of your devices made from this Mac. Check that you no longer need them."),
            symbol: "iphone",
            locations: ["~/Library/Application Support/MobileSync/Backup/*"],
            needsFullDiskAccess: true, risk: .review),
    ]
}
