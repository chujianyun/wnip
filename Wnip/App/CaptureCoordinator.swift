import Foundation
import SwiftUI

enum CaptureCoordinatorError: LocalizedError, Equatable {
    case permissionDenied(URL)
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required."
        case .captureFailed(let message):
            return message
        }
    }
}

@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published private(set) var shortcut: HotKeyShortcut = .defaultCapture
    @Published var presentedError: CaptureCoordinatorError?

    private let permission: any ScreenRecordingAuthorizing
    private let screen: any ScreenCapturing
    private let overlay: any OverlayControlling
    private let hotKey: any HotKeyRegistering
    private let preferences: any PreferencesStoring
    private var captureTask: Task<Void, Never>?
    private var requestID = 0

    init() {
        permission = PermissionService()
        screen = ScreenCaptureService()
        overlay = OverlayController()
        hotKey = HotKeyService()
        preferences = PreferencesStore()
    }

    init(
        permission: any ScreenRecordingAuthorizing,
        screen: any ScreenCapturing,
        overlay: any OverlayControlling,
        hotKey: any HotKeyRegistering,
        preferences: any PreferencesStoring
    ) {
        self.permission = permission
        self.screen = screen
        self.overlay = overlay
        self.hotKey = hotKey
        self.preferences = preferences
    }

    func start() {
        do {
            let preferences = try preferences.load()
            shortcut = preferences.shortcut
            try hotKey.register(preferences.shortcut) { [weak self] in
                self?.startCapture(mode: .region)
            }
        } catch {
            presentedError = .captureFailed(error.localizedDescription)
        }
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

    func cancelCapture() {
        requestID &+= 1
        captureTask?.cancel()
        captureTask = nil
        overlay.dismissAll()
    }

    func waitForPendingCaptureForTesting() async {
        await captureTask?.value
    }
}
