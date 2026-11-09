import XCTest

@testable import MopsterCore

final class IgnoreListTests: XCTestCase {
    func testDescendantIsIgnoredSiblingIsNot() {
        let list = IgnoreList(paths: ["/Users/x/Projects/old"])
        XCTAssertTrue(list.contains(URL(fileURLWithPath: "/Users/x/Projects/old")))
        XCTAssertTrue(list.contains(URL(fileURLWithPath: "/Users/x/Projects/old/deep/file")))
        XCTAssertTrue(list.contains(URL(fileURLWithPath: "/users/x/projects/OLD/file")))
        XCTAssertFalse(list.contains(URL(fileURLWithPath: "/Users/x/Projects/older")))
        XCTAssertFalse(list.contains(URL(fileURLWithPath: "/Users/x/Projects")))
    }

    func testCodableShape() throws {
        let data = try JSONEncoder().encode(IgnoreList(paths: ["/a"]))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String: [String]], ["paths": ["/a"]])
        XCTAssertEqual(try JSONDecoder().decode(IgnoreList.self, from: data).paths, ["/a"])
    }

    func testEmptyListIgnoresNothing() {
        XCTAssertFalse(IgnoreList(paths: []).contains(URL(fileURLWithPath: "/a")))
    }
}
