import Foundation
import XCTest

@testable import MopsterCore

final class ProcessSamplerTests: XCTestCase {
    func testCpuPercentFromDelta() {
        XCTAssertEqual(
            ProcessSampler.cpuPercent(previousNanos: 1_000_000_000, currentNanos: 1_500_000_000, elapsed: 1),
            50, accuracy: 0.001)
    }

    func testCpuPercentCanExceedOneHundredOnMultipleCores() {
        XCTAssertEqual(
            ProcessSampler.cpuPercent(previousNanos: 0, currentNanos: 3_000_000_000, elapsed: 1.5), 200, accuracy: 0.001)
    }

    func testCpuPercentIsZeroWithoutElapsedTimeOrWhenCounterGoesBack() {
        XCTAssertEqual(ProcessSampler.cpuPercent(previousNanos: 0, currentNanos: 10, elapsed: 0), 0)
        XCTAssertEqual(ProcessSampler.cpuPercent(previousNanos: 100, currentNanos: 10, elapsed: 1), 0)
    }

    func testCurrentProcessIsSampled() {
        let sampler = ProcessSampler()
        let me = sampler.sample().first { $0.pid == getpid() }
        XCTAssertNotNil(me)
        XCTAssertGreaterThan(me?.memoryBytes ?? 0, 0)
        XCTAssertEqual(me?.uid, getuid())
        XCTAssertEqual(me?.cpuPercent, 0, "first sample of a pid is 0%")
    }

    func testBusyLoopShowsCpuOnSecondSample() {
        let sampler = ProcessSampler()
        _ = sampler.sample()
        let end = Date().addingTimeInterval(0.4)
        var x = 0.0
        while Date() < end { x += sqrt(Double.random(in: 1...2)) }
        XCTAssertGreaterThan(x, 0)
        let me = sampler.sample().first { $0.pid == getpid() }
        XCTAssertGreaterThan(me?.cpuPercent ?? 0, 20)
    }

    func testUnknownPidsAreSkipped() {
        XCTAssertNil(ProcessSampler.read(pid: Int32.max))
        XCTAssertNil(ProcessSampler.read(pid: -1))
    }

    func testBundleURLIsNearestEnclosingApp() {
        XCTAssertEqual(
            ProcessSampler.bundleURL(forExecutable: "/Applications/Foo.app/Contents/MacOS/Foo")?.path,
            "/Applications/Foo.app")
        XCTAssertEqual(
            ProcessSampler.bundleURL(forExecutable: "/Applications/Foo.app/Contents/Frameworks/Bar.app/Contents/MacOS/Bar")?
                .path,
            "/Applications/Foo.app/Contents/Frameworks/Bar.app")
        XCTAssertNil(ProcessSampler.bundleURL(forExecutable: "/usr/bin/yes"))
    }

    func testMemoryPressureMapping() {
        XCTAssertEqual(MemoryPressure(level: 1), .normal)
        XCTAssertEqual(MemoryPressure(level: 2), .warning)
        XCTAssertEqual(MemoryPressure(level: 4), .critical)
        XCTAssertEqual(MemoryPressure(level: 3), .normal)
        XCTAssertEqual(MemoryPressure(level: 0), .normal)
    }

    func testCpuLoadIsZeroFirstThenBounded() {
        let monitor = CPULoadMonitor()
        XCTAssertEqual(monitor.load(), 0)
        let end = Date().addingTimeInterval(0.2)
        while Date() < end {}
        let load = monitor.load()
        XCTAssertGreaterThanOrEqual(load, 0)
        XCTAssertLessThanOrEqual(load, 1)
    }

    func testLiveSamplingReturnsProcessesAndLoad() async {
        let live = LiveProcessSampling()
        let result = await live.sample()
        XCTAssertTrue(result.processes.contains { $0.pid == getpid() })
    }
}

final class ProcessControlPolicyTests: XCTestCase {
    private let me: uid_t = 501
    private let ownPID: pid_t = 4242

    private func sample(pid: pid_t = 100, uid: uid_t = 501, path: String?) -> ProcessSample {
        ProcessSample(pid: pid, name: "x", uid: uid, path: path, cpuPercent: 0, memoryBytes: 1, bundleURL: nil)
    }

    private func canQuit(_ p: ProcessSample) -> Bool {
        ProcessControlPolicy.canQuit(p, currentUID: me, ownPID: ownPID)
    }

    func testOwnPidCannotBeQuit() {
        XCTAssertFalse(canQuit(sample(pid: ownPID, path: "/Applications/Mopster.app/Contents/MacOS/Mopster")))
    }

    func testOtherUidCannotBeQuit() {
        XCTAssertFalse(canQuit(sample(uid: 0, path: "/Applications/Foo.app/Contents/MacOS/Foo")))
    }

    func testSystemPathsCannotBeQuit() {
        XCTAssertFalse(canQuit(sample(path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow")))
        XCTAssertFalse(canQuit(sample(path: "/usr/libexec/x")))
        XCTAssertFalse(canQuit(sample(path: "/bin/sh")))
        XCTAssertFalse(canQuit(sample(path: "/sbin/launchd")))
        XCTAssertFalse(canQuit(sample(path: "/Library/Apple/System/Library/x")))
        XCTAssertFalse(canQuit(sample(path: "/private/var/db/x")))
    }

    func testUserApplicationsCanBeQuit() {
        XCTAssertTrue(canQuit(sample(path: "/Applications/Foo.app/Contents/MacOS/Foo")))
        XCTAssertTrue(canQuit(sample(path: "/Users/x/bin/tool")))
    }

    func testUnknownPathCannotBeQuit() {
        XCTAssertFalse(canQuit(sample(path: nil)))
        XCTAssertFalse(canQuit(sample(path: "")))
    }
}
