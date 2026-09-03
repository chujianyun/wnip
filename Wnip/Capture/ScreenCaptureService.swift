import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
protocol ScreenCapturing: AnyObject {
    func availableContent() async throws -> CaptureContent
    func captureDisplay(_ display: DisplayDescriptor, excluding windows: [CaptureCandidateWindow]) async throws -> PixelImage
    func captureWindow(_ window: CaptureCandidateWindow) async throws -> PixelImage
}

/// The narrow boundary lets the service's domain error contract be tested
/// without requiring screen-recording permission or a live desktop.
@MainActor
protocol ScreenCaptureKitAdapting: AnyObject {
    func availableContent() async throws -> CaptureContent
    func captureDisplay(id: UInt32, excludingWindowIDs: [UInt32]) async throws -> PixelImage
    func captureWindow(id: UInt32) async throws -> PixelImage
}

@MainActor
final class ScreenCaptureService: ScreenCapturing {
    private let adapter: any ScreenCaptureKitAdapting
    private let contentFilter: ShareableContentFilter

    init() {
        self.adapter = ScreenCaptureKitAdapter()
        self.contentFilter = ShareableContentFilter(ownBundleIdentifier: Bundle.main.bundleIdentifier)
    }

    init(adapter: any ScreenCaptureKitAdapting, ownBundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.adapter = adapter
        self.contentFilter = ShareableContentFilter(ownBundleIdentifier: ownBundleIdentifier)
    }

    func availableContent() async throws -> CaptureContent {
        do {
            let content = try await adapter.availableContent()
            return CaptureContent(
                displays: content.displays,
                windows: contentFilter.filter(content.windows)
            )
        } catch {
            throw map(error)
        }
    }

    func captureDisplay(
        _ display: DisplayDescriptor,
        excluding windows: [CaptureCandidateWindow]
    ) async throws -> PixelImage {
        do {
            return try await adapter.captureDisplay(
                id: display.id,
                excludingWindowIDs: windows.map(\.id)
            )
        } catch {
            throw map(error)
        }
    }

    func captureWindow(_ window: CaptureCandidateWindow) async throws -> PixelImage {
        do {
            return try await adapter.captureWindow(id: window.id)
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> CaptureFailure {
        if error is CancellationError {
            return .cancelled
        }

        if let error = error as? ScreenCaptureKitAdapterFailure, error == .unavailable {
            return .unavailable
        }

        let error = error as NSError
        if error.domain == SCStreamErrorDomain, error.code == -3801 {
            return .permissionDenied
        }
        return .captureFailed(error.localizedDescription)
    }
}

@MainActor
final class ScreenCaptureKitAdapter: ScreenCaptureKitAdapting {
    func availableContent() async throws -> CaptureContent {
        let content = try await SCShareableContent.current
        return CaptureContent(
            displays: content.displays.map(displayDescriptor(from:)),
            windows: content.windows.map(candidate(from:))
        )
    }

    func captureDisplay(id: UInt32, excludingWindowIDs: [UInt32]) async throws -> PixelImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw ScreenCaptureKitAdapterFailure.unavailable
        }

        let excludedWindows = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        return try await captureImage(using: filter)
    }

    func captureWindow(id: UInt32) async throws -> PixelImage {
        let content = try await SCShareableContent.current
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw ScreenCaptureKitAdapterFailure.unavailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await captureImage(using: filter)
    }

    private func displayDescriptor(from display: SCDisplay) -> DisplayDescriptor {
        let nativeWidth = CGFloat(CGDisplayPixelsWide(display.displayID))
        let scale = display.width > 0 ? nativeWidth / CGFloat(display.width) : 1
        return DisplayDescriptor(id: display.displayID, frame: display.frame, scale: scale)
    }

    private func candidate(from window: SCWindow) -> CaptureCandidateWindow {
        CaptureCandidateWindow(
            id: window.windowID,
            title: window.title,
            applicationName: window.owningApplication?.applicationName,
            bundleIdentifier: window.owningApplication?.bundleIdentifier,
            frame: window.frame,
            isVisible: window.isOnScreen,
            isOnScreen: window.isOnScreen,
            isDesktopElement: window.owningApplication == nil || window.windowLayer < 0
        )
    }

    private func captureImage(using filter: SCContentFilter) async throws -> PixelImage {
        let scale = max(CGFloat(filter.pointPixelScale), 1)
        let contentRect = filter.contentRect
        let width = contentRect.width * scale
        let height = contentRect.height * scale
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw ScreenCaptureKitAdapterFailure.unavailable
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(width.rounded(.up))
        configuration.height = Int(height.rounded(.up))
        configuration.showsCursor = false

        let image: CGImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: ScreenCaptureKitAdapterFailure.unavailable)
                }
            }
        }
        return PixelImage(image: image, scale: scale, colorSpace: image.colorSpace)
    }
}

private enum ScreenCaptureKitAdapterFailure: Error, Equatable {
    case unavailable
}
