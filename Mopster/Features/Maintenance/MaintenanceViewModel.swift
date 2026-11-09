import Foundation
import MopsterCore
import Observation

@MainActor @Observable
final class MaintenanceViewModel {
    enum Status: Equatable {
        case running
        case finished(MaintenanceOutcome)
    }

    let tasks: [MaintenanceTask]
    var selection: Set<String> = []
    private(set) var statuses: [String: Status] = [:]
    private(set) var lastRuns: [String: Date] = [:]
    private(set) var isRunning = false
    @ObservationIgnored private let env: AppEnvironment

    /// `initialOutcomes` lets previews and screenshot scenes start after a run.
    init(
        env: AppEnvironment, initialSelection: Set<String> = [], initialOutcomes: [String: MaintenanceOutcome] = [:]
    ) {
        self.env = env
        tasks = MaintenanceCatalog.tasks.filter { $0.isAvailable() }
        selection = initialSelection
        statuses = initialOutcomes.mapValues { .finished($0) }
        lastRuns = Dictionary(uniqueKeysWithValues: tasks.compactMap { task in
            env.maintenanceHistory.lastRun(of: task.id).map { (task.id, $0) }
        })
        for (id, outcome) in initialOutcomes {
            if case .succeeded = outcome { lastRuns[id] = .now }
        }
    }

    var canRun: Bool { !selection.isEmpty && !isRunning }
    var hasAdminSelection: Bool { tasks.contains { selection.contains($0.id) && $0.needsAdmin } }

    func isSelected(_ task: MaintenanceTask) -> Bool { selection.contains(task.id) }

    func setSelected(_ task: MaintenanceTask, _ on: Bool) {
        if on { selection.insert(task.id) } else { selection.remove(task.id) }
    }

    func output(for task: MaintenanceTask) -> String? {
        guard case .finished(let outcome)? = statuses[task.id] else { return nil }
        let text: String
        switch outcome {
        case .succeeded(let output): text = task.showsOutput ? output : ""
        case .failed(let output): text = output
        case .cancelled: text = ""
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func runSelected() async {
        let selected = tasks.filter { selection.contains($0.id) }
        guard canRun, !selected.isEmpty else { return }
        isRunning = true
        statuses = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, .running) })
        let outcomes = await env.maintenance.run(selected)
        let history = env.maintenanceHistory
        let now = Date()
        for task in selected {
            let outcome = outcomes[task.id] ?? .failed("")
            statuses[task.id] = .finished(outcome)
            if case .succeeded = outcome {
                history.recordSuccess(of: task.id, at: now)
                lastRuns[task.id] = now
            }
        }
        isRunning = false
    }
}
