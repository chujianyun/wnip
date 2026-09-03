import CoreGraphics
import Foundation

enum CaptureMode: Equatable, Sendable {
    case region
    case window
    case fullScreen
}

enum CaptureFailure: LocalizedError, Equatable {
    case permissionDenied
    case unavailable
    case captureFailed(String)
    case invalidSelection
    case cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required."
        case .unavailable:
            return "Screen capture is unavailable."
        case .captureFailed(let message):
            return message
        case .invalidSelection:
            return "The selected area is invalid."
        case .cancelled:
            return "Capture was cancelled."
        }
    }
}

struct DisplayDescriptor: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    let scale: CGFloat

    init(id: UInt32, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }

    init(id: Int, frame: CGRect, scale: CGFloat) {
        self.init(id: UInt32(id), frame: frame, scale: scale)
    }

    /// Converts an AppKit global point-space rect (origin at bottom-left) to
    /// ScreenCaptureKit's display-local pixel rect (origin at top-left).
    func pixelRect(forGlobalRect rect: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - frame.minX) * scale,
            y: (frame.maxY - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}

struct PixelImage {
    let image: CGImage
    let scale: CGFloat
    let colorSpace: CGColorSpace

    init(image: CGImage, scale: CGFloat, colorSpace: CGColorSpace? = nil) {
        self.image = image
        self.scale = scale
        self.colorSpace = colorSpace ?? image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    }
}
