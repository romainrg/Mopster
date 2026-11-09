import XCTest

@testable import MopsterCore

final class SafetyGuardTests: XCTestCase {
    private var home: URL!
    private var appBundle: URL!
    private var guardrail: SafetyGuard!

    override func setUpWithError() throws {
        home = try makeTemporaryTree([
            "Library/Caches/x": 1, "Library/Application Support/": 0, "Projects/": 0,
            "Downloads/": 0, "Applications/Mopster.app/Contents/": 0,
        ])
        appBundle = home.appendingPathComponent("Applications/Mopster.app")
        guardrail = SafetyGuard(home: home, appBundle: appBundle)
    }

    private func check(_ path: String) -> SafetyVerdict {
        guardrail.check(URL(fileURLWithPath: path))
    }

    private func inHome(_ relative: String) -> SafetyVerdict {
        guardrail.check(home.appendingPathComponent(relative))
    }

    func testPrivateSpellingMatrixGivesTheSameVerdictAsTheRealFile() throws {
        let name = "mopster-guard-\(UUID().uuidString)"
        let real = URL(fileURLWithPath: "/private/tmp/\(name)")
        try FileManager.default.createDirectory(
            at: real.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: real.appendingPathComponent(".ssh"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: real) }
        let bundle = URL(fileURLWithPath: "/Applications/Mopster.app")
        for homeSpelling in ["/tmp/\(name)", "/private/tmp/\(name)"] {
            let guarded = SafetyGuard(home: URL(fileURLWithPath: homeSpelling), appBundle: bundle)
            for candidateSpelling in ["/tmp/\(name)", "/private/tmp/\(name)"] {
                let context = "home \(homeSpelling), candidate \(candidateSpelling)"
                XCTAssertEqual(
                    guarded.check(URL(fileURLWithPath: candidateSpelling + "/Library/Caches/a")), .allowed, context)
                XCTAssertEqual(
                    guarded.check(URL(fileURLWithPath: candidateSpelling + "/.ssh/id")), .refused(.secretStore),
                    context)
            }
        }
    }

    func testAllowedPaths() {
        XCTAssertEqual(inHome("Library/Caches/x"), .allowed)
        XCTAssertEqual(inHome("Projects"), .allowed)
        XCTAssertEqual(check("/Applications/Foo.app"), .allowed)
        XCTAssertEqual(check("/Library/LaunchAgents/com.x.plist"), .allowed)
    }

    func testStructuralFolders() {
        let expected = SafetyVerdict.refused(.structuralFolder)
        XCTAssertEqual(guardrail.check(home), expected)
        XCTAssertEqual(inHome("Downloads"), expected)
        XCTAssertEqual(inHome(".Trash"), expected)
        XCTAssertEqual(inHome("Library"), expected)
        XCTAssertEqual(inHome("Library/Caches"), expected)
        XCTAssertEqual(inHome("Library/Application Support"), expected)
        XCTAssertEqual(check("/Applications"), expected)
        XCTAssertEqual(check("/Library/LaunchAgents"), expected)
    }

    func testExtraRootItselfIsStructuralAndContentsAreAllowed() {
        let root = home.appendingPathComponent("Projects/telescope")
        let guarded = SafetyGuard(home: home, appBundle: appBundle, extraRoots: [root])
        XCTAssertEqual(guarded.check(root), .refused(.structuralFolder))
        XCTAssertEqual(guarded.check(root.appendingPathComponent("node_modules")), .allowed)
        let added = guardrail.adding(root: root)
        XCTAssertEqual(added.check(root), .refused(.structuralFolder))
    }

    func testVolumeRootsAreHonored() {
        let guarded = guardrail.adding(root: URL(fileURLWithPath: "/Volumes/MopsterTestDisk"))
        XCTAssertEqual(guarded.check(URL(fileURLWithPath: "/Volumes/MopsterTestDisk")), .refused(.structuralFolder))
        XCTAssertEqual(guarded.check(URL(fileURLWithPath: "/Volumes/MopsterTestDisk/old")), .allowed)
    }

