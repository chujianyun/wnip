import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum CaptureCoordinatorError: LocalizedError, Equatable {
    case permissionDenied(URL)
    case captureFailed(String)
    case shortcutFailed(String)
    case saveDirectoryNotRemembered(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required."
        case .captureFailed(let message):
            return message
        case .saveDirectoryNotRemembered(let message):
            return message
        case .shortcutFailed(let message):
            return message
        }
    }

}

@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published private(set) var regionShortcut: HotKeyShortcut = .defaultRegionCapture
    @Published private(set) var windowShortcut: HotKeyShortcut = .defaultWindowCapture
    @Published private(set) var appPreferences = AppPreferences()
    @Published var presentedError: CaptureCoordinatorError?

    private let permission: any ScreenRecordingAuthorizing
    private let screen: any ScreenCapturing
    private let overlay: any OverlayControlling
    private let regionHotKey: any HotKeyRegistering
    private let windowHotKey: any HotKeyRegistering
    private let pinHotKey: any HotKeyRegistering
    private let backgroundEditor: any BackgroundEditorPresenting
    private let pinnedImages: any PinnedImagePresenting
    private var latestScreenshot: (image: PixelImage, frame: CGRect)?
    private var isCapturing = false
    private let preferences: any PreferencesStoring
    private let clipboard: ImageClipboard
    private let output: any OutputServing
    private let feedback: any CompletionFeedbackServing
    private var captureTask: Task<Void, Never>?
    private var requestID = 0
    private var isRecordingShortcut = false
    private var isCopying = false

    init() {
        permission = PermissionService()
        screen = ScreenCaptureService()
        overlay = OverlayController()
        regionHotKey = HotKeyService()
        windowHotKey = HotKeyService()
        pinHotKey = HotKeyService()
        backgroundEditor = BackgroundEditorController()
        pinnedImages = PinnedImageController()
        preferences = PreferencesStore()
        clipboard = ImageClipboard()
        output = OutputService()
        feedback = CompletionFeedbackService()
    }

    init(
        permission: any ScreenRecordingAuthorizing,
        screen: any ScreenCapturing,
        overlay: any OverlayControlling,
        regionHotKey: any HotKeyRegistering,
        windowHotKey: any HotKeyRegistering,
        preferences: any PreferencesStoring,
        clipboard: ImageClipboard? = nil,
        output: (any OutputServing)? = nil,
        feedback: (any CompletionFeedbackServing)? = nil,
        pinHotKey: (any HotKeyRegistering)? = nil,
        pinnedImages: (any PinnedImagePresenting)? = nil,
        backgroundEditor: (any BackgroundEditorPresenting)? = nil
    ) {
        self.permission = permission
        self.screen = screen
        self.overlay = overlay
        self.regionHotKey = regionHotKey
        self.windowHotKey = windowHotKey
        self.pinHotKey = pinHotKey ?? HotKeyService()
        self.backgroundEditor = backgroundEditor ?? BackgroundEditorController()
        self.pinnedImages = pinnedImages ?? PinnedImageController()
        self.preferences = preferences
        self.clipboard = clipboard ?? ImageClipboard()
        self.output = output ?? OutputService()
        self.feedback = feedback ?? CompletionFeedbackService(notify: { _ in }, playSound: { _ in }, performHaptic: { _ in })
    }

    func start() {
        do {
            let preferences = try preferences.load()
            appPreferences = preferences
            regionShortcut = preferences.regionShortcut
            windowShortcut = preferences.windowShortcut
        } catch {
            presentedError = .captureFailed(error.localizedDescription)
            return
        }
        registerCurrentShortcuts()
    }

    func startCapture(mode: CaptureMode, addingBackground: Bool = false) {
        requestID &+= 1
        let currentID = requestID
        captureTask?.cancel()
        isCopying = false
        overlay.dismissAll()
        isCapturing = true

        captureTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, currentID == requestID else { return }
            guard permission.isAuthorized() || permission.requestAuthorization() else {
                guard !Task.isCancelled, currentID == requestID else { return }
                // The system permission request already presents its own dialog.
                presentedError = nil
                isCapturing = false
                return
            }

            do {
                let content = try await screen.availableContent()
                guard !Task.isCancelled, currentID == requestID else { return }
                var presentation = OverlayPresentation(mode: mode, displays: content.displays, windows: content.windows)
                presentation.addingBackground = addingBackground
                // Freeze the same source used by both live annotations and export,
                // before creating any screenshot overlay windows.
                for display in content.displays {
                    let source = try await screen.captureDisplay(display, excluding: [])
                    guard !Task.isCancelled, currentID == requestID else { return }
                    presentation.sourceImages[display.id] = source
                }
                switch presentedError {
                case .shortcutFailed?: break
                default: presentedError = nil
                }
                overlay.present(
                    presentation,
                    callbacks: OverlayCallbacks(onCopy: { [weak self] selection in
                        self?.copySelection(selection, requestID: currentID)
                    }, onSave: { [weak self] selection in
                        self?.copySelection(selection, requestID: currentID, save: true)
                    }, onPin: { [weak self] selection in
                        self?.copySelection(selection, requestID: currentID, pin: true)
                    }, onCancel: { [weak self] in
                        self?.cancelCapture()
                    })
                )
            } catch {
                guard !Task.isCancelled, currentID == requestID else { return }
                isCapturing = false
                if error as? CaptureFailure == .permissionDenied {
                    presentedError = .permissionDenied(permission.privacySettingsURL)
                } else {
                    presentedError = .captureFailed(error.localizedDescription)
                }
            }
        }
    }

    func updateRegionShortcut(_ shortcut: HotKeyShortcut) {
        guard shortcut != .pinScreenshot else {
            presentedError = .shortcutFailed("That shortcut is reserved for Pin Screenshot.")
            return
        }
        guard shortcut != windowShortcut else {
            presentedError = .shortcutFailed("That shortcut is already assigned to Window Capture.")
            return
        }
        updateShortcut(
            shortcut,
            current: regionShortcut,
            hotKey: regionHotKey,
            mode: .region,
            apply: { $0.regionShortcut = shortcut },
            publish: { [weak self] in self?.regionShortcut = shortcut }
        )
    }

    func updateWindowShortcut(_ shortcut: HotKeyShortcut) {
        guard shortcut != .pinScreenshot else {
            presentedError = .shortcutFailed("That shortcut is reserved for Pin Screenshot.")
            return
        }
        guard shortcut != regionShortcut else {
            presentedError = .shortcutFailed("That shortcut is already assigned to Region Capture.")
            return
        }
        updateShortcut(
            shortcut,
            current: windowShortcut,
            hotKey: windowHotKey,
            mode: .window,
            apply: { $0.windowShortcut = shortcut },
            publish: { [weak self] in self?.windowShortcut = shortcut }
        )
    }

    private func updateShortcut(
        _ shortcut: HotKeyShortcut,
        current: HotKeyShortcut,
        hotKey: any HotKeyRegistering,
        mode: CaptureMode,
        apply: (inout AppPreferences) -> Void,
        publish: () -> Void
    ) {
        guard shortcut != current else { return }
        do {
            try hotKey.register(shortcut) { [weak self] in
                self?.startCapture(mode: mode)
            }
            do {
                var updated = try preferences.load()
                apply(&updated)
                try preferences.save(updated)
                appPreferences = updated
            } catch {
                try? hotKey.register(current) { [weak self] in
                    self?.startCapture(mode: mode)
                }
                throw error
            }
            publish()
            presentedError = nil
        } catch {
            presentedError = .shortcutFailed(error.localizedDescription)
        }
    }

    func cancelCapture() {
        requestID &+= 1
        captureTask?.cancel()
        captureTask = nil
        isCapturing = false
        isCopying = false
        overlay.dismissAll()
    }

    func pinScreenshot() {
        guard !isRecordingShortcut, !isCopying else { return }
        if isCapturing {
            overlay.pinSelection()
        } else if let latestScreenshot {
            pinnedImages.present(latestScreenshot.image, near: latestScreenshot.frame)
        }
    }

    private func copySelection(_ selection: OverlayPresentation, requestID currentID: Int, save: Bool = false, pin: Bool = false) {
        guard currentID == requestID, !isCopying, selection.showsToolbar,
              !selection.selection.rect.isEmpty,
              let display = selection.displays.first(where: { $0.id == selection.activeDisplayID }) else { return }
        isCopying = true
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { if currentID == requestID { isCopying = false } }
            guard !Task.isCancelled, currentID == requestID else { return }
            do {
                guard let source = selection.sourceImages[display.id] else {
                    throw CaptureFailure.captureFailed("The screenshot source is unavailable. Please capture again.")
                }
                let crop = OverlayInteractionGeometry.localRect(
                    forGlobalRect: selection.selection.rect, in: display.frame)
                let rendered = try ScreenshotImageRenderer().render(
                    source: source, crop: crop, annotations: selection.annotations,
                    shadow: !selection.addingBackground && CaptureShadowPolicy.shouldApply(mode: selection.mode,
                        regionEnabled: appPreferences.regionShadow, windowEnabled: appPreferences.windowShadow))
                guard !Task.isCancelled, currentID == requestID else { return }
                if selection.addingBackground {
                    isCapturing = false
                    overlay.dismissAll()
                    backgroundEditor.present(source: rendered) { [weak self] composed, save in
                        guard let self else { throw BackgroundFailure.renderFailed }
                        return try self.exportBackground(composed, scale: source.scale, frame: selection.selection.rect, save: save)
                    }
                    return
                }
                var bookmarkWarning: String?
                let image = PixelImage(image: rendered, scale: source.scale, colorSpace: source.colorSpace)
                if pin {
                    pinnedImages.present(image, near: selection.selection.rect)
                } else if save {
                    let result = try output.save(rendered, preferences: appPreferences)
                    if result.shouldRememberDirectory {
                        do {
                            try preferences.replaceSaveDirectoryBookmark(for: result.url.deletingLastPathComponent())
                            appPreferences = try preferences.load()
                        } catch {
                            bookmarkWarning = "The screenshot was saved, but its folder could not be remembered: \(error.localizedDescription)"
                        }
                    }
                } else {
                    try clipboard.write(image)
                }
                latestScreenshot = (image, selection.selection.rect)
                if !pin { feedback.perform(save ? .saved : .copied, preferences: appPreferences) }
                isCapturing = false
                overlay.dismissAll()
                presentedError = bookmarkWarning.map(CaptureCoordinatorError.saveDirectoryNotRemembered)
                NSApp.deactivate()
            } catch OutputFailure.cancelled {
                // Keep the editor and frozen image available when the save panel is cancelled.
            } catch {
                guard !Task.isCancelled, currentID == requestID else { return }
                presentedError = .captureFailed(error.localizedDescription)
            }
        }
    }

    private func exportBackground(_ image: CGImage, scale: CGFloat, frame: CGRect, save: Bool) throws -> String {
        var message = "已复制图片"
        if save {
            let result = try output.save(image, preferences: appPreferences)
            message = "已保存：\(result.url.lastPathComponent)"
            if result.shouldRememberDirectory {
                do {
                    try preferences.replaceSaveDirectoryBookmark(for: result.url.deletingLastPathComponent())
                    appPreferences = try preferences.load()
                } catch {
                    message += "（保存成功，但无法记住目录）"
                }
            }
        } else {
            try clipboard.write(PixelImage(image: image, scale: scale))
        }
        latestScreenshot = (PixelImage(image: image, scale: scale), frame)
        feedback.perform(save ? .saved : .copied, preferences: appPreferences)
        return message
    }

    func updatePreference<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>, to value: Value) {
        do {
            var replacement = try preferences.load()
            replacement[keyPath: keyPath] = value
            try preferences.save(replacement)
            appPreferences = replacement
        } catch {
            presentedError = .captureFailed(error.localizedDescription)
        }
    }

    func clearPresentedError() {
        presentedError = nil
    }

    func beginShortcutRecording() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        regionHotKey.unregister()
        windowHotKey.unregister()
        pinHotKey.unregister()
    }

    func endShortcutRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        registerCurrentShortcuts()
    }

    private func registerCurrentShortcuts() {
        var firstError: Error?
        do {
            try regionHotKey.register(regionShortcut) { [weak self] in
                self?.startCapture(mode: .region)
            }
        } catch {
            firstError = error
        }
        do {
            try windowHotKey.register(windowShortcut) { [weak self] in
                self?.startCapture(mode: .window)
            }
        } catch {
            if firstError == nil { firstError = error }
        }
        do {
            try pinHotKey.register(.pinScreenshot) { [weak self] in
                self?.pinScreenshot()
            }
        } catch {
            if firstError == nil { firstError = error }
        }
        if let firstError {
            presentedError = .shortcutFailed(firstError.localizedDescription)
        }
    }

    func waitForPendingCaptureForTesting() async {
        await captureTask?.value
    }
}
