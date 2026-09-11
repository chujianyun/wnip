import AppKit
import CoreGraphics

struct BackgroundRenderer {
    func render(source: CGImage, style: BackgroundStyle, background: CGImage? = nil, maxDimension: CGFloat? = nil) throws -> CGImage {
        let layout = try BackgroundLayout(source: CGSize(width: source.width, height: source.height), style: style)
        let factor = maxDimension.map { min(1, max(1, $0) / max(layout.size.width, layout.size.height)) } ?? 1
        let width = max(1, Int((layout.size.width * factor).rounded()))
        let height = max(1, Int((layout.size.height * factor).rounded()))
        let context = try Self.context(width, height)
        context.scaleBy(x: CGFloat(width) / layout.size.width, y: CGFloat(height) / layout.size.height)
        context.interpolationQuality = .high
        let canvas = CGRect(origin: .zero, size: layout.size)
        switch style.kind {
        case .solid:
            context.setFillColor(HexRGB(style.solid)!.cgColor); context.fill(canvas)
        case .gradient:
            try Self.drawGradient(style, context: context, canvas: canvas)
        case .image:
            guard let background else { throw BackgroundFailure.missingImage }
            let scale = max(canvas.width / CGFloat(background.width), canvas.height / CGFloat(background.height)) * style.imageZoom
            let size = CGSize(width: CGFloat(background.width) * scale, height: CGFloat(background.height) * scale)
            let frame = CGRect(x: (canvas.width - size.width) * style.imageX,
                               y: (canvas.height - size.height) * (1 - style.imageY), width: size.width, height: size.height)
            context.draw(background, in: frame)
        }
        let short = CGFloat(min(source.width, source.height))
        let frame = layout.screenshot
        let outer = frame.insetBy(dx: -layout.border, dy: -layout.border)
        let radius = min(short * style.radius, short / 2)
        let path = CGPath(roundedRect: outer, cornerWidth: radius + layout.border, cornerHeight: radius + layout.border, transform: nil)
        context.saveGState()
        if style.shadow > 0 {
            context.setShadow(offset: CGSize(width: 0, height: -short * 0.018), blur: short * 0.035,
                              color: CGColor(gray: 0, alpha: style.shadow))
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(path); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(source, in: frame)
        context.restoreGState()
        guard let image = context.makeImage() else { throw BackgroundFailure.renderFailed }
        return image
    }

    static func context(_ width: Int, _ height: Int) throws -> CGContext {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw BackgroundFailure.renderFailed }
        return context
    }

    private static func drawGradient(_ style: BackgroundStyle, context: CGContext, canvas: CGRect) throws {
        let colors = style.colors.map { HexRGB($0)! }
        if style.multiPoint {
            // A compact bilinear color field gives identical corner colors at any output size.
            let side = 192
            let field = try Self.context(side, side)
            guard let data = field.data?.assumingMemoryBound(to: UInt8.self) else { throw BackgroundFailure.renderFailed }
            for y in 0..<side {
                for x in 0..<side {
                    let u = CGFloat(x) / CGFloat(side - 1), v = CGFloat(y) / CGFloat(side - 1)
                    let weights = [(1-u)*(1-v), u*(1-v), (1-u)*v, u*v]
                    let offset = y * field.bytesPerRow + x * 4
                    data[offset] = UInt8(clamping: Int(zip(colors, weights).reduce(0) { $0 + $1.0.r * $1.1 } * 255))
                    data[offset+1] = UInt8(clamping: Int(zip(colors, weights).reduce(0) { $0 + $1.0.g * $1.1 } * 255))
                    data[offset+2] = UInt8(clamping: Int(zip(colors, weights).reduce(0) { $0 + $1.0.b * $1.1 } * 255))
                    data[offset+3] = 255
                }
            }
            guard let image = field.makeImage() else { throw BackgroundFailure.renderFailed }
            context.draw(image, in: canvas)
        } else {
            let palette = [colors[0].cgColor, colors[1].cgColor, colors[2].cgColor, colors[3].cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: palette, locations: [0, 0.33, 0.67, 1]) else { throw BackgroundFailure.renderFailed }
            let angle = style.angle * .pi / 180
            let dx = cos(angle), dy = sin(angle)
            let extent = abs(dx) * canvas.width / 2 + abs(dy) * canvas.height / 2
            context.drawLinearGradient(gradient,
                start: CGPoint(x: canvas.midX - dx * extent, y: canvas.midY - dy * extent),
                end: CGPoint(x: canvas.midX + dx * extent, y: canvas.midY + dy * extent),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }
}

/// Original vector artwork shipped in code; no external downloads or licensing dependency.
enum BackgroundArtwork {
    static let choices = [(id: "builtin:dunes", title: "暖沙丘"), (id: "builtin:orbit", title: "蓝色轨道")]
    static func image(id: String) throws -> CGImage {
        guard choices.contains(where: { $0.id == id }) else { throw BackgroundFailure.missingImage }
        let context = try BackgroundRenderer.context(1600, 1200)
        let dunes = id == "builtin:dunes"
        context.setFillColor(HexRGB(dunes ? "F7EADB" : "152B52")!.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        if dunes {
            for (index, hex) in ["EBCBAD", "D8AB89", "BF8C70", "9E715F"].enumerated() {
                let y = CGFloat(index) * -180 + 700
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 0, y: y))
                path.addCurve(to: CGPoint(x: 1600, y: y+100), control1: CGPoint(x: 450, y: y+500), control2: CGPoint(x: 950, y: y-400))
                path.addLine(to: CGPoint(x: 1600, y: 0)); path.closeSubpath()
                context.setFillColor(HexRGB(hex)!.cgColor); context.addPath(path); context.fillPath()
            }
        } else {
            for index in (0..<12).reversed() {
                let size = CGFloat(index+1) * 155
                context.setStrokeColor(CGColor(srgbRed: 0.3, green: 0.7, blue: 0.95, alpha: CGFloat(13-index)/30))
                context.setLineWidth(28)
                context.strokeEllipse(in: CGRect(x: 1300-size/2, y: 950-size/2, width: size, height: size))
            }
        }
        guard let image = context.makeImage() else { throw BackgroundFailure.renderFailed }
        return image
    }
}
