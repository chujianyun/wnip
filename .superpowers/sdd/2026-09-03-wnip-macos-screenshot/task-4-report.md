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

## Review fix round 1 — exclude Wnip windows from display captures

### Files changed

- `Wnip/Capture/ScreenCaptureService.swift`
  - `captureDisplay` now unions caller-provided exclusions with every raw adapter candidate whose bundle identifier matches Wnip, retaining caller order then source z-order and removing duplicates.
  - The production adapter repeats that bundle-identifier exclusion against the fresh `SCShareableContent` snapshot used to create `SCContentFilter`, closing the gap between the service's discovery snapshot and capture snapshot.
  - Replaced the magic `-3801` value with `Int(SCStreamError.userDeclined.rawValue)`.
- `WnipTests/Capture/ShareableContentFilterTests.swift`
  - Added a public-service contract test with an injected adapter that exposes visible and invisible Wnip windows, records the final display exclusion IDs, and verifies caller exclusions are retained.
  - Updated the permission-denial fixture to use `Int(SCStreamError.userDeclined.rawValue)`.

### RED / GREEN evidence

1. RED before the production change:
   - Command: `xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/ShareableContentFilterTests`
   - Result: failed as intended in `testCaptureDisplayExcludesEveryWnipWindowAlongsideCallerExclusions`: `XCTAssertEqual failed: ("[99]") is not equal to ("[99, 10, 20]")`. The old service forwarded only the caller's ID, omitting both visible and off-screen Wnip candidates.
2. GREEN after the service and adapter changes:
   - Same focused command: 5 tests executed, 0 failures.
3. Final verification:
   - `xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/ShareableContentFilterTests` — 5 tests executed, 0 failures.
   - `xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'` — 31 tests executed, 0 failures.
   - `xcodebuild build -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'` — `BUILD SUCCEEDED`.
   - Installed `/Users/wuming/Library/Developer/Xcode/DerivedData/Wnip-bqdmxdrgjdjhezhcosqbjccokyfh/Build/Products/Debug/Wnip.app` to `/Users/wuming/Applications/Wnip.app`; launched it, observed `smoke-running-pid=64357` after two seconds, then terminated that smoke-test process.

### Self-review

- The public service deliberately uses unfiltered adapter content for the exclusion set, so Wnip windows are excluded even if they are invisible, off-screen, or otherwise absent from the public candidate list.
- Wnip ownership is determined only by bundle identifier; no title or visibility heuristic is used.
- The caller's exclusions remain first, followed by all Wnip-owned windows in the source order; duplicate IDs are emitted once.
- Existing z-order behavior in `ShareableContentFilter` and both capture error mappings are unchanged.

### Concerns

- The automated contract test validates the public service's computed exclusion IDs. It does not request a live screen capture because that requires a user-granted Screen Recording permission; the production adapter's second bundle-ID pass is compile- and suite-verified but not exercised against a real `SCShareableContent` response in CI.
