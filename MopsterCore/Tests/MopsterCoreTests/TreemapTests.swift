import CoreGraphics
import XCTest

@testable import MopsterCore

final class TreemapTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
    private let typical: [Double] = [6, 6, 4, 3, 2, 2, 1]

    func testAreasProportional() {
        let rects = Treemap.squarify(typical, in: bounds)
        let total = typical.reduce(0, +)
        XCTAssertEqual(rects.count, typical.count)
        for (size, rect) in zip(typical, rects) {
            let expected = size / total * Double(bounds.width * bounds.height)
            XCTAssertEqual(Double(rect.width * rect.height), expected, accuracy: expected * 0.005)
        }
    }

    func testRectsInsideBoundsAndNonOverlapping() {
        let rects = Treemap.squarify(typical, in: bounds)
        let outer = bounds.insetBy(dx: -0.001, dy: -0.001)
        for rect in rects { XCTAssertTrue(outer.contains(rect)) }
        for i in rects.indices {
            for j in rects.indices where j > i {
                let overlap = rects[i].insetBy(dx: 0.01, dy: 0.01).intersection(rects[j].insetBy(dx: 0.01, dy: 0.01))
                XCTAssertTrue(overlap.isNull || overlap.isEmpty, "\(i) overlaps \(j)")
            }
        }
    }

    func testWorstAspectRatioBelow4ForTypicalInput() {
        for rect in Treemap.squarify(typical, in: bounds) {
            XCTAssertLessThan(max(rect.width / rect.height, rect.height / rect.width), 4)
        }
    }

    func testSingleItemFillsRect() {
        XCTAssertEqual(Treemap.squarify([5], in: bounds), [bounds])
    }

    func testZeroSizesGiveZeroRectsAtTheirIndex() {
        let rects = Treemap.squarify([4, 0, 2, -1], in: bounds)
        XCTAssertEqual(rects[1], .zero)
        XCTAssertEqual(rects[3], .zero)
        XCTAssertGreaterThan(rects[0].width * rects[0].height, 0)
        XCTAssertEqual(Treemap.squarify([], in: bounds), [])
        XCTAssertEqual(Treemap.squarify([0, 0], in: bounds), [.zero, .zero])
    }
}
