import Foundation
import Security

public enum CodeSignature: Sendable, Equatable {
    case apple
    case developerID(team: String)
    case adHoc
    case unsigned
    case invalid
    case missing
}

public enum CodeSignatureInspector {
    /// Never throws; anything unexpected (directories, sockets, unreadable files) is `.invalid` or `.missing`.
    public static func inspect(_ path: String) -> CodeSignature {
        var info = stat()
        guard !path.isEmpty, stat(path, &info) == 0 else { return .missing }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
            let code = staticCode
        else { return .invalid }

        let validity = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil)
        if validity == errSecCSUnsigned { return .unsigned }
        guard validity == errSecSuccess else { return .invalid }

        var infoRef: CFDictionary?
        guard
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef)
                == errSecSuccess,
            let dictionary = infoRef as? [String: Any]
        else { return .invalid }

        let rawFlags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        if rawFlags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return .adHoc }
        if satisfies(code, "anchor apple") { return .apple }
        if let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
            satisfies(code, "anchor apple generic")
        {
            return .developerID(team: team)
        }
        return .invalid
    }

    private static func satisfies(_ code: SecStaticCode, _ requirementText: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
            let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
