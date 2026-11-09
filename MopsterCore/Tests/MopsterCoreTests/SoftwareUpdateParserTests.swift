import XCTest
@testable import MopsterCore

final class SoftwareUpdateParserTests: XCTestCase {
    func testModernFormat() {
        let output = """
            Software Update Tool

            Finding available software
            Software Update found the following new or updated software:
            * Label: macOS Sonoma 14.4.1-23E224
            \tTitle: macOS Sonoma 14.4.1, Version: 14.4.1, Size: 1234567KiB, Recommended: YES, Action: restart,
            * Label: Safari17.4.1SonomaAuto-17.4.1
            \tTitle: Safari, Version: 17.4.1, Size: 150000KiB, Recommended: NO, Action: none,
            """
        let updates = SoftwareUpdateParser.parse(output)
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].label, "macOS Sonoma 14.4.1-23E224")
        XCTAssertEqual(updates[0].title, "macOS Sonoma 14.4.1")
        XCTAssertEqual(updates[0].version, "14.4.1")
        XCTAssertTrue(updates[0].recommended)
        XCTAssertTrue(updates[0].restart)
        XCTAssertEqual(updates[1].title, "Safari")
        XCTAssertFalse(updates[1].recommended)
        XCTAssertFalse(updates[1].restart)
    }

    func testLegacyFormat() {
        let output = """
            Software Update Tool

            Finding available software

            Software Update found the following new or updated software:
               * macOS Sonoma 14.4.1-23E224
            \tmacOS Sonoma 14.4.1 (14.4.1), 1234567K [recommended] [restart]
               * Safari17.4.1-17.4.1
            \tSafari (17.4.1), 150000K
            """
        let updates = SoftwareUpdateParser.parse(output)
        XCTAssertEqual(updates.count, 2)
        XCTAssertEqual(updates[0].label, "macOS Sonoma 14.4.1-23E224")
        XCTAssertEqual(updates[0].title, "macOS Sonoma 14.4.1")
        XCTAssertEqual(updates[0].version, "14.4.1")
        XCTAssertTrue(updates[0].recommended)
        XCTAssertTrue(updates[0].restart)
        XCTAssertFalse(updates[1].recommended)
        XCTAssertFalse(updates[1].restart)
    }

    func testRealMacOutputWithoutActionField() {
        let output = """
            Software Update Tool

            Finding available software
            Software Update found the following new or updated software:
            * Label: Command Line Tools for Xcode 27.2-27.2
            \tTitle: Command Line Tools for Xcode 27.2, Version: 27.2, Size: 521120KiB, Recommended: YES, 
            * Label: macOS 27.2-26B123
            \tTitle: macOS 27.2, Version: 27.2, Size: 6067473KiB, Recommended: YES, Action: restart,
            """
        let updates = SoftwareUpdateParser.parse(output)
        XCTAssertEqual(updates.map(\.version), ["27.2", "27.2"])
        XCTAssertEqual(updates.map(\.restart), [false, true])
        XCTAssertEqual(updates.map(\.recommended), [true, true])
    }

    func testNoNewSoftware() {
        XCTAssertEqual(
            SoftwareUpdateParser.parse("Software Update Tool\n\nFinding available software\nNo new software available.\n"),
            [])
    }

    func testUnknownTextIsEmpty() {
        XCTAssertEqual(SoftwareUpdateParser.parse("something unexpected\nhappened"), [])
        XCTAssertEqual(SoftwareUpdateParser.parse(""), [])
    }
}
