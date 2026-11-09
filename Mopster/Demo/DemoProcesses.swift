import Foundation
import MopsterCore

/// Fictional processes with slight jitter per call; quitting removes one from the in-memory list.
final class DemoProcessSampling: ProcessSampling, @unchecked Sendable {
    private struct Base {
        let pid: pid_t
        let name: String
        let cpu: Double
        let megabytes: Double
        let path: String
        var uid: uid_t = getuid()
    }

    private let lock = NSLock()
    private var removed: Set<pid_t> = []

    private static let bases = [
        Base(pid: 4101, name: "Photo Editor", cpu: 38, megabytes: 1850, path: "/Applications/Photo Editor.app/Contents/MacOS/Photo Editor"),
        Base(pid: 4102, name: "Web Browser", cpu: 22, megabytes: 2400, path: "/Applications/Web Browser.app/Contents/MacOS/Web Browser"),
        Base(pid: 4103, name: "Video Converter", cpu: 96, megabytes: 780, path: "/Applications/Video Converter.app/Contents/MacOS/Video Converter"),
        Base(pid: 4104, name: "Music", cpu: 4.5, megabytes: 420, path: "/Applications/Music.app/Contents/MacOS/Music"),
        Base(pid: 4105, name: "Notes", cpu: 0.8, megabytes: 310, path: "/Applications/Notes.app/Contents/MacOS/Notes"),
        Base(pid: 4106, name: "Code Editor", cpu: 11, megabytes: 1320, path: "/Applications/Code Editor.app/Contents/MacOS/Code Editor"),
        Base(pid: 4107, name: "Chat", cpu: 2.4, megabytes: 640, path: "/Applications/Chat.app/Contents/MacOS/Chat"),
        Base(pid: 4108, name: "Terminal", cpu: 0.3, megabytes: 120, path: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
        Base(pid: 4109, name: "Spreadsheet", cpu: 1.6, megabytes: 540, path: "/Applications/Spreadsheet.app/Contents/MacOS/Spreadsheet"),
        Base(pid: 4110, name: "Cloud Sync", cpu: 6.5, megabytes: 230, path: "/Applications/Cloud Sync.app/Contents/MacOS/Cloud Sync"),
        Base(pid: 4111, name: "Calendar", cpu: 0.2, megabytes: 180, path: "/Applications/Calendar.app/Contents/MacOS/Calendar"),
        Base(pid: 4112, name: "Weather", cpu: 1.1, megabytes: 95, path: "/Applications/Weather.app/Contents/MacOS/Weather"),
        Base(pid: 301, name: "WindowServer", cpu: 14, megabytes: 760, path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", uid: 88),
        Base(pid: 188, name: "kernel_task", cpu: 9, megabytes: 410, path: "/System/Library/Kernels/kernel", uid: 0),
        Base(pid: 412, name: "mds_stores", cpu: 3.2, megabytes: 520, path: "/System/Library/Frameworks/CoreServices.framework/Frameworks/Metadata.framework/Support/mds_stores", uid: 0),
    ]

    func sample() async -> (processes: [ProcessSample], load: SystemLoad) {
        let gone = lock.withLock { removed }
        let processes = Self.bases.filter { !gone.contains($0.pid) }.map { base in
            let jitter = Double.random(in: 0.9...1.1)
            return ProcessSample(
                pid: base.pid, name: base.name, uid: base.uid, path: base.path,
                cpuPercent: base.cpu * jitter, memoryBytes: UInt64(base.megabytes * jitter * 1_048_576),
                bundleURL: base.path.range(of: ".app/").map { URL(fileURLWithPath: String(base.path[..<$0.lowerBound]) + ".app") })
        }
        return (processes, SystemLoad(memoryPressure: .normal, cpuLoad: 0.34))
    }

    func remove(_ pid: pid_t) { lock.withLock { _ = removed.insert(pid) } }
}

@MainActor
struct DemoProcessControl: ProcessControlling {
    let sampling: DemoProcessSampling

    func quit(_ process: ProcessSample) -> Bool {
        sampling.remove(process.pid)
        return true
    }

    func forceQuit(_ process: ProcessSample) -> Bool { quit(process) }
}
