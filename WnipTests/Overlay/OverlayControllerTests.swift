import AppKit
import SwiftUI
import XCTest
@testable import Wnip

@MainActor
final class OverlayControllerTests: XCTestCase {
    func testPinShortcutRequiresCommandShiftP() {
        XCTAssertEqual(OverlayKeyboardShortcut.resolve(keyCode: 35,
            charactersIgnoringModifiers: "P", modifiers: [.command, .shift]), .pin)
        XCTAssertEqual(OverlayKeyboardShortcut.resolve(keyCode: 35,
            charactersIgnoringModifiers: "P", modifiers: [.command, .shift, .capsLock]), .pin)
        for modifiers: NSEvent.ModifierFlags in [[], .command, .shift, [.command, .shift, .option]] {
            XCTAssertNil(OverlayKeyboardShortcut.resolve(keyCode: 35,
                charactersIgnoringModifiers: "p", modifiers: modifiers))
        }
    }

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

    func testToolbarDrawUndoAndExportKeepCommittedSelection() throws {
        for mode: CaptureMode in [.region, .window, .fullScreen] {
            let (controller, view) = try makeWindowOverlay(mode: mode)
            defer { controller.dismissAll() }
            let display = view.viewModel.display
            let selection = SelectionModel(rect: display.frame.insetBy(dx: 20, dy: 20))
            view.onSelectionCommitted(display.id, selection)
            view.onToolbarAction(.ellipse)
            XCTAssertTrue(view.viewModel.isAnnotating)
            let model = view.viewModel.annotationModel
            model.gestureChanged(startLocation: CGPoint(x: 100, y: 100), location: CGPoint(x: 200, y: 150))
            model.gestureEnded(startLocation: CGPoint(x: 100, y: 100), location: CGPoint(x: 200, y: 150))
            XCTAssertEqual(model.document.annotations.first?.content,
                           .ellipse(CGRect(x: 100, y: 100, width: 100, height: 50)))
            XCTAssertEqual(view.viewModel.presentation.selection, selection)
            view.onToolbarAction(.undo)
            XCTAssertTrue(model.document.annotations.isEmpty)
            XCTAssertEqual(view.viewModel.presentation.selection, selection)
        }
    }

    func testCopyAndSaveIncludeDrawnAndPendingTextAnnotations() throws {
        let display = DisplayDescriptor(id: UInt32.max - 3,
            frame: CGRect(x: 50_000, y: 50_000, width: 800, height: 600), scale: 1)
        let controller = OverlayController()
        var copies: [OverlayPresentation] = []
        var saves: [OverlayPresentation] = []
        var pins: [OverlayPresentation] = []
        controller.present(OverlayPresentation(mode: .region, displays: [display]),
            callbacks: OverlayCallbacks(onCopy: { copies.append($0) }, onSave: { saves.append($0) }, onPin: { pins.append($0) }))
        defer { controller.dismissAll() }
        let view = try overlayView(displayID: display.id)
        let selection = SelectionModel(rect: display.frame.insetBy(dx: 20, dy: 20))
        view.onSelectionCommitted(display.id, selection)
        view.onToolbarAction(.rectangle)
        let model = view.viewModel.annotationModel
        model.gestureChanged(startLocation: CGPoint(x: 80, y: 80), location: CGPoint(x: 180, y: 180))
        model.gestureEnded(startLocation: CGPoint(x: 80, y: 80), location: CGPoint(x: 180, y: 180))
        view.onToolbarAction(.text)
        model.pointerDown(at: CGPoint(x: 100, y: 220))
        model.pointerUp(at: CGPoint(x: 100, y: 220))
        model.textDraft = "Check"
        controller.pinSelection()
        view.onToolbarAction(.copy)
        view.onToolbarAction(.save)
        XCTAssertEqual(pins.first?.annotations.count, 2)
        XCTAssertEqual(pins.first?.annotations, copies.first?.annotations)
        XCTAssertEqual(copies.first?.annotations.count, 2)
        XCTAssertEqual(saves.first?.annotations, copies.first?.annotations)
        XCTAssertEqual(copies.first?.selection, selection)
        XCTAssertNil(model.textEditorOrigin)
        controller.present(OverlayPresentation(mode: .region, displays: [display]), callbacks: OverlayCallbacks())
        let next = try overlayView(displayID: display.id)
        XCTAssertFalse(next.viewModel.isAnnotating)
        XCTAssertTrue(next.viewModel.annotationModel.document.annotations.isEmpty)
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
