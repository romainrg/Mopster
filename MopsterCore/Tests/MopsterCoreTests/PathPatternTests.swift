import XCTest

@testable import MopsterCore

final class PathPatternTests: XCTestCase {
    func testTildeAndStarExpandToExistingChildren() throws {
        let home = try makeTemporaryTree([
            "Library/Caches/a/": 0, "Library/Caches/b/": 0, "Library/Caches/.hidden/": 0,
        ])
        let result = PathPattern.expand("~/Library/Caches/*", home: home)
        XCTAssertEqual(result.map(\.lastPathComponent), ["a", "b"])
        XCTAssertTrue(result.allSatisfy { $0.isFileURL })
    }

    func testPatternWithSpacesAndUnicode() throws {
        let nfd = "E\u{301}te\u{301}"
        let nfc = "\u{C9}t\u{E9}"
        let home = try makeTemporaryTree([
            "Library/Saved Application State/com.x.savedState/": 0, "\(nfd)/": 0,
        ])
        XCTAssertEqual(PathPattern.expand("~/Library/Saved Application State/*", home: home).count, 1)
        XCTAssertEqual(PathPattern.expand("~/\(nfc)", home: home).count, 1)
        XCTAssertEqual(PathPattern.expand("~/\(nfc.dropLast())*", home: home).count, 1)
        let entry = try XCTUnwrap(PathPattern.expand("~/*", home: home).first { $0.lastPathComponent.unicodeScalars.first == "E" })
        XCTAssertTrue(PathPattern.matches(entry, pattern: "~/\(nfc)", home: home))
    }

    func testMissingLiteralComponentYieldsEmpty() throws {
        let home = try makeTemporaryTree(["Library/Caches/a/": 0])
        XCTAssertEqual(PathPattern.expand("~/Library/Nope/*", home: home), [])
        XCTAssertEqual(PathPattern.expand("~/Nope", home: home), [])
    }

    func testAbsolutePatternAndMiddleStar() throws {
        let home = try makeTemporaryTree(["Library/Caches/com.a/x/": 0, "Library/Caches/com.b/x/": 0, "Library/Caches/com.b/y/": 0])
        let result = PathPattern.expand("\(home.path)/Library/Caches/com.*/x", home: home)
        XCTAssertEqual(result.map { $0.deletingLastPathComponent().lastPathComponent }, ["com.a", "com.b"])
    }

    func testMatches() throws {
        let home = try makeTemporaryTree(["Library/Caches/a/": 0])
        let a = home.appendingPathComponent("Library/Caches/a")
        XCTAssertTrue(PathPattern.matches(a, pattern: "~/Library/Caches/*", home: home))
        XCTAssertFalse(PathPattern.matches(a, pattern: "~/Library/Logs/*", home: home))
        XCTAssertFalse(PathPattern.matches(a, pattern: "~/Library/*", home: home))
        XCTAssertFalse(PathPattern.matches(a.appendingPathComponent(".x"), pattern: "~/Library/Caches/a/*", home: home))
    }

    func testHomeWithGlobAndSpecialCharactersIsLiteral() throws {
        let container = try makeTemporaryTree([:])
        let home = container.appendingPathComponent("h[x] * ? \"q\" b\\s \u{1F600}", isDirectory: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Caches/a"), withIntermediateDirectories: true)
        let expected = home.appendingPathComponent("Library/Caches/a").standardizedFileURL
        XCTAssertEqual(PathPattern.expand("~/Library/Caches/*", home: home), [expected])
        XCTAssertEqual(PathPattern.expand("~/Library/Caches/a", home: home), [expected])
        XCTAssertTrue(PathPattern.matches(expected, pattern: "~/Library/Caches/*", home: home))
        XCTAssertTrue(PathPattern.matches(expected, pattern: "~/Library/Caches/a", home: home))
    }

    func testLiteralComponentWithQuoteAndBackslash() throws {
        let home = try makeTemporaryTree(["Library/it's \"x\" a\\b/": 0, "Library/it's \"x\" a\\b/c/": 0])
        let entry = home.appendingPathComponent("Library/it's \"x\" a\\b").standardizedFileURL
        let pattern = "~/Library/it's \"x\" a\\b"
        XCTAssertEqual(PathPattern.expand(pattern, home: home), [entry])
        XCTAssertTrue(PathPattern.matches(entry, pattern: pattern, home: home))
        XCTAssertEqual(PathPattern.expand(pattern + "/*", home: home).count, 1)
    }

    func testEmojiNameMatchedByStar() throws {
        let home = try makeTemporaryTree(["Library/Caches/\u{1F4A9} cache/": 0, "Library/Caches/b/": 0])
        let result = PathPattern.expand("~/Library/Caches/*", home: home)
        XCTAssertEqual(result.count, 2)
        for url in result {
            XCTAssertTrue(PathPattern.matches(url, pattern: "~/Library/Caches/*", home: home))
        }
        XCTAssertTrue(result.contains { $0.lastPathComponent == "\u{1F4A9} cache" })
    }
}
