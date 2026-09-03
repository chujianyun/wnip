import CoreGraphics
import Foundation

/// A window that can be presented as a capture target. The value deliberately
/// contains no ScreenCaptureKit object so filtering remains deterministic and
/// unit-testable.
struct CaptureCandidateWindow: Equatable, Sendable {
    let id: UInt32
    let title: String?
    let applicationName: String?
    let bundleIdentifier: String?
    let frame: CGRect
    let isVisible: Bool
    let isOnScreen: Bool
    let isDesktopElement: Bool

    init(
        id: UInt32,
        title: String?,
        applicationName: String?,
        bundleIdentifier: String?,
        frame: CGRect,
        isVisible: Bool,
        isOnScreen: Bool,
        isDesktopElement: Bool
    ) {
        self.id = id
        self.title = title
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        self.isVisible = isVisible
        self.isOnScreen = isOnScreen
        self.isDesktopElement = isDesktopElement
    }
}

struct CaptureContent: Sendable {
    let displays: [DisplayDescriptor]
    let windows: [CaptureCandidateWindow]

    init(displays: [DisplayDescriptor], windows: [CaptureCandidateWindow]) {
        self.displays = displays
        self.windows = windows
    }
}

/// Applies Wnip's window-target policy without reordering ScreenCaptureKit's
/// front-to-back window sequence.
struct ShareableContentFilter {
    let ownBundleIdentifier: String?

    init(ownBundleIdentifier: String?) {
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    func filter(_ windows: [CaptureCandidateWindow]) -> [CaptureCandidateWindow] {
        windows.filter { window in
            guard window.isVisible,
                  window.isOnScreen,
                  !window.isDesktopElement,
                  window.frame.hasFinitePositiveArea else {
                return false
            }

            guard let ownBundleIdentifier else { return true }
            return window.bundleIdentifier != ownBundleIdentifier
        }
    }
}

private extension CGRect {
    var hasFinitePositiveArea: Bool {
        !isNull &&
            origin.x.isFinite &&
            origin.y.isFinite &&
            size.width.isFinite &&
            size.height.isFinite &&
            size.width > 0 &&
            size.height > 0
    }
}
