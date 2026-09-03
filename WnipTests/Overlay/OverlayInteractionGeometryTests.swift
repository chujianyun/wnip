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
