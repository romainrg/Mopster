import Foundation
import MopsterCore

/// Fictional apps with plausible leftovers and orphans; reads and removes nothing on disk.
struct DemoAppInventory: AppInventoryProviding {
    func apps() async -> [InstalledApp] {
        try? await Task.sleep(for: .milliseconds(400))
        return Self.apps
    }

    func leftovers(for app: InstalledApp) async -> [CleanupItem] {
        Self.leftovers(forBundleID: app.bundleID)
    }

    func orphans() async -> [CleanupGroup] { Self.orphanGroups }
}

extension DemoAppInventory {
    private struct Sample {
        let name: String
        let id: String
        let version: String
        let megabytes: Int64
        let daysAgo: Int?
        var store = false
        var locked = false
    }

    private static let samples = [
        Sample(name: "Pixel Studio", id: "com.example.pixelstudio", version: "4.2.1", megabytes: 1_240, daysAgo: 1),
        Sample(name: "Notebook", id: "com.example.notebook", version: "2.9", megabytes: 310, daysAgo: 0, store: true),
        Sample(name: "Chat Room", id: "com.example.chatroom", version: "8.14.0", megabytes: 560, daysAgo: 2),
        Sample(name: "Media Player", id: "com.example.mediaplayer", version: "3.1.4", megabytes: 220, daysAgo: 17),
        Sample(name: "Code Forge", id: "com.example.codeforge", version: "1.88.0", megabytes: 940, daysAgo: 0),
        Sample(name: "Sketch Pad", id: "com.example.sketchpad", version: "6.0", megabytes: 410, daysAgo: 95, store: true),
        Sample(name: "Video Cutter", id: "com.example.videocutter", version: "11.2", megabytes: 2_850, daysAgo: 210, store: true),
        Sample(name: "Photo Vault", id: "com.example.photovault", version: "5.7.2", megabytes: 680, daysAgo: 41),
        Sample(name: "Terminal Plus", id: "com.example.terminalplus", version: "2.3", megabytes: 85, daysAgo: 4),
        Sample(name: "Budget Tracker", id: "com.example.budget", version: "3.4.1", megabytes: 140, daysAgo: nil, store: true),
        Sample(name: "Cloud Drive", id: "com.example.clouddrive", version: "112.0", megabytes: 390, daysAgo: 0),
        Sample(name: "Web Browser (System)", id: "com.example.webbrowser", version: "18.1", megabytes: 20, daysAgo: 0, locked: true),
    ]

    static let apps: [InstalledApp] = samples.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }.map { sample in
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(sample.name).app"), bundleID: sample.id, name: sample.name,
            version: sample.version, build: "1", isAppStore: sample.store, sparkleFeed: nil,
            minimumSystemVersion: nil, isLocked: sample.locked, size: sample.megabytes * 1_000_000,
            lastUsed: sample.daysAgo.map { Date(timeIntervalSinceNow: -Double($0) * 86_400 - 5 * 3_600) })
    }

    private struct LeftoverSample {
        let folder: String
        let name: String
        let kilobytes: Int64
        var byName = false
    }

    private static func samples(for id: String, name: String) -> [LeftoverSample] {
        [
            LeftoverSample(folder: "Library/Application Support", name: name, kilobytes: 340_000, byName: true),
            LeftoverSample(folder: "Library/Caches", name: id, kilobytes: 210_000),
            LeftoverSample(folder: "Library/Containers", name: id, kilobytes: 48_000),
            LeftoverSample(folder: "Library/HTTPStorages", name: id, kilobytes: 640),
            LeftoverSample(folder: "Library/Preferences", name: "\(id).plist", kilobytes: 12),
            LeftoverSample(folder: "Library/Saved Application State", name: "\(id).savedState", kilobytes: 3_200),
            LeftoverSample(folder: "Library/Logs", name: name, kilobytes: 900, byName: true),
        ]
    }

    static func leftovers(forBundleID id: String) -> [CleanupItem] {
        guard let app = apps.first(where: { $0.bundleID == id }), !app.isLocked else { return [] }
        let trimmed = id == "com.example.budget" || id == "com.example.terminalplus"
        return samples(for: id, name: app.name).dropFirst(trimmed ? 3 : 0).map { sample in
            let url = URL(fileURLWithPath: "\(DemoData.demoHome)/\(sample.folder)/\(sample.name)")
            return CleanupItem(
                url: url, name: sample.name, detail: "~/\(sample.folder)", size: sample.kilobytes * 1_000,
                risk: sample.byName ? .review : .safe, isSelectedByDefault: !sample.byName)
        }
        + (id == "com.example.pixelstudio"
            ? [
                CleanupItem(
                    url: URL(fileURLWithPath: "/Library/Application Support/Pixel Studio"), name: "Pixel Studio",
                    detail: "/Library/Application Support", size: 18_000_000, risk: .review,
                    isSelectedByDefault: false)
            ] : [])
    }

    private static let orphanSamples: [(id: String, vendorNote: String?, items: [(folder: String, name: String, kilobytes: Int64)])] = [
        (
            "com.example.oldeditor", nil,
            [
                ("Library/Application Support", "com.example.oldeditor", 420_000),
                ("Library/Caches", "com.example.oldeditor", 180_000),
                ("Library/Preferences", "com.example.oldeditor.plist", 8),
            ]
        ),
        (
            "com.example.chatroom.beta", "Chat Room",
            [
                ("Library/Application Support", "com.example.chatroom.beta", 96_000),
                ("Library/Saved Application State", "com.example.chatroom.beta.savedState", 2_400),
            ]
        ),
        (
            "com.example.screencap", nil,
            [
                ("Library/Containers", "com.example.screencap", 54_000),
                ("Library/HTTPStorages", "com.example.screencap", 300),
            ]
        ),
        (
            "com.example.vpnclient", nil,
            [("Library/Logs", "com.example.vpnclient", 12_000), ("Library/Cookies", "com.example.vpnclient.binarycookies", 24)]
        ),
    ]

    static var orphanGroups: [CleanupGroup] {
        orphanSamples.map { sample in
            CleanupGroup(
                id: sample.id, title: LocalizedStringResource(stringLiteral: sample.id),
                explanation: sample.vendorNote.map(OrphanDetector.sharedVendorNote(appName:)),
                symbol: "questionmark.app", risk: .review,
                items: sample.items.map { item in
                    CleanupItem(
                        url: URL(fileURLWithPath: "\(DemoData.demoHome)/\(item.folder)/\(item.name)"), name: item.name,
                        detail: "~/\(item.folder)", size: item.kilobytes * 1_000, risk: .review,
                        isSelectedByDefault: false)
                }.sorted { $0.size > $1.size })
        }.sorted { $0.totalSize > $1.totalSize }
    }

    /// Sizes of every demo path, for the simulated removal report.
    static var sizes: [String: Int64] {
        var result: [String: Int64] = [:]
        for app in apps {
            result[app.url.path] = app.size
            for item in leftovers(forBundleID: app.bundleID) { result[item.url.path] = item.size }
        }
        for item in orphanGroups.flatMap(\.items) { result[item.url.path] = item.size }
        return result
    }
}
