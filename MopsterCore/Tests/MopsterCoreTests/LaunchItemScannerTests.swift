import XCTest

@testable import MopsterCore

final class LaunchItemScannerTests: XCTestCase {
    private func writePlist(_ dict: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
    }

    func testParsesProgramAndProgramArguments() throws {
        let dir = try makeTemporaryTree(["agents/": 0])
        let agents = dir.appendingPathComponent("agents")
        try writePlist(["Label": "com.a.one", "Program": "/usr/bin/one"], to: agents.appendingPathComponent("one.plist"))
        try writePlist(
            ["Label": "com.a.two", "ProgramArguments": ["/usr/bin/two", "--flag"]],
            to: agents.appendingPathComponent("two.plist"))
        try writePlist(
            ["Label": "com.a.both", "Program": "/usr/bin/p", "ProgramArguments": ["/usr/bin/q"]],
            to: agents.appendingPathComponent("both.plist"))
        try Data().write(to: agents.appendingPathComponent("ignored.txt"))

        let items = LaunchItemScanner(directories: [.userAgents: agents]).scan()

        XCTAssertEqual(items.map(\.label), ["com.a.both", "com.a.one", "com.a.two"])
        XCTAssertEqual(items.map(\.program), ["/usr/bin/p", "/usr/bin/one", "/usr/bin/two"])
        XCTAssertTrue(items.allSatisfy { $0.domain == .userAgents && !$0.isUnreadable })
        XCTAssertEqual(items[0].id, items[0].plist.path)
    }

    func testMalformedPlistIsListedAsUnreadable() throws {
        let dir = try makeTemporaryTree(["d/": 0])
        let d = dir.appendingPathComponent("d")
        try Data([0xFF, 0x00, 0x13, 0x37]).write(to: d.appendingPathComponent("x.plist"))

        let items = LaunchItemScanner(directories: [.systemDaemons: d]).scan()

        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isUnreadable)
        XCTAssertNil(items[0].label)
        XCTAssertNil(items[0].program)
    }

    func testMissingDirectoryYieldsNothingAndDomainsAreKept() throws {
        let dir = try makeTemporaryTree(["a/": 0, "b/": 0])
        try writePlist(["Label": "z"], to: dir.appendingPathComponent("a/z.plist"))
        try writePlist(["Label": "y"], to: dir.appendingPathComponent("b/y.plist"))
        let items = LaunchItemScanner(directories: [
            .systemAgents: dir.appendingPathComponent("a"),
            .systemDaemons: dir.appendingPathComponent("b"),
            .userAgents: dir.appendingPathComponent("nope"),
        ]).scan()
        XCTAssertEqual(items.map(\.label), ["y", "z"])
        XCTAssertEqual(items.map(\.domain), [.systemDaemons, .systemAgents])
    }

    func testRelativeProgramHasNoFlagsAndEmptyProgramIsNil() throws {
        let dir = try makeTemporaryTree(["d/": 0])
        let d = dir.appendingPathComponent("d")
        try writePlist(["Label": "a.bash", "ProgramArguments": ["bash", "-c", "x"]], to: d.appendingPathComponent("a.plist"))
        try writePlist(["Label": "b.empty", "Program": ""], to: d.appendingPathComponent("b.plist"))
        let items = LaunchItemScanner(directories: [.userAgents: d]).scan()
        XCTAssertEqual(items.map(\.program), ["bash", nil])
        XCTAssertEqual(PersistenceFlags.flags(for: items[0], signature: .missing), [])
        XCTAssertEqual(PersistenceFlags.flags(for: items[1], signature: .missing), [])
    }
}
