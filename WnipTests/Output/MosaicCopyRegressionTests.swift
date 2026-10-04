import AppKit
import SwiftUI
import XCTest
@testable import Wnip

@MainActor
final class MosaicCopyRegressionTests: XCTestCase {
    func testCroppedMosaicSamplesTheSameRowsAsTheEditorAfterPasting() throws {
        for scale in [1, 2] {
            let source = try makeImage(width: 64 * scale, height: 96 * scale, scale: CGFloat(scale)) { x, y in
                let stripe: UInt8 = (x / scale).isMultiple(of: 2) ? 32 : 224
                return y < 48 * scale ? (stripe, 0, 0, 255) : (0, 0, stripe, 255)
            }
            // Off-centre vertical crops expose the top-left / bottom-left mix-up.
            for top in [8, 64] {
                let crop = CGRect(x: 8, y: top, width: 48, height: 24)
                let annotation = Annotation(
                    content: .mosaic([CGPoint(x: 16, y: top + 12), CGPoint(x: 48, y: top + 12)]),
                    parameters: AnnotationToolParameters(color: .clear, lineWidth: 12, fontSize: 12)
                )
                let document = AnnotationDocument(annotations: [annotation], sourceBounds: CGRect(x: 0, y: 0, width: 64, height: 96))
                let model = AnnotationCanvasModel(document: document, selectedTool: .mosaic)
                let preview = SwiftUI.ImageRenderer(content:
                    AnnotationCanvas(model: model, sourceImage: NSImage(cgImage: source.image, size: NSSize(width: 64, height: 96)))
                        .showsParameterControls(false)
                        .frame(width: 64, height: 96)
                )
                preview.scale = CGFloat(scale)
                let previewBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(preview.cgImage))
                let rendered = try ScreenshotImageRenderer().render(source: source, crop: crop, annotations: [annotation], shadow: false)
                let pasteboard = NSPasteboard.withUniqueName()
                defer { pasteboard.releaseGlobally() }
                try ImageClipboard(pasteboard: pasteboard).write(PixelImage(image: rendered, scale: CGFloat(scale)))

                for type in [NSPasteboard.PasteboardType.png, .tiff] {
                    let pasted = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(pasteboard.data(forType: type))))
                    XCTAssertEqual(pasted.pixelsWide, 48 * scale)
                    XCTAssertEqual(pasted.pixelsHigh, 24 * scale)
                    let expected = try XCTUnwrap(previewBitmap.colorAt(x: 32 * scale, y: (top + 12) * scale)?.usingColorSpace(.sRGB))
                    let actual = try XCTUnwrap(pasted.colorAt(x: 24 * scale, y: 12 * scale)?.usingColorSpace(.sRGB))
                    XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.03, "\(type) scale=\(scale) cropY=\(top)")
                    XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.03, "\(type) scale=\(scale) cropY=\(top)")
                    if top < 48 {
                        XCTAssertGreaterThan(actual.redComponent, 0.1)
                        XCTAssertLessThan(actual.blueComponent, 0.03)
                    } else {
                        XCTAssertGreaterThan(actual.blueComponent, 0.1)
                        XCTAssertLessThan(actual.redComponent, 0.03)
                    }
                    // Pixels outside the stroke must still come from the unchanged crop.
                    let outside = try XCTUnwrap(pasted.colorAt(x: 2 * scale, y: 2 * scale)?.usingColorSpace(.sRGB))
                    let original = try XCTUnwrap(NSBitmapImageRep(cgImage: source.image)
                        .colorAt(x: 10 * scale, y: (top + 2) * scale)?.usingColorSpace(.sRGB))
                    XCTAssertEqual(outside.redComponent, original.redComponent, accuracy: 0.01)
                    XCTAssertEqual(outside.greenComponent, original.greenComponent, accuracy: 0.01)
                    XCTAssertEqual(outside.blueComponent, original.blueComponent, accuracy: 0.01)
                }
            }
        }
    }

    func testVerticalCropKeepsMosaicGridAnchoredToFullSource() throws {
        for scale in [1, 2] {
            let source = try makeImage(width: 40 * scale, height: 80 * scale, scale: CGFloat(scale)) { _, y in
                let value = UInt8(y * 3 / scale)
                return (value, value, value, 255)
            }
            let annotation = Annotation(content: .mosaic([CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 80)]), parameters: AnnotationToolParameters(color: .clear, lineWidth: 16, fontSize: 12))
            let renderer = ScreenshotImageRenderer()
            let full = NSBitmapImageRep(cgImage: try renderer.render(source: source, crop: CGRect(x: 0, y: 0, width: 40, height: 80), annotations: [annotation], shadow: false))
            for top: CGFloat in [0, 3.5, 51] {
                let cropped = NSBitmapImageRep(cgImage: try renderer.render(source: source, crop: CGRect(x: 4, y: top, width: 32, height: 24), annotations: [annotation], shadow: false))
                for y in [2, 10, 20] {
                    let original = try XCTUnwrap(full.colorAt(x: 20 * scale, y: Int((top * CGFloat(scale)).rounded()) + y * scale))
                    let actual = try XCTUnwrap(cropped.colorAt(x: 16 * scale, y: y * scale))
                    XCTAssertEqual(actual.redComponent, original.redComponent, accuracy: 0.01, "scale=\(scale) cropY=\(top), row=\(y)")
                }
            }
        }
    }
}
