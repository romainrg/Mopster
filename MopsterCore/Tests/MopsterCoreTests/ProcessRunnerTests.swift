import XCTest

@testable import MopsterCore

final class ProcessRunnerTests: XCTestCase {
    func testCapturesOutput() async throws {
        let result = try await ProcessRunner.run("/bin/echo", ["hello world"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "hello world\n")
    }

    func testTimeoutTerminatesAndThrows() async {
        do {
            _ = try await ProcessRunner.run("/bin/sleep", ["5"], timeout: 0.3)
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? ProcessRunnerError, .timedOut)
        }
    }

    func testMissingExecutableThrowsNotFound() async {
        do {
            _ = try await ProcessRunner.run("/nonexistent/bin", [])
            XCTFail("expected notFound")
        } catch {
            XCTAssertEqual(error as? ProcessRunnerError, .notFound)
        }
    }

    func testFastExitingChildNeverLosesOutput() async throws {
        for _ in 0..<200 {
            let result = try await ProcessRunner.run("/bin/echo", ["hello"])
            XCTAssertEqual(result.stdout, "hello\n")
        }
    }
}
