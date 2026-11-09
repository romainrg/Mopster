public enum AppleScriptQuoting {
    /// A double-quoted AppleScript string literal. Only `\` and `"` need escaping.
    public static func literal(_ s: String) -> String {
        var result = "\""
        for character in s.unicodeScalars {
            if character == "\\" || character == "\"" { result.unicodeScalars.append("\\") }
            result.unicodeScalars.append(character)
        }
        return result + "\""
    }
}
