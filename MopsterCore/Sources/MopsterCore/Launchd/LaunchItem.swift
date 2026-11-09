import Foundation

public enum LaunchDomain: Sendable, Hashable, CaseIterable {
    case userAgents, systemAgents, systemDaemons
}

public struct LaunchItem: Identifiable, Sendable, Equatable {
    public let plist: URL
    public let label: String?
    public let program: String?
    public let domain: LaunchDomain
    public let isUnreadable: Bool

    public var id: String { plist.path }

    public init(plist: URL, label: String?, program: String?, domain: LaunchDomain, isUnreadable: Bool) {
        self.plist = plist
        self.label = label
        self.program = program
        self.domain = domain
        self.isUnreadable = isUnreadable
    }
}

public struct InspectedLaunchItem: Identifiable, Sendable, Equatable {
    public let item: LaunchItem
    public let signature: CodeSignature
    public let flags: [PersistenceFlag]
    public let isDisabled: Bool

    public var id: String { item.id }

    public init(item: LaunchItem, signature: CodeSignature, flags: [PersistenceFlag], isDisabled: Bool) {
        self.item = item
        self.signature = signature
        self.flags = flags
        self.isDisabled = isDisabled
    }
}

public protocol LaunchItemProviding: Sendable {
    func items() async -> [InspectedLaunchItem]
}

/// The three standard launch item directories, inspected with code signatures and `launchctl` state.
public struct LiveLaunchItemProvider: LaunchItemProviding {
    private let directories: [LaunchDomain: URL]
    private let uid: uid_t
    private let maxConcurrentInspections: Int

    public init(home: URL, uid: uid_t = getuid(), maxConcurrentInspections: Int = 4) {
        self.directories = [
            .userAgents: home.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
            .systemAgents: URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
            .systemDaemons: URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true),
        ]
        self.uid = uid
        self.maxConcurrentInspections = max(1, maxConcurrentInspections)
    }

    public func items() async -> [InspectedLaunchItem] {
        let items = LaunchItemScanner(directories: directories).scan()
        async let guiDisabled = disabledLabels(domain: "gui/\(uid)")
        async let systemDisabled = disabledLabels(domain: "system")
        let resolved = Dictionary(
            uniqueKeysWithValues: Set(items.compactMap(\.program)).map { ($0, Self.resolve($0)) })
        let signatures = await inspectSignatures(of: Set(resolved.values.compactMap { $0 }))
        let gui = await guiDisabled
        let system = await systemDisabled

        return items.map { item in
            let signature =
                item.program.flatMap { resolved[$0] ?? nil }.flatMap { signatures[$0] } ?? .missing
            let disabledSet = item.domain == .systemDaemons ? system : gui
            return InspectedLaunchItem(
                item: item,
                signature: signature,
                flags: PersistenceFlags.flags(for: item, signature: signature),
                isDisabled: item.label.map(disabledSet.contains) ?? false)
        }
    }

    /// Absolute paths are used as-is; bare names are looked up the way launchd does, in the default PATH.
    private static func resolve(_ program: String) -> String? {
        if program.hasPrefix("/") { return program }
        guard !program.contains("/") else { return nil }
        return ["/usr/bin", "/bin", "/usr/sbin", "/sbin"].map { "\($0)/\(program)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func disabledLabels(domain: String) async -> Set<String> {
        guard
            let result = try? await ProcessRunner.run("/bin/launchctl", ["print-disabled", domain]),
            result.status == 0
        else { return [] }
        return Launchctl.parseDisabled(result.stdout)
    }

    private func inspectSignatures(of paths: Set<String>) async -> [String: CodeSignature] {
        await withTaskGroup(of: (String, CodeSignature).self) { group in
            var iterator = paths.makeIterator()
            var running = 0
            var results: [String: CodeSignature] = [:]
            while running < maxConcurrentInspections, let path = iterator.next() {
                group.addTask { (path, CodeSignatureInspector.inspect(path)) }
                running += 1
            }
            while let (path, signature) = await group.next() {
                results[path] = signature
                if let next = iterator.next() {
                    group.addTask { (next, CodeSignatureInspector.inspect(next)) }
                }
            }
            return results
        }
    }
}
