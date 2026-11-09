import Foundation

public struct SystemUpdate: Sendable, Equatable {
    public let label: String
    public let title: String
    public let version: String
    public let recommended: Bool
    public let restart: Bool

    public init(label: String, title: String, version: String, recommended: Bool, restart: Bool) {
        self.label = label
        self.title = title
        self.version = version
        self.recommended = recommended
        self.restart = restart
    }
}

/// Parses `softwareupdate --list`, in its current (`* Label:`) and older (`* name`) layouts.
public enum SoftwareUpdateParser {
    public static func parse(_ output: String) -> [SystemUpdate] {
        var updates: [SystemUpdate] = []
        var label: String?

        func flush(title: String? = nil, version: String = "", recommended: Bool = false, restart: Bool = false) {
            guard let pending = label else { return }
            updates.append(
                SystemUpdate(
                    label: pending, title: title ?? pending, version: version, recommended: recommended,
                    restart: restart))
            label = nil
        }

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("*") {
                flush()
                let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
                let name = rest.hasPrefix("Label:") ? rest.dropFirst("Label:".count) : Substring(rest)
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                label = trimmed.isEmpty ? nil : trimmed
            } else if label != nil, !line.isEmpty {
                if line.hasPrefix("Title:") {
                    flush(
                        title: field("Title", in: line, until: "Version"), version: field("Version", in: line, until: "Size") ?? "",
                        recommended: field("Recommended", in: line, until: "Action") == "YES",
                        restart: field("Action", in: line, until: nil) == "restart")
                } else if let legacy = legacyDetails(line) {
                    flush(
                        title: legacy.title, version: legacy.version, recommended: line.contains("[recommended]"),
                        restart: line.contains("[restart]"))
                }
            }
        }
        flush()
        return updates
    }

    /// Value of `Name: value` up to `, Next:` (or to the end of the line when `next` is nil).
    private static func field(_ name: String, in line: String, until next: String?) -> String? {
        guard let start = line.range(of: "\(name): ") else { return nil }
        let rest = line[start.upperBound...]
        let end = next.flatMap { rest.range(of: ", \($0):")?.lowerBound } ?? rest.endIndex
        let value = rest[..<end].trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespaces))
        return value.isEmpty ? nil : value
    }

    /// `Title (1.2.3), 1234K [recommended] [restart]`
    private static func legacyDetails(_ line: String) -> (title: String, version: String)? {
        guard let close = line.range(of: "), ", options: .backwards) ?? line.range(of: ")", options: .backwards),
            let open = line[..<close.lowerBound].range(of: " (", options: .backwards)
        else { return nil }
        return (String(line[..<open.lowerBound]), String(line[open.upperBound..<close.lowerBound]))
    }
}
