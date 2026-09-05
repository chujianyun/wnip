import XCTest
@testable import Wnip

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    func testCopySelectedRegionWindowAndFullScreenWritesPasteableImageAndDismisses() async throws {
        for mode: CaptureMode in [.region, .window, .fullScreen] {
            let pasteboard = NSPasteboard.withUniqueName()
            defer { pasteboard.releaseGlobally() }
            let screen = ScreenCaptureFake(content: ScreenCaptureFake.fixture)
            let overlay = OverlayFake()
            let coordinator = makeCoordinator(permissionGranted: true, screen: screen, overlay: overlay,
                clipboard: ImageClipboard(pasteboard: pasteboard))
            coordinator.startCapture(mode: mode)
            await coordinator.waitForPendingCaptureForTesting()
            var selection = try XCTUnwrap(overlay.presentations.first)
            selection.activeDisplayID = 1
            selection.showsToolbar = true
            selection.selection = SelectionModel(rect: mode == .fullScreen
                ? ScreenCaptureFake.fixture.displays[0].frame : CGRect(x: 10, y: 20, width: 30, height: 40))
            if mode == .window {
                selection.selectedWindow = CaptureCandidateWindow(id: 7, title: nil, applicationName: nil,
                    bundleIdentifier: "test", frame: selection.selection.rect,
                    isVisible: true, isOnScreen: true, isDesktopElement: false)
            }
            overlay.callbacks[0].onCopy(selection)
            overlay.callbacks[0].onCopy(selection)
            await coordinator.waitForPendingCaptureForTesting()

            let png = try XCTUnwrap(pasteboard.data(forType: .png))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: png))
            XCTAssertNotNil(pasteboard.data(forType: .tiff))
            XCTAssertFalse((pasteboard.readObjects(forClasses: [NSImage.self]) ?? []).isEmpty)
            XCTAssertEqual(bitmap.pixelsWide, mode == .region ? 30 : 100)
            XCTAssertEqual(bitmap.pixelsHigh, mode == .region ? 40 : 100)
            XCTAssertEqual(screen.windowCaptureCount, mode == .window ? 1 : 0)
            XCTAssertEqual(screen.displayCaptureCount, mode == .window ? 0 : 1)
            XCTAssertEqual(overlay.dismissAllCallCount, 2)
        }
    }

    func testCancelledCopyDoesNotChangeClipboard() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Existing clipboard", forType: .string)
        let screen = ScreenCaptureFake(content: ScreenCaptureFake.fixture)
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(permissionGranted: true, screen: screen, overlay: overlay,
            clipboard: ImageClipboard(pasteboard: pasteboard))
        coordinator.startCapture(mode: .region)
        await coordinator.waitForPendingCaptureForTesting()
        var selection = try XCTUnwrap(overlay.presentations.first)
        selection.showsToolbar = true
        selection.activeDisplayID = 1
        selection.selection = SelectionModel(rect: ScreenCaptureFake.fixture.displays[0].frame)
        overlay.callbacks[0].onCopy(selection)
        coordinator.cancelCapture()
        await Task.yield()
        XCTAssertEqual(pasteboard.string(forType: .string), "Existing clipboard")
    }

    func testCaptureFailureKeepsSelectionAndClipboardAndAllowsRetry() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Keep", forType: .string)
        let screen = ScreenCaptureFake(content: ScreenCaptureFake.fixture)
        screen.captureError = CaptureFailure.unavailable
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(permissionGranted: true, screen: screen, overlay: overlay,
            clipboard: ImageClipboard(pasteboard: pasteboard))
        coordinator.startCapture(mode: .fullScreen)
        await coordinator.waitForPendingCaptureForTesting()
        var selection = try XCTUnwrap(overlay.presentations.first)
        selection.showsToolbar = true
        selection.activeDisplayID = 1
        selection.selection = SelectionModel(rect: ScreenCaptureFake.fixture.displays[0].frame)
        overlay.callbacks[0].onCopy(selection)
        await coordinator.waitForPendingCaptureForTesting()
        XCTAssertEqual(pasteboard.string(forType: .string), "Keep")
        XCTAssertEqual(overlay.dismissAllCallCount, 1)
        XCTAssertNotNil(coordinator.presentedError)
        screen.captureError = nil
        overlay.callbacks[0].onCopy(selection)
        await coordinator.waitForPendingCaptureForTesting()
        XCTAssertNotNil(pasteboard.data(forType: .png))
        XCTAssertEqual(overlay.dismissAllCallCount, 2)
        XCTAssertNil(coordinator.presentedError)
    }

    func testCropMapsGlobalTopLeftSelectionToRetinaPixels() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 200,
            bitsPerComponent: 8, bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 100, width: 200, height: 100))
        context.setFillColor(NSColor.blue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let original = PixelImage(image: try XCTUnwrap(context.makeImage()), scale: 2)
        let display = DisplayDescriptor(id: 1, frame: CGRect(x: -100, y: 50, width: 100, height: 100), scale: 2)
        let cropped = try ScreenshotCrop.crop(original,
            selection: CGRect(x: -100, y: 125, width: 30, height: 25), display: display)
        XCTAssertEqual(cropped.image.width, 60)
        XCTAssertEqual(cropped.image.height, 50)
        let color = try XCTUnwrap(NSBitmapImageRep(cgImage: cropped.image).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.9)
        XCTAssertLessThan(color.blueComponent, 0.1)
    }

    func testErrorPresentationMatchesPermissionCaptureAndShortcutFailures() {
        let privacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        let permissionPresentation = SettingsAlertPresentation(
            error: .permissionDenied(privacyURL)
        )

        XCTAssertEqual(permissionPresentation.title, "Screen Recording Permission Required")
        XCTAssertEqual(permissionPresentation.message, "Screen Recording permission is required.")
        XCTAssertEqual(permissionPresentation.primaryButtonTitle, "Open System Settings")
        XCTAssertEqual(permissionPresentation.cancelButtonTitle, "Cancel")
        var openedURL: URL?
        permissionPresentation.openRecovery { openedURL = $0 }
        XCTAssertEqual(openedURL, privacyURL)

        let capturePresentation = SettingsAlertPresentation(
            error: .captureFailed("Unavailable")
        )
        XCTAssertEqual(
            capturePresentation.title,
            "Capture Failed"
        )
        XCTAssertEqual(capturePresentation.primaryButtonTitle, "OK")
        XCTAssertNil(capturePresentation.cancelButtonTitle)
        openedURL = nil
        capturePresentation.openRecovery { openedURL = $0 }
        XCTAssertNil(openedURL)

        let shortcutPresentation = SettingsAlertPresentation(
            error: .shortcutFailed("Conflict")
        )
        XCTAssertEqual(
            shortcutPresentation.title,
            "Shortcut Could Not Be Updated"
        )
        XCTAssertEqual(shortcutPresentation.primaryButtonTitle, "OK")
        XCTAssertNil(shortcutPresentation.cancelButtonTitle)
    }

    func testAuthorizedRegionRequestPresentsRegionOverlay() async {
        let screen = ScreenCaptureFake(content: ScreenCaptureFake.fixture)
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(permissionGranted: true, screen: screen, overlay: overlay)

        coordinator.startCapture(mode: .region)
        await coordinator.waitForPendingCaptureForTesting()

        XCTAssertEqual(screen.availableContentCallCount, 1)
        XCTAssertEqual(overlay.presentations.map(\.mode), [.region])
    }

    func testAuthorizedWindowRequestPreservesWindowMode() async {
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(permissionGranted: true, overlay: overlay)

        coordinator.startCapture(mode: .window)
        await coordinator.waitForPendingCaptureForTesting()

        XCTAssertEqual(overlay.presentations.map(\.mode), [.window])
    }

    func testAuthorizedFullScreenRequestPreservesFullScreenMode() async {
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(permissionGranted: true, overlay: overlay)

        coordinator.startCapture(mode: .fullScreen)
        await coordinator.waitForPendingCaptureForTesting()

        XCTAssertEqual(overlay.presentations.map(\.mode), [.fullScreen])
    }

    func testDeniedPermissionDoesNotPresentAnOverlay() async {
        let permission = PermissionFake(isAuthorized: false, authorizationRequestResult: false)
        let screen = ScreenCaptureFake(content: ScreenCaptureFake.fixture)
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(permission: permission, screen: screen, overlay: overlay)

        coordinator.startCapture(mode: .region)
        await coordinator.waitForPendingCaptureForTesting()

        XCTAssertEqual(permission.authorizationRequestCallCount, 1)
        XCTAssertEqual(screen.availableContentCallCount, 0)
        XCTAssertTrue(overlay.presentations.isEmpty)
        XCTAssertEqual(coordinator.presentedError, CaptureCoordinatorError.permissionDenied(permission.privacySettingsURL))
    }

    func testCancelCaptureDismissesOverlays() {
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(overlay: overlay)

        coordinator.cancelCapture()

        XCTAssertEqual(overlay.dismissAllCallCount, 1)
    }

    func testOverlayCancelCallbackCancelsAndDismissesOverlays() async {
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(permissionGranted: true, overlay: overlay)

        coordinator.startCapture(mode: .region)
        await coordinator.waitForPendingCaptureForTesting()
        overlay.callbacks.single?.onCancel()

        XCTAssertEqual(overlay.dismissAllCallCount, 2)
    }

    func testSecondRequestCancelsFirstBeforeOnlyPresentingNewestResult() async {
        let screen = ScreenCaptureFake(content: ScreenCaptureFake.fixture, suspendsFirstRequest: true)
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(permissionGranted: true, screen: screen, overlay: overlay)

        coordinator.startCapture(mode: .region)
        await screen.waitUntilFirstRequestSuspends()

        coordinator.startCapture(mode: .fullScreen)
        await coordinator.waitForPendingCaptureForTesting()
        screen.resumeFirstRequest()
        await Task.yield()

        XCTAssertTrue(screen.firstRequestObservedCancellation)
        XCTAssertEqual(overlay.presentations.map(\.mode), [.fullScreen])
    }

    func testReplacementDoesNotPublishCancelledRequestPermissionError() async {
        let permission = PermissionFake(
            isAuthorized: false,
            authorizationRequestResult: { !Task.isCancelled }
        )
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(permission: permission, overlay: overlay)

        coordinator.startCapture(mode: .region)
        coordinator.startCapture(mode: .fullScreen)
        await coordinator.waitForPendingCaptureForTesting()
        await Task.yield()

        XCTAssertNil(coordinator.presentedError)
        XCTAssertEqual(permission.authorizationRequestCallCount, 1)
        XCTAssertEqual(overlay.presentations.map(\.mode), [.fullScreen])
    }

    func testStartRegistersPersistedShortcutsThatStartTheirCaptureModes() async {
        let preferences = PreferencesFake(
            regionShortcut: HotKeyShortcut(keyCode: 12, modifiers: 3),
            windowShortcut: HotKeyShortcut(keyCode: 13, modifiers: 4)
        )
        let regionHotKey = HotKeyFake()
        let windowHotKey = HotKeyFake()
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(
            permissionGranted: true,
            overlay: overlay,
            regionHotKey: regionHotKey,
            windowHotKey: windowHotKey,
            preferences: preferences
        )

        coordinator.start()
        regionHotKey.trigger()
        await coordinator.waitForPendingCaptureForTesting()
        windowHotKey.trigger()
        await coordinator.waitForPendingCaptureForTesting()

        XCTAssertEqual(coordinator.regionShortcut, preferences.preferences.regionShortcut)
        XCTAssertEqual(coordinator.windowShortcut, preferences.preferences.windowShortcut)
        XCTAssertEqual(regionHotKey.registeredShortcuts, [preferences.preferences.regionShortcut])
        XCTAssertEqual(windowHotKey.registeredShortcuts, [preferences.preferences.windowShortcut])
        XCTAssertEqual(overlay.presentations.map(\.mode), [.region, .window])
    }

    func testUpdatingWindowShortcutRegistersPersistsAndTriggersWindowCapture() async {
        let preferences = PreferencesFake()
        let windowHotKey = HotKeyFake()
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(
            permissionGranted: true,
            overlay: overlay,
            windowHotKey: windowHotKey,
            preferences: preferences
        )
        coordinator.start()
        let replacement = HotKeyShortcut(keyCode: 15, modifiers: 5)

        coordinator.updateWindowShortcut(replacement)
        windowHotKey.trigger()
        await coordinator.waitForPendingCaptureForTesting()

        XCTAssertEqual(coordinator.windowShortcut, replacement)
        XCTAssertEqual(preferences.preferences.windowShortcut, replacement)
        XCTAssertEqual(windowHotKey.registeredShortcuts, [.defaultWindowCapture, replacement])
        XCTAssertEqual(overlay.presentations.map(\.mode), [.window])
    }

    func testShortcutMatchingOtherCaptureModeIsRejectedAndPreservesOldShortcut() {
        let preferences = PreferencesFake()
        let regionHotKey = HotKeyFake()
        let coordinator = makeCoordinator(regionHotKey: regionHotKey, preferences: preferences)
        coordinator.start()

        coordinator.updateRegionShortcut(.defaultWindowCapture)

        XCTAssertEqual(coordinator.regionShortcut, .defaultRegionCapture)
        XCTAssertEqual(preferences.preferences.regionShortcut, .defaultRegionCapture)
        XCTAssertEqual(regionHotKey.registeredShortcuts, [.defaultRegionCapture])
        XCTAssertEqual(coordinator.presentedError, .shortcutFailed("That shortcut is already assigned to Window Capture."))
    }

    func testRegistrationConflictPreservesPreviouslyRegisteredShortcutAndPreferences() {
        let conflicting = HotKeyShortcut(keyCode: 15, modifiers: 5)
        let preferences = PreferencesFake()
        let regionHotKey = HotKeyFake(conflictingShortcuts: [conflicting])
        let coordinator = makeCoordinator(regionHotKey: regionHotKey, preferences: preferences)
        coordinator.start()

        coordinator.updateRegionShortcut(conflicting)

        XCTAssertEqual(coordinator.regionShortcut, .defaultRegionCapture)
        XCTAssertEqual(preferences.preferences.regionShortcut, .defaultRegionCapture)
        XCTAssertEqual(regionHotKey.shortcut, .defaultRegionCapture)
        XCTAssertEqual(coordinator.presentedError, .shortcutFailed(HotKeyFailure.conflict.localizedDescription))
    }

    func testRegionRegistrationFailureDoesNotPreventWindowShortcutFromStartingCapture() async {
        let regionHotKey = HotKeyFake(conflictingShortcuts: [.defaultRegionCapture])
        let windowHotKey = HotKeyFake()
        let overlay = OverlayFake()
        let coordinator = makeCoordinator(
            permissionGranted: true,
            overlay: overlay,
            regionHotKey: regionHotKey,
            windowHotKey: windowHotKey
        )

        coordinator.start()
        windowHotKey.trigger()
        await coordinator.waitForPendingCaptureForTesting()

        XCTAssertEqual(windowHotKey.shortcut, .defaultWindowCapture)
        XCTAssertEqual(overlay.presentations.map(\.mode), [.window])
        XCTAssertEqual(coordinator.presentedError, .shortcutFailed(HotKeyFailure.conflict.localizedDescription))
    }

    func testShortcutRecordingTemporarilyUnregistersAndThenRestoresBothHotKeys() {
        let regionHotKey = HotKeyFake()
        let windowHotKey = HotKeyFake()
        let coordinator = makeCoordinator(regionHotKey: regionHotKey, windowHotKey: windowHotKey)
        coordinator.start()

        coordinator.beginShortcutRecording()

        XCTAssertNil(regionHotKey.shortcut)
        XCTAssertNil(windowHotKey.shortcut)

        coordinator.endShortcutRecording()

        XCTAssertEqual(regionHotKey.shortcut, .defaultRegionCapture)
        XCTAssertEqual(windowHotKey.shortcut, .defaultWindowCapture)
    }

    private func makeCoordinator(
        permissionGranted: Bool = false,
        permission: PermissionFake? = nil,
        screen: ScreenCaptureFake? = nil,
        overlay: OverlayFake? = nil,
        regionHotKey: HotKeyFake? = nil,
        windowHotKey: HotKeyFake? = nil,
        preferences: PreferencesFake? = nil,
        clipboard: ImageClipboard? = nil
    ) -> CaptureCoordinator {
        CaptureCoordinator(
            permission: permission ?? PermissionFake(
                isAuthorized: permissionGranted,
                authorizationRequestResult: permissionGranted
            ),
            screen: screen ?? ScreenCaptureFake(content: ScreenCaptureFake.fixture),
            overlay: overlay ?? OverlayFake(),
            regionHotKey: regionHotKey ?? HotKeyFake(),
            windowHotKey: windowHotKey ?? HotKeyFake(),
            preferences: preferences ?? PreferencesFake(),
            clipboard: clipboard
        )
    }
}

