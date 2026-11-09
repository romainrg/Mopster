import XCTest

@testable import MopsterCore

final class SecurityCheckerTests: XCTestCase {
    private func checker(
        osMajor: Int = 15, outputs: [String: String] = [:], bundle: (String?, Date?) = (nil, nil),
        defaults: [String: Any] = [:]
    ) -> LiveSecurityChecker {
        LiveSecurityChecker(
            osMajor: osMajor, softwareUpdateDefaults: { defaults }, xprotectBundle: { bundle },
            run: { exe, _ in outputs[exe] })
    }

    func testReportsAllSevenInOrder() async {
        let checks = await checker().run()
        XCTAssertEqual(
            checks.map(\.id),
            [.sip, .gatekeeper, .fileVault, .firewall, .xprotect, .autoSecurityUpdates, .pendingMacOSUpdates])
    }

    func testMissingExecutablesAreUnknownNeverACrash() async {
        let checks = await checker().run()
        XCTAssertTrue(checks.allSatisfy { $0.status == .unknown })
    }

    func testParsesCommandOutputs() async {
        let checks = await checker(
            outputs: [
                "/usr/bin/csrutil": "System Integrity Protection status: enabled.",
                "/usr/sbin/spctl": "assessments disabled",
                "/usr/bin/fdesetup": "FileVault is On.",
                "/usr/libexec/ApplicationFirewall/socketfilterfw": "Firewall is disabled. (State = 0)",
                "/usr/bin/xprotect": "Version: 5371 Installed: 2026-11-04 03:56:18 +0000",
            ],
            defaults: ["CriticalUpdateInstall": 1, "ConfigDataInstall": 1]
        ).run()
        let byID = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0) })
        XCTAssertEqual(byID[.sip]?.status, .ok)
        XCTAssertEqual(byID[.gatekeeper]?.status, .warning)
        XCTAssertEqual(byID[.fileVault]?.status, .ok)
        XCTAssertEqual(byID[.firewall]?.status, .warning)
        XCTAssertEqual(byID[.xprotect]?.detail, "5371 · 2026-11-04")
        XCTAssertEqual(byID[.autoSecurityUpdates]?.status, .ok)
        XCTAssertEqual(byID[.pendingMacOSUpdates]?.status, .unknown)
        XCTAssertNil(byID[.pendingMacOSUpdates]?.detail)
    }

    func testXProtectUsesBundleOnMacOS14() async {
        let checks = await checker(osMajor: 14, bundle: ("5271", Date(timeIntervalSince1970: 1_762_227_378))).run()
        let xprotect = checks.first { $0.id == .xprotect }
        XCTAssertEqual(xprotect?.status, .ok)
        XCTAssertTrue(xprotect?.detail?.hasPrefix("5271") == true)
    }
}
