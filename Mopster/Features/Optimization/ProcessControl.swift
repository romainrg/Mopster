import AppKit
import Foundation
import MopsterCore

@MainActor
protocol ProcessControlling {
    /// Asks the process to quit; false when it was refused or is not allowed.
    func quit(_ process: ProcessSample) -> Bool
    func forceQuit(_ process: ProcessSample) -> Bool
}

struct LiveProcessControl: ProcessControlling {
    func quit(_ process: ProcessSample) -> Bool {
        guard isStillQuittable(process) else { return false }
        if let app = NSRunningApplication(processIdentifier: process.pid) { return app.terminate() }
        return kill(process.pid, SIGTERM) == 0
    }

    func forceQuit(_ process: ProcessSample) -> Bool {
        guard isStillQuittable(process) else { return false }
        if let app = NSRunningApplication(processIdentifier: process.pid) { return app.forceTerminate() }
        return kill(process.pid, SIGKILL) == 0
    }

    /// The pid may have been reused since the list was sampled.
    private func isStillQuittable(_ process: ProcessSample) -> Bool {
        guard let fresh = ProcessSampler.snapshot(pid: process.pid), fresh.path == process.path else { return false }
        return ProcessControlPolicy.canQuit(fresh, currentUID: getuid(), ownPID: getpid())
    }
}
