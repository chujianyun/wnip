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
    let windowLayer: Int
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
        isDesktopElement: Bool,
        windowLayer: Int = 0
    ) {
        self.id = id
        self.title = title
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
        self.windowLayer = windowLayer
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

/// Applies Wnip's window-target policy without changing the supplied z-order.
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
                  // Floating recording/assistant overlays can cover a display
                  // while remaining visually transparent. They must not hide
                  // the normal application windows from rectangle hit testing.
                  window.windowLayer == 0,
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

/// ScreenCaptureKit exposes available windows, not a guaranteed stacking order.
/// Only offer windows present in the WindowServer's on-screen snapshot.
enum WindowStack {
    static func ordered(_ windows: [CaptureCandidateWindow], frontToBackIDs: [UInt32]) -> [CaptureCandidateWindow] {
        let candidates = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return frontToBackIDs.compactMap { candidates[$0] }
    }
}
