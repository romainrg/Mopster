import XCTest
@testable import MopsterCore

final class MaintenanceBatchTests: XCTestCase {
    private func task(_ id: String, _ steps: [[String]], admin: Bool = true) -> MaintenanceTask {
        MaintenanceTask(
            id: id, title: L("t", "T"), explanation: L("e", "E"), steps: steps, needsAdmin: admin)
    }

    func testScriptEchoesOneResultPerTask() {
        let script = MaintenanceBatch.adminScript(for: [
            task("a", [["/bin/echo", "x"]]), task("b", [["/bin/echo", "1"], ["/bin/echo", "2"]]),
        ])
        XCTAssertTrue(script.hasPrefix("#!/bin/sh\n"))
        XCTAssertFalse(script.contains("set -e"))
        XCTAssertEqual(script.components(separatedBy: "MOPSTER_RESULT").count - 1, 2)
        XCTAssertTrue(script.contains("printf '\\nMOPSTER_RESULT %s %d\\n' a $?"))
        XCTAssertTrue(script.contains("printf '\\nMOPSTER_RESULT %s %d\\n' b $?"))
        XCTAssertTrue(script.contains("('/bin/echo' '1' && '/bin/echo' '2')"))
    }

    func testOnlyAdminTasksGoInTheScript() {
        let script = MaintenanceBatch.adminScript(for: [
            task("a", [["/bin/echo"]]), task("b", [["/bin/echo"]], admin: false),
        ])
        XCTAssertTrue(script.contains("MOPSTER_RESULT %s %d\\n' a "))
        XCTAssertFalse(script.contains("MOPSTER_RESULT %s %d\\n' b "))
    }

    func testCommandArgumentsAreSingleQuoteEscaped() {
        let script = MaintenanceBatch.adminScript(for: [task("a", [["/bin/echo", "it's"]])])
        XCTAssertTrue(script.contains("'it'\\''s'"))
    }

    func testParseResultsMapsExitCodes() {
        let output = "noise\nMOPSTER_RESULT a 0\nMOPSTER_RESULT b 1\nMOPSTER_RESULT c 127\n"
        XCTAssertEqual(MaintenanceBatch.parseResults(output), ["a": 0, "b": 1, "c": 127])
    }

    func testOutputWithoutTrailingNewlineStillParses() async throws {
        let tasks = [task("a", [["/usr/bin/printf", "no newline"]]), task("b", [["/usr/bin/true"]])]
        let result = try await ProcessRunner.run("/bin/sh", ["-c", MaintenanceBatch.adminScript(for: tasks)])
        XCTAssertEqual(MaintenanceBatch.parseResults(result.stdout), ["a": 0, "b": 0])
        XCTAssertEqual(MaintenanceBatch.withoutResultLines(result.stdout), "no newline")
    }

    func testParseToleratesExtraWhitespace() {
        XCTAssertEqual(MaintenanceBatch.parseResults("  MOPSTER_RESULT  a   0 \n\tMOPSTER_RESULT b 3\r\n"), ["a": 0, "b": 3])
    }

    func testCatalogIdsAreShellSafe() {
        for task in MaintenanceCatalog.tasks {
            XCTAssertNotNil(task.id.range(of: "^[A-Za-z0-9]+$", options: .regularExpression), task.id)
        }
    }

    func testMissingResultLineMeansFailed() {
        let tasks = [task("a", [["/bin/echo"]]), task("b", [["/bin/echo"]])]
        let codes = MaintenanceBatch.parseResults("MOPSTER_RESULT a 0\n")
        XCTAssertTrue(MaintenanceBatch.succeeded(tasks[0], in: codes))
        XCTAssertFalse(MaintenanceBatch.succeeded(tasks[1], in: codes))
    }

    /// Guards the hard rule "no task may delete user data": only known, harmless commands may appear in the catalog.
    func testEveryStepUsesAnAllowedExecutable() {
        let lsregister =
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        let allowed: Set<String> = [
            "/usr/sbin/purge", "/usr/bin/dscacheutil", "/usr/bin/killall", "/usr/bin/mdutil", lsregister,
            "/usr/bin/atsutil", "/usr/bin/qlmanage", "/usr/sbin/diskutil",
        ]
        let exactArguments: [String: [String]] = [
            "/usr/sbin/diskutil": ["verifyVolume", "/"],
            "/usr/bin/atsutil": ["databases", "-removeUser"],
            "/usr/bin/killall": ["-HUP", "mDNSResponder"],
        ]
        let forbidden = ["/bin/sh", "/bin/bash", "-c", "-delete"]
        let hint = "Adding a maintenance task? Justify it in review and extend this allowlist deliberately."
        for task in MaintenanceCatalog.tasks {
            for step in task.steps {
                let executable = step[0]
                XCTAssertTrue(allowed.contains(executable), "\(task.id): \(executable) is not allowed. \(hint)")
                if let exact = exactArguments[executable] {
                    XCTAssertEqual(Array(step.dropFirst()), exact, "\(task.id): unexpected arguments. \(hint)")
                }
                for argument in step {
                    XCTAssertFalse(forbidden.contains(argument), "\(task.id): \(argument). \(hint)")
                    XCTAssertFalse(argument.lowercased().contains("erase"),
                        "\(task.id): \(argument). \(hint)")
                }
            }
        }
    }

    func testCatalogIdsAreUniqueAndStringsLocalized() throws {
        let ids = MaintenanceCatalog.tasks.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.count, 7)
        try assertCatalogContains(MaintenanceCatalog.tasks.flatMap { [$0.title, $0.explanation] })
    }

    func testScriptRunsThroughShWithoutPrivilegesAndReportsFailures() async throws {
        let tasks = [task("ok", [["/usr/bin/true"]]), task("bad", [["/usr/bin/true"], ["/usr/bin/false"]])]
        let result = try await ProcessRunner.run("/bin/sh", ["-c", MaintenanceBatch.adminScript(for: tasks)])
        let codes = MaintenanceBatch.parseResults(result.stdout)
        XCTAssertEqual(codes["ok"], 0)
        XCTAssertEqual(codes["bad"], 1)
    }
}

final class LiveMaintenanceRunnerTests: XCTestCase {
    func testStepsStopAtFirstFailure() async {
        let task = MaintenanceTask(
            id: "t", title: L("t", "T"), explanation: L("e", "E"),
            steps: [["/usr/bin/true"], ["/usr/bin/false"], ["/bin/echo", "never"]], needsAdmin: false)
        let outcomes = await LiveMaintenanceRunner().run([task])
        XCTAssertEqual(outcomes["t"], .failed(""))
    }

    func testNonAdminSuccessKeepsOutput() async {
        let task = MaintenanceTask(
            id: "t", title: L("t", "T"), explanation: L("e", "E"), steps: [["/bin/echo", "hi"]], needsAdmin: false)
        let outcomes = await LiveMaintenanceRunner().run([task])
        XCTAssertEqual(outcomes["t"], .succeeded("hi"))
    }

    func testResultLinesSurviveCarriageReturns() {
        XCTAssertEqual(MaintenanceBatch.parseResults("a\rMOPSTER_RESULT x 0\rMOPSTER_RESULT y 2\r"), ["x": 0, "y": 2])
    }

    func testErrorMessagesAreLocalized() throws {
        try assertCatalogContains([
            L("maintenance.error.timedOut", "The command took too long and was stopped."),
            L("maintenance.error.notFound", "The command is not available on this Mac."),
        ])
    }
}
