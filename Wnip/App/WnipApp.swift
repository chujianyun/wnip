import SwiftUI

@main
struct WnipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Wnip", systemImage: "camera.viewfinder") {
            Button("Capture Region") {
                appDelegate.coordinator.startCapture(mode: .region)
            }
            Button("Capture Window") {
                appDelegate.coordinator.startCapture(mode: .window)
            }
            Button("Capture Full Screen") {
                appDelegate.coordinator.startCapture(mode: .fullScreen)
            }
            Divider()
            SettingsLink()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Settings {
            SettingsView(coordinator: appDelegate.coordinator)
        }
    }
}
