import AppKit
import SwiftUI
import XCTest
@testable import Wnip

@MainActor
final class AnnotationToolbarTests: XCTestCase {
    func testToolbarKeepsIconsVisibleWhenSystemAppearanceIsDark() throws {
        let renderer = ImageRenderer(
            content: AnnotationToolbar(onAction: { _ in })
                .environment(\.colorScheme, .dark)
        )
        renderer.proposedSize = ProposedViewSize(AnnotationToolbar.preferredSize)
        renderer.scale = 2

        let image = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(rgbaBitmap(from: image, scale: 2))
        let darkNeutralPixelCount = bitmap.darkNeutralPixelCount(
            in: CGRect(x: 8, y: 8, width: 418, height: 28),
            pointScale: 2
        )

        XCTAssertGreaterThan(
            darkNeutralPixelCount,
            100,
            "White toolbar should render dark, non-destructive button glyphs in dark appearance"
        )
    }

    private func rgbaBitmap(from image: NSImage, scale: CGFloat) -> RGBABitmap? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
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
        return RGBABitmap(width: width, height: height, bytesPerRow: bytesPerRow, pixels: pixels)
    }
}

private struct RGBABitmap {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let pixels: [UInt8]

    func darkNeutralPixelCount(in pointRect: CGRect, pointScale: CGFloat) -> Int {
        let pixelRect = CGRect(
            x: pointRect.minX * pointScale,
            y: pointRect.minY * pointScale,
            width: pointRect.width * pointScale,
            height: pointRect.height * pointScale
        ).integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))

        var count = 0
        for y in Int(pixelRect.minY)..<Int(pixelRect.maxY) {
            for x in Int(pixelRect.minX)..<Int(pixelRect.maxX) {
                let offset = (y * bytesPerRow) + (x * 4)
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let alpha = Int(pixels[offset + 3])
                let brightest = max(red, green, blue)
                let darkest = min(red, green, blue)

                if alpha > 200, brightest < 150, brightest - darkest < 24 {
                    count += 1
                }
            }
        }
        return count
    }
}
