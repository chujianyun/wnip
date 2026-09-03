import AppKit
import SwiftUI
import XCTest
@testable import Wnip

@MainActor
final class OverlayControllerTests: XCTestCase {
    func testCommandZRequiresExactCommandModifier() {
        XCTAssertEqual(
            OverlayKeyboardShortcut.resolve(
                keyCode: 6,
                charactersIgnoringModifiers: "z",
                modifiers: .command
            ),
            .undo
        )

        let modifiedVariants: [NSEvent.ModifierFlags] = [
            [.command, .shift],
            [.command, .option],
            [.command, .control]
        ]
        for modifiers in modifiedVariants {
            XCTAssertNil(
                OverlayKeyboardShortcut.resolve(
                    keyCode: 6,
                    charactersIgnoringModifiers: "z",
                    modifiers: modifiers
                ),
                "Unexpectedly consumed modifiers: \(modifiers)"
            )
        }
    }

    func testEscapeRoutesCancel() {
        XCTAssertEqual(
            OverlayKeyboardShortcut.resolve(
                keyCode: 53,
                charactersIgnoringModifiers: "\u{1b}",
                modifiers: []
            ),
            .cancel
        )
    }

    func testUpdateRefreshesVisibleFrameWhenDisplayDescriptorIsUnchanged() throws {
        let display = DisplayDescriptor(
            id: UInt32.max - 1,
            frame: CGRect(x: 50_000, y: 50_000, width: 200, height: 120),
            scale: 1
        )
        let presentation = OverlayPresentation(mode: .region, displays: [display])
        var suppliedVisibleFrame = CGRect(x: 50_000, y: 50_000, width: 200, height: 100)
        let controller = OverlayController { _ in suppliedVisibleFrame }
        controller.present(presentation, callbacks: OverlayCallbacks())
        defer { controller.dismissAll() }

        let panel = try XCTUnwrap(
            NSApp.windows.compactMap { $0 as? CaptureOverlayWindow }
                .first(where: { $0.displayID == display.id })
        )
        let hostingView = try XCTUnwrap(panel.contentView as? NSHostingView<CaptureOverlayView>)
        XCTAssertEqual(hostingView.rootView.viewModel.visibleFrame, suppliedVisibleFrame)

        suppliedVisibleFrame = CGRect(x: 50_000, y: 50_010, width: 200, height: 90)
        controller.update(presentation)

        XCTAssertEqual(hostingView.rootView.viewModel.visibleFrame, suppliedVisibleFrame)
    }
}
