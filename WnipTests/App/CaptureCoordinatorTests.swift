import XCTest
@testable import Wnip

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
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

    private func makeCoordinator(
        permissionGranted: Bool = false,
        permission: PermissionFake? = nil,
        screen: ScreenCaptureFake? = nil,
        overlay: OverlayFake? = nil,
        regionHotKey: HotKeyFake? = nil,
        windowHotKey: HotKeyFake? = nil,
        preferences: PreferencesFake? = nil
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
            preferences: preferences ?? PreferencesFake()
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
        fatalError("CaptureCoordinator should not capture an image before the user selects a target.")
    }

    func captureWindow(_ window: CaptureCandidateWindow) async throws -> PixelImage {
        fatalError("CaptureCoordinator should not capture an image before the user selects a target.")
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
