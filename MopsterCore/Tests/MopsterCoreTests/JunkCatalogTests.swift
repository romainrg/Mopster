import XCTest
@testable import MopsterCore

final class JunkCatalogTests: XCTestCase {
    func testIdsUnique() {
        let ids = JunkCatalog.rules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryLocationStartsWithTilde() {
        for rule in JunkCatalog.rules {
            for pattern in rule.locations + rule.exclusions {
                XCTAssertTrue(pattern.hasPrefix("~/"), "\(rule.id): \(pattern)")
            }
        }
    }

    func testFullDiskAccessRules() {
        XCTAssertEqual(
            Set(JunkCatalog.rules.filter(\.needsFullDiskAccess).map(\.id)),
            ["browserCaches", "mailDownloads", "deviceBackups"])
    }

    func testCatalogItemsPassSafetyGuard() async throws {
        var spec: [String: Int] = [:]
        for rule in JunkCatalog.rules {
            let first = rule.locations[0].dropFirst(2).replacingOccurrences(of: "*", with: "item")
            spec[rule.extensions == nil ? first : first + ".dmg"] = 10
        }
        let home = try makeTemporaryTree(spec)
        let result = try await JunkScanner(home: home, ignore: IgnoreList()).scan { _ in }
        XCTAssertEqual(result.groups.map(\.id), JunkCatalog.rules.map(\.id))
        let guardian = SafetyGuard(
            home: home, appBundle: home.deletingLastPathComponent().appendingPathComponent("Applications/Mopster.app"))
        for item in result.groups.flatMap(\.items) {
            XCTAssertEqual(guardian.check(item.url), .allowed, item.id)
        }
    }

    func testCatalogStringsAreLocalized() throws {
        try assertCatalogContains(JunkCatalog.rules.flatMap { [$0.title, $0.explanation] })
    }
}
