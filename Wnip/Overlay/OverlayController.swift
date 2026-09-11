import AppKit
import SwiftUI

enum OverlayKeyboardAction: Equatable, Sendable {
    case cancel
    case undo
    case copy
    case pin
}

enum OverlayKeyboardShortcut {
    static func resolve(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> OverlayKeyboardAction? {
        if keyCode == 53 {
            return .cancel
        }
        let effectiveModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        if (keyCode == 36 || keyCode == 76),
           effectiveModifiers.intersection([.command, .control, .option, .shift]).isEmpty {
            return .copy
        }
        if effectiveModifiers.subtracting(.capsLock) == [.command, .shift], keyCode == 35 {
            return .pin
        }
        if effectiveModifiers == .command,
           charactersIgnoringModifiers?.lowercased() == "z" {
            return .undo
        }
        return nil
    }
}

struct OverlayPresentation: Equatable, Sendable {
    let mode: CaptureMode
    let displays: [DisplayDescriptor]
    let windows: [CaptureCandidateWindow]
    var selection: SelectionModel
    var hoveredWindowID: UInt32?
    var activeDisplayID: UInt32?
    var showsToolbar: Bool
    var selectedWindow: CaptureCandidateWindow?
    var addingBackground = false
    var annotations: [Annotation] = []
    var sourceImages: [UInt32: PixelImage] = [:]

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
    var onCopy: @MainActor (OverlayPresentation) -> Void = { _ in }
    var onSave: @MainActor (OverlayPresentation) -> Void = { _ in }
    var onPin: @MainActor (OverlayPresentation) -> Void = { _ in }
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
    func pinSelection()
}

@MainActor
final class OverlayController: OverlayControlling {
    private var windows: [UInt32: CaptureOverlayWindow] = [:]
    private var viewModels: [UInt32: CaptureOverlayViewModel] = [:]
    private var presentation: OverlayPresentation?
    private var callbacks = OverlayCallbacks()
    private var eventMonitor: Any?
    private let visibleFrameProvider: @MainActor (DisplayDescriptor) -> CGRect

    init(
        visibleFrameProvider: @escaping @MainActor (DisplayDescriptor) -> CGRect = { display in
            AppKitScreenGeometry.current.first(where: { $0.displayID == display.id })?.visibleFrame
                ?? display.frame
        }
    ) {
        self.visibleFrameProvider = visibleFrameProvider
    }

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
                    viewModel.update(
                        presentation: presentation,
                        visibleFrame: visibleFrameProvider(display)
                    )
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
            visibleFrame: visibleFrameProvider(display),
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
                self?.commitSelection(selection, activeDisplayID: displayID)
                self?.callbacks.onSelectionCommitted(displayID, selection)
            },
            onWindowHovered: { [weak self] displayID, window in
                self?.setHoveredWindow(window, activeDisplayID: displayID)
            },
            onWindowSelected: { [weak self] displayID, window in
                self?.commitSelection(SelectionModel(rect: window.frame), activeDisplayID: displayID)
                self?.presentation?.selectedWindow = window
                self?.callbacks.onWindowSelected(displayID, window)
            },
            onDisplaySelected: { [weak self] display in
                self?.commitSelection(SelectionModel(rect: display.frame), activeDisplayID: display.id)
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

    private func commitSelection(_ selection: SelectionModel, activeDisplayID: UInt32) {
        guard var presentation,
              !selection.rect.isEmpty,
              !selection.rect.isNull,
              presentation.displays.contains(where: { $0.id == activeDisplayID }) else { return }
        presentation.selection = selection
        presentation.activeDisplayID = activeDisplayID
        presentation.hoveredWindowID = nil
        presentation.showsToolbar = true
        apply(presentation)
        makeActivePanelKey()
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
        guard var presentation, !presentation.showsToolbar else { return }
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

    func pinSelection() {
        routeToolbarAction(.pin)
    }

    private func routeToolbarAction(_ action: OverlayToolbarAction) {
        let viewModel = presentation?.activeDisplayID.flatMap { viewModels[$0] }
        switch action {
        case .cancel:
            callbacks.onCancel()
        case .undo:
            if viewModel?.annotationModel.textEditorOrigin != nil {
                viewModel?.annotationModel.cancelTextEditing()
            } else {
                _ = viewModel?.annotationModel.undo()
            }
            callbacks.onUndo()
        case .copy, .save, .pin, .background:
            guard var presentation, presentation.showsToolbar,
                  !presentation.selection.rect.isEmpty else { return }
            _ = viewModel?.annotationModel.commitActiveTextInput()
            presentation.annotations = viewModel?.annotationModel.document.annotations ?? []
            if action == .background { presentation.addingBackground = true; callbacks.onCopy(presentation) }
            else if action == .copy { callbacks.onCopy(presentation) }
            else if action == .save { callbacks.onSave(presentation) }
            else { callbacks.onPin(presentation) }
        default:
            guard presentation?.showsToolbar == true, let viewModel else { return }
            _ = viewModel.annotationModel.commitActiveTextInput()
            if viewModel.annotationModel.handleToolbarAction(action) {
                viewModel.isAnnotating = true
            }
            callbacks.onToolbarAction(action)
        }
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch OverlayKeyboardShortcut.resolve(
                keyCode: event.keyCode,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                modifiers: event.modifierFlags
            ) {
            case .cancel:
                if self.windows.values.contains(where: { $0.firstResponder is NSTextView }) {
                    return event
                }
                self.callbacks.onCancel()
                return nil
            case .undo:
                if self.windows.values.contains(where: { $0.firstResponder is NSTextView }) {
                    return event
                }
                self.routeToolbarAction(.undo)
                return nil
            case .copy:
                // Let text editors consume Return while entering an annotation.
                if self.windows.values.contains(where: { $0.firstResponder is NSTextView }) {
                    return event
                }
                self.routeToolbarAction(.copy)
                return nil
            case .pin:
                self.pinSelection()
                return nil
            case nil:
                return event
            }
        }
    }

    private func makeActivePanelKey() {
        let activeID = presentation?.activeDisplayID ?? presentation?.displays.first?.id
        if let activeID {
            windows[activeID]?.makeKeyAndOrderFront(nil)
        }
    }

}
