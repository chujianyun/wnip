import XCTest
@testable import Wnip

final class OverlayInteractionGeometryTests: XCTestCase {
    func testConvertsGlobalSelectionToDisplayLocalTopLeftCoordinates() {
        let displayFrame = CGRect(x: -1440, y: 0, width: 1440, height: 900)

        let localRect = OverlayInteractionGeometry.localRect(
            forGlobalRect: CGRect(x: -1340, y: 100, width: 200, height: 50),
            in: displayFrame
        )

        XCTAssertEqual(localRect, CGRect(x: 100, y: 750, width: 200, height: 50))
    }

    func testConvertsDisplayLocalPointToGlobalBottomLeftCoordinates() {
        let displayFrame = CGRect(x: -1440, y: 0, width: 1440, height: 900)

        let globalPoint = OverlayInteractionGeometry.globalPoint(
            forLocalPoint: CGPoint(x: 100, y: 750),
            in: displayFrame
        )

        XCTAssertEqual(globalPoint, CGPoint(x: -1340, y: 150))
    }

    func testFindsEachResizeHandleAtItsVisibleCenter() {
        let selection = CGRect(x: 20, y: 30, width: 100, height: 60)
        let cases: [(CGPoint, SelectionHandle)] = [
            (CGPoint(x: 20, y: 90), .topLeft),
            (CGPoint(x: 70, y: 90), .top),
            (CGPoint(x: 120, y: 90), .topRight),
            (CGPoint(x: 120, y: 60), .right),
            (CGPoint(x: 120, y: 30), .bottomRight),
            (CGPoint(x: 70, y: 30), .bottom),
            (CGPoint(x: 20, y: 30), .bottomLeft),
            (CGPoint(x: 20, y: 60), .left)
        ]

        for (point, expectedHandle) in cases {
            XCTAssertEqual(
                OverlayInteractionGeometry.resizeHandle(at: point, selection: selection),
                expectedHandle
            )
        }
    }

    func testEmptySelectionHasNoResizeHandles() {
        XCTAssertNil(
            OverlayInteractionGeometry.resizeHandle(
                at: .zero,
                selection: .zero
            )
        )
    }

    func testSelectsFrontmostWindowContainingPointer() {
        let front = candidate(id: 1, frame: CGRect(x: 50, y: 50, width: 100, height: 100))
        let back = candidate(id: 2, frame: CGRect(x: 0, y: 0, width: 300, height: 300))

        let match = OverlayInteractionGeometry.window(
            at: CGPoint(x: 75, y: 75),
            candidatesInFrontToBackOrder: [front, back]
        )

        XCTAssertEqual(match?.id, 1)
    }

    func testWindowEditingCanResizeCapturedSelection() {
        let original = SelectionModel(rect: CGRect(x: 20, y: 20, width: 40, height: 30))
        let start = CGPoint(x: 60, y: 35)

        let drag = OverlayInteractionGeometry.selectionDrag(
            at: start,
            mode: .window,
            showsToolbar: true,
            selection: original.rect
        )
        let updated = OverlayInteractionGeometry.updatedSelection(
            original,
            drag: drag,
            from: start,
            to: CGPoint(x: 80, y: 35),
            within: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(drag, .resize(.right))
        XCTAssertEqual(updated.rect, CGRect(x: 20, y: 20, width: 60, height: 30))
    }

    func testFullScreenEditingCanResizeCapturedSelection() {
        let original = SelectionModel(rect: CGRect(x: 20, y: 20, width: 60, height: 50))
        let start = CGPoint(x: 50, y: 20)

        let drag = OverlayInteractionGeometry.selectionDrag(
            at: start,
            mode: .fullScreen,
            showsToolbar: true,
            selection: original.rect
        )
        let updated = OverlayInteractionGeometry.updatedSelection(
            original,
            drag: drag,
            from: start,
            to: CGPoint(x: 50, y: 10),
            within: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(drag, .resize(.bottom))
        XCTAssertEqual(updated.rect, CGRect(x: 20, y: 10, width: 60, height: 60))
    }

    func testFullScreenEditingHighlightsCropInsteadOfWholeDisplay() {
        let crop = CGRect(x: 20, y: 20, width: 60, height: 50)

        let highlighted = OverlayInteractionGeometry.highlightedRect(
            mode: .fullScreen,
            showsToolbar: true,
            selection: crop,
            hoveredWindow: nil,
            displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
            isActiveDisplay: true
        )

        XCTAssertEqual(highlighted, crop)
    }

    func testWindowSelectionIsNotResizableBeforeEditing() {
        XCTAssertNil(
            OverlayInteractionGeometry.selectionDrag(
                at: CGPoint(x: 60, y: 35),
                mode: .window,
                showsToolbar: false,
                selection: CGRect(x: 20, y: 20, width: 40, height: 30)
            )
        )
    }

    func testWindowHoverTrackingStopsDuringEditing() {
        XCTAssertTrue(
            OverlayInteractionGeometry.tracksWindowHover(
                mode: .window,
                showsToolbar: false
            )
        )
        XCTAssertFalse(
            OverlayInteractionGeometry.tracksWindowHover(
                mode: .window,
                showsToolbar: true
            )
        )
    }

    func testCommittedSelectionDoesNotRestartFromCanvasOrOutsideClicks() {
        let selection = CGRect(x: 100, y: 100, width: 800, height: 400)
        for mode: CaptureMode in [.region, .window, .fullScreen] {
            for point in [CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 70)] {
                let drag = OverlayInteractionGeometry.selectionDrag(
                    at: point, mode: mode, showsToolbar: true, selection: selection)
                XCTAssertNil(drag, "Committed \(mode) selection must not restart")
                XCTAssertEqual(OverlayInteractionGeometry.updatedSelection(
                    SelectionModel(rect: selection), drag: drag, from: point,
                    to: CGPoint(x: 500, y: 350),
                    within: CGRect(x: 0, y: 0, width: 1920, height: 1080)).rect, selection)
            }
        }
    }

    func testRegionStillStartsSelectionBeforeCommit() {
        XCTAssertEqual(OverlayInteractionGeometry.selectionDrag(
            at: CGPoint(x: 200, y: 200), mode: .region,
            showsToolbar: false, selection: .zero), .newSelection)
    }

    private func candidate(id: UInt32, frame: CGRect) -> CaptureCandidateWindow {
        CaptureCandidateWindow(
            id: id,
            title: "Window \(id)",
            applicationName: "Example",
            bundleIdentifier: "com.example.app",
            frame: frame,
            isVisible: true,
            isOnScreen: true,
            isDesktopElement: false
        )
    }
}
