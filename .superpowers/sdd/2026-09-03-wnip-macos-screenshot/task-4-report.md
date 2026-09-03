# Task 4 report — ScreenCaptureKit capture service

## Delivered

- `Wnip/Capture/ShareableContentFilter.swift`
  - Defines `CaptureCandidateWindow`, `CaptureContent`, and the pure, order-preserving candidate filter.
  - Excludes Wnip itself, desktop elements, invisible/off-screen windows, and zero-size or non-finite frames.
- `Wnip/Capture/ScreenCaptureService.swift`
  - Defines the main-actor `ScreenCapturing` service and an injectable `ScreenCaptureKitAdapting` boundary.
  - The production adapter reads `SCShareableContent.current`, builds `SCContentFilter` instances for displays and independent windows, requests native-pixel output dimensions using `pointPixelScale`, and preserves `CGImage` color-space and scale in `PixelImage`.
  - Maps ScreenCaptureKit user-declined errors to `CaptureFailure.permissionDenied`; other adapter capture errors become `CaptureFailure.captureFailed`.
- `WnipTests/Capture/ShareableContentFilterTests.swift`
  - Tests the pure filter and the public service error contract through an injected adapter.

## RED / GREEN evidence

1. Initial RED:
   - Command: `xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/ShareableContentFilterTests`
   - Result: failed as intended because `CaptureCandidateWindow`, `ScreenCaptureKitAdapting`, and `CaptureContent` did not exist.
2. Initial GREEN:
   - Same focused test target passed with 3 tests: order-preserving filter, permission-denial mapping, and generic capture-failure mapping.
3. Regression RED from self-review:
   - Added `testKeepsAnUnownedNormalWindowWhenTheHostBundleIdentifierIsUnavailable`.
   - Focused test failed as intended: expected `[9]`, received `[]` when both bundle identifiers were absent.
4. Regression GREEN:
   - Updated the filter to compare bundle identifiers only when Wnip has a non-nil identifier.
   - Focused suite passed: 4 tests, 0 failures.

## Final verification

- `xcodegen generate && xcodebuild clean build -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'` — succeeded.
- `xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'` — 30 tests passed, 0 failures.
- `xcodebuild build -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' SWIFT_STRICT_CONCURRENCY=complete` — succeeded. The only strict-concurrency warnings are pre-existing `HotKeyService` deinit warnings for non-Sendable registrations/registrar; Task 4 sources emitted none.
- Installed the final Debug product to `/Users/wuming/Applications/Wnip.app`, launched it successfully (PID 62485), confirmed it stayed running for a two-second smoke check, then terminated that smoke-test process.

## Self-review

- `SCShareableContent.current`, `SCContentFilter(display:excludingWindows:)`, `SCContentFilter(desktopIndependentWindow:)`, and `SCScreenshotManager.captureImage` were compiled against the local macOS 15 target.
- Candidate filtering is independent of the live ScreenCaptureKit objects and retains incoming z-order.
- Display configuration dimensions are `contentRect × pointPixelScale`, rounded up to native pixels; `PixelImage` retains the capture image's color space and the same scale.
- No UI was added.

## Concerns

- ScreenCaptureKit supplies `SCWindow.isOnScreen` but no separate visibility property. The native adapter maps its `isVisible` field from `isOnScreen`; the pure filter retains both predicates so callers/adapters with richer visibility information remain correct.
- The injected-boundary tests deliberately avoid making a real screen-recording request. Real capture requires a user-granted Screen Recording permission and is covered structurally by compilation plus the adapter boundary rather than an automated permission-dependent test.
