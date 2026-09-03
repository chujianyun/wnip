import AppKit
import SwiftUI

struct OverlayPresentation: Equatable, Sendable {
    let mode: CaptureMode
    let displays: [DisplayDescriptor]
    let windows: [CaptureCandidateWindow]
    var selection: SelectionModel
    var hoveredWindowID: UInt32?
    var activeDisplayID: UInt32?
    var showsToolbar: Bool

    init(
        mode: CaptureMode,
        displays: [DisplayDescriptor],
        windows: [CaptureCandidateWindow] = [],
        selection: SelectionModel = SelectionModel(),
        hoveredWindowID: UInt32? = nil,
        activeDisplayID: UInt32? = nil,
        showsToolbar: Bool = false
    ) {
        self.mode = mode
        self.displays = displays
        self.windows = windows
        self.selection = selection
        self.hoveredWindowID = hoveredWindowID
        self.activeDisplayID = activeDisplayID
        self.showsToolbar = showsToolbar
    }
}

struct OverlayCallbacks {
    var onCancel: @MainActor () -> Void = {}
    var onUndo: @MainActor () -> Void = {}
    var onSelectionChanged: @MainActor (UInt32, SelectionModel) -> Void = { _, _ in }
    var onSelectionCommitted: @MainActor (UInt32, SelectionModel) -> Void = { _, _ in }
    var onWindowHovered: @MainActor (UInt32, CaptureCandidateWindow?) -> Void = { _, _ in }
    var onWindowSelected: @MainActor (UInt32, CaptureCandidateWindow) -> Void = { _, _ in }
    var onDisplaySelected: @MainActor (DisplayDescriptor) -> Void = { _ in }
    var onToolbarAction: @MainActor (OverlayToolbarAction) -> Void = { _ in }
}

@MainActor
protocol OverlayControlling: AnyObject {
    func present(_ presentation: OverlayPresentation, callbacks: OverlayCallbacks)
    func update(_ presentation: OverlayPresentation)
    func dismissAll()
}

@MainActor
final class OverlayController: OverlayControlling {
    private var windows: [UInt32: CaptureOverlayWindow] = [:]
    private var viewModels: [UInt32: CaptureOverlayViewModel] = [:]
    private var presentation: OverlayPresentation?
    private var callbacks = OverlayCallbacks()
    private var eventMonitor: Any?

    func present(_ presentation: OverlayPresentation, callbacks: OverlayCallbacks) {
        dismissAll()
        self.presentation = presentation
        self.callbacks = callbacks
        installEventMonitor()
        reconcileWindows(for: presentation)
        NSApp.activate(ignoringOtherApps: true)
        makeActivePanelKey()
    }

    func update(_ presentation: OverlayPresentation) {
        guard self.presentation != nil else { return }
        self.presentation = presentation
        reconcileWindows(for: presentation)
        for viewModel in viewModels.values {
            viewModel.presentation = presentation
        }
        makeActivePanelKey()
    }

    func dismissAll() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        for window in windows.values {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        viewModels.removeAll()
        presentation = nil
        callbacks = OverlayCallbacks()
    }

    deinit {
        MainActor.assumeIsolated {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            for window in windows.values {
                window.orderOut(nil)
                window.close()
            }
        }
    }

    private func reconcileWindows(for presentation: OverlayPresentation) {
        let displayIDs = Set(presentation.displays.map(\.id))
        let removedIDs = Set(windows.keys).subtracting(displayIDs)
        for displayID in removedIDs {
            if let window = windows.removeValue(forKey: displayID) {
                window.orderOut(nil)
                window.contentView = nil
                window.close()
            }
            viewModels.removeValue(forKey: displayID)
        }

        for display in presentation.displays {
            if let window = windows[display.id], let viewModel = viewModels[display.id] {
                if viewModel.display == display {
                    window.setFrame(display.frame, display: false)
                    viewModel.presentation = presentation
                    continue
                }
                window.orderOut(nil)
                window.contentView = nil
                window.close()
                windows.removeValue(forKey: display.id)
                viewModels.removeValue(forKey: display.id)
            }
            makeWindow(for: display, presentation: presentation)
        }
    }

    private func makeWindow(for display: DisplayDescriptor, presentation: OverlayPresentation) {
        let viewModel = CaptureOverlayViewModel(
            display: display,
            visibleFrame: visibleFrame(for: display),
            presentation: presentation
        )
        let view = CaptureOverlayView(
            viewModel: viewModel,
            onActiveDisplay: { [weak self] displayID in
                self?.setActiveDisplay(displayID)
            },
            onSelectionChanged: { [weak self] displayID, selection in
                self?.setSelection(selection, activeDisplayID: displayID)
            },
            onSelectionCommitted: { [weak self] displayID, selection in
                self?.callbacks.onSelectionCommitted(displayID, selection)
            },
            onWindowHovered: { [weak self] displayID, window in
                self?.setHoveredWindow(window, activeDisplayID: displayID)
            },
            onWindowSelected: { [weak self] displayID, window in
                self?.callbacks.onWindowSelected(displayID, window)
            },
            onDisplaySelected: { [weak self] display in
                self?.callbacks.onDisplaySelected(display)
            },
            onToolbarAction: { [weak self] action in
                self?.routeToolbarAction(action)
            }
        )
        let window = CaptureOverlayWindow(display: display, rootView: view)
        viewModels[display.id] = viewModel
        windows[display.id] = window
        window.orderFrontRegardless()
    }

    private func setActiveDisplay(_ displayID: UInt32) {
        guard var presentation, presentation.activeDisplayID != displayID else { return }
        presentation.activeDisplayID = displayID
        apply(presentation)
    }

    private func setSelection(_ selection: SelectionModel, activeDisplayID: UInt32) {
        guard var presentation else { return }
        presentation.selection = selection
        presentation.activeDisplayID = activeDisplayID
        apply(presentation)
        callbacks.onSelectionChanged(activeDisplayID, selection)
    }

    private func setHoveredWindow(
        _ window: CaptureCandidateWindow?,
        activeDisplayID: UInt32
    ) {
        guard var presentation else { return }
        presentation.hoveredWindowID = window?.id
        presentation.activeDisplayID = activeDisplayID
        apply(presentation)
        callbacks.onWindowHovered(activeDisplayID, window)
    }

    private func apply(_ presentation: OverlayPresentation) {
        self.presentation = presentation
        for viewModel in viewModels.values {
            viewModel.presentation = presentation
        }
    }

    private func routeToolbarAction(_ action: OverlayToolbarAction) {
        switch action {
        case .cancel:
            callbacks.onCancel()
        case .undo:
            callbacks.onUndo()
        default:
            callbacks.onToolbarAction(action)
        }
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.callbacks.onCancel()
                return nil
            }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "z" {
                self.callbacks.onUndo()
                return nil
            }
            return event
        }
    }

    private func makeActivePanelKey() {
        let activeID = presentation?.activeDisplayID ?? presentation?.displays.first?.id
        if let activeID {
            windows[activeID]?.makeKeyAndOrderFront(nil)
        }
    }

    private func visibleFrame(for display: DisplayDescriptor) -> CGRect {
        let matchingScreen = NSScreen.screens.first { screen in
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return screenNumber?.uint32Value == display.id
        }
        return matchingScreen?.visibleFrame ?? display.frame
    }
}
