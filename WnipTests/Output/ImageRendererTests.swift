import CoreGraphics
import XCTest
@testable import Wnip

final class ImageRendererTests: XCTestCase {
    func testRetinaCropProducesPixelSizedImage() throws {
        let source = try makeImage(width: 8, height: 6, scale: 2) { x, y in
            (UInt8(x * 20), UInt8(y * 30), 40, 255)
        }

        let rendered = try ScreenshotImageRenderer().render(
            source: source,
            crop: CGRect(x: 1, y: 0.5, width: 2, height: 1.5),
            annotations: [],
            shadow: false
        )

        XCTAssertEqual(rendered.width, 4)
        XCTAssertEqual(rendered.height, 3)
    }

    func testCropUsesTopLeftSourceCoordinates() throws {
        let source = try makeImage(width: 2, height: 4, scale: 1) { _, y in
            switch y {
            case 0: (255, 0, 0, 255)
            case 1: (0, 255, 0, 255)
            case 2: (0, 0, 255, 255)
            default: (255, 255, 255, 255)
            }
        }

        let rendered = try ScreenshotImageRenderer().render(
            source: source,
            crop: CGRect(x: 0, y: 0, width: 2, height: 2),
            annotations: [],
            shadow: false
        )

        let first = try rgba(rendered, x: 0, y: 0)
        let second = try rgba(rendered, x: 0, y: 1)
        XCTAssertEqual([first.0, first.1, first.2, first.3], [255, 0, 0, 255])
        XCTAssertEqual([second.0, second.1, second.2, second.3], [0, 255, 0, 255])
    }

    func testEveryVectorToolProducesVisiblePixels() throws {
        let parameters = AnnotationToolParameters(color: .red, lineWidth: 2, fontSize: 12)
        let annotations: [Annotation] = [
            Annotation(content: .rectangle(CGRect(x: 2, y: 2, width: 8, height: 7)), parameters: parameters),
            Annotation(content: .ellipse(CGRect(x: 12, y: 2, width: 8, height: 7)), parameters: parameters),
            Annotation(content: .line(from: CGPoint(x: 2, y: 12), to: CGPoint(x: 10, y: 18)), parameters: parameters),
            Annotation(content: .arrow(from: CGPoint(x: 12, y: 12), to: CGPoint(x: 22, y: 18)), parameters: parameters),
            Annotation(content: .pen([CGPoint(x: 2, y: 22), CGPoint(x: 9, y: 27)]), parameters: parameters),
            Annotation(content: .mosaic([CGPoint(x: 12, y: 22), CGPoint(x: 20, y: 27)]), parameters: AnnotationTool.mosaic.defaultParameters),
            Annotation(content: .text(origin: CGPoint(x: 2, y: 30), value: "W"), parameters: parameters),
            Annotation(content: .highlight([CGPoint(x: 12, y: 32), CGPoint(x: 22, y: 35)]), parameters: AnnotationTool.highlight.defaultParameters),
            Annotation(content: .step(center: CGPoint(x: 27, y: 8), number: 1), parameters: parameters)
        ]
        let transparent = try makeImage(width: 40, height: 40, scale: 1) { _, _ in (0, 0, 0, 0) }

        // Mosaic is excluded here because it pixelates the source it covers, so
        // over a fully transparent fixture it correctly stays transparent; its
        // visible effect is asserted against opaque pixels below.
        for annotation in annotations where annotation.tool != .mosaic {
            let rendered = try ScreenshotImageRenderer().render(
                source: transparent,
                crop: CGRect(x: 0, y: 0, width: 40, height: 40),
                annotations: [annotation],
                shadow: false
            )
            XCTAssertGreaterThan(try nonTransparentPixelCount(rendered), 0, "\(annotation.tool) rendered nothing")
        }
    }

