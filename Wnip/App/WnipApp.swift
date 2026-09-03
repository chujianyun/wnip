import SwiftUI

@main
struct WnipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Wnip", systemImage: "camera.viewfinder") {
            Button("Capture Region") { }
            Button("Capture Window") { }
            Button("Capture Full Screen") { }
            Divider()
            SettingsLink()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        Settings {
            Text("Wnip Settings")
                .frame(width: 360, height: 220)
        }
    }
}
