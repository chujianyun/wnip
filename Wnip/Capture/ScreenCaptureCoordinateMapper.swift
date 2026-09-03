import AppKit
import CoreGraphics

struct AppKitScreenGeometry: Equatable, Sendable {
    let displayID: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
    let scale: CGFloat

    @MainActor
    static var current: [AppKitScreenGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return nil
            }
            return AppKitScreenGeometry(
                displayID: number.uint32Value,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                scale: screen.backingScaleFactor
            )
        }
    }
}

/// Normalizes ScreenCaptureKit/Core Graphics geometry at the producer boundary.
/// Everything downstream receives AppKit global points (bottom-left, Y-up).
struct ScreenCaptureCoordinateMapper: Sendable {
    private let mainDisplayHeight: CGFloat
    private let screensByID: [UInt32: AppKitScreenGeometry]

    init(mainDisplayHeight: CGFloat, screens: [AppKitScreenGeometry]) {
        self.mainDisplayHeight = mainDisplayHeight
        self.screensByID = Dictionary(uniqueKeysWithValues: screens.map { ($0.displayID, $0) })
    }

    @MainActor
    static func current() -> ScreenCaptureCoordinateMapper {
        ScreenCaptureCoordinateMapper(
            mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height,
            screens: AppKitScreenGeometry.current
        )
    }

    func displayDescriptor(
        displayID: UInt32,
        quartzFrame: CGRect,
        fallbackScale: CGFloat
    ) -> DisplayDescriptor {
        if let screen = screensByID[displayID] {
            return DisplayDescriptor(
                id: displayID,
                frame: screen.frame,
                scale: screen.scale
            )
        }
        return DisplayDescriptor(
            id: displayID,
            frame: appKitRect(fromQuartzRect: quartzFrame),
            scale: validScale(fallbackScale)
        )
    }

    func appKitRect(fromQuartzRect rect: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: rect.minX,
            y: mainDisplayHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func validScale(_ scale: CGFloat) -> CGFloat {
        scale.isFinite && scale > 0 ? scale : 1
    }
}
