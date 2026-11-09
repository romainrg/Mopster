import Foundation

public struct MaintenanceTask: Identifiable, Sendable {
    public let id: String
    public let title: LocalizedStringResource
    public let explanation: LocalizedStringResource
    /// Each step is an executable followed by its arguments; steps run in order and stop at the first failure.
    public let steps: [[String]]
    public let needsAdmin: Bool
    public let restartAdvised: Bool
    public let showsOutput: Bool
    public var isAvailable: @Sendable () -> Bool

    public init(
        id: String, title: LocalizedStringResource, explanation: LocalizedStringResource, steps: [[String]],
        needsAdmin: Bool, restartAdvised: Bool = false, showsOutput: Bool = false,
        isAvailable: @escaping @Sendable () -> Bool = { true }
    ) {
        self.id = id
        self.title = title
        self.explanation = explanation
        self.steps = steps
        self.needsAdmin = needsAdmin
        self.restartAdvised = restartAdvised
        self.showsOutput = showsOutput
        self.isAvailable = isAvailable
    }
}

public enum MaintenanceOutcome: Sendable, Equatable {
    case succeeded(String)
    case failed(String)
    case cancelled
}

public protocol MaintenanceRunning: Sendable {
    func run(_ tasks: [MaintenanceTask]) async -> [String: MaintenanceOutcome]
}
