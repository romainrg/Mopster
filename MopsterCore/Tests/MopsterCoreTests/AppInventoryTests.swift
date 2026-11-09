import XCTest
@testable import MopsterCore

enum FakeApp {
    @discardableResult
    static func make(at url: URL, plist: [String: Any], receipt: Bool = false) throws -> URL {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        if receipt {
            let dir = contents.appendingPathComponent("_MASReceipt", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(count: 10).write(to: dir.appendingPathComponent("receipt"))
        }
        return url
    }
}

final class AppInventoryTests: XCTestCase {
    func testReadsInfoPlistFields() throws {
        let root = try makeTemporaryTree(["Apps/": 0])
        let apps = root.appendingPathComponent("Apps")
        try FakeApp.make(
            at: apps.appendingPathComponent("Bar.app"),
            plist: [
                "CFBundleIdentifier": "com.foo.Bar", "CFBundleDisplayName": "Bar Pro",
                "CFBundleName": "Bar", "CFBundleShortVersionString": "2.1", "CFBundleVersion": "210",
                "SUFeedURL": "https://example.com/appcast.xml", "LSMinimumSystemVersion": "13.0",
            ], receipt: true)
        let found = AppInventory(roots: [apps]).apps()
        XCTAssertEqual(found.count, 1)
        let app = try XCTUnwrap(found.first)
        XCTAssertEqual(app.bundleID, "com.foo.Bar")
        XCTAssertEqual(app.name, "Bar Pro")
        XCTAssertEqual(app.version, "2.1")
        XCTAssertEqual(app.build, "210")
        XCTAssertTrue(app.isAppStore)
        XCTAssertEqual(app.sparkleFeed, URL(string: "https://example.com/appcast.xml"))
        XCTAssertEqual(app.minimumSystemVersion, "13.0")
        XCTAssertFalse(app.isLocked)
        XCTAssertGreaterThan(app.size, 0)
        XCTAssertEqual(app.id, app.url.path)
    }

    func testNameFallbacksAndMissingBundleID() throws {
        let root = try makeTemporaryTree(["Apps/": 0])
        let apps = root.appendingPathComponent("Apps")
        try FakeApp.make(at: apps.appendingPathComponent("A.app"), plist: ["CFBundleIdentifier": "com.a.a", "CFBundleName": "Alpha"])
        try FakeApp.make(at: apps.appendingPathComponent("Beta.app"), plist: ["CFBundleIdentifier": "com.b.b"])
        try FakeApp.make(at: apps.appendingPathComponent("NoID.app"), plist: ["CFBundleName": "NoID"])
        let found = AppInventory(roots: [apps]).apps()
        XCTAssertEqual(found.map(\.name), ["Alpha", "Beta"])
        XCTAssertFalse(found[0].isAppStore)
        XCTAssertNil(found[0].sparkleFeed)
        XCTAssertEqual(found[0].version, "")
    }

    func testFindsAppsInPlainSubfoldersOnly() throws {
        let root = try makeTemporaryTree(["Apps/Utilities/": 0, "Apps/Some.app/Inner/": 0, "Apps/Deep/Deeper/": 0])
        let apps = root.appendingPathComponent("Apps")
        try FakeApp.make(at: apps.appendingPathComponent("Utilities/Foo.app"), plist: ["CFBundleIdentifier": "com.u.foo"])
        try FakeApp.make(at: apps.appendingPathComponent("Deep/Deeper/Hidden.app"), plist: ["CFBundleIdentifier": "com.u.hidden"])
        try FakeApp.make(at: apps.appendingPathComponent("Some.app"), plist: ["CFBundleIdentifier": "com.u.some"])
        try FakeApp.make(
            at: apps.appendingPathComponent("Some.app/Inner/Nested.app"), plist: ["CFBundleIdentifier": "com.u.nested"])
        let ids = AppInventory(roots: [apps]).apps().map(\.bundleID)
        XCTAssertEqual(Set(ids), ["com.u.foo", "com.u.some"])
    }

    func testSortedCaseInsensitively() throws {
        let root = try makeTemporaryTree(["Apps/": 0])
        let apps = root.appendingPathComponent("Apps")
        for (file, id) in [("zeta", "com.z.z"), ("Alpha", "com.a.a"), ("beta", "com.b.b")] {
            try FakeApp.make(at: apps.appendingPathComponent("\(file).app"), plist: ["CFBundleIdentifier": id])
        }
        XCTAssertEqual(AppInventory(roots: [apps]).apps().map(\.name), ["Alpha", "beta", "zeta"])
    }

    func testSymlinkIntoSystemPrefixIsLocked() throws {
        let root = try makeTemporaryTree(["Apps/": 0, "FakeSystem/": 0])
        let system = root.appendingPathComponent("FakeSystem")
        let apps = root.appendingPathComponent("Apps")
        try FakeApp.make(at: system.appendingPathComponent("Safari.app"), plist: ["CFBundleIdentifier": "com.apple.Safari"])
        try FakeApp.make(at: apps.appendingPathComponent("Own.app"), plist: ["CFBundleIdentifier": "com.own.app"])
        try FileManager.default.createSymbolicLink(
            at: apps.appendingPathComponent("Safari.app"), withDestinationURL: system.appendingPathComponent("Safari.app"))
        let prefix = AppInventory.realPath(system) + "/"
        let found = AppInventory(roots: [apps], systemPrefix: prefix).apps()
        XCTAssertEqual(found.first { $0.bundleID == "com.apple.Safari" }?.isLocked, true)
        XCTAssertEqual(found.first { $0.bundleID == "com.own.app" }?.isLocked, false)
    }

    func testHiddenFlaggedBundleIsListed() throws {
        let root = try makeTemporaryTree(["Apps/": 0])
        let apps = root.appendingPathComponent("Apps")
        let bundle = try FakeApp.make(at: apps.appendingPathComponent("Hid.app"), plist: ["CFBundleIdentifier": "com.h.h"])
        var url = bundle
        var values = URLResourceValues()
        values.isHidden = true
        try url.setResourceValues(values)
        XCTAssertEqual(AppInventory(roots: [apps]).apps().map(\.bundleID), ["com.h.h"])
    }

    func testMissingRootIsIgnored() {
        XCTAssertTrue(AppInventory(roots: [URL(fileURLWithPath: "/nonexistent-mopster-root")]).apps().isEmpty)
    }
}
