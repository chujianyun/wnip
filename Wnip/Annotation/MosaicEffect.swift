import CoreGraphics

enum MosaicEffect {
    /// Pixel cells remain visually stable while the brush width controls only
    /// how much of the source image is revealed through the mosaic stroke.
    static let blockSizeInPoints: CGFloat = 8

    static func pixelatedImage(
        _ image: CGImage,
        scale: CGFloat,
        colorSpace: CGColorSpace
    ) -> CGImage? {
        let blockSizeInPixels = max(2, blockSizeInPoints * max(scale, 1))
        let width = max(1, Int((CGFloat(image.width) / blockSizeInPixels).rounded(.up)))
        let height = max(1, Int((CGFloat(image.height) / blockSizeInPixels).rounded(.up)))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
