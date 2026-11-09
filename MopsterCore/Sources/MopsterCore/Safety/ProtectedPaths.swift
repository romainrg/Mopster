import Foundation

public enum ProtectedPaths {
    /// Absolute paths nothing below (or at) may ever be removed. `/` itself is protected separately.
    /// `/private/etc` and similar are not listed: they sit outside every allowed root and are refused as such.
    public static let protectedSystem = [
        "/System", "/usr", "/bin", "/sbin", "/private/var/db", "/Library/Apple", "/private/var/root", "/cores",
    ]

    /// Paths relative to the home folder: off-limits entirely, contents included.
    public static let secretStores = [
        ".ssh", ".gnupg", ".aws", ".kube", "Library/Keychains", "Library/Mobile Documents",
    ]

    /// Folders directly in the home folder that are never removable themselves (their contents are).
    public static let standardHomeFolders = [
        "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "Applications", ".Trash",
    ]

    /// System locations whose contents may be removed.
    public static let systemAllowedRoots = [
        "/Applications", "/Library/Application Support", "/Library/LaunchAgents", "/Library/LaunchDaemons",
        "/Library/PrivilegedHelperTools",
    ]
}