@MainActor
private final class PermissionFake: ScreenRecordingAuthorizing {
    let privacySettingsURL = URL(string: "https://example.com/privacy")!
    private let authorized: Bool
    private let authorizationRequestResult: @MainActor () -> Bool
    private(set) var authorizationRequestCallCount = 0

    init(isAuthorized: Bool, authorizationRequestResult: Bool) {
        authorized = isAuthorized
        self.authorizationRequestResult = { authorizationRequestResult }
    }

    init(
        isAuthorized: Bool,
        authorizationRequestResult: @escaping @MainActor () -> Bool
    ) {
        authorized = isAuthorized
        self.authorizationRequestResult = authorizationRequestResult
    }

    func isAuthorized() -> Bool {
        authorized
    }

    func requestAuthorization() -> Bool {
        authorizationRequestCallCount += 1
        return authorizationRequestResult()
    }
}

@MainActor
private final class ScreenCaptureFake: ScreenCapturing {
    var captureError: Error?
    private(set) var displayCaptureCount = 0
    private(set) var windowCaptureCount = 0
    private func image() -> PixelImage {
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
            bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return PixelImage(image: context.makeImage()!, scale: 1)
    }
    static let fixture = CaptureContent(
        displays: [DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)],
        windows: []
    )

    private let content: CaptureContent
    private let suspendsFirstRequest: Bool
    private var firstRequestContinuation: CheckedContinuation<Void, Never>?
    private(set) var availableContentCallCount = 0
    private(set) var firstRequestObservedCancellation = false

    init(content: CaptureContent, suspendsFirstRequest: Bool = false) {
        self.content = content
        self.suspendsFirstRequest = suspendsFirstRequest
    }

    func availableContent() async throws -> CaptureContent {
        availableContentCallCount += 1
        if suspendsFirstRequest, availableContentCallCount == 1 {
            await withCheckedContinuation { continuation in
                firstRequestContinuation = continuation
            }
            firstRequestObservedCancellation = Task.isCancelled
        }
        return content
    }

    func captureDisplay(_ display: DisplayDescriptor, excluding windows: [CaptureCandidateWindow]) async throws -> PixelImage {
        displayCaptureCount += 1
        if let captureError { throw captureError }
        return image()
    }

    func captureWindow(_ window: CaptureCandidateWindow) async throws -> PixelImage {
        windowCaptureCount += 1
        if let captureError { throw captureError }
        return image()
    }

    func waitUntilFirstRequestSuspends() async {
        while firstRequestContinuation == nil {
            await Task.yield()
        }
    }

    func resumeFirstRequest() {
        let continuation = firstRequestContinuation
        firstRequestContinuation = nil
        continuation?.resume()
    }
}

