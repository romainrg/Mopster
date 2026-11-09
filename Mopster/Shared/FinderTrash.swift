import Darwin
import Foundation
import MopsterCore

/// Asks Finder to move an item to the Trash (it prompts for an administrator password when needed).
/// Requires the Automation permission for Finder, which macOS requests on first use.
/// Symbolic links are refused: they are never handed to Finder, which could act on the link's target.
struct FinderTrash: TrashOperation {
    private static let queue = DispatchQueue(label: "io.github.romainrg.Mopster.FinderTrash")

    private final class Outcome: @unchecked Sendable {
        var result: Result<URL?, Error> = .success(nil)
    }

    func trash(_ url: URL) throws -> URL? {
        var info = stat()
        if lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
            throw Self.error("Mopster does not ask Finder to remove symbolic links", code: -2)
        }
        let source = """
            tell application "Finder"
                set trashed to delete (POSIX file \(AppleScriptQuoting.literal(url.path)))
            end tell
            try
                return POSIX path of (trashed as alias)
            on error
                return ""
            end try
            """
        let outcome = Outcome()
        let done = DispatchSemaphore(value: 0)
        Self.queue.async {
            outcome.result = Result { try Self.run(source) }
            done.signal()
        }
        done.wait()
        return try outcome.result.get()
    }

    private static func run(_ source: String) throws -> URL? {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw error("Invalid script", code: -1) }
        let output = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Finder could not move the item to the Trash"
            throw error(message, code: errorInfo[NSAppleScript.errorNumber] as? Int ?? -1)
        }
        guard let path = output.stringValue, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func error(_ message: String, code: Int) -> NSError {
        NSError(domain: "FinderTrash", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
