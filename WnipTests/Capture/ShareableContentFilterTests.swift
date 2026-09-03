import ScreenCaptureKit
import XCTest
@testable import Wnip

@MainActor
final class ShareableContentFilterTests: XCTestCase {
    // Removing any of the predicates below must expose a non-capturable window.
    func testFiltersNonCapturableWindowsAndPreservesShareableContentZOrder() {
        let filter = ShareableContentFilter(ownBundleIdentifier: "com.wnip.app")
        let windows = [
            candidate(id: 1, title: "Frontmost"),
            candidate(id: 2, title: "Wnip", bundleIdentifier: "com.wnip.app"),
            candidate(id: 3, title: "Desktop", isDesktopElement: true),
            candidate(id: 4, title: "Hidden", isVisible: false),
            candidate(id: 5, title: "Zero", frame: CGRect(x: 10, y: 10, width: 0, height: 500)),
            candidate(id: 6, title: "Malformed", frame: CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100)),
            candidate(id: 7, title: "Off screen", isOnScreen: false),
            candidate(id: 8, title: "Second")
        ]

        let result = filter.filter(windows)

        XCTAssertEqual(result.map { $0.id }, [1, 8])
    }

    func testKeepsAnUnownedNormalWindowWhenTheHostBundleIdentifierIsUnavailable() {
        let filter = ShareableContentFilter(ownBundleIdentifier: nil)
        let window = CaptureCandidateWindow(
            id: 9,
            title: "System panel",
            applicationName: nil,
            bundleIdentifier: nil,
            frame: CGRect(x: 10, y: 10, width: 500, height: 400),
            isVisible: true,
            isOnScreen: true,
            isDesktopElement: false
        )

        XCTAssertEqual(filter.filter([window]).map { $0.id }, [9])
    }

    func testMapsScreenRecordingDenialFromTheAdapterToPermissionFailure() async {
        let adapter = ControlledScreenCaptureKitAdapter(
            contentError: NSError(
                domain: SCStreamErrorDomain,
                code: Int(SCStreamError.userDeclined.rawValue)
            )
        )
        let service = ScreenCaptureService(adapter: adapter)

        await XCTAssertThrowsErrorAsync(try await service.availableContent()) { error in
            XCTAssertEqual(error as? CaptureFailure, .permissionDenied)
        }
    }

    func testCaptureDisplayExcludesEveryWnipWindowAlongsideCallerExclusions() async {
        let ownVisibleWindow = candidate(id: 10, title: "Wnip overlay", bundleIdentifier: "com.wnip.app")
        let ownHiddenWindow = candidate(
            id: 20,
            title: "Wnip panel",
            bundleIdentifier: "com.wnip.app",
            isVisible: false,
            isOnScreen: false
        )
        let otherWindow = candidate(id: 30, title: "Other app")
        let adapter = ControlledScreenCaptureKitAdapter(
            content: CaptureContent(displays: [], windows: [ownVisibleWindow, ownHiddenWindow, otherWindow]),
            displayError: NSError(
                domain: "CaptureTest",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Expected capture assertion."]
            )
        )
        let service = ScreenCaptureService(adapter: adapter, ownBundleIdentifier: "com.wnip.app")
        let display = DisplayDescriptor(id: 42, frame: .zero, scale: 2)
        let callerExcludedWindow = candidate(id: 99, title: "Caller exclusion")

        await XCTAssertThrowsErrorAsync(
            try await service.captureDisplay(display, excluding: [callerExcludedWindow])
        ) { error in
            XCTAssertEqual(error as? CaptureFailure, .captureFailed("Expected capture assertion."))
        }

        XCTAssertEqual(adapter.displayExclusionIDs, [99, 10, 20])
    }

    func testMapsCaptureFailureFromTheAdapterToCaptureFailure() async {
        let adapter = ControlledScreenCaptureKitAdapter(
            displayError: NSError(
                domain: "CaptureTest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The display disappeared."]
            )
        )
        let service = ScreenCaptureService(adapter: adapter)
        let display = DisplayDescriptor(id: 42, frame: .zero, scale: 2)

        await XCTAssertThrowsErrorAsync(try await service.captureDisplay(display, excluding: [])) { error in
            XCTAssertEqual(error as? CaptureFailure, .captureFailed("The display disappeared."))
        }
    }

    private func candidate(
        id: UInt32,
        title: String,
        bundleIdentifier: String = "com.example.app",
        frame: CGRect = CGRect(x: 10, y: 10, width: 500, height: 400),
        isVisible: Bool = true,
        isOnScreen: Bool = true,
        isDesktopElement: Bool = false
    ) -> CaptureCandidateWindow {
        CaptureCandidateWindow(
            id: id,
            title: title,
            applicationName: "Example",
            bundleIdentifier: bundleIdentifier,
            frame: frame,
            isVisible: isVisible,
            isOnScreen: isOnScreen,
            isDesktopElement: isDesktopElement
        )
    }
}

@MainActor
private final class ControlledScreenCaptureKitAdapter: ScreenCaptureKitAdapting {
    private let content: CaptureContent
    private let contentError: Error?
    private let displayError: Error?
    private(set) var displayExclusionIDs: [UInt32] = []

    init(
        content: CaptureContent = CaptureContent(displays: [], windows: []),
        contentError: Error? = nil,
        displayError: Error? = nil
    ) {
        self.content = content
        self.contentError = contentError
        self.displayError = displayError
    }

    func availableContent() async throws -> CaptureContent {
        if let contentError { throw contentError }
        return content
    }

    func captureDisplay(
        id: UInt32,
        excludingWindowIDs: [UInt32]
    ) async throws -> PixelImage {
        displayExclusionIDs = excludingWindowIDs
        if let displayError { throw displayError }
        fatalError("The test should not request an image when no display error was configured.")
    }

    func captureWindow(id: UInt32) async throws -> PixelImage {
        fatalError("The test should not request a window image.")
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown.", file: file, line: line)
    } catch {
        handler(error)
    }
}