    func testMosaicChangesOnlyCoveredOriginalPixels() throws {
        let source = try makeImage(width: 32, height: 8, scale: 1) { x, _ in
            x.isMultiple(of: 2) ? (0, 0, 0, 255) : (255, 255, 255, 255)
        }
        let mosaic = Annotation(
            content: .mosaic([CGPoint(x: 2, y: 4), CGPoint(x: 14, y: 4)]),
            parameters: AnnotationToolParameters(color: .clear, lineWidth: 6, fontSize: 12)
        )

        let rendered = try ScreenshotImageRenderer().render(
            source: source,
            crop: CGRect(x: 0, y: 0, width: 32, height: 8),
            annotations: [mosaic],
            shadow: false
        )

        let covered = try rgba(rendered, x: 6, y: 4)
        let coveredSource = try rgba(source.image, x: 6, y: 4)
        let untouched = try rgba(rendered, x: 28, y: 4)
        let untouchedSource = try rgba(source.image, x: 28, y: 4)
        XCTAssertNotEqual(
            [covered.0, covered.1, covered.2, covered.3],
            [coveredSource.0, coveredSource.1, coveredSource.2, coveredSource.3]
        )
        XCTAssertEqual(
            [untouched.0, untouched.1, untouched.2, untouched.3],
            [untouchedSource.0, untouchedSource.1, untouchedSource.2, untouchedSource.3]
        )
    }

    func testMosaicSamplesPixelsFromTheCoveredSourceRows() throws {
        let source = try makeImage(width: 16, height: 16, scale: 1) { _, y in
            y < 8 ? (255, 0, 0, 255) : (0, 0, 255, 255)
        }
        let mosaic = Annotation(
            content: .mosaic([CGPoint(x: 2, y: 3), CGPoint(x: 14, y: 3)]),
            parameters: AnnotationToolParameters(color: .clear, lineWidth: 4, fontSize: 12)
        )

        let rendered = try ScreenshotImageRenderer().render(
            source: source,
            crop: CGRect(x: 0, y: 0, width: 16, height: 16),
            annotations: [mosaic],
            shadow: false
        )

        let coveredTopPixel = try rgba(rendered, x: 8, y: 3)
        XCTAssertGreaterThan(
            Int(coveredTopPixel.0) - Int(coveredTopPixel.2),
            200,
            "A top-edge mosaic stroke must sample the top source rows, not vertically mirrored rows"
        )
    }

    func testMosaicBrushWidthDoesNotChangePixelBlockSize() throws {
        let source = try makeImage(width: 64, height: 40, scale: 1) { x, _ in
            let value = UInt8(x * 4)
            return (value, value, value, 255)
        }
        let narrow = Annotation(
            content: .mosaic([CGPoint(x: 2, y: 8), CGPoint(x: 62, y: 8)]),
            parameters: AnnotationToolParameters(color: .clear, lineWidth: 4, fontSize: 12)
        )
        let wide = Annotation(
            content: .mosaic([CGPoint(x: 2, y: 28), CGPoint(x: 62, y: 28)]),
            parameters: AnnotationToolParameters(color: .clear, lineWidth: 16, fontSize: 12)
        )

        let rendered = try ScreenshotImageRenderer().render(
            source: source,
            crop: CGRect(x: 0, y: 0, width: 64, height: 40),
            annotations: [narrow, wide],
            shadow: false
        )

        for x in [10, 22, 34, 46] {
            let narrowPixel = try rgba(rendered, x: x, y: 8)
            let widePixel = try rgba(rendered, x: x, y: 28)
            XCTAssertEqual(
                [narrowPixel.0, narrowPixel.1, narrowPixel.2],
                [widePixel.0, widePixel.1, widePixel.2],
                "Brush width should change coverage, not mosaic pixel granularity at x=\(x)"
            )
        }
    }

