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
        case .saveDirectoryNotRemembered:
            title = "Screenshot Saved"
            recoveryURL = nil
        case .saveDirectoryUpdateFailed:
            title = "Save Folder Could Not Be Updated"
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
                LabeledContent("Pin Screenshot", value: "⌘⇧P")
            }
            Section("Output") {
                Picker("Format", selection: preferenceBinding(\.format)) {
                    Text("PNG").tag(ScreenshotFormat.png)
                    Text("JPEG").tag(ScreenshotFormat.jpeg)
                }
                TextField("Filename rule", text: preferenceBinding(\.filenameRule))
                if coordinator.appPreferences.format == .jpeg {
                    Slider(value: preferenceBinding(\.jpegQuality), in: 0.1...1) { Text("JPEG quality") }
                }
                Toggle("Region shadow", isOn: preferenceBinding(\.regionShadow))
                Toggle("Window shadow", isOn: preferenceBinding(\.windowShadow))
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Save folder")
                        Spacer()
                        Button("Choose…", action: chooseSaveDirectory)
                    }
                    Text(coordinator.appPreferences.saveDirectoryURL?.path ?? "Choose when saving for the first time")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(coordinator.appPreferences.saveDirectoryURL?.path ?? "")
                    if coordinator.appPreferences.saveDirectoryURL != nil {
                        Text("Missing folders will be created automatically when saving.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Choose a different save folder next time") {
                            coordinator.clearSaveDirectory()
                        }
                        .font(.caption)
                    }
                }
            }
            Section("Completion feedback") {
                Toggle("Show notification", isOn: preferenceBinding(\.completionNotificationEnabled))
                Toggle("Play sound", isOn: preferenceBinding(\.completionSoundEnabled))
                Toggle("Haptic feedback", isOn: preferenceBinding(\.hapticFeedbackEnabled))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 540)
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

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Save Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = coordinator.appPreferences.saveDirectoryURL
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        coordinator.setSaveDirectory(directory)
    }

    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(get: { coordinator.appPreferences[keyPath: keyPath] },
                set: { coordinator.updatePreference(keyPath, to: $0) })
    }

    private func recordingChanged(_ isRecording: Bool) {
        if isRecording {
            coordinator.beginShortcutRecording()
        } else {
            coordinator.endShortcutRecording()
        }
    }
}
