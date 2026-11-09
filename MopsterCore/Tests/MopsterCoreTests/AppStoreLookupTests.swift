import XCTest
@testable import MopsterCore

final class AppStoreLookupTests: XCTestCase {
    func testURL() {
        XCTAssertEqual(
            AppStoreLookup.url(bundleID: "com.foo.Bar", country: "fr")?.absoluteString,
            "https://itunes.apple.com/lookup?bundleId=com.foo.Bar&country=fr")
    }

    func testParsesSample() {
        let json = #"{"resultCount":1,"results":[{"kind":"mac-software","trackId":409183694,"version":"14.2","bundleId":"com.apple.iWork.Keynote"}]}"#
        let parsed = AppStoreLookup.parse(Data(json.utf8))
        XCTAssertEqual(parsed?.version, "14.2")
        XCTAssertEqual(parsed?.trackID, 409_183_694)
    }

    func testPrefersMacSoftwareResult() {
        let json = """
            {"resultCount":2,"results":[
            {"kind":"software","trackId":1,"version":"9.0"},
            {"kind":"mac-software","trackId":2,"version":"3.1"}]}
            """
        let parsed = AppStoreLookup.parse(Data(json.utf8))
        XCTAssertEqual(parsed?.version, "3.1")
        XCTAssertEqual(parsed?.trackID, 2)
    }

    func testNoMacResultIsNil() {
        let json = #"{"resultCount":1,"results":[{"kind":"software","trackId":1,"version":"9.0"}]}"#
        XCTAssertNil(AppStoreLookup.parse(Data(json.utf8)))
    }

    func testNoResultsIsNil() {
        XCTAssertNil(AppStoreLookup.parse(Data(#"{"resultCount":0,"results":[]}"#.utf8)))
    }

    func testMalformedIsNil() {
        XCTAssertNil(AppStoreLookup.parse(Data("nope".utf8)))
        XCTAssertNil(AppStoreLookup.parse(Data(#"{"resultCount":1,"results":[{"kind":"mac-software","trackId":1}]}"#.utf8)))
        XCTAssertNil(AppStoreLookup.parse(Data(#"{"resultCount":1,"results":[{"kind":"mac-software","version":"1"}]}"#.utf8)))
        XCTAssertNil(AppStoreLookup.parse(Data(#"{"resultCount":1,"results":[]}"#.utf8)))
        XCTAssertNil(AppStoreLookup.parse(Data("[]".utf8)))
    }
}
