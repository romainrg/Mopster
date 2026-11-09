import XCTest
@testable import MopsterCore

final class SelectionTests: XCTestCase {
    private func item(_ name: String, size: Int64, byDefault: Bool) -> CleanupItem {
        CleanupItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, size: size,
            risk: byDefault ? .safe : .review, isSelectedByDefault: byDefault)
    }

    private func groups() -> [CleanupGroup] {
        [
            CleanupGroup(
                id: "a", title: L("A", "A"), symbol: "folder",
                items: [item("a1", size: 10, byDefault: true), item("a2", size: 20, byDefault: true)]),
            CleanupGroup(
                id: "b", title: L("B", "B"), symbol: "folder", risk: .review,
                items: [item("b1", size: 100, byDefault: false), item("b2", size: 200, byDefault: false)]),
        ]
    }

    func testDefaultsSelectOnlySafePreselected() {
        let groups = groups()
        let selection = Selection(defaultsFrom: groups)
        XCTAssertEqual(selection.urls(in: groups).map(\.lastPathComponent), ["a1", "a2"])
    }

    func testGroupStateNoneSomeAll() {
        let groups = groups()
        var selection = Selection(defaultsFrom: groups)
        XCTAssertEqual(selection.state(of: groups[0]), .all)
        XCTAssertEqual(selection.state(of: groups[1]), .none)
        selection.toggle(groups[0].items[0].id)
        XCTAssertEqual(selection.state(of: groups[0]), .some)
        selection.setAll(in: groups[1], true)
        XCTAssertEqual(selection.state(of: groups[1]), .all)
        selection.setAll(in: groups[0], false)
        XCTAssertEqual(selection.state(of: groups[0]), .none)
    }

    func testTotalSizeSumsSelected() {
        let groups = groups()
        var selection = Selection(defaultsFrom: groups)
        XCTAssertEqual(selection.totalSize(in: groups), 30)
        selection.toggle(groups[1].items[1].id)
        XCTAssertEqual(selection.totalSize(in: groups), 230)
        XCTAssertEqual(groups[1].totalSize, 300)
    }
}
