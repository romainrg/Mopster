import Foundation

public enum LaunchControlError: Error, Equatable {
    case notAllowed
    case missingLabel
    case commandFailed(String)

}

public protocol LaunchAgentControlling: Sendable {
    func disable(_ item: InspectedLaunchItem) async throws
    func enable(_ item: InspectedLaunchItem) async throws
}

/// Disables and enables the user's own launch agents through `launchctl`.
public struct LiveLaunchAgentControl: LaunchAgentControlling {
    public typealias Run = @Sendable (String, [String]) async throws -> (status: Int32, stdout: String, stderr: String)

    private let uid: uid_t
    private let run: Run

    public init(uid: uid_t = getuid()) {
        self.init(uid: uid) { try await ProcessRunner.run($0, $1, timeout: 15) }
    }

    init(uid: uid_t, run: @escaping Run) {
        self.uid = uid
        self.run = run
    }

    public func disable(_ item: InspectedLaunchItem) async throws {
        let label = try validate(item)
        try await execute(Launchctl.disableArguments(label: label, uid: uid), required: "disable")
    }

    public func enable(_ item: InspectedLaunchItem) async throws {
        let label = try validate(item)
        try await execute(
            Launchctl.enableArguments(label: label, plist: item.item.plist, uid: uid), required: "enable")
    }

    private func validate(_ item: InspectedLaunchItem) throws -> String {
        guard item.item.domain == .userAgents else { throw LaunchControlError.notAllowed }
        guard let label = item.item.label, !label.isEmpty else { throw LaunchControlError.missingLabel }
        return label
    }

    /// `bootout` (not loaded) and `bootstrap` (already loaded) failures are expected; the `disable`/`enable` step must succeed.
    private func execute(_ commands: [[String]], required verb: String) async throws {
        for arguments in commands {
            do {
                let result = try await run("/bin/launchctl", arguments)
                if result.status != 0 && arguments.first == verb {
                    let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    throw LaunchControlError.commandFailed(message.isEmpty ? "launchctl \(verb) failed" : message)
                }
            } catch let error as LaunchControlError {
                throw error
            } catch {
                if arguments.first == verb { throw LaunchControlError.commandFailed(error.localizedDescription) }
            }
        }
    }
}
