import XCTest

@testable import MopsterCore

final class HealthScoreTests: XCTestCase {
    func testCleanMacScoresHundred() {
        let score = HealthScore(
            safeJunkBytes: 0, securityWarnings: 0, flaggedItems: 0, memoryPressure: .normal, brokenItems: 0,
            pendingUpdates: 0, diskUsedFraction: 0.4)
        XCTAssertEqual(score.value, 100)
        XCTAssertEqual(score.level, .good)
    }

    func testAreasThatCouldNotBeCheckedCostNothing() {
        XCTAssertEqual(HealthScore().value, 100)
    }

    func testEachAreaIsCappedSoOneAreaNeverDominates() {
        XCTAssertEqual(HealthScore(securityWarnings: 10).value, 82)
        XCTAssertEqual(HealthScore(flaggedItems: 50).value, 95)
        XCTAssertEqual(HealthScore(brokenItems: 50).value, 97)
        XCTAssertEqual(HealthScore(pendingUpdates: 40).value, 95)
    }

    func testJunkAndDiskCountOnlyPastAThreshold() {
        XCTAssertEqual(HealthScore(safeJunkBytes: 900_000_000).value, 100)
        XCTAssertEqual(HealthScore(safeJunkBytes: 2_000_000_000).value, 97)
        XCTAssertEqual(HealthScore(safeJunkBytes: 8_000_000_000).value, 94)
        XCTAssertEqual(HealthScore(diskUsedFraction: 0.79).value, 100)
        XCTAssertEqual(HealthScore(diskUsedFraction: 0.85).value, 97)
        XCTAssertEqual(HealthScore(diskUsedFraction: 0.95).value, 90)
    }

    func testMemoryPressure() {
        XCTAssertEqual(HealthScore(memoryPressure: .warning).value, 90)
        XCTAssertEqual(HealthScore(memoryPressure: .critical).value, 75)
    }

    func testTypicalMacWithSomeJunkAndUpdatesIsStillGood() {
        let score = HealthScore(
            safeJunkBytes: 8_100_000_000, securityWarnings: 1, flaggedItems: 3, memoryPressure: .normal,
            brokenItems: 1, pendingUpdates: 5, diskUsedFraction: 0.83)
        XCTAssertEqual(score.value, 76)
        XCTAssertEqual(score.level, .good)
    }

    func testLevels() {
        let fair = HealthScore(securityWarnings: 3, memoryPressure: .warning)
        XCTAssertEqual(fair.value, 72)
        XCTAssertEqual(fair.level, .fair)
        let poor = HealthScore(
            safeJunkBytes: 6_000_000_000, securityWarnings: 2, memoryPressure: .critical, diskUsedFraction: 0.95)
        XCTAssertEqual(poor.value, 47)
        XCTAssertEqual(poor.level, .poor)
    }

    func testNegativeCountsAreIgnored() {
        XCTAssertEqual(HealthScore(securityWarnings: -3, pendingUpdates: -1).value, 100)
    }
}

final class VolumeCapacityTests: XCTestCase {
    func testReadsTheVolumeOfAFolder() throws {
        let root = try makeTemporaryTree(["a.bin": 10])
        let capacity = try XCTUnwrap(VolumeCapacity.of(root))
        XCTAssertGreaterThan(capacity.total, 0)
        XCTAssertGreaterThanOrEqual(capacity.available, 0)
        XCTAssertLessThanOrEqual(capacity.used, capacity.total)
        XCTAssertTrue((0...1).contains(capacity.usedFraction))
    }

    func testMissingPathIsNil() {
        XCTAssertNil(VolumeCapacity.of(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")))
    }

    func testUsedSpace() {
        let capacity = VolumeCapacity(total: 494_000_000_000, available: 82_000_000_000)
        XCTAssertEqual(capacity.used, 412_000_000_000)
        XCTAssertEqual(capacity.usedFraction, 412.0 / 494.0, accuracy: 0.0001)
    }

    func testPurgeableSpaceAboveTotalNeverMakesUsedNegative() {
        let capacity = VolumeCapacity(total: 100, available: 120)
        XCTAssertEqual(capacity.used, 0)
        XCTAssertEqual(capacity.usedFraction, 0)
        XCTAssertEqual(VolumeCapacity(total: 0, available: 0).usedFraction, 0)
    }
}
