import XCTest
@testable import Wnip

final class ToolbarPlacementTests: XCTestCase {
    func testPlacesToolbarBelowSelectionWhenDisplayHasRoom() {
        let frame = ToolbarPlacement.resolve(
            selection: CGRect(x: 300, y: 300, width: 200, height: 100),
            visibleFrame: CGRect(x: 100, y: 50, width: 800, height: 600),
            toolbarSize: CGSize(width: 180, height: 44)
        )

        XCTAssertEqual(frame, CGRect(x: 310, y: 248, width: 180, height: 44))
    }

    func testPlacesToolbarAboveSelectionWhenBelowWouldLeaveDisplay() {
        let frame = ToolbarPlacement.resolve(
            selection: CGRect(x: 300, y: 60, width: 200, height: 40),
            visibleFrame: CGRect(x: 100, y: 50, width: 800, height: 600),
            toolbarSize: CGSize(width: 180, height: 44)
        )

        XCTAssertEqual(frame, CGRect(x: 310, y: 108, width: 180, height: 44))
    }

    func testPlacesToolbarInsideSelectionWhenNeitherOutsideEdgeHasRoom() {
        let frame = ToolbarPlacement.resolve(
            selection: CGRect(x: 250, y: 55, width: 500, height: 190),
            visibleFrame: CGRect(x: 100, y: 50, width: 800, height: 200),
            toolbarSize: CGSize(width: 180, height: 44)
        )

        XCTAssertEqual(frame, CGRect(x: 410, y: 63, width: 180, height: 44))
    }

    func testClampsToolbarAgainstLeftDisplaySafeEdge() {
        let frame = ToolbarPlacement.resolve(
            selection: CGRect(x: 100, y: 300, width: 20, height: 100),
            visibleFrame: CGRect(x: 100, y: 50, width: 800, height: 600),
            toolbarSize: CGSize(width: 180, height: 44)
        )

        XCTAssertEqual(frame, CGRect(x: 108, y: 248, width: 180, height: 44))
    }

    func testClampsToolbarAgainstRightDisplaySafeEdge() {
        let frame = ToolbarPlacement.resolve(
            selection: CGRect(x: 880, y: 300, width: 20, height: 100),
            visibleFrame: CGRect(x: 100, y: 50, width: 800, height: 600),
            toolbarSize: CGSize(width: 180, height: 44)
        )

        XCTAssertEqual(frame, CGRect(x: 712, y: 248, width: 180, height: 44))
    }

    func testClampsPixelBadgeAgainstEveryVisibleEdge() {
        let visibleBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let badgeSize = CGSize(width: 100, height: 22)

        let topRight = PixelBadgePlacement.resolve(
            selection: CGRect(x: 790, y: 2, width: 10, height: 10),
            visibleBounds: visibleBounds,
            badgeSize: badgeSize
        )
        let bottomLeft = PixelBadgePlacement.resolve(
            selection: CGRect(x: -40, y: 700, width: 10, height: 10),
            visibleBounds: visibleBounds,
            badgeSize: badgeSize
        )

        XCTAssertEqual(topRight, CGRect(x: 696, y: 4, width: 100, height: 22))
        XCTAssertEqual(bottomLeft, CGRect(x: 4, y: 574, width: 100, height: 22))
    }
}
