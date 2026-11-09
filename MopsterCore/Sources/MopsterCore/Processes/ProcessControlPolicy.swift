import Foundation

/// Which processes Mopster offers to quit: the user's own, never system or launchd-managed helpers.
public enum ProcessControlPolicy {
    private static let protectedPrefixes = ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/", "/private/var/"]

    public static func canQuit(_ process: ProcessSample, currentUID: uid_t, ownPID: pid_t) -> Bool {
        guard process.uid == currentUID, process.pid != ownPID,
            let path = process.path, !path.isEmpty
        else { return false }
        return !protectedPrefixes.contains { path.hasPrefix($0) }
    }
}
