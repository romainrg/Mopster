import XCTest

@testable import MopsterCore

final class SecurityParsersTests: XCTestCase {
    // Samples: enabled ones captured on a Mac; disabled ones follow Apple's documented wording.
    func testSIP() {
        XCTAssertEqual(SecurityParsers.parseSIP(csrutilStatus: "System Integrity Protection status: enabled.\n"), .ok)
        XCTAssertEqual(SecurityParsers.parseSIP(csrutilStatus: "System Integrity Protection status: disabled.\n"), .warning)
        XCTAssertEqual(
            SecurityParsers.parseSIP(
                csrutilStatus: "System Integrity Protection status: unknown (Custom Configuration).\n"), .warning)
        XCTAssertEqual(SecurityParsers.parseSIP(csrutilStatus: "garbage"), .unknown)
        XCTAssertEqual(SecurityParsers.parseSIP(csrutilStatus: ""), .unknown)
    }

    func testGatekeeper() {
        XCTAssertEqual(SecurityParsers.parseGatekeeper(spctlStatus: "assessments enabled\n"), .ok)
        XCTAssertEqual(SecurityParsers.parseGatekeeper(spctlStatus: "assessments disabled\n"), .warning)
        XCTAssertEqual(SecurityParsers.parseGatekeeper(spctlStatus: "usage: spctl"), .unknown)
        XCTAssertEqual(SecurityParsers.parseGatekeeper(spctlStatus: ""), .unknown)
    }

    func testFileVault() {
        XCTAssertEqual(
            SecurityParsers.parseFileVault(
                fdesetupStatus: "FileVault is On.\nFileVault master keychain appears to be installed.\n"), .ok)
        XCTAssertEqual(SecurityParsers.parseFileVault(fdesetupStatus: "FileVault is Off.\n"), .warning)
        XCTAssertEqual(SecurityParsers.parseFileVault(fdesetupStatus: "Encryption in progress: Percent completed = 12"), .ok)
        XCTAssertEqual(SecurityParsers.parseFileVault(fdesetupStatus: "Error: something odd"), .unknown)
        XCTAssertEqual(SecurityParsers.parseFileVault(fdesetupStatus: ""), .unknown)
    }

    func testFirewall() {
        XCTAssertEqual(SecurityParsers.parseFirewall(socketfilterfw: "Firewall is enabled. (State = 1)\n"), .ok)
        XCTAssertEqual(SecurityParsers.parseFirewall(socketfilterfw: "Firewall is enabled. (State = 2)\n"), .ok)
        XCTAssertEqual(SecurityParsers.parseFirewall(socketfilterfw: "Firewall is disabled. (State = 0)\n"), .warning)
        XCTAssertEqual(SecurityParsers.parseFirewall(socketfilterfw: "nope"), .unknown)
        XCTAssertEqual(SecurityParsers.parseFirewall(socketfilterfw: ""), .unknown)
    }

    func testXProtect() {
        let enabled = SecurityParsers.parseXProtect(versionOutput: "Version: 5371 Installed: 2026-11-04 03:56:18 +0000\n")
        XCTAssertEqual(enabled.status, .ok)
        XCTAssertEqual(enabled.detail, "5371 · 2026-11-04")
        let versionOnly = SecurityParsers.parseXProtect(versionOutput: "Version: 5300\n")
        XCTAssertEqual(versionOnly.status, .ok)
        XCTAssertEqual(versionOnly.detail, "5300")
        let garbage = SecurityParsers.parseXProtect(versionOutput: "xprotect: command not found")
        XCTAssertEqual(garbage.status, .unknown)
        XCTAssertNil(garbage.detail)
        XCTAssertEqual(SecurityParsers.parseXProtect(versionOutput: "").status, .unknown)
    }

    func testXProtectBundleFallback() {
        let date = Date(timeIntervalSince1970: 1_762_227_378)
        let outcome = SecurityParsers.xprotectBundle(version: "5271", modified: date)
        XCTAssertEqual(outcome.status, .ok)
        XCTAssertTrue(outcome.detail?.hasPrefix("5271 · 2025-11-") == true, outcome.detail ?? "nil")
        XCTAssertEqual(SecurityParsers.xprotectBundle(version: nil, modified: date).status, .unknown)
    }

    func testAutoUpdates() {
        XCTAssertEqual(SecurityParsers.parseAutoUpdates(defaults: ["CriticalUpdateInstall": 1, "ConfigDataInstall": 1]), .ok)
        XCTAssertEqual(SecurityParsers.parseAutoUpdates(defaults: ["CriticalUpdateInstall": true, "ConfigDataInstall": true]), .ok)
        XCTAssertEqual(SecurityParsers.parseAutoUpdates(defaults: ["CriticalUpdateInstall": 0, "ConfigDataInstall": 1]), .warning)
        XCTAssertEqual(SecurityParsers.parseAutoUpdates(defaults: ["CriticalUpdateInstall": 1, "ConfigDataInstall": false]), .warning)
        XCTAssertEqual(SecurityParsers.parseAutoUpdates(defaults: [:]), .unknown)
        XCTAssertEqual(SecurityParsers.parseAutoUpdates(defaults: ["Other": 1, "CriticalUpdateInstall": "garbage"]), .unknown)
    }
}
