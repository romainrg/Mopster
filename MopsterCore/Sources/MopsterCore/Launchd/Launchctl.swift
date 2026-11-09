import Foundation

/// Pure argument builders: each label and path is one argv element, never part of a shell string.
public enum Launchctl {
    public static func disableArguments(label: String, uid: uid_t) -> [[String]] {
        [["bootout", "gui/\(uid)/\(label)"], ["disable", "gui/\(uid)/\(label)"]]
    }

    public static func enableArguments(label: String, plist: URL, uid: uid_t) -> [[String]] {
        [["enable", "gui/\(uid)/\(label)"], ["bootstrap", "gui/\(uid)", plist.path]]
    }

    /// Labels marked disabled in `launchctl print-disabled` output (modern `=> disabled` and older `=> true`).
    public static func parseDisabled(_ printDisabledOutput: String) -> Set<String> {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"^\s*"(.*)"\s*(?:=>|=)\s*(disabled|true)\b"#, options: [])
        else { return [] }
        var labels: Set<String> = []
        printDisabledOutput.enumerateLines { line, _ in
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                let labelRange = Range(match.range(at: 1), in: line)
            else { return }
            labels.insert(String(line[labelRange]))
        }
        return labels
    }
}
