import Darwin
import Foundation

public struct ProcessSample: Identifiable, Sendable, Equatable {
    public let pid: pid_t
    public let name: String
    public let uid: uid_t
    public let path: String?
    /// Can exceed 100 on multiple cores, like Activity Monitor.
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let bundleURL: URL?

    public var id: pid_t { pid }

    public init(
        pid: pid_t, name: String, uid: uid_t, path: String?, cpuPercent: Double, memoryBytes: UInt64, bundleURL: URL?
    ) {
        self.pid = pid
        self.name = name
        self.uid = uid
        self.path = path
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.bundleURL = bundleURL
    }
}

/// Lists running processes with CPU% computed from the delta between two calls.
/// Not thread-safe: `LiveProcessSampling` serializes access.
public final class ProcessSampler {
    private struct Previous {
        var nanos: UInt64
        var time: TimeInterval
    }

    private var previous: [pid_t: Previous] = [:]
    private let now: () -> TimeInterval

    public init() {
        now = { ProcessInfo.processInfo.systemUptime }
    }

    init(now: @escaping () -> TimeInterval) { self.now = now }

    public func sample() -> [ProcessSample] {
        let time = now()
        var current: [pid_t: Previous] = [:]
        var samples: [ProcessSample] = []
        for pid in Self.allPIDs() {
            guard let raw = Self.read(pid: pid) else { continue }
            var percent = 0.0
            if let before = previous[pid] {
                percent = Self.cpuPercent(
                    previousNanos: before.nanos, currentNanos: raw.nanos, elapsed: time - before.time)
            }
            current[pid] = Previous(nanos: raw.nanos, time: time)
            samples.append(
                ProcessSample(
                    pid: pid, name: raw.name, uid: raw.uid, path: raw.path, cpuPercent: percent,
                    memoryBytes: raw.memory, bundleURL: raw.path.flatMap(Self.bundleURL(forExecutable:))))
        }
        previous = current
        return samples
    }

    /// Fresh single-process read (CPU 0), used to re-check a pid right before acting on it.
    public static func snapshot(pid: pid_t) -> ProcessSample? {
        guard let raw = read(pid: pid) else { return nil }
        return ProcessSample(
            pid: pid, name: raw.name, uid: raw.uid, path: raw.path, cpuPercent: 0, memoryBytes: raw.memory,
            bundleURL: raw.path.flatMap(bundleURL(forExecutable:)))
    }

    /// CPU time in nanoseconds, elapsed time in seconds.
    public static func cpuPercent(previousNanos: UInt64, currentNanos: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, currentNanos >= previousNanos else { return 0 }
        return Double(currentNanos - previousNanos) / (elapsed * 1_000_000_000) * 100
    }

    /// Nearest enclosing `.app` of an executable path.
    static func bundleURL(forExecutable path: String) -> URL? {
        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" { return url }
            url.deleteLastPathComponent()
        }
        return nil
    }

    struct Raw {
        var name: String
        var uid: uid_t
        var path: String?
        var nanos: UInt64
        var memory: UInt64
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info.denom == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : info
    }()

    private static func allPIDs() -> [pid_t] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) * 2)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    /// Nil when the process is gone or its info is not readable.
    static func read(pid: pid_t) -> Raw? {
        guard pid > 0 else { return nil }
        var task = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize else { return nil }
        var bsd = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, bsdSize) == bsdSize else { return nil }

        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = pathLength > 0 ? String(cString: pathBuffer) : nil

        var nameBuffer = [CChar](repeating: 0, count: 256)
        var name = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 ? String(cString: nameBuffer) : ""
        if name.isEmpty { name = path.map { ($0 as NSString).lastPathComponent } ?? "" }
        if name.isEmpty { name = "pid \(pid)" }

        let ticks = task.pti_total_user &+ task.pti_total_system
        let nanos = ticks / UInt64(timebase.denom) * UInt64(timebase.numer)
            + ticks % UInt64(timebase.denom) * UInt64(timebase.numer) / UInt64(timebase.denom)
        return Raw(name: name, uid: bsd.pbi_uid, path: path, nanos: nanos, memory: task.pti_resident_size)
    }
}
