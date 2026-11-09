import Foundation

public struct AppUpdate: Identifiable, Sendable {
    public enum Source: Sendable {
        case appStore(trackID: Int)
        case sparkle
    }

    public var id: String { app.id }
    public let app: InstalledApp
    public let available: String
    public let source: Source

    public init(app: InstalledApp, available: String, source: Source) {
        self.app = app
        self.available = available
        self.source = source
    }
}

public struct UpdateCheckResult: Sendable {
    public let updates: [AppUpdate]
    public let unknown: [InstalledApp]
    /// nil when `softwareupdate` could not be run or failed.
    public let system: [SystemUpdate]?

    public init(updates: [AppUpdate], unknown: [InstalledApp], system: [SystemUpdate]?) {
        self.updates = updates
        self.unknown = unknown
        self.system = system
    }
}

public protocol UpdateChecking: Sendable {
    func check(apps: [InstalledApp]) async -> UpdateCheckResult
}

public struct UpdateChecker: UpdateChecking {
    private let http: any HTTPClient
    private let country: String
    private let osVersion: OperatingSystemVersion
    private let maxConcurrent: Int
    private let timeout: TimeInterval
    private let systemUpdates: @Sendable () async -> [SystemUpdate]?

    public init(
        http: any HTTPClient,
        country: String = Locale.current.region?.identifier.lowercased() ?? "us",
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        maxConcurrent: Int = 4,
        timeout: TimeInterval = 15,
        systemUpdates: @escaping @Sendable () async -> [SystemUpdate]? = UpdateChecker.softwareUpdateList
    ) {
        self.http = http
        self.country = country
        self.osVersion = osVersion
        self.maxConcurrent = max(1, maxConcurrent)
        self.timeout = timeout
        self.systemUpdates = systemUpdates
    }

    @Sendable
    public static func softwareUpdateList() async -> [SystemUpdate]? {
        guard let result = try? await ProcessRunner.run("/usr/sbin/softwareupdate", ["--list"], timeout: 120),
            result.status == 0
        else { return nil }
        return SoftwareUpdateParser.parse(result.stdout + "\n" + result.stderr)
    }

    private enum Outcome: Sendable {
        case update(AppUpdate)
        case upToDate
        case unknown
    }

    public func check(apps: [InstalledApp]) async -> UpdateCheckResult {
        async let system = systemUpdates()
        let candidates = apps.filter { $0.isAppStore || $0.sparkleFeed != nil }
        var outcomes = [Outcome](repeating: .unknown, count: candidates.count)

        await withTaskGroup(of: (Int, Outcome).self) { group in
            var next = 0
            func launch(into group: inout TaskGroup<(Int, Outcome)>) {
                guard next < candidates.count else { return }
                let index = next
                next += 1
                group.addTask { (index, await outcome(for: candidates[index])) }
            }
            for _ in 0..<min(maxConcurrent, candidates.count) { launch(into: &group) }
            while let (index, outcome) = await group.next() {
                outcomes[index] = outcome
                launch(into: &group)
            }
        }

        var updates: [AppUpdate] = []
        var unknown: [InstalledApp] = []
        for (app, outcome) in zip(candidates, outcomes) {
            switch outcome {
            case .update(let update): updates.append(update)
            case .unknown: unknown.append(app)
            case .upToDate: break
            }
        }
        return UpdateCheckResult(updates: updates, unknown: unknown, system: await system)
    }

    private func outcome(for app: InstalledApp) async -> Outcome {
        app.isAppStore ? await checkAppStore(app) : await checkSparkle(app)
    }

    private func checkAppStore(_ app: InstalledApp) async -> Outcome {
        guard !app.version.isEmpty, let url = AppStoreLookup.url(bundleID: app.bundleID, country: country),
            let data = try? await http.get(url, timeout: timeout), let found = AppStoreLookup.parse(data)
        else { return .unknown }
        guard AppVersion(found.version) > AppVersion(app.version) else { return .upToDate }
        return .update(AppUpdate(app: app, available: found.version, source: .appStore(trackID: found.trackID)))
    }

    private func checkSparkle(_ app: InstalledApp) async -> Outcome {
        guard let feed = app.sparkleFeed, feed.scheme?.lowercased() == "https",
            let data = try? await http.get(feed, timeout: timeout), let items = AppcastParser.parse(data),
            let newest = AppcastParser.newestCompatible(items, osVersion: osVersion)
        else { return .unknown }
        let installed = app.build.isEmpty ? app.version : app.build
        guard AppVersion(newest.version) > AppVersion(installed) else { return .upToDate }
        return .update(AppUpdate(app: app, available: newest.shortVersion ?? newest.version, source: .sparkle))
    }
}
