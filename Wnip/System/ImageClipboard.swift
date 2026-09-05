import AppKit
import SwiftUI

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

@MainActor
enum ScreenshotAnnotations {
    /// Overlay annotations use display-local points with a top-left origin.
    static func render(_ image: PixelImage, annotations: [Annotation],
                       selection: CGRect, display: DisplayDescriptor) throws -> PixelImage {
        guard !annotations.isEmpty else { return image }
        let local = OverlayInteractionGeometry.localRect(forGlobalRect: selection, in: display.frame)
        guard !local.isEmpty else { throw CaptureFailure.invalidSelection }
        let translated = annotations.map { $0.translated(by: CGSize(width: -local.minX, height: -local.minY)) }
        let model = AnnotationCanvasModel(document: AnnotationDocument(
            annotations: translated, sourceBounds: CGRect(origin: .zero, size: local.size)))
        let content = AnnotationCanvas(model: model,
            sourceImage: NSImage(cgImage: image.image, size: local.size), showsEditingControls: false)
            .frame(width: local.width, height: local.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = CGFloat(image.image.width) / local.width
        guard let rendered = renderer.cgImage else {
            throw CaptureFailure.captureFailed("The annotations could not be rendered.")
        }
        return PixelImage(image: rendered, scale: image.scale, colorSpace: image.colorSpace)
    }
}
