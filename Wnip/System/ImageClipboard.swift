import AppKit

@MainActor
final class ImageClipboard {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ image: PixelImage) throws {
        let bitmap = NSBitmapImageRep(cgImage: image.image)
        guard let png = bitmap.representation(using: .png, properties: [:]),
              let tiff = bitmap.tiffRepresentation else {
            throw CaptureFailure.captureFailed("The screenshot could not be encoded.")
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw CaptureFailure.captureFailed("The screenshot could not be copied. Please try again.")
        }
    }
}

enum ScreenshotCrop {
    static func crop(_ image: PixelImage, selection: CGRect, display: DisplayDescriptor) throws -> PixelImage {
        let rect = selection.intersection(display.frame)
        guard !rect.isNull, !rect.isEmpty, display.frame.width > 0, display.frame.height > 0 else {
            throw CaptureFailure.invalidSelection
        }
        let scaleX = CGFloat(image.image.width) / display.frame.width
        let scaleY = CGFloat(image.image.height) / display.frame.height
        let pixels = CGRect(x: (rect.minX - display.frame.minX) * scaleX,
                            y: (display.frame.maxY - rect.maxY) * scaleY,
                            width: rect.width * scaleX, height: rect.height * scaleY).integral
        guard let cropped = image.image.cropping(to: pixels) else {
            throw CaptureFailure.invalidSelection
        }
        return PixelImage(image: cropped, scale: image.scale, colorSpace: image.colorSpace)
    }
}
