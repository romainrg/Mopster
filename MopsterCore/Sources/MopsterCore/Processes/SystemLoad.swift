import Darwin
import Foundation

public enum MemoryPressure: Sendable, Equatable {
    case normal, warning, critical

    /// `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
    init(level: Int32) {
        switch level {
        case 2: self = .warning
        case 4: self = .critical
        default: self = .normal
        }
    }

    static func current() -> MemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        return MemoryPressure(level: level)
    }
}

public struct SystemLoad: Sendable, Equatable {
    public var memoryPressure: MemoryPressure
    /// 0...1
    public var cpuLoad: Double

    public init(memoryPressure: MemoryPressure, cpuLoad: Double) {
        self.memoryPressure = memoryPressure
        self.cpuLoad = cpuLoad
    }
}

/// CPU load from the delta of `host_statistics` ticks between calls; 0 on the first call.
final class CPULoadMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: (busy: UInt64, total: UInt64)?

    func load() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        return lock.withLock {
            defer { previous = (busy, total) }
            guard let previous, total > previous.total else { return 0 }
            return min(1, max(0, Double(busy - previous.busy) / Double(total - previous.total)))
        }
    }
}

public protocol ProcessSampling: Sendable {
    func sample() async -> (processes: [ProcessSample], load: SystemLoad)
}

/// Owns a sampler and serializes calls.
public actor LiveProcessSampling: ProcessSampling {
    private let sampler = ProcessSampler()
    private let cpu = CPULoadMonitor()

    public init() {}

    public func sample() async -> (processes: [ProcessSample], load: SystemLoad) {
        let processes = sampler.sample()
        return (processes, SystemLoad(memoryPressure: .current(), cpuLoad: cpu.load()))
    }
}
