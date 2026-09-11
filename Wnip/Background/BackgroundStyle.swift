import Foundation
import CoreGraphics

struct BackgroundStyle: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable { case solid, gradient, image }
    enum Aspect: String, Codable, CaseIterable {
        case auto, square, fourThree, threeTwo, wide, portrait, custom
        var title: String {
            switch self {
            case .auto: "自适应"
            case .square: "1:1"
            case .fourThree: "4:3"
            case .threeTwo: "3:2"
            case .wide: "16:9"
            case .portrait: "9:16"
            case .custom: "自定义"
            }
        }
    }
    var kind: Kind = .gradient
    var solid = "F4F5F7"
    var colors = GradientPreset.all[0].colors
    var multiPoint = true
    var angle: Double = 45
    var imageID = "builtin:dunes"
    var imageZoom: Double = 1
    var imageX: Double = 0.5
    var imageY: Double = 0.5
    var aspect: Aspect = .auto
    var customWidth: Double = 4
    var customHeight: Double = 3
    /// Fractions of the screenshot's shorter dimension, independent of display scale.
    var padding: Double = 0.12
    var radius: Double = 0.025
    var shadow: Double = 0.35
    var border: Double = 0

    var aspectRatio: Double? {
        switch aspect {
        case .auto: nil
        case .square: 1
        case .fourThree: 4.0 / 3
        case .threeTwo: 1.5
        case .wide: 16.0 / 9
        case .portrait: 9.0 / 16
        case .custom: customWidth / customHeight
        }
    }

    func validated() throws -> Self {
        let values = [angle, imageZoom, imageX, imageY, customWidth, customHeight, padding, radius, shadow, border]
        guard values.allSatisfy(\.isFinite), (0...360).contains(angle),
              (1...4).contains(imageZoom), (0...1).contains(imageX), (0...1).contains(imageY),
              (1...100).contains(customWidth), (1...100).contains(customHeight),
              (0...0.6).contains(padding), (0...0.15).contains(radius),
              (0...1).contains(shadow), (0...0.05).contains(border),
              HexRGB(solid) != nil, colors.count == 4, colors.allSatisfy({ HexRGB($0) != nil }) else {
            throw BackgroundFailure.invalidStyle
        }
        if let ratio = aspectRatio, !(0.1...10).contains(ratio) { throw BackgroundFailure.invalidStyle }
        return self
    }
}

struct GradientPreset: Identifiable {
    let id: String
    let colors: [String] // top-left, top-right, bottom-left, bottom-right
    static let all: [Self] = [
        .init(id: "青绿极光", colors: ["006970", "DEFFC0", "70F4FF", "008B91"]),
        .init(id: "蓝紫星云", colors: ["252A7D", "AEB6FF", "7975ED", "5630A0"]),
        .init(id: "粉紫梦境", colors: ["8963BA", "FFE0EE", "EFB9E1", "B589DD"]),
        .init(id: "橙粉晨光", colors: ["F48163", "FFE4B8", "FFC7D3", "EE83A8"]),
        .init(id: "日落暖黄", colors: ["C96643", "FFEAA2", "FFBE5C", "ED8674"]),
        .init(id: "浅蓝薄荷", colors: ["8FC9E8", "E4FDE9", "CBF5F4", "79CBB9"])
    ]
}

struct HexRGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    init?(_ string: String) {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, value.allSatisfy(\.isHexDigit), let number = UInt32(value, radix: 16) else { return nil }
        r = CGFloat((number >> 16) & 255) / 255
        g = CGFloat((number >> 8) & 255) / 255
        b = CGFloat(number & 255) / 255
    }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

enum BackgroundFailure: LocalizedError {
    case invalidStyle, tooLarge, renderFailed, invalidImage, missingImage
    var errorDescription: String? {
        switch self {
        case .invalidStyle: "请检查颜色和比例：颜色需为 6 位 HEX，比例范围为 1:10 至 10:1。"
        case .tooLarge: "画布过大，请减少留白或调整比例（最多 6400 万像素，单边不超过 16384）。"
        case .renderFailed: "无法生成背景图片，请调整尺寸后重试。"
        case .invalidImage: "无法读取这张背景图，请选择有效的 PNG、JPEG 或 HEIC 图片。"
        case .missingImage: "已保存的背景图不可用，请重新导入或选择内置背景。"
        }
    }
}

struct BackgroundLayout {
    let size: CGSize
    let screenshot: CGRect
    let border: CGFloat
    init(source: CGSize, style: BackgroundStyle) throws {
        _ = try style.validated()
        guard source.width > 0, source.height > 0, source.width.isFinite, source.height.isFinite else { throw BackgroundFailure.invalidImage }
        let short = min(source.width, source.height)
        border = short * style.border
        let inset = short * style.padding + border
        var width = source.width + 2 * inset
        var height = source.height + 2 * inset
        if let ratio = style.aspectRatio {
            if width / height < ratio { width = height * ratio } else { height = width / ratio }
        }
        width = ceil(width); height = ceil(height)
        guard width <= 16384, height <= 16384, width * height <= 64_000_000 else { throw BackgroundFailure.tooLarge }
        size = CGSize(width: width, height: height)
        screenshot = CGRect(x: (width - source.width) / 2, y: (height - source.height) / 2, width: source.width, height: source.height)
    }
}
