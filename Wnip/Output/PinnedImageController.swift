import AppKit

@MainActor
protocol PinnedImagePresenting: AnyObject {
    func present(_ image: PixelImage, near selection: CGRect)
}

@MainActor
final class PinnedImageController: NSObject, PinnedImagePresenting, NSWindowDelegate {
    private(set) var panels: [PinnedImagePanel] = []

    func present(_ image: PixelImage, near selection: CGRect) {
        let screen = NSScreen.screens.max {
            $0.frame.intersection(selection).area < $1.frame.intersection(selection).area
        } ?? NSScreen.main
        let frame = Self.frame(for: image, near: selection, visibleFrame: screen?.visibleFrame)
        let panel = PinnedImagePanel(image: image, frame: frame)
        panel.delegate = self
        panels.append(panel)
        panel.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? PinnedImagePanel else { return }
        panels.removeAll { $0 === panel }
    }

    static func frame(for image: PixelImage, near selection: CGRect, visibleFrame: CGRect?) -> CGRect {
        let scale = max(image.scale, 1)
        var size = CGSize(width: CGFloat(image.image.width) / scale,
                          height: CGFloat(image.image.height) / scale)
        if let visibleFrame {
            let ratio = min(1, visibleFrame.width / size.width, visibleFrame.height / size.height)
            size.width *= ratio
            size.height *= ratio
        }
        size.width = max(36, size.width)
        size.height = max(36, size.height)
        var frame = CGRect(x: selection.midX - size.width / 2,
                           y: selection.midY - size.height / 2, width: size.width, height: size.height)
        if let visibleFrame {
            frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - size.width)
            frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - size.height)
        }
        return frame
    }

    deinit {
        MainActor.assumeIsolated {
            for panel in panels {
                panel.delegate = nil
                panel.close()
            }
        }
    }
}

@MainActor
final class PinnedImagePanel: NSPanel {
    init(image: PixelImage, frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "Pinned Screenshot"
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        let imageView = PinnedImageView(frame: CGRect(origin: .zero, size: frame.size))
        imageView.image = NSImage(cgImage: image.image, size: CGSize(
            width: CGFloat(image.image.width) / max(image.scale, 1),
            height: CGFloat(image.image.height) / max(image.scale, 1)))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel("Pinned Screenshot. Drag to move.")
        contentView = imageView

        let close = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Close Pinned Screenshot")!, target: self, action: #selector(closePin))
        close.isBordered = false
        close.bezelStyle = .circular
        close.contentTintColor = .white
        close.wantsLayer = true
        close.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        close.layer?.cornerRadius = 12
        close.frame = CGRect(x: 6, y: frame.height - 30, width: 24, height: 24)
        close.autoresizingMask = [.maxXMargin, .minYMargin]
        close.toolTip = "Close Pinned Screenshot"
        imageView.addSubview(close)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @objc private func closePin() { close() }

    override func cancelOperation(_ sender: Any?) { close() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() }
        else { super.keyDown(with: event) }
    }
}

private final class PinnedImageView: NSImageView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        window?.performDrag(with: event)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
