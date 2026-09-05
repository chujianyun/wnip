import AppKit
import CoreGraphics
import Foundation

protocol ImageRendering {
    /// Composites the captured source, the selected crop and the vector
    /// annotations into the final export bitmap.
    ///
    /// `crop` and all annotation coordinates are expressed in source point
    /// space (origin at the top-left of the capture, y growing downwards), so a
    /// Retina source is cropped in points and rendered back out in pixels.
    func render(
        source: PixelImage,
        crop: CGRect,
        annotations: [Annotation],
        shadow: Bool
    ) throws -> CGImage
}

enum ImageRenderFailure: LocalizedError, Equatable {
    case invalidCrop
    case contextUnavailable
    case imageCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidCrop:
            return "The selected area is outside the captured image."
        case .contextUnavailable:
            return "A drawing surface could not be created."
        case .imageCreationFailed:
            return "The screenshot could not be composited."
        }
    }
}

/// Region captures stay flat, window captures get the soft macOS shadow, and
/// full-screen captures never add one.
enum CaptureShadowPolicy {
    static func shouldApply(
        mode: CaptureMode,
        regionEnabled: Bool,
        windowEnabled: Bool
    ) -> Bool {
        switch mode {
        case .region:
            return regionEnabled
        case .window:
            return windowEnabled
        case .fullScreen:
            return false
        }
    }
}

struct ScreenshotImageRenderer: ImageRendering {
    func render(
        source: PixelImage,
        crop: CGRect,
        annotations: [Annotation],
        shadow: Bool
    ) throws -> CGImage {
        let scale = max(source.scale, 1)
        let sourceBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(source.image.width) / scale,
            height: CGFloat(source.image.height) / scale
        )
        let resolvedCrop = crop.standardized.intersection(sourceBounds)
        guard !resolvedCrop.isNull, !resolvedCrop.isEmpty else {
            throw ImageRenderFailure.invalidCrop
        }

        let pixelSize = CGSize(
            width: max(1, (resolvedCrop.width * scale).rounded()),
            height: max(1, (resolvedCrop.height * scale).rounded())
        )
        let colorSpace = Self.renderColorSpace(source.colorSpace)
        let cropped = try croppedImage(
            from: source,
            crop: resolvedCrop,
            pixelSize: pixelSize,
            scale: scale,
            colorSpace: colorSpace
        )

        let context = try Self.makeContext(
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            colorSpace: colorSpace
        )
        context.interpolationQuality = .none
        drawImagePreservingTopLeftRows(
            cropped,
            in: context,
            destinationSize: pixelSize
        )

        let transform = OutputTransform(crop: resolvedCrop, scale: scale)
        let pixelatedSource = annotations.contains(where: { $0.tool == .mosaic })
            ? MosaicEffect.pixelatedImage(source.image, scale: scale, colorSpace: colorSpace)
            : nil
        let pixelatedSourceFrame = CGRect(
            x: -(resolvedCrop.minX * scale).rounded(),
            y: -(resolvedCrop.minY * scale).rounded(),
            width: CGFloat(source.image.width),
            height: CGFloat(source.image.height)
        )
        for annotation in annotations where annotation.tool == .mosaic {
            applyMosaic(
                annotation,
                in: context,
                pixelatedSource: pixelatedSource,
                pixelatedSourceFrame: pixelatedSourceFrame,
                pixelSize: pixelSize,
                transform: transform
            )
        }
        for annotation in annotations where annotation.tool != .mosaic {
            draw(annotation, in: context, transform: transform, colorSpace: colorSpace)
        }

