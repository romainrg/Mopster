import XCTest
@testable import MopsterCore

final class AppVersionTests: XCTestCase {
    func testOrdering() {
        let greater: [(String, String)] = [
            ("1.10", "1.9"), ("2024.10.1", "2024.9"), ("10.0", "9.9.9"), ("0.1", ""),
            ("1.0", "1.0b3"), ("1.0b4", "1.0b3"), ("1.2.3 (457)", "1.2.3 (456)"),
            ("1.2.3 (456)", "1.2.3"), ("1.0", "1.0-beta"), ("1.0.1", "1.0"), ("0", ""),
        ]
        for (high, low) in greater {
            XCTAssertGreaterThan(AppVersion(high), AppVersion(low), "\(high) > \(low)")
            XCTAssertLessThan(AppVersion(low), AppVersion(high), "\(low) < \(high)")
        }
    }

    func testEquality() {
        XCTAssertEqual(AppVersion("2"), AppVersion("2.0.0"))
        XCTAssertEqual(AppVersion("1.2.3 (456)"), AppVersion("1.2.3.456"))
        XCTAssertEqual(AppVersion(""), AppVersion("beta"))
        XCTAssertNotEqual(AppVersion("0"), AppVersion(""))
    }

    func testHashableMatchesEquality() {
        XCTAssertEqual(Set([AppVersion("2"), AppVersion("2.0.0"), AppVersion("2.0")]).count, 1)
        XCTAssertEqual(Set([AppVersion("2"), AppVersion("2.1")]).count, 2)
    }

    func testLeadingAlphabeticPrefixIsIgnored() {
        XCTAssertLessThan(AppVersion("v2.0"), AppVersion("v3.0"))
        XCTAssertEqual(AppVersion("v2.0"), AppVersion("2.0"))
        XCTAssertEqual(AppVersion("V3"), AppVersion("3"))
        XCTAssertGreaterThan(AppVersion("v10"), AppVersion("v9.9"))
    }

    func testEqualTailsHashEqually() {
        XCTAssertEqual(AppVersion("1.0b3"), AppVersion("1.0b03"))
        XCTAssertEqual(AppVersion("1.0b3").hashValue, AppVersion("1.0b03").hashValue)
        XCTAssertEqual(Set([AppVersion("1.0b3"), AppVersion("1.0b03"), AppVersion("v1.0b3")]).count, 1)
        XCTAssertEqual(Set([AppVersion("1.0b3"), AppVersion("1.0b4")]).count, 2)
    }
}
