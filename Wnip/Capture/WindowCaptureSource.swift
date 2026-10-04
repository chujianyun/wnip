import CoreGraphics

/// Keeps existing display-local annotation/crop coordinates while replacing the
/// desktop pixels with the isolated window. Areas outside it stay transparent.
enum WindowCaptureSource {
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
