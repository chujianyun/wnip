import AppKit

enum AppBranding {
    static var menuBarImage: NSImage? {
        guard let image = NSImage(named: "MenuBarIcon")?.copy() as? NSImage else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
