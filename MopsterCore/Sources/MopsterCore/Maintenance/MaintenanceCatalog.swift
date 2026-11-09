import Foundation

public enum MaintenanceCatalog {
    public static let tasks: [MaintenanceTask] = definitions.map { task in
        var checked = task
        checked.isAvailable = { FileManager.default.isExecutableFile(atPath: task.steps[0][0]) }
        return checked
    }

    private static let definitions: [MaintenanceTask] = [
        MaintenanceTask(
            id: "freeRAM",
            title: L("maintenance.freeRAM.title", "Free up RAM"),
            explanation: L(
                "maintenance.freeRAM.explanation",
                "Asks macOS to release inactive memory. macOS already does this on its own; useful before a memory-hungry task."
            ),
            steps: [["/usr/sbin/purge"]], needsAdmin: true),
        MaintenanceTask(
            id: "flushDNS",
            title: L("maintenance.flushDNS.title", "Flush DNS cache"),
            explanation: L(
                "maintenance.flushDNS.explanation",
                "Forgets the website addresses your Mac has remembered. Useful when a site moved or a network change left stale entries."
            ),
            steps: [["/usr/bin/dscacheutil", "-flushcache"], ["/usr/bin/killall", "-HUP", "mDNSResponder"]],
            needsAdmin: true),
        MaintenanceTask(
            id: "reindexSpotlight",
            title: L("maintenance.reindexSpotlight.title", "Reindex Spotlight"),
            explanation: L(
                "maintenance.reindexSpotlight.explanation",
                "Rebuilds the Spotlight search index of the startup disk. Search results are incomplete until it finishes, which can take a while."
            ),
            steps: [["/usr/bin/mdutil", "-E", "/"]], needsAdmin: true),
        MaintenanceTask(
            id: "rebuildLaunchServices",
            title: L("maintenance.rebuildLaunchServices.title", "Rebuild Launch Services database"),
            explanation: L(
                "maintenance.rebuildLaunchServices.explanation",
                "Rebuilds the list that decides which app opens which file and fills the “Open With” menu. Useful when it shows apps that are gone or the wrong default."
            ),
            steps: [[lsregister, "-r", "-domain", "local", "-domain", "system", "-domain", "user"]],
            needsAdmin: false),
        MaintenanceTask(
            id: "clearFontCaches",
            title: L("maintenance.clearFontCaches.title", "Clear font caches"),
            explanation: L(
                "maintenance.clearFontCaches.explanation",
                "Removes your user font caches so macOS rebuilds them. Useful when fonts look wrong or are missing. Restarting your Mac afterwards is advised."
            ),
            steps: [["/usr/bin/atsutil", "databases", "-removeUser"]], needsAdmin: false, restartAdvised: true),
        MaintenanceTask(
            id: "resetQuickLook",
            title: L("maintenance.resetQuickLook.title", "Reset Quick Look cache"),
            explanation: L(
                "maintenance.resetQuickLook.explanation",
                "Clears the cached previews and reloads Quick Look. Useful when a preview is stale or blank."),
            steps: [["/usr/bin/qlmanage", "-r", "cache"], ["/usr/bin/qlmanage", "-r"]], needsAdmin: false),
        MaintenanceTask(
            id: "verifyStartupDisk",
            title: L("maintenance.verifyStartupDisk.title", "Verify startup disk"),
            explanation: L(
                "maintenance.verifyStartupDisk.explanation",
                "Checks the startup volume for file system errors without changing anything. It can take a few minutes."),
            steps: [["/usr/sbin/diskutil", "verifyVolume", "/"]], needsAdmin: false, showsOutput: true),
    ]

    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
}
