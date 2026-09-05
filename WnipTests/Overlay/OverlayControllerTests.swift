import AppKit
import SwiftUI
import XCTest
@testable import Wnip

@MainActor
final class OverlayControllerTests: XCTestCase {
    func testReturnAndKeypadEnterResolveToCopyWithoutModifiers() {
        for keyCode: UInt16 in [36, 76] {
            XCTAssertEqual(OverlayKeyboardShortcut.resolve(keyCode: keyCode,
                charactersIgnoringModifiers: "\r", modifiers: []), .copy)
            XCTAssertNil(OverlayKeyboardShortcut.resolve(keyCode: keyCode,
                charactersIgnoringModifiers: "\r", modifiers: .command))
        }
    }

    func testCopyOnlyForwardsCommittedSelectionIncludingWindowTarget() throws {
        let display = DisplayDescriptor(id: UInt32.max - 3,
            frame: CGRect(x: 50_000, y: 50_000, width: 800, height: 600), scale: 1)
        let controller = OverlayController()
        var copies: [OverlayPresentation] = []
        controller.present(OverlayPresentation(mode: .window, displays: [display]),
            callbacks: OverlayCallbacks(onCopy: { copies.append($0) }))
        defer { controller.dismissAll() }
        let view = try overlayView(displayID: display.id)
        view.onToolbarAction(.copy)
        XCTAssertTrue(copies.isEmpty)
        let window = CaptureCandidateWindow(id: 7, title: nil, applicationName: nil,
            bundleIdentifier: "test", frame: display.frame.insetBy(dx: 20, dy: 20),
            isVisible: true, isOnScreen: true, isDesktopElement: false)
        view.onWindowSelected(display.id, window)
        view.onToolbarAction(.copy)
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(copies.first?.selectedWindow, window)
        XCTAssertEqual(copies.first?.selection.rect, window.frame)
    }

    func testSelectingWindowLocksSelectionAndShowsToolbar() throws {
        let (controller, view) = try makeWindowOverlay()
        defer { controller.dismissAll() }
        let display = view.viewModel.display
        let target = CaptureCandidateWindow(
            id: 7, title: "Test", applicationName: "Test", bundleIdentifier: "test.app",
            frame: display.frame.insetBy(dx: 20, dy: 20), isVisible: true,
            isOnScreen: true, isDesktopElement: false
        )

        view.onWindowSelected(display.id, target)

        XCTAssertTrue(view.viewModel.presentation.showsToolbar)
        XCTAssertEqual(view.viewModel.presentation.selection.rect, target.frame)
        XCTAssertEqual(view.viewModel.presentation.activeDisplayID, display.id)
        XCTAssertNil(view.viewModel.presentation.hoveredWindowID)
        view.onWindowHovered(display.id, nil)
        XCTAssertEqual(view.viewModel.presentation.selection.rect, target.frame)
        XCTAssertTrue(view.viewModel.presentation.showsToolbar)
    }

    func testCommittingSelectionShowsToolbarAndNewCaptureResetsIt() throws {
        let (controller, view) = try makeWindowOverlay(mode: .region)
        defer { controller.dismissAll() }
        let display = view.viewModel.display
        let selection = SelectionModel(rect: display.frame.insetBy(dx: 20, dy: 20))
        view.onSelectionCommitted(display.id, selection)
        XCTAssertTrue(view.viewModel.presentation.showsToolbar)
        XCTAssertEqual(view.viewModel.presentation.selection, selection)

        controller.present(OverlayPresentation(mode: .window, displays: [display]), callbacks: OverlayCallbacks())
        let next = try overlayView(displayID: display.id)
        XCTAssertFalse(next.viewModel.presentation.showsToolbar)
        XCTAssertTrue(next.viewModel.presentation.selection.rect.isEmpty)
    }

    func testEmptySelectionDoesNotShowToolbar() throws {
        let (controller, view) = try makeWindowOverlay()
        defer { controller.dismissAll() }
        view.onSelectionCommitted(view.viewModel.display.id, SelectionModel())
        XCTAssertFalse(view.viewModel.presentation.showsToolbar)
    }

    func testSelectingDisplayShowsToolbarForFullScreenSelection() throws {
        let (controller, view) = try makeWindowOverlay(mode: .fullScreen)
        defer { controller.dismissAll() }
        view.onDisplaySelected(view.viewModel.display)
        XCTAssertTrue(view.viewModel.presentation.showsToolbar)
        XCTAssertEqual(view.viewModel.presentation.selection.rect, view.viewModel.display.frame)
    }

    private func makeWindowOverlay(mode: CaptureMode = .window) throws -> (OverlayController, CaptureOverlayView) {
        let display = DisplayDescriptor(id: UInt32.max - 2,
            frame: CGRect(x: 50_000, y: 50_000, width: 800, height: 600), scale: 1)
        let controller = OverlayController()
        controller.present(OverlayPresentation(mode: mode, displays: [display]), callbacks: OverlayCallbacks())
        return (controller, try overlayView(displayID: display.id))
    }

    private func overlayView(displayID: UInt32) throws -> CaptureOverlayView {
        let panel = try XCTUnwrap(NSApp.windows.compactMap { $0 as? CaptureOverlayWindow }
            .first { $0.displayID == displayID && $0.contentView != nil })
        return try XCTUnwrap(panel.contentView as? NSHostingView<CaptureOverlayView>).rootView
    }

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