    func testRootVolumeSymlinkIsNotHonored() throws {
        let volumes = URL(fileURLWithPath: "/Volumes")
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: volumes.path)) ?? []
        guard let startup = entries.first(where: {
            volumes.appendingPathComponent($0).resolvingSymlinksInPath().path == "/"
        }) else { throw XCTSkip("No /Volumes entry resolves to /") }
        let root = volumes.appendingPathComponent(startup)
        let guarded = guardrail.adding(root: root)
        let outside = SafetyVerdict.refused(.outsideAllowedRoots)
        XCTAssertEqual(guarded.check(root.appendingPathComponent("Library/Foo")), outside)
        XCTAssertEqual(guarded.check(root.appendingPathComponent("Users/Shared/x")), outside)
    }

    func testRootSymlinkInsideHomeIsNotHonored() throws {
        let link = home.appendingPathComponent("rootlink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/"))
        let guarded = guardrail.adding(root: link)
        XCTAssertEqual(
            guarded.check(link.appendingPathComponent("private/etc/hosts")), .refused(.outsideAllowedRoots))
    }

    func testSymlinkedSecretStoreRealLocationIsSecret() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: home.appendingPathComponent("dotfiles/ssh"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: home.appendingPathComponent(".ssh"), withDestinationURL: home.appendingPathComponent("dotfiles/ssh"))
        XCTAssertEqual(inHome("dotfiles/ssh/id"), .refused(.secretStore))
        XCTAssertEqual(inHome("dotfiles/ssh"), .refused(.secretStore))
        XCTAssertEqual(inHome("dotfiles"), .refused(.secretStore))
        XCTAssertEqual(guardrail.check(home), .refused(.structuralFolder))
        XCTAssertEqual(inHome("Projects"), .allowed)
    }

    func testSymlinkIntoSecretStoreIsSecret() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: home.appendingPathComponent(".ssh"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: home.appendingPathComponent("link"), withDestinationURL: home.appendingPathComponent(".ssh"))
        XCTAssertEqual(inHome("link/id"), .refused(.secretStore))
    }

    func testSymlinkedStandardFolderTargetIsStructural() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: home.appendingPathComponent("Dropbox/Documents"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            at: home.appendingPathComponent("Documents"),
            withDestinationURL: home.appendingPathComponent("Dropbox/Documents"))
        XCTAssertEqual(inHome("Dropbox/Documents"), .refused(.structuralFolder))
        XCTAssertEqual(inHome("Dropbox/Documents/a.txt"), .allowed)
    }

    func testAncestorOfAppBundleIsMopsterItself() {
        let bundle = home.appendingPathComponent("Applications/Tools/Mopster.app")
        let guarded = SafetyGuard(home: home, appBundle: bundle)
        XCTAssertEqual(guarded.check(home.appendingPathComponent("Applications/Tools")), .refused(.mopsterItself))
        XCTAssertEqual(guarded.check(home.appendingPathComponent("Applications")), .refused(.structuralFolder))
    }

    func testUnresolvableParentIsRefused() throws {
        let locked = home.appendingPathComponent("Projects/locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: locked.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/private/etc"))
        XCTAssertEqual(chmod(locked.path, 0o000), 0)
        XCTAssertEqual(
            guardrail.check(locked.appendingPathComponent("link/hosts")), .refused(.unresolvable))
    }

    func testExtraRootSwappedForSymlinkToSystemFolderIsDropped() throws {
        let fm = FileManager.default
        let root = home.appendingPathComponent("Projects/real")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let guarded = guardrail.adding(root: root)
        XCTAssertEqual(guarded.check(root.appendingPathComponent("file")), .allowed)
        try fm.removeItem(at: root)
        try fm.createSymbolicLink(at: root, withDestinationURL: URL(fileURLWithPath: "/private/etc"))
        XCTAssertNotEqual(guarded.check(root.appendingPathComponent("hosts")), .allowed)
        XCTAssertEqual(guarded.check(root.appendingPathComponent("hosts")), .refused(.outsideAllowedRoots))
    }

    func testNonexistentExtraRootLaterLinkedToRootIsDropped() throws {
        let root = home.appendingPathComponent("Projects/later")
        let guarded = guardrail.adding(root: root)
        XCTAssertEqual(guarded.check(root.appendingPathComponent("x")), .allowed)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: URL(fileURLWithPath: "/"))
        XCTAssertEqual(guarded.check(root.appendingPathComponent("private/etc/hosts")), .refused(.outsideAllowedRoots))
        XCTAssertEqual(guarded.check(root.appendingPathComponent("Users/Shared")), .refused(.outsideAllowedRoots))
    }

    func testRealExtraRootStaysHonored() throws {
        let root = home.appendingPathComponent("Projects/stable")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let guarded = guardrail.adding(root: root)
        XCTAssertEqual(guarded.check(root), .refused(.structuralFolder))
        XCTAssertEqual(guarded.check(root.appendingPathComponent("a/b")), .allowed)
    }

    func testSecretStores() {
        let expected = SafetyVerdict.refused(.secretStore)
        XCTAssertEqual(inHome(".ssh/id_ed25519"), expected)
        XCTAssertEqual(inHome(".aws"), expected)
        XCTAssertEqual(inHome("Library/Keychains/login.keychain-db"), expected)
        XCTAssertEqual(inHome("Library/Keychains"), expected)
        XCTAssertEqual(inHome("Library/Mobile Documents/x"), expected)
    }

    func testProtectedSystemPaths() {
        let expected = SafetyVerdict.refused(.protectedSystemPath)
        for path in [
            "/System/Library", "/usr/bin/true", "/bin", "/sbin", "/private/var/db/x", "/var/db/x",
            "/system/library", "/",
        ] {
            XCTAssertEqual(check(path), expected, path)
        }
    }

    func testInsideAppBundle() {
        XCTAssertEqual(
            check("/Applications/Foo.app/Contents/Resources/fr.lproj"), .refused(.insideAppBundle))
        XCTAssertEqual(check("/Applications/Foo.APP/Contents"), .refused(.insideAppBundle))
        XCTAssertEqual(check("/Applications/Foo.app"), .allowed)
    }

    func testMopsterItself() {
        XCTAssertEqual(guardrail.check(appBundle), .refused(.mopsterItself))
        XCTAssertEqual(
            guardrail.check(appBundle.appendingPathComponent("Contents/MacOS/Mopster")), .refused(.mopsterItself))
    }

    func testOutsideAllowedRoots() {
        XCTAssertEqual(check("/private/etc/hosts"), .refused(.outsideAllowedRoots))
        XCTAssertEqual(check("/Users/Shared/x"), .refused(.outsideAllowedRoots))
        let guarded = guardrail.adding(root: URL(fileURLWithPath: "/private/etc"))
        XCTAssertEqual(guarded.check(URL(fileURLWithPath: "/private/etc/hosts")), .refused(.outsideAllowedRoots))
    }

    func testSymlinkToProtectedPathIsRefused() throws {
        let link = home.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System"))
        XCTAssertEqual(
            guardrail.check(link.appendingPathComponent("Library")), .refused(.protectedSystemPath))
        XCTAssertEqual(guardrail.check(link), .refused(.protectedSystemPath))
    }

    func testDotDotThroughSymlinkIsResolvedBeforeJudging() throws {
        let link = home.appendingPathComponent("hop")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System/Library"))
        let sneaky = URL(fileURLWithPath: link.path + "/../Frameworks")
        XCTAssertNotEqual(guardrail.check(sneaky), .allowed)
    }

    func testCaseInsensitiveAndNormalizationInsensitive() {
        XCTAssertEqual(inHome("library/CACHES"), .refused(.structuralFolder))
        XCTAssertEqual(inHome(".SSH/id"), .refused(.secretStore))
    }
}
