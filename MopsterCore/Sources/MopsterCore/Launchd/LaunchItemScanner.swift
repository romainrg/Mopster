import Foundation

public struct LaunchItemScanner: Sendable {
    private let directories: [LaunchDomain: URL]

    public init(directories: [LaunchDomain: URL]) {
        self.directories = directories
    }

    public func scan() -> [LaunchItem] {
        var items: [LaunchItem] = []
        for (domain, directory) in directories {
            let urls =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil, options: [])) ?? []
            for url in urls where url.pathExtension == "plist" {
                items.append(Self.read(url, domain: domain))
            }
        }
        return items.sorted {
            let (a, b) = ($0.label ?? "", $1.label ?? "")
            return a == b ? $0.plist.path < $1.plist.path : a < b
        }
    }

    private static func read(_ url: URL, domain: LaunchDomain) -> LaunchItem {
        guard
            let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any]
        else {
            return LaunchItem(plist: url, label: nil, program: nil, domain: domain, isUnreadable: true)
        }
        func nonEmpty(_ value: Any?) -> String? {
            guard let string = value as? String, !string.isEmpty else { return nil }
            return string
        }
        let program = nonEmpty(plist["Program"]) ?? nonEmpty((plist["ProgramArguments"] as? [Any])?.first)
        return LaunchItem(
            plist: url, label: plist["Label"] as? String, program: program, domain: domain, isUnreadable: false)
    }
}
