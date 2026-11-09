import Foundation

public enum PersistenceFlag: Sendable, Equatable {
    case programMissing
    case unsignedOrAdHoc
    case hiddenOrTemporaryLocation
    case knownAdware(String)
}

/// Flags mean "worth a look", never "malware".
public enum PersistenceFlags {
    private static let temporaryRoots = [
        "/tmp", "/private/tmp", "/var/tmp", "/private/var/tmp", "/Users/Shared",
    ]

    public static func flags(for item: LaunchItem, signature: CodeSignature) -> [PersistenceFlag] {
        guard !item.isUnreadable else { return [] }
        var flags: [PersistenceFlag] = []

        if let program = item.program, program.hasPrefix("/"), signature == .missing {
            flags.append(.programMissing)
        }
        if signature == .unsigned || signature == .adHoc { flags.append(.unsignedOrAdHoc) }
        if let program = item.program, isHiddenOrTemporary(program) { flags.append(.hiddenOrTemporaryLocation) }

        let tokens = adwareTokens(label: item.label, program: item.program)
        for name in KnownAdware.names where tokens.contains(name.lowercased()) {
            flags.append(.knownAdware(name))
        }
        return flags
    }

    private static func adwareTokens(label: String?, program: String?) -> Set<String> {
        var tokens: Set<String> = []
        func add(_ text: String, separators: String) {
            let set = CharacterSet(charactersIn: separators)
            for part in text.lowercased().components(separatedBy: set) where !part.isEmpty { tokens.insert(part) }
        }
        if let label { add(label, separators: ".-_") }
        if let program {
            let components = program.split(separator: "/").map(String.init)
            if let last = components.last { add(last, separators: ".-_ ") }
            for component in components where component.lowercased().hasSuffix(".app") {
                add(String(component.dropLast(4)), separators: ".-_ ")
            }
        }
        return tokens
    }

    private static func isHiddenOrTemporary(_ program: String) -> Bool {
        let path = (program as NSString).standardizingPath
        if temporaryRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        return path.split(separator: "/").contains { $0.hasPrefix(".") }
    }
}
