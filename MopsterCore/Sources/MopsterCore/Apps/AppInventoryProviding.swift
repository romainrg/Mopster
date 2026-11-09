import Foundation

public protocol AppInventoryProviding: Sendable {
    func apps() async -> [InstalledApp]
    func leftovers(for app: InstalledApp) async -> [CleanupItem]
    func orphans() async -> [CleanupGroup]
}

public actor LiveAppInventory: AppInventoryProviding {
    private let home: URL
    private let systemRoot: URL
    private let isKnownToLaunchServices: @Sendable (String) -> Bool

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemRoot: URL = URL(fileURLWithPath: "/"),
        isKnownToLaunchServices: @escaping @Sendable (String) -> Bool
    ) {
        self.home = home
        self.systemRoot = systemRoot
        self.isKnownToLaunchServices = isKnownToLaunchServices
    }

    private var cached: [InstalledApp]?

    private var inventory: AppInventory {
        AppInventory(roots: [
            systemRoot.appendingPathComponent("Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ])
    }

    public func apps() async -> [InstalledApp] {
        let found = inventory.apps()
        cached = found
        return found
    }

    public func leftovers(for app: InstalledApp) async -> [CleanupItem] {
        let installed = await cachedApps()
        return LeftoverFinder(home: home, systemRoot: systemRoot).leftovers(for: app, among: installed)
    }

    public func orphans() async -> [CleanupGroup] {
        let installed = await cachedApps().map { (bundleID: $0.bundleID, name: $0.name) }
        return OrphanDetector(home: home, installedApps: installed, isKnownToLaunchServices: isKnownToLaunchServices)
            .orphans()
    }

    private func cachedApps() async -> [InstalledApp] {
        if let cached, !cached.isEmpty { return cached }
        return await apps()
    }
}
