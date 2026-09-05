import XCTest
@testable import Wnip

final class AnnotationParameterControlsPlacementTests: XCTestCase {
    let screen = CGRect(x: -800, y: 0, width: 800, height: 600)
    let controls = CGSize(width: 220, height: 36)

    func testControlsAreAboveSelectionAndPixelBadgeWithNegativeDisplayOrigin() {
        let selection = CGRect(x: -650, y: 180, width: 400, height: 220)
        let frame = AnnotationParameterControlsPlacement.resolve(selection: selection, visibleFrame: screen, controlsSize: controls)
        XCTAssertEqual(frame.minX, selection.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, selection.maxY + 26)
        XCTAssertFalse(frame.intersects(selection))
        XCTAssertTrue(screen.contains(frame))
    }

    func testTopEdgeFallsBelowToolbarWithoutCoveringIt() {
        let selection = CGRect(x: -700, y: 350, width: 500, height: 250)
        let toolbar = ToolbarPlacement.resolve(selection: selection, visibleFrame: screen, toolbarSize: CGSize(width: 486, height: 50))
        let frame = AnnotationParameterControlsPlacement.resolve(selection: selection, visibleFrame: screen,
            controlsSize: controls, toolbarFrame: toolbar)
        XCTAssertLessThan(frame.maxY, toolbar.minY)
        XCTAssertFalse(frame.intersects(selection))
        XCTAssertTrue(screen.contains(frame))
    }

    func testBottomEdgeControlsAvoidToolbarAboveSelection() {
        let selection = CGRect(x: -700, y: 5, width: 500, height: 250)
        let toolbar = ToolbarPlacement.resolve(selection: selection, visibleFrame: screen, toolbarSize: CGSize(width: 486, height: 50))
        let frame = AnnotationParameterControlsPlacement.resolve(selection: selection, visibleFrame: screen,
            controlsSize: controls, toolbarFrame: toolbar)
        XCTAssertGreaterThan(frame.minY, toolbar.maxY)
        XCTAssertTrue(screen.contains(frame))
    }

    func testFullScreenKeepsControlsInsideAndBelowPixelBadge() {
        let frame = AnnotationParameterControlsPlacement.resolve(selection: screen, visibleFrame: screen, controlsSize: controls)
        XCTAssertTrue(screen.contains(frame))
        XCTAssertLessThanOrEqual(frame.maxY, screen.maxY - 26)
    }
}