        guard let composited = context.makeImage() else {
            throw ImageRenderFailure.imageCreationFailed
        }
        guard shadow else { return composited }
        return try addShadow(to: composited, colorSpace: colorSpace, scale: scale)
    }

    private func croppedImage(
        from source: PixelImage,
        crop: CGRect,
        pixelSize: CGSize,
        scale: CGFloat,
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        let pixelRect = CGRect(
            x: (crop.minX * scale).rounded(),
            y: (crop.minY * scale).rounded(),
            width: pixelSize.width,
            height: pixelSize.height
        ).intersection(
            CGRect(x: 0, y: 0, width: source.image.width, height: source.image.height)
        )
        guard !pixelRect.isNull,
              !pixelRect.isEmpty,
              let image = source.image.cropping(to: pixelRect) else {
            throw ImageRenderFailure.imageCreationFailed
        }
        return image
    }

    private func applyMosaic(
        _ annotation: Annotation,
        in context: CGContext,
        pixelatedSource: CGImage?,
        pixelatedSourceFrame: CGRect,
        pixelSize: CGSize,
        transform: OutputTransform
    ) {
        guard case .mosaic(let points) = annotation.content,
              points.count > 1,
              let pixelatedSource else { return }

        let path = CGMutablePath()
        path.addLines(
            between: points.map { transform.point($0) },
            transform: .identity
        )
        let brushWidth = max(1, annotation.parameters.lineWidth * transform.scale)

        context.saveGState()
        context.addPath(path)
        context.setLineWidth(brushWidth)
        context.setLineCap(.square)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()

        context.interpolationQuality = .none
        drawImagePreservingTopLeftRows(
            pixelatedSource,
            in: context,
            destinationRect: pixelatedSourceFrame,
            canvasHeight: pixelSize.height
        )
        context.interpolationQuality = .default
        context.restoreGState()
    }

    /// A bitmap context configured for top-left vector coordinates would
    /// otherwise vertically invert CGImage rows when drawing the source.
    private func drawImagePreservingTopLeftRows(
        _ image: CGImage,
        in context: CGContext,
        destinationSize: CGSize
    ) {
        drawImagePreservingTopLeftRows(
            image,
            in: context,
            destinationRect: CGRect(origin: .zero, size: destinationSize),
            canvasHeight: destinationSize.height
        )
    }

    private func drawImagePreservingTopLeftRows(
        _ image: CGImage,
        in context: CGContext,
        destinationRect: CGRect,
        canvasHeight: CGFloat
    ) {
        context.saveGState()
        context.translateBy(x: 0, y: canvasHeight)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: destinationRect)
        context.restoreGState()
    }

    private func draw(
        _ annotation: Annotation,
        in context: CGContext,
        transform: OutputTransform,
        colorSpace: CGColorSpace
    ) {
        let color = Self.color(annotation.parameters.color, in: colorSpace)
        let lineWidth = max(0.5, annotation.parameters.lineWidth * transform.scale)
        context.saveGState()
        context.setStrokeColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.content {
        case .rectangle(let rect):
            context.stroke(transform.rect(rect).standardized)
        case .ellipse(let rect):
            context.strokeEllipse(in: transform.rect(rect).standardized)
        case .line(let start, let end):
            strokeSegment(from: start, to: end, in: context, transform: transform)
        case .arrow:
            guard let geometry = annotation.arrowGeometry else { break }
            strokeSegment(
                from: geometry.start,
                to: geometry.tip,
                in: context,
                transform: transform
            )
            for head in [geometry.headA, geometry.headB] where head != geometry.tip {
                strokeSegment(
                    from: geometry.tip,
                    to: head,
                    in: context,
                    transform: transform
                )
            }
        case .pen(let points), .highlight(let points):
            stroke(points, in: context, transform: transform)
        case .mosaic:
            break
        case .text(let origin, let value):
            drawText(
                value,
                at: transform.point(origin),
                font: .systemFont(ofSize: annotation.parameters.fontSize * transform.scale),
                color: annotation.parameters.color,
                centeredIn: nil,
                in: context
            )
        case .step(let center, let number):
            drawStep(
                number,
                at: transform.point(center),
                fontSize: annotation.parameters.fontSize * transform.scale,
                fillColor: color,
                in: context
            )
        }
        context.restoreGState()
    }

    private func stroke(
        _ points: [CGPoint],
        in context: CGContext,
        transform: OutputTransform
    ) {
        guard points.count > 1 else { return }
        let path = CGMutablePath()
        path.addLines(between: points.map { transform.point($0) }, transform: .identity)
        context.addPath(path)
        context.strokePath()
    }

    private func strokeSegment(
        from start: CGPoint,
        to end: CGPoint,
        in context: CGContext,
        transform: OutputTransform
    ) {
        context.move(to: transform.point(start))
        context.addLine(to: transform.point(end))
        context.strokePath()
    }

    private func drawStep(
        _ number: Int,
        at center: CGPoint,
        fontSize: CGFloat,
        fillColor: CGColor,
        in context: CGContext
    ) {
        let radius = max(fontSize * 0.75, 12)
        let badge = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.setFillColor(fillColor)
        context.fillEllipse(in: badge)
        drawText(
            String(number),
            at: .zero,
            font: .boldSystemFont(ofSize: fontSize),
            color: AnnotationColor(red: 1, green: 1, blue: 1, alpha: 1),
            centeredIn: badge,
            in: context
        )
    }

    /// Text is drawn through AppKit so the exported glyphs match the on-canvas
    /// layout produced by `AnnotationTextGeometry`.
    private func drawText(
        _ value: String,
        at origin: CGPoint,
        font: NSFont,
        color: AnnotationColor,
        centeredIn centeringRect: CGRect?,
        in context: CGContext
    ) {
        guard !value.isEmpty else { return }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Self.nsColor(color)
        ]
        var drawOrigin = origin
        if let centeringRect {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            attributes[.paragraphStyle] = paragraph
            let size = NSAttributedString(string: value, attributes: attributes).size()
            drawOrigin = CGPoint(
                x: centeringRect.midX - (size.width / 2),
                y: centeringRect.midY - (size.height / 2)
            )
        }

        let text = NSAttributedString(string: value, attributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        text.draw(at: drawOrigin)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func addShadow(
        to image: CGImage,
        colorSpace: CGColorSpace,
        scale: CGFloat
    ) throws -> CGImage {
        let blur = 10 * scale
        let offsetY = 4 * scale
        // The padding keeps the shadow tail inside the canvas so the exported
        // corners stay fully transparent.
        let padding = ((blur * 3) + abs(offsetY)).rounded(.up)
        let width = Int(padding * 2) + image.width
        let height = Int(padding * 2) + image.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageRenderFailure.contextUnavailable }

        context.setShadow(
            offset: CGSize(width: 0, height: -offsetY),
            blur: blur,
            color: CGColor(gray: 0, alpha: 0.42)
        )
        context.draw(
            image,
            in: CGRect(
                x: padding,
                y: padding,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        context.setShadow(offset: .zero, blur: 0, color: nil)

        guard let shadowed = context.makeImage() else {
            throw ImageRenderFailure.imageCreationFailed
        }
        return shadowed
    }

    private static func makeContext(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace
    ) throws -> CGContext {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ImageRenderFailure.contextUnavailable }

        // Work in the same top-left origin, y-down space the annotations use.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(true)
        context.interpolationQuality = .default
        return context
    }

    private static func renderColorSpace(_ colorSpace: CGColorSpace) -> CGColorSpace {
        colorSpace.numberOfComponents == 3
            ? colorSpace
            : CGColorSpace(name: CGColorSpace.sRGB) ?? colorSpace
    }

    private static func color(_ color: AnnotationColor, in colorSpace: CGColorSpace) -> CGColor {
        CGColor(
            colorSpace: colorSpace,
            components: [
                CGFloat(color.red),
                CGFloat(color.green),
                CGFloat(color.blue),
                CGFloat(color.alpha)
            ]
        ) ?? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    }

    private static func nsColor(_ color: AnnotationColor) -> NSColor {
        NSColor(
            srgbRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
    }
}

/// Maps source point-space geometry into output pixel space.
private struct OutputTransform {
    let crop: CGRect
    let scale: CGFloat

    func point(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: (point.x - crop.minX) * scale,
            y: (point.y - crop.minY) * scale
        )
    }

    func rect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - crop.minX) * scale,
            y: (rect.minY - crop.minY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}
