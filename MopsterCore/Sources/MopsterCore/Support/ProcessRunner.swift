import Foundation

public enum ProcessRunnerError: Error, Equatable, Sendable {
    case notFound
    case timedOut
}

/// Runs an executable directly (never through a shell) and captures its output.
public struct ProcessRunner {
    public static func run(
        _ exe: String, _ args: [String], timeout: TimeInterval = 30
    ) async throws -> (status: Int32, stdout: String, stderr: String) {
        guard FileManager.default.isExecutableFile(atPath: exe) else { throw ProcessRunnerError.notFound }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exe)
            process.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = FileHandle.nullDevice

            let state = RunState()
            let group = DispatchGroup()
            let queue = DispatchQueue.global(qos: .utility)

            // Both readers and the termination handler are accounted for before the process starts.
            group.enter()
            group.enter()
            group.enter()

            let timer = DispatchWorkItem {
                guard process.isRunning else { return }
                state.markTimedOut()
                process.terminate()
                queue.asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
            state.timer = timer

            process.terminationHandler = { finished in
                state.setStatus(finished.terminationStatus)
                timer.cancel()
                group.leave()
            }

            group.notify(queue: queue) {
                guard state.claimResume() else { return }
                if state.failedToStart {
                    continuation.resume(throwing: ProcessRunnerError.notFound)
                } else if state.timedOut {
                    continuation.resume(throwing: ProcessRunnerError.timedOut)
                } else {
                    continuation.resume(
                        returning: (
                            state.status,
                            String(decoding: state.out, as: UTF8.self),
                            String(decoding: state.err, as: UTF8.self)
                        ))
                }
            }

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                try? outPipe.fileHandleForWriting.close()
                try? errPipe.fileHandleForWriting.close()
                state.markFailedToStart()
                group.leave()
                group.leave()
                group.leave()
                return
            }
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()

            queue.async {
                state.out = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            queue.async {
                state.err = errPipe.fileHandleForReading.readDataToEndOfFile()
                group.leave()
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        }
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var _timedOut = false
    private var _failedToStart = false
    private var _status: Int32 = 0
    private var resumed = false
    var out = Data()
    var err = Data()
    var timer: DispatchWorkItem?

    var timedOut: Bool { lock.withLock { _timedOut } }
    var failedToStart: Bool { lock.withLock { _failedToStart } }
    var status: Int32 { lock.withLock { _status } }
    func setStatus(_ value: Int32) { lock.withLock { _status = value } }
    func claimResume() -> Bool {
        lock.withLock {
            defer { resumed = true }
            return !resumed
        }
    }
    func markTimedOut() { lock.withLock { _timedOut = true } }
    func markFailedToStart() { lock.withLock { _failedToStart = true } }
}
