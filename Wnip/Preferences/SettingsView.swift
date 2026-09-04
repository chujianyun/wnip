import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: CaptureCoordinator

    var body: some View {
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
            "Shortcut Could Not Be Updated",
            isPresented: Binding(
                get: { coordinator.presentedError != nil },
                set: { if !$0 { coordinator.clearPresentedError() } }
            )
        ) {
            Button("OK") { coordinator.clearPresentedError() }
        } message: {
            Text(coordinator.presentedError?.localizedDescription ?? "Unknown error")
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
