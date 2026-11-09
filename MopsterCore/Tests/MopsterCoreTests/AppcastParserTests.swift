import XCTest
@testable import MopsterCore

final class AppcastParserTests: XCTestCase {
    private let sample = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>App</title>
            <item>
              <title>1.0</title>
              <enclosure url="https://x.test/a.zip" sparkle:version="100" sparkle:shortVersionString="1.0"/>
            </item>
            <item>
              <sparkle:version>120</sparkle:version>
              <sparkle:shortVersionString>1.2</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
              <enclosure url="https://x.test/b.zip"/>
            </item>
            <item>
              <sparkle:version>130</sparkle:version>
              <sparkle:channel>beta</sparkle:channel>
            </item>
            <item>
              <sparkle:version>140</sparkle:version>
              <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
            </item>
            <item><title>no version</title></item>
          </channel>
        </rss>
        """

    private let os14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 4, patchVersion: 1)

    func testParsesAttributesAndElements() throws {
        let items = try XCTUnwrap(AppcastParser.parse(Data(sample.utf8)))
        XCTAssertEqual(items.map(\.version), ["100", "120", "130", "140"])
        XCTAssertEqual(items[0].shortVersion, "1.0")
        XCTAssertEqual(items[1].shortVersion, "1.2")
        XCTAssertEqual(items[1].minimumSystemVersion, "13.0")
        XCTAssertEqual(items[2].channel, "beta")
        XCTAssertNil(items[0].channel)
    }

    func testNewestCompatibleSkipsBetaAndTooNew() throws {
        let items = try XCTUnwrap(AppcastParser.parse(Data(sample.utf8)))
        XCTAssertEqual(AppcastParser.newestCompatible(items, osVersion: os14)?.version, "120")
    }

    func testNewestCompatibleRespectsOSVersion() throws {
        let items = try XCTUnwrap(AppcastParser.parse(Data(sample.utf8)))
        let os12 = OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)
        XCTAssertEqual(AppcastParser.newestCompatible(items, osVersion: os12)?.version, "100")
    }

    func testNewestUsesVersionComparisonNotOrder() {
        let items = [
            AppcastItem(version: "9", shortVersion: nil, minimumSystemVersion: nil, channel: nil),
            AppcastItem(version: "10", shortVersion: nil, minimumSystemVersion: nil, channel: nil),
        ]
        XCTAssertEqual(AppcastParser.newestCompatible(items, osVersion: os14)?.version, "10")
    }

    func testGarbageIsNil() {
        XCTAssertNil(AppcastParser.parse(Data("not xml <<<".utf8)))
        XCTAssertNil(AppcastParser.parse(Data()))
        XCTAssertNil(AppcastParser.parse(Data("<html><body>hi</body></html>".utf8)))
    }

    func testTruncatedXMLIsNil() {
        XCTAssertNil(AppcastParser.parse(Data("<rss><channel><item><sparkle:version>1".utf8)))
    }
}
