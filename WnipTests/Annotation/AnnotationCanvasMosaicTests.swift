import AppKit
import SwiftUI
import XCTest
@testable import Wnip

@MainActor
final class AnnotationCanvasMosaicTests: XCTestCase {
    func testCanvasRendersMosaicAsPixelatedSourceInsteadOfDarkOverlay() throws {
        let source = try makeImage(width: 32, height: 16, scale: 1) { x, _ in
            x.isMultiple(of: 2) ? (0, 0, 0, 255) : (255, 255, 255, 255)
        }
        let sourceImage = NSImage(
            cgImage: source.image,
            size: NSSize(width: source.image.width, height: source.image.height)
        )
        let mosaic = Annotation(
            content: .mosaic([CGPoint(x: 4, y: 8), CGPoint(x: 20, y: 8)]),
            parameters: AnnotationToolParameters(color: .clear, lineWidth: 8, fontSize: 12)
        )
        let document = AnnotationDocument(
            annotations: [mosaic],
            sourceBounds: CGRect(x: 0, y: 0, width: 32, height: 16)
        )
        let model = AnnotationCanvasModel(document: document, selectedTool: .mosaic)
        let renderer = SwiftUI.ImageRenderer(
            content: AnnotationCanvas(model: model, sourceImage: sourceImage)
                .showsParameterControls(false)
                .frame(width: 32, height: 16)
        )
        renderer.proposedSize = ProposedViewSize(width: 32, height: 16)
        renderer.scale = 1

        let rendered = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(rgbaBitmap(from: rendered))
        let coveredDistance = bitmap.colorDistance(
            between: CGPoint(x: 8, y: 8),
            and: CGPoint(x: 9, y: 8)
        )
        let untouchedDistance = bitmap.colorDistance(
            between: CGPoint(x: 24, y: 1),
            and: CGPoint(x: 25, y: 1)
        )

        XCTAssertLessThan(
            coveredDistance,
            30,
            "Adjacent source stripes under the mosaic stroke should collapse into one pixel block"
        )
        XCTAssertGreaterThan(
            untouchedDistance,
            600,
            "Pixels outside the mosaic stroke should remain unchanged"
        )
    }

    private func rgbaBitmap(from image: NSImage) -> CanvasRGBABitmap? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return CanvasRGBABitmap(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
    }
}

private struct CanvasRGBABitmap {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]

    func colorDistance(between first: CGPoint, and second: CGPoint) -> Int {
        let a = rgba(at: first)
        let b = rgba(at: second)
        return abs(Int(a.0) - Int(b.0))
            + abs(Int(a.1) - Int(b.1))
            + abs(Int(a.2) - Int(b.2))
    }

    private func rgba(at point: CGPoint) -> (UInt8, UInt8, UInt8, UInt8) {
        let x = min(max(Int(point.x), 0), width - 1)
        let y = min(max(Int(point.y), 0), height - 1)
        let offset = (y * bytesPerRow) + (x * 4)
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
    }
}
