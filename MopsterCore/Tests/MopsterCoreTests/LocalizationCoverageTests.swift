import XCTest

final class LocalizationCoverageTests: XCTestCase {
    func testEveryKeyHasFrenchTranslation() throws {
        let catalog = try StringCatalog.load()
        XCTAssertFalse(catalog.strings.isEmpty)
        for (key, entry) in catalog.strings {
            assertTranslated(key: key, entry: entry)
        }
    }
}
