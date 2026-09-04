import Foundation
import SwiftUI

enum CaptureCoordinatorError: LocalizedError, Equatable {
    case permissionDenied(URL)
    case captureFailed(String)
    case shortcutFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required."
        case .captureFailed(let message):
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
    @Published var presentedError: CaptureCoordinatorError?

    private let permission: any ScreenRecordingAuthorizing
    private let screen: any ScreenCapturing
    private let overlay: any OverlayControlling
    private let regionHotKey: any HotKeyRegistering
    private let windowHotKey: any HotKeyRegistering
    private let preferences: any PreferencesStoring
    private var captureTask: Task<Void, Never>?
    private var requestID = 0
    private var isRecordingShortcut = false

    init() {
        permission = PermissionService()
        screen = ScreenCaptureService()
        overlay = OverlayController()
        regionHotKey = HotKeyService()
        windowHotKey = HotKeyService()
        preferences = PreferencesStore()
    }

    init(
        permission: any ScreenRecordingAuthorizing,
        screen: any ScreenCapturing,
        overlay: any OverlayControlling,
        regionHotKey: any HotKeyRegistering,
        windowHotKey: any HotKeyRegistering,
        preferences: any PreferencesStoring
    ) {
        self.permission = permission
        self.screen = screen
        self.overlay = overlay
        self.regionHotKey = regionHotKey
        self.windowHotKey = windowHotKey
        self.preferences = preferences
    }

    func start() {
        do {
            let preferences = try preferences.load()
            regionShortcut = preferences.regionShortcut
            windowShortcut = preferences.windowShortcut
        } catch {
            presentedError = .captureFailed(error.localizedDescription)
            return
        }
        registerCurrentShortcuts()
    }

    func startCapture(mode: CaptureMode) {
        requestID &+= 1
        let currentID = requestID
        captureTask?.cancel()
        overlay.dismissAll()

        captureTask = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, currentID == requestID else { return }
            guard permission.isAuthorized() || permission.requestAuthorization() else {
                guard !Task.isCancelled, currentID == requestID else { return }
                presentedError = .permissionDenied(permission.privacySettingsURL)
                return
            }

            do {
                let content = try await screen.availableContent()
                guard !Task.isCancelled, currentID == requestID else { return }
                overlay.present(
                    OverlayPresentation(
                        mode: mode,
                        displays: content.displays,
                        windows: content.windows
                    ),
                    callbacks: OverlayCallbacks(onCancel: { [weak self] in
                        self?.cancelCapture()
                    })
                )
            } catch {
                guard !Task.isCancelled, currentID == requestID else { return }
                presentedError = .captureFailed(error.localizedDescription)
            }
        }
    }

    func updateRegionShortcut(_ shortcut: HotKeyShortcut) {
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
        overlay.dismissAll()
    }

    func clearPresentedError() {
        presentedError = nil
    }

    func beginShortcutRecording() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        regionHotKey.unregister()
        windowHotKey.unregister()
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
        if let firstError {
            presentedError = .shortcutFailed(firstError.localizedDescription)
        }
    }

    func waitForPendingCaptureForTesting() async {
        await captureTask?.value
    }
}
