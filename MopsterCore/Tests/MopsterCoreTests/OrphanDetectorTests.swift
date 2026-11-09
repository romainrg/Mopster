import XCTest
@testable import MopsterCore

final class OrphanDetectorTests: XCTestCase {
    private func detector(_ home: URL, installed: Set<String> = ["com.foo.Bar"], known: Set<String> = []) -> OrphanDetector {
        OrphanDetector(
            home: home,
            installedApps: installed.map { (bundleID: $0, name: String($0.split(separator: ".").last ?? "")) },
            isKnownToLaunchServices: { known.contains($0) })
    }

    func testOrphansAndExclusions() throws {
        let home = try makeTemporaryTree([
            "Library/Caches/com.gone.App/x": 100,
            "Library/Preferences/com.gone.App.plist": 10,
            "Library/Caches/com.foo.Bar.helper/x": 5,
            "Library/Caches/com.apple.x/x": 5,
            "Library/Caches/com.apple.thing.deep/x": 5,
            "Library/Caches/NotABundleID/x": 5,
            "Library/Caches/two.parts/x": 5,
            "Library/Caches/com.known.App/x": 5,
            "Library/Caches/io.github.romainrg.Mopster/x": 5,
            "Library/Caches/io.github.romainrg.Mopster.helper/x": 5,
            "Library/Caches/com.foo/x": 5,
        ])
        let groups = detector(home, known: ["com.known.App"]).orphans()
        XCTAssertEqual(groups.map(\.id), ["com.gone.App"])
        let group = groups[0]
        XCTAssertEqual(group.items.count, 2)
        XCTAssertEqual(group.symbol, "questionmark.app")
        XCTAssertEqual(group.risk, .review)
        XCTAssertNil(group.explanation)
        XCTAssertEqual(String(localized: group.title), "com.gone.App")
        XCTAssertTrue(group.items.allSatisfy { !$0.isSelectedByDefault })
    }

    func testBrewServiceAgentsAreNotOrphans() throws {
        let home = try makeTemporaryTree([
            "Library/LaunchAgents/homebrew.mxcl.postgresql.plist": 5,
            "Library/Caches/com.gone.App/x": 5,
        ])
        XCTAssertEqual(detector(home).orphans().map(\.id), ["com.gone.App"])
    }

    func testLogRotationNamesAreNotOrphans() throws {
        let home = try makeTemporaryTree([
            "Library/Logs/com.gone.App.log.old.4": 5,
            "Library/Logs/com.gone.Other.log": 5,
            "Library/Logs/com.gone.Third.1": 5,
            "Library/Logs/com.gone.Real/x": 5,
        ])
        XCTAssertEqual(detector(home).orphans().map(\.id), ["com.gone.Real"])
    }

    func testInstalledIDIsPrefixOfCandidateOrViceVersa() throws {
        let home = try makeTemporaryTree([
            "Library/Caches/com.foo.Bar.helper.xpc/x": 5,
            "Library/Caches/com.foo.Bar/x": 5,
            "Library/Caches/com.foo.Bar.Updater.Agent/x": 5,
        ])
        XCTAssertTrue(detector(home).orphans().isEmpty)
        let home2 = try makeTemporaryTree(["Library/Caches/com.foo.Bar/x": 5])
        XCTAssertTrue(detector(home2, installed: ["com.foo.Bar.Pro"]).orphans().isEmpty)
    }

    func testByHostGroupContainersAndSuffixes() throws {
        let home = try makeTemporaryTree([
            "Library/Preferences/ByHost/com.gone.App.00000000-1111-2222-3333-444444444444.plist": 5,
            "Library/Preferences/ByHost/com.other.App.0123456789abcdef.plist": 5,
            "Library/Group Containers/ABCDE12345.com.third.App/x": 5,
            "Library/Group Containers/group.com.fourth.App/x": 5,
            "Library/Saved Application State/com.fifth.App.savedState/x": 5,
            "Library/Cookies/com.sixth.App.binarycookies": 5,
        ])
        let ids = Set(detector(home).orphans().map(\.id))
        XCTAssertEqual(ids, ["com.gone.App", "com.other.App", "com.third.App", "com.fourth.App", "com.fifth.App", "com.sixth.App"])
    }

    func testGroupsSortedBySizeDescending() throws {
        let home = try makeTemporaryTree([
            "Library/Caches/com.small.App/x": 10, "Library/Caches/com.big.App/x": 100_000,
        ])
        XCTAssertEqual(detector(home).orphans().map(\.id), ["com.big.App", "com.small.App"])
    }

    func testSystemLocationsAreNeverScanned() throws {
        let home = try makeTemporaryTree(["Library/Caches/": 0])
        XCTAssertTrue(detector(home).orphans().isEmpty)
    }

    func testSystemAndContainerPrefixFormsAreNotOrphans() throws {
        let home = try makeTemporaryTree([
            "Library/Application Scripts/group.com.apple.x/a": 5,
            "Library/Application Scripts/ABCDE12345.com.apple.x/a": 5,
            "Library/Application Scripts/ABCDE12345.groups.com.apple.x/a": 5,
            "Library/Preferences/systemgroup.com.apple.x.plist": 5,
            "Library/Application Scripts/group.is.workflow.shortcuts/a": 5,
            "Library/Application Scripts/group.is.workflow.my.app/a": 5,
        ])
        XCTAssertTrue(detector(home).orphans().isEmpty)
    }

    func testStackedPrefixesResolveToInstalledApp() throws {
        let home = try makeTemporaryTree(["Library/Group Containers/EQHXZ8M8AV.group.com.google.drivefs/x": 5])
        XCTAssertTrue(detector(home, installed: ["com.google.drivefs"]).orphans().isEmpty)
        XCTAssertEqual(detector(home, installed: []).orphans().map(\.id), ["com.google.drivefs"])
    }

    func testCaseVariantsFormOneGroupAndItemsAreReview() throws {
        let home = try makeTemporaryTree([
            "Library/Caches/com.gone.App/x": 5, "Library/Logs/com.Gone.app/x": 5,
        ])
        let groups = detector(home).orphans()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].items.count, 2)
        XCTAssertTrue(groups[0].items.allSatisfy { $0.risk == .review })
    }

    func testSharedVendorNoteNamesTheInstalledApp() throws {
        let home = try makeTemporaryTree([
            "Library/Caches/com.microsoft.teams/x": 5,
            "Library/Caches/com.unrelated.App/x": 5,
            "Library/Caches/com.github.cli/x": 5,
            "Library/Caches/io.github.someone.tool/x": 5,
        ])
        let detector = OrphanDetector(
            home: home,
            installedApps: [
                (bundleID: "com.Microsoft.Word", name: "Microsoft Word"),
                (bundleID: "com.github.GitHubDesktop", name: "GitHub Desktop"),
                (bundleID: "io.github.other.app", name: "Other"),
            ],
            isKnownToLaunchServices: { _ in false })
        let groups = Dictionary(uniqueKeysWithValues: detector.orphans().map { ($0.id, $0) })
        let note = try XCTUnwrap(groups["com.microsoft.teams"]?.explanation)
        XCTAssertEqual(note.key, "orphans.sharedVendor")
        XCTAssertTrue(String(localized: note).contains("Microsoft Word"))
        XCTAssertNil(groups["com.unrelated.App"]?.explanation)
        XCTAssertNil(groups["com.github.cli"]?.explanation, "hosting namespace says nothing about the developer")
        XCTAssertNil(groups["io.github.someone.tool"]?.explanation)
        try assertCatalogContains([L("orphans.sharedVendor", "Another app from the same developer is installed: \("x"). Check before removing.")])
    }
}
