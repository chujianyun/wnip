import AppKit
import SwiftUI

struct SettingsAlertPresentation: Equatable {
    let title: String
    let message: String
    let recoveryURL: URL?

    init(error: CaptureCoordinatorError) {
        message = error.localizedDescription
        switch error {
        case .permissionDenied(let url):
            title = "Screen Recording Permission Required"
            recoveryURL = url
        case .captureFailed:
            title = "Capture Failed"
            recoveryURL = nil
        case .shortcutFailed:
            title = "Shortcut Could Not Be Updated"
            recoveryURL = nil
        }
    }

    var primaryButtonTitle: String {
        recoveryURL == nil ? "OK" : "Open System Settings"
    }

    var cancelButtonTitle: String? {
        recoveryURL == nil ? nil : "Cancel"
    }

    func openRecovery(using opener: (URL) -> Void) {
        guard let recoveryURL else { return }
        opener(recoveryURL)
    }
}

struct SettingsView: View {
    @ObservedObject var coordinator: CaptureCoordinator

    var body: some View {
        let alert = coordinator.presentedError.map(SettingsAlertPresentation.init)

        Form {
            Section("Shortcuts") {
                LabeledContent("Region Capture") {
                    ShortcutRecorder(
                        shortcut: coordinator.regionShortcut,
                        onChange: { coordinator.updateRegionShortcut($0) },
                        onRecordingChanged: recordingChanged
                    )
                    .frame(width: 120, height: 28)
                }
                LabeledContent("Window Capture") {
                    ShortcutRecorder(
                        shortcut: coordinator.windowShortcut,
                        onChange: { coordinator.updateWindowShortcut($0) },
                        onRecordingChanged: recordingChanged
                    )
                    .frame(width: 120, height: 28)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 190)
        .alert(
            alert?.title ?? "Wnip",
            isPresented: Binding(
                get: { coordinator.presentedError != nil },
                set: { if !$0 { coordinator.clearPresentedError() } }
            )
        ) {
            if let alert, let cancelButtonTitle = alert.cancelButtonTitle {
                Button(alert.primaryButtonTitle) {
                    coordinator.clearPresentedError()
                    alert.openRecovery { NSWorkspace.shared.open($0) }
                }
                Button(cancelButtonTitle, role: .cancel) {
                    coordinator.clearPresentedError()
                }
            } else if let alert {
                Button(alert.primaryButtonTitle) { coordinator.clearPresentedError() }
            }
        } message: {
            Text(alert?.message ?? "Unknown error")
        }
    }

    private func recordingChanged(_ isRecording: Bool) {
        if isRecording {
            coordinator.beginShortcutRecording()
        } else {
            coordinator.endShortcutRecording()
        }
    }
}
