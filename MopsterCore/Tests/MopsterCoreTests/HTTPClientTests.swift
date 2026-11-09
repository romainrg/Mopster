import XCTest
@testable import MopsterCore

final class HTTPClientTests: XCTestCase {
    private func stream(_ count: Int) -> AsyncStream<UInt8> {
        AsyncStream { continuation in
            for _ in 0..<count { continuation.yield(7) }
            continuation.finish()
        }
    }

    func testCollectAcceptsExactlyTheLimit() async throws {
        let data = try await URLSessionHTTPClient.collect(stream(100), limit: 100)
        XCTAssertEqual(data.count, 100)
    }

    func testCollectRejectsOneByteOverTheLimit() async {
        do {
            _ = try await URLSessionHTTPClient.collect(stream(101), limit: 100)
            XCTFail("expected a throw")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .dataLengthExceedsMaximum)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
