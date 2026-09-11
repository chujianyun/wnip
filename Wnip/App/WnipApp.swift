import SwiftUI

@main
struct WnipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Capture Region") { appDelegate.coordinator.startCapture(mode: .region) }
            Button("Capture Window") { appDelegate.coordinator.startCapture(mode: .window) }
            Button("Capture Full Screen") { appDelegate.coordinator.startCapture(mode: .fullScreen) }
            Menu("截图加背景") {
                Button("区域截图加背景") { appDelegate.coordinator.startCapture(mode: .region, addingBackground: true) }
                Button("窗口截图加背景") { appDelegate.coordinator.startCapture(mode: .window, addingBackground: true) }
                Button("全屏截图加背景") { appDelegate.coordinator.startCapture(mode: .fullScreen, addingBackground: true) }
            }
            Button("Pin Screenshot (⌘⇧P)") { appDelegate.coordinator.pinScreenshot() }
            Divider()
            SettingsLink()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } label: {
            if let image = AppBranding.menuBarImage {
                Image(nsImage: image)
                    .accessibilityLabel("Wnip")
            } else {
                Image(systemName: "camera.viewfinder")
                    .accessibilityLabel("Wnip")
            }
        }
        Settings {
            SettingsView(coordinator: appDelegate.coordinator)
        }
    }
}
