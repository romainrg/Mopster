import XCTest

@testable import MopsterCore

final class PersistenceFlagsTests: XCTestCase {
    private func item(label: String? = "com.example.agent", program: String? = "/usr/local/bin/x", unreadable: Bool = false)
        -> LaunchItem
    {
        LaunchItem(
            plist: URL(fileURLWithPath: "/tmp/x.plist"), label: label, program: program, domain: .userAgents,
            isUnreadable: unreadable)
    }

    func testMissingProgramIsFlagged() {
        XCTAssertEqual(PersistenceFlags.flags(for: item(), signature: .missing), [.programMissing])
    }

    func testUnsignedAndAdHoc() {
        XCTAssertEqual(PersistenceFlags.flags(for: item(), signature: .unsigned), [.unsignedOrAdHoc])
        XCTAssertEqual(PersistenceFlags.flags(for: item(), signature: .adHoc), [.unsignedOrAdHoc])
        XCTAssertEqual(PersistenceFlags.flags(for: item(), signature: .apple), [])
        XCTAssertEqual(PersistenceFlags.flags(for: item(), signature: .developerID(team: "ABC")), [])
    }

    func testHiddenOrTemporaryLocations() {
        for path in [
            "/tmp/x", "/private/tmp/x", "/var/tmp/x", "/private/var/tmp/x", "/Users/Shared/x",
            "/Users/me/.hidden/x", "/Users/me/Library/.agent",
        ] {
            XCTAssertTrue(
                PersistenceFlags.flags(for: item(program: path), signature: .developerID(team: "T"))
                    .contains(.hiddenOrTemporaryLocation), path)
        }
        XCTAssertFalse(
            PersistenceFlags.flags(for: item(program: "/tmpfoo/x"), signature: .apple)
                .contains(.hiddenOrTemporaryLocation))
        XCTAssertFalse(
            PersistenceFlags.flags(for: item(program: "/Applications/A.app/x"), signature: .apple)
                .contains(.hiddenOrTemporaryLocation))
    }

    func testKnownAdwareMatchesLabelCaseInsensitively() {
        XCTAssertEqual(
            PersistenceFlags.flags(for: item(label: "com.Pirrit.agent"), signature: .apple), [.knownAdware("pirrit")])
    }

    func testKnownAdwareMatchesPath() {
        XCTAssertEqual(
            PersistenceFlags.flags(for: item(program: "/Applications/MacKeeper.app/x"), signature: .apple),
            [.knownAdware("mackeeper")])
    }

    func testUnreadableGetsNoFlags() {
        XCTAssertEqual(
            PersistenceFlags.flags(for: item(label: nil, program: nil, unreadable: true), signature: .missing), [])
    }

    func testFlagsAreOrderedDeterministically() {
        let flags = PersistenceFlags.flags(
            for: item(label: "com.genieo.x", program: "/tmp/.x"), signature: .unsigned)
        XCTAssertEqual(flags, [.unsignedOrAdHoc, .hiddenOrTemporaryLocation, .knownAdware("genieo")])
    }

    func testOrdinaryWordsAndDirectoryNamesAreNotAdware() {
        let apple = item(label: "com.apple.threadloader.agent", program: "/usr/libexec/ThreadLoader")
        XCTAssertEqual(PersistenceFlags.flags(for: apple, signature: .apple), [])
        let directory = item(label: "com.x.tool", program: "/Users/x/Projects/pirrit-research/tool")
        XCTAssertEqual(PersistenceFlags.flags(for: directory, signature: .apple), [])
        XCTAssertEqual(
            PersistenceFlags.flags(for: item(label: "com.conduit.spigot"), signature: .apple), [])
    }

    func testAdwareTokensMatchLabelAndProgramName() {
        XCTAssertEqual(
            PersistenceFlags.flags(for: item(label: "com.pirrit.agent"), signature: .apple), [.knownAdware("pirrit")])
        XCTAssertEqual(
            PersistenceFlags.flags(
                for: item(label: "com.x.y", program: "/Library/Application Support/Pirrit/pirrit"), signature: .apple),
            [.knownAdware("pirrit")])
    }

    func testRelativeProgramIsNeutral() {
        XCTAssertEqual(PersistenceFlags.flags(for: item(program: "bash"), signature: .missing), [])
    }
}