    func testMosaicPixelGridStaysAnchoredWhenExportIsCropped() throws {
        let source = try makeImage(width: 40, height: 16, scale: 1) { x, _ in
            let value = UInt8(x * 6)
            return (value, value, value, 255)
        }
        let mosaic = Annotation(
            content: .mosaic([CGPoint(x: 0, y: 8), CGPoint(x: 40, y: 8)]),
            parameters: AnnotationToolParameters(color: .clear, lineWidth: 12, fontSize: 12)
        )

        let full = try ScreenshotImageRenderer().render(
            source: source,
            crop: CGRect(x: 0, y: 0, width: 40, height: 16),
            annotations: [mosaic],
            shadow: false
        )
        let cropped = try ScreenshotImageRenderer().render(
            source: source,
            crop: CGRect(x: 3, y: 0, width: 24, height: 16),
            annotations: [mosaic],
            shadow: false
        )

        for sourceX in [6, 10, 18, 26] {
            let fullPixel = try rgba(full, x: sourceX, y: 8)
            let croppedPixel = try rgba(cropped, x: sourceX - 3, y: 8)
            XCTAssertEqual(
                [fullPixel.0, fullPixel.1, fullPixel.2],
                [croppedPixel.0, croppedPixel.1, croppedPixel.2],
                "Cropping should not shift the mosaic grid at source x=\(sourceX)"
            )
        }
    }

    func testTransparentSourceStaysTransparentOutsideAnnotation() throws {
        let source = try makeImage(width: 12, height: 12, scale: 1) { _, _ in (0, 0, 0, 0) }
        let rectangle = Annotation(content: .rectangle(CGRect(x: 4, y: 4, width: 4, height: 4)))

        let rendered = try ScreenshotImageRenderer().render(
            source: source,
            crop: CGRect(x: 0, y: 0, width: 12, height: 12),
            annotations: [rectangle],
            shadow: false
        )

        XCTAssertEqual(try rgba(rendered, x: 0, y: 0).3, 0)
        XCTAssertGreaterThan(try nonTransparentPixelCount(rendered), 0)
    }

    func testShadowPolicyHonorsModeRules() {
        XCTAssertFalse(CaptureShadowPolicy.shouldApply(mode: .region, regionEnabled: false, windowEnabled: true))
        XCTAssertTrue(CaptureShadowPolicy.shouldApply(mode: .region, regionEnabled: true, windowEnabled: false))
        XCTAssertTrue(CaptureShadowPolicy.shouldApply(mode: .window, regionEnabled: false, windowEnabled: true))
        XCTAssertFalse(CaptureShadowPolicy.shouldApply(mode: .window, regionEnabled: true, windowEnabled: false))
        XCTAssertFalse(CaptureShadowPolicy.shouldApply(mode: .fullScreen, regionEnabled: true, windowEnabled: true))
    }

    func testShadowAddsTransparentCanvasAroundContent() throws {
        let source = try makeImage(width: 4, height: 4, scale: 1) { _, _ in (255, 0, 0, 255) }
        let rendered = try ScreenshotImageRenderer().render(
            source: source,
            crop: CGRect(x: 0, y: 0, width: 4, height: 4),
            annotations: [],
            shadow: true
        )
        XCTAssertGreaterThan(rendered.width, 4)
        XCTAssertGreaterThan(rendered.height, 4)
        XCTAssertEqual(try rgba(rendered, x: 0, y: 0).3, 0)
    }
}

func makeImage(
    width: Int,
    height: Int,
    scale: CGFloat,
    pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)
) throws -> PixelImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let value = pixel(x, y)
            let offset = ((y * width) + x) * 4
            bytes[offset] = value.0
            bytes[offset + 1] = value.1
            bytes[offset + 2] = value.2
            bytes[offset + 3] = value.3
        }
    }
    let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let image = try XCTUnwrap(CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ))
    return PixelImage(image: image, scale: scale, colorSpace: colorSpace)
}

private func rgba(_ image: CGImage, x: Int, y: Int) throws -> (UInt8, UInt8, UInt8, UInt8) {
    let data = try XCTUnwrap(image.dataProvider?.data as Data?)
    let offset = (y * image.bytesPerRow) + (x * 4)
    return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
}

private func nonTransparentPixelCount(_ image: CGImage) throws -> Int {
    let data = try XCTUnwrap(image.dataProvider?.data as Data?)
    return (0..<image.height).reduce(0) { count, y in
        count + (0..<image.width).filter { x in data[(y * image.bytesPerRow) + (x * 4) + 3] > 0 }.count
    }
}
