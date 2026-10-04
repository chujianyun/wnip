import AppKit
import SwiftUI
import XCTest
@testable import Wnip

@MainActor
final class ColorPanelOverlayTests: XCTestCase {
    private let display = DisplayDescriptor(
        id: UInt32.max - 5,
        frame: CGRect(x: 50_000, y: 50_000, width: 800, height: 600),
        scale: 1
    )

    func testColorPanelFloatsAboveCaptureOverlayWhileAnnotating() throws {
        let controller = OverlayController()
        controller.present(OverlayPresentation(mode: .region, displays: [display]), callbacks: OverlayCallbacks())
        defer {
            controller.dismissAll()
            NSColorPanel.shared.orderOut(nil)
        }
        let overlay = try XCTUnwrap(NSApp.windows.compactMap { $0 as? CaptureOverlayWindow }
            .first { $0.displayID == display.id })

        // Clicking the SwiftUI ColorPicker in the annotation toolbar shows the shared NSColorPanel.
        let panel = NSColorPanel.shared
        panel.orderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(panel.isVisible, "Color panel should be visible once the picker is clicked")
        XCTAssertGreaterThan(
            panel.level.rawValue,
            overlay.level.rawValue,
            "Color panel must float above the screenSaver-level overlay; otherwise it stays hidden behind the fullscreen capture window until the capture ends"
        )
    }

    func testColorPanelLevelIsRestoredAfterOverlayDismisses() throws {
        let panel = NSColorPanel.shared
        let original = panel.level
        let controller = OverlayController()
        controller.present(OverlayPresentation(mode: .region, displays: [display]), callbacks: OverlayCallbacks())
        controller.dismissAll()
        XCTAssertEqual(panel.level, original, "Dismissing the overlay must restore the color panel's original level")
    }

    func testOverlayColorWellReassertsPanelLevelWhenPickerShown() throws {
        let controller = OverlayController()
        controller.present(OverlayPresentation(mode: .region, displays: [display]), callbacks: OverlayCallbacks())
        defer {
            controller.dismissAll()
            NSColorPanel.shared.orderOut(nil)
        }
        let overlay = try XCTUnwrap(NSApp.windows.compactMap { $0 as? CaptureOverlayWindow }
            .first { $0.displayID == display.id })

        // The real click path on macOS 26: activating a color well shows the
        // shared panel and resets its level back to floating. The overlay well
        // must re-assert the level after showing it.
        let panel = NSColorPanel.shared
        panel.level = .floating
        let well = OverlayColorWell()
        well.activate(true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertTrue(panel.isVisible)
        XCTAssertGreaterThan(
            panel.level.rawValue,
            overlay.level.rawValue,
            "Activating the overlay color well must leave the panel above the screenSaver-level overlay"
        )
    }
}
