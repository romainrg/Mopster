import XCTest

@testable import MopsterCore

final class AppleScriptQuotingTests: XCTestCase {
    func testQuotesBackslashesAndUnicode() {
        XCTAssertEqual(AppleScriptQuoting.literal(#"/a "b" \c/é😀"#), #""/a \"b\" \\c/é😀""#)
    }

    func testNewlinesAndDecomposedUnicodePassThrough() {
        let nfd = "e\u{301}"
        XCTAssertEqual(AppleScriptQuoting.literal("a\nb\(nfd)"), "\"a\nb\(nfd)\"")
    }
}
