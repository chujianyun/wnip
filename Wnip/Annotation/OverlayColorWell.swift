import AppKit
import SwiftUI

/// Color well used inside the capture overlay. AppKit resets the shared
/// NSColorPanel's level to `.floating` every time a well activates it, which
/// drops the panel behind the screenSaver-level overlay window. Re-assert the
/// level after each activation so the panel stays above the overlay.
final class OverlayColorWell: NSColorWell {
    static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

    override func activate(_ exclusive: Bool) {
        NSColorPanel.shared.showsAlpha = true
        super.activate(exclusive)
        NSColorPanel.shared.level = Self.panelLevel
    }
}

struct OverlayColorPicker: NSViewRepresentable {
    @Binding var color: Color
    var isEnabled = true

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> OverlayColorWell {
        let well = OverlayColorWell()
        well.color = NSColor(color)
        well.isContinuous = true
        well.setAccessibilityTitle("Color")
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ nsView: OverlayColorWell, context: Context) {
        let updated = NSColor(color)
        if nsView.color != updated {
            nsView.color = updated
        }
        nsView.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        let color: Binding<Color>

        init(color: Binding<Color>) {
            self.color = color
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            color.wrappedValue = Color(nsColor: sender.color)
        }
    }
}