@MainActor
private final class OverlayFake: OverlayControlling {
    private(set) var presentations: [OverlayPresentation] = []
    private(set) var callbacks: [OverlayCallbacks] = []
    private(set) var dismissAllCallCount = 0

    func present(_ presentation: OverlayPresentation, callbacks: OverlayCallbacks) {
        presentations.append(presentation)
        self.callbacks.append(callbacks)
    }

    func update(_ presentation: OverlayPresentation) {}

    func dismissAll() {
        dismissAllCallCount += 1
    }
}

private extension Array where Element == OverlayCallbacks {
    var single: OverlayCallbacks? {
        count == 1 ? first : nil
    }
}

@MainActor
private final class HotKeyFake: HotKeyRegistering {
    private(set) var shortcut: HotKeyShortcut?
    private(set) var registeredShortcuts: [HotKeyShortcut] = []
    private var handler: (@MainActor () -> Void)?
    private let conflictingShortcuts: Set<HotKeyShortcut>

    init(conflictingShortcuts: Set<HotKeyShortcut> = []) {
        self.conflictingShortcuts = conflictingShortcuts
    }

    func register(_ shortcut: HotKeyShortcut) throws {
        if conflictingShortcuts.contains(shortcut) {
            throw HotKeyFailure.conflict
        }
        self.shortcut = shortcut
        registeredShortcuts.append(shortcut)
    }

    func register(_ shortcut: HotKeyShortcut, handler: @escaping @MainActor () -> Void) throws {
        try register(shortcut)
        self.handler = handler
    }

    func unregister() {
        shortcut = nil
        handler = nil
    }

    func trigger() {
        handler?()
    }
}

private final class PreferencesFake: PreferencesStoring {
    private(set) var preferences: AppPreferences

    init(
        regionShortcut: HotKeyShortcut = .defaultRegionCapture,
        windowShortcut: HotKeyShortcut = .defaultWindowCapture
    ) {
        preferences = AppPreferences(
            regionShortcut: regionShortcut,
            windowShortcut: windowShortcut
        )
    }

    func load() throws -> AppPreferences {
        preferences
    }

    func save(_ preferences: AppPreferences) throws {
        self.preferences = preferences
    }

    func replaceSaveDirectoryBookmark(for directory: URL) throws {}
}
