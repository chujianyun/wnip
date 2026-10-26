import CoreGraphics

struct WindowCaptureSnapshot {
    let image: PixelImage
    let frame: CGRect
}

/// Keeps existing display-local annotation/crop coordinates while replacing the
/// desktop pixels with the isolated window. Areas outside it stay transparent.
enum WindowCaptureSource {
    /// A display-bound filter includes the selected window's popovers, even
    /// beyond its frame, against transparency. Trim that isolated image without
    /// guessing window ownership from titles or including other app windows.
    static func snapshot(_ image: PixelImage, windowFrame: CGRect,
                         display: DisplayDescriptor) throws -> WindowCaptureSnapshot {
        let width = image.image.width, height = image.image.height
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: image.colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              image.scale.isFinite, image.scale > 0 else { throw CaptureFailure.unavailable }
        context.draw(image.image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw CaptureFailure.unavailable
        }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where bytes[y * context.bytesPerRow + x * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { throw CaptureFailure.unavailable }
        let pixels = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            .union(display.pixelRect(forGlobalRect: windowFrame.intersection(display.frame)))
            .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cropped = image.image.cropping(to: pixels) else { throw CaptureFailure.unavailable }
        let frame = CGRect(x: display.frame.minX + pixels.minX / image.scale,
            y: display.frame.maxY - pixels.maxY / image.scale,
            width: pixels.width / image.scale, height: pixels.height / image.scale)
        return WindowCaptureSnapshot(image: PixelImage(image: cropped, scale: image.scale,
            colorSpace: image.colorSpace), frame: frame)
    }

    static func canvas(_ image: PixelImage, windowFrame: CGRect, display: DisplayDescriptor) throws -> PixelImage {
        let scale = image.scale
        guard scale.isFinite, scale > 0,
              display.frame.width.isFinite, display.frame.height.isFinite,
              display.frame.width > 0, display.frame.height > 0,
              let context = CGContext(data: nil,
                  width: Int((display.frame.width * scale).rounded(.up)),
                  height: Int((display.frame.height * scale).rounded(.up)),
                  bitsPerComponent: 8, bytesPerRow: 0, space: image.colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CaptureFailure.unavailable
        }
        context.scaleBy(x: scale, y: scale)
        context.draw(image.image, in: windowFrame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY))
        guard let canvas = context.makeImage() else { throw CaptureFailure.unavailable }
        return PixelImage(image: canvas, scale: scale, colorSpace: image.colorSpace)
    }
}
