import CoreGraphics
import Foundation

@MainActor
protocol ScreenRecordingAuthorizing {
    var privacySettingsURL: URL { get }

    func isAuthorized() -> Bool
    func requestAuthorization() -> Bool
}

/// Contains only the system authorization boundary. Presenting an alert or
/// opening System Settings remains the responsibility of the caller's UI.
@MainActor
final class PermissionService: ScreenRecordingAuthorizing {
    let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    func isAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestAuthorization() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

typealias ScreenRecordingPermissionService = PermissionService
