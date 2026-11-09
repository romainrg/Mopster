import XCTest

@testable import MopsterCore

final class LaunchAgentControlTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [[String]] = []
        var calls: [[String]] { lock.withLock { _calls } }
        func record(_ args: [String]) { lock.withLock { _calls.append(args) } }
    }

    private func item(domain: LaunchDomain = .userAgents, label: String? = "com.example.agent") -> InspectedLaunchItem {
        InspectedLaunchItem(
            item: LaunchItem(
                plist: URL(fileURLWithPath: "/Users/me/Library/LaunchAgents/com.example.agent.plist"),
                label: label, program: "/usr/bin/true", domain: domain, isUnreadable: false),
            signature: .unsigned, flags: [], isDisabled: false)
    }

    private func control(_ recorder: Recorder, failing: Set<String> = []) -> LiveLaunchAgentControl {
        LiveLaunchAgentControl(uid: 501) { exe, args in
            XCTAssertEqual(exe, "/bin/launchctl")
            recorder.record(args)
            return (failing.contains(args[0]) ? 1 : 0, "", "boom")
        }
    }

    func testDisableRunsBootoutThenDisable() async throws {
        let recorder = Recorder()
        try await control(recorder).disable(item())
        XCTAssertEqual(
            recorder.calls, [["bootout", "gui/501/com.example.agent"], ["disable", "gui/501/com.example.agent"]])
    }

    func testBootoutFailureIsIgnored() async throws {
        let recorder = Recorder()
        try await control(recorder, failing: ["bootout"]).disable(item())
        XCTAssertEqual(recorder.calls.count, 2)
    }

    func testDisableFailureThrows() async {
        let recorder = Recorder()
        do {
            try await control(recorder, failing: ["disable"]).disable(item())
            XCTFail("expected a throw")
        } catch {}
    }

    func testEnableRunsEnableThenBootstrapAndIgnoresBootstrapFailure() async throws {
        let recorder = Recorder()
        try await control(recorder, failing: ["bootstrap"]).enable(item())
        XCTAssertEqual(
            recorder.calls,
            [
                ["enable", "gui/501/com.example.agent"],
                ["bootstrap", "gui/501", "/Users/me/Library/LaunchAgents/com.example.agent.plist"],
            ])
    }

    func testEnableFailureThrows() async {
        do {
            try await control(Recorder(), failing: ["enable"]).enable(item())
            XCTFail("expected a throw")
        } catch {}
    }

    func testOnlyUserAgentsAreAllowed() async {
        for domain in [LaunchDomain.systemAgents, .systemDaemons] {
            let recorder = Recorder()
            do {
                try await control(recorder).disable(item(domain: domain))
                XCTFail("expected a throw")
            } catch {}
            do {
                try await control(recorder).enable(item(domain: domain))
                XCTFail("expected a throw")
            } catch {}
            XCTAssertTrue(recorder.calls.isEmpty)
        }
    }

    func testItemWithoutLabelThrows() async {
        do {
            try await control(Recorder()).disable(item(label: nil))
            XCTFail("expected a throw")
        } catch {}
    }
}
