import XCTest
@testable import Wnip

final class SelectionModelTests: XCTestCase {
    func testForwardDragProducesNormalizedSelection() {
        var selection = SelectionModel()

        selection.begin(at: CGPoint(x: 20, y: 30))
        selection.update(to: CGPoint(x: 80, y: 90), within: CGRect(x: 0, y: 0, width: 200, height: 200))

        XCTAssertEqual(selection.rect, CGRect(x: 20, y: 30, width: 60, height: 60))
    }

    func testReverseDragProducesNormalizedSelection() {
        var selection = SelectionModel()

        selection.begin(at: CGPoint(x: 80, y: 90))
        selection.update(to: CGPoint(x: 20, y: 30), within: CGRect(x: 0, y: 0, width: 200, height: 200))

        XCTAssertEqual(selection.rect, CGRect(x: 20, y: 30, width: 60, height: 60))
    }

    func testDragEnforcesEightPointMinimumSize() {
        var selection = SelectionModel()

        selection.begin(at: CGPoint(x: 30, y: 30))
        selection.update(to: CGPoint(x: 32, y: 34), within: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(selection.rect, CGRect(x: 30, y: 30, width: 8, height: 8))
    }

    func testDragAtBoundsPreservesMinimumSizeByShiftingInward() {
        var selection = SelectionModel()

        selection.begin(at: CGPoint(x: 98, y: 98))
        selection.update(to: CGPoint(x: 100, y: 100), within: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(selection.rect, CGRect(x: 92, y: 92, width: 8, height: 8))
    }

    func testDragClampsSelectionToBounds() {
        var selection = SelectionModel()

        selection.begin(at: CGPoint(x: 40, y: 40))
        selection.update(to: CGPoint(x: 140, y: -10), within: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(selection.rect, CGRect(x: 40, y: 0, width: 60, height: 40))
    }

    func testTopLeftResizeKeepsOppositeCornerAndClampsToBounds() {
        var selection = SelectionModel(rect: CGRect(x: 20, y: 20, width: 40, height: 30))

        selection.resize(handle: .topLeft, to: CGPoint(x: -10, y: 70), within: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(selection.rect, CGRect(x: 0, y: 20, width: 60, height: 50))
    }

    func testRightResizeHonorsMinimumWidth() {
        var selection = SelectionModel(rect: CGRect(x: 20, y: 20, width: 40, height: 30))

        selection.resize(handle: .right, to: CGPoint(x: 23, y: 35), within: CGRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertEqual(selection.rect, CGRect(x: 20, y: 20, width: 8, height: 30))
    }

    func testEveryResizeHandleMovesOnlyItsAttachedEdges() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let cases: [(SelectionHandle, CGPoint, CGRect)] = [
            (.top, CGPoint(x: 40, y: 70), CGRect(x: 20, y: 20, width: 40, height: 50)),
            (.topRight, CGPoint(x: 70, y: 70), CGRect(x: 20, y: 20, width: 50, height: 50)),
            (.bottomRight, CGPoint(x: 70, y: 10), CGRect(x: 20, y: 10, width: 50, height: 40)),
            (.bottom, CGPoint(x: 40, y: 10), CGRect(x: 20, y: 10, width: 40, height: 40)),
            (.bottomLeft, CGPoint(x: 10, y: 10), CGRect(x: 10, y: 10, width: 50, height: 40)),
            (.left, CGPoint(x: 10, y: 35), CGRect(x: 10, y: 20, width: 50, height: 30))
        ]

        for (handle, point, expectedRect) in cases {
            var selection = SelectionModel(rect: CGRect(x: 20, y: 20, width: 40, height: 30))

            selection.resize(handle: handle, to: point, within: bounds)

            XCTAssertEqual(selection.rect, expectedRect, "Unexpected rect for \(handle)")
        }
    }

    func testSelectionConvertsToPixelsOnMixedScaleDisplay() {
        let oneXSelection = SelectionModel(rect: CGRect(x: 100, y: 100, width: 200, height: 50))
        let oneXDisplay = DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 1)
        let twoXSelection = SelectionModel(rect: CGRect(x: -1340, y: 100, width: 200, height: 50))
        let twoXDisplay = DisplayDescriptor(id: 2, frame: CGRect(x: -1440, y: 0, width: 1440, height: 900), scale: 2)

        XCTAssertEqual(oneXSelection.pixelRect(on: oneXDisplay), CGRect(x: 100, y: 750, width: 200, height: 50))
        XCTAssertEqual(twoXSelection.pixelRect(on: twoXDisplay), CGRect(x: 200, y: 1500, width: 400, height: 100))
    }
}
