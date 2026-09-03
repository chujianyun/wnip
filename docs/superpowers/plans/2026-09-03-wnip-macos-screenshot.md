# Wnip macOS Screenshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS 15+ menu-bar screenshot application with region, window, and display capture; non-destructive annotation; clipboard and file output; and persistent preferences.

**Architecture:** A SwiftUI application shell owns protocol-backed AppKit and ScreenCaptureKit services. A `CaptureCoordinator` state machine connects capture, per-display overlays, editing, rendering, and output while pure value models isolate coordinate, annotation, naming, and transition logic for unit tests.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ScreenCaptureKit, CoreGraphics, CoreImage, UniformTypeIdentifiers, ServiceManagement, UserNotifications, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-03-wnip-macos-screenshot-design.md`

## Global Constraints

- Minimum deployment target is macOS 15.0 Sequoia.
- Screenshot pixels and annotations stay in local memory and are never uploaded.
- Exclude Wnip windows, overlays, and desktop elements from captures.
- Support mixed-scale multi-display coordinate conversion.
- Use test-first red/green/refactor cycles for every core behavior.
- Do not implement scrolling capture, purchases, subscriptions, OCR, recording, or cloud features.

---

### Task 1: Project shell and domain foundations

**Files:**
- Create: `project.yml`
- Create: `Wnip/App/WnipApp.swift`
- Create: `Wnip/App/AppDelegate.swift`
- Create: `Wnip/Domain/CaptureTypes.swift`
- Create: `WnipTests/Domain/CaptureTypesTests.swift`

**Interfaces:**
- Produces: `CaptureMode`, `CaptureFailure`, `DisplayDescriptor`, `PixelImage`, and an executable menu-bar app target.

- [ ] **Step 1: Write the failing domain test**

```swift
import XCTest
@testable import Wnip

final class CaptureTypesTests: XCTestCase {
    func testDisplayConvertsGlobalPointsToLocalPixels() {
        let display = DisplayDescriptor(id: 7, frame: CGRect(x: -1440, y: 0, width: 1440, height: 900), scale: 2)
        XCTAssertEqual(display.pixelRect(forGlobalRect: CGRect(x: -1340, y: 100, width: 200, height: 50)),
                       CGRect(x: 200, y: 1500, width: 400, height: 100))
    }
}
```

- [ ] **Step 2: Generate the Xcode project and verify RED**

Run: `xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/CaptureTypesTests`
Expected: FAIL because `DisplayDescriptor` does not exist.

- [ ] **Step 3: Add the minimal project and domain implementation**

Define `CaptureMode { region, window, fullScreen }`, `CaptureFailure: LocalizedError`, a `DisplayDescriptor` whose conversion flips AppKit's bottom-left point coordinates into ScreenCaptureKit's top-left pixels, and `PixelImage` containing `CGImage`, scale, and color space. Configure an accessory-policy SwiftUI app with a `MenuBarExtra`, Settings scene, macOS 15 deployment target, and unit-test target.

- [ ] **Step 4: Verify GREEN**

Run the focused test, then `xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'`.
Expected: PASS with no warnings.

- [ ] **Step 5: Commit**

```bash
git add project.yml Wnip WnipTests
git commit -m "feat: scaffold Wnip macOS app"
```

### Task 2: Selection model and capture session state machine

**Files:**
- Create: `Wnip/Capture/SelectionModel.swift`
- Create: `Wnip/Capture/CaptureSession.swift`
- Create: `WnipTests/Capture/SelectionModelTests.swift`
- Create: `WnipTests/Capture/CaptureSessionTests.swift`

**Interfaces:**
- Consumes: `CaptureMode`, `DisplayDescriptor`, `CaptureFailure`.
- Produces: `SelectionModel.begin(at:)`, `update(to:within:)`, `resize(handle:to:within:)`; `CaptureSession.handle(_:)`; `CapturePhase` and `CaptureEvent`.

- [ ] **Step 1: Write failing selection tests** for forward/reverse drags, minimum 8-point size, bounds clamping, resize handles, and mixed-scale pixel conversion.
- [ ] **Step 2: Run the focused suite and verify RED** because `SelectionModel` is absent.
- [ ] **Step 3: Implement normalized/clamped geometry** as pure value operations with no AppKit window dependency.
- [ ] **Step 4: Run selection tests and verify GREEN**.
- [ ] **Step 5: Write failing state tests** covering idle → permission → selecting → editing → exporting → completed, cancellation from every active phase, recoverable export failure returning to editing, and repeated start cancelling the old session.
- [ ] **Step 6: Run and verify RED** because transition handling is absent.
- [ ] **Step 7: Implement the exhaustive state reducer**; invalid transitions return `.ignored` without mutating state.
- [ ] **Step 8: Run the full suite and verify GREEN**.
- [ ] **Step 9: Commit** with `feat: add selection and capture state models`.

### Task 3: Preferences, permission, hot key, and launch services

**Files:**
- Create: `Wnip/Preferences/PreferencesStore.swift`
- Create: `Wnip/System/PermissionService.swift`
- Create: `Wnip/System/HotKeyService.swift`
- Create: `Wnip/System/LaunchAtLoginService.swift`
- Create: `WnipTests/Preferences/PreferencesStoreTests.swift`
- Create: `WnipTests/System/HotKeyServiceTests.swift`

**Interfaces:**
- Produces: `AppPreferences`, `PreferencesStoring`, `ScreenRecordingAuthorizing`, `HotKeyRegistering`, `LaunchAtLoginControlling`.
- Default shortcut: Command+Shift+X; default filename rule: `Wnip-yyyy-MM-dd_HH-mm-ss`; default JPEG quality: 0.9.

- [ ] **Step 1: Write failing preference tests** for every documented default, Codable persistence, and security-scoped bookmark replacement.
- [ ] **Step 2: Verify RED**, then implement a namespaced `UserDefaults` store and verify GREEN.
- [ ] **Step 3: Write failing hot-key tests** using an injected registrar to prove conflicts preserve the previous shortcut.
- [ ] **Step 4: Verify RED**, implement Carbon hot-key registration and conflict rollback, then verify GREEN.
- [ ] **Step 5: Implement permission checks** with `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`, and the macOS Privacy settings URL; keep UI presentation outside the service.
- [ ] **Step 6: Implement login-item control** using `SMAppService.mainApp` and map service errors to user-facing failures.
- [ ] **Step 7: Run all tests and commit** with `feat: add persistent preferences and system services`.

### Task 4: ScreenCaptureKit capture service

**Files:**
- Create: `Wnip/Capture/ScreenCaptureService.swift`
- Create: `Wnip/Capture/ShareableContentFilter.swift`
- Create: `WnipTests/Capture/ShareableContentFilterTests.swift`

**Interfaces:**
- Produces: `ScreenCapturing.availableContent()`, `captureDisplay(_:excluding:)`, `captureWindow(_:)`; `CaptureCandidateWindow`.

- [ ] **Step 1: Write failing filter tests** proving Wnip, desktop, invisible, zero-size, and off-screen windows are removed while normal windows remain in z-order.
- [ ] **Step 2: Verify RED**, implement the pure filter, and verify GREEN.
- [ ] **Step 3: Implement ScreenCaptureKit adapters** using `SCShareableContent`, `SCContentFilter`, and `SCScreenshotManager.captureImage`; request native pixel dimensions and preserve color metadata.
- [ ] **Step 4: Add adapter error mapping tests** with an injected ScreenCaptureKit boundary and confirm permission/capture failures map to `CaptureFailure`.
- [ ] **Step 5: Run all tests and commit** with `feat: capture displays and windows with ScreenCaptureKit`.

### Task 5: Per-display overlay, region/window interaction, and toolbar

**Files:**
- Create: `Wnip/Overlay/OverlayController.swift`
- Create: `Wnip/Overlay/CaptureOverlayWindow.swift`
- Create: `Wnip/Overlay/CaptureOverlayView.swift`
- Create: `Wnip/Overlay/ToolbarPlacement.swift`
- Create: `Wnip/Overlay/AnnotationToolbar.swift`
- Create: `WnipTests/Overlay/ToolbarPlacementTests.swift`

**Interfaces:**
- Consumes: `DisplayDescriptor`, `SelectionModel`, `CaptureCandidateWindow`, editor commands.
- Produces: `OverlayControlling.present(...)`, `update(...)`, `dismissAll()` and `ToolbarPlacement.resolve(selection:visibleFrame:toolbarSize:)`.

- [ ] **Step 1: Write failing placement tests** for below, above, and inside fallback positions and display-safe clamping.
- [ ] **Step 2: Verify RED**, implement placement, and verify GREEN.
- [ ] **Step 3: Build one borderless `NSPanel` per display** at screen-saver window level with transparent SwiftUI content, dark outside mask, blue border, eight resize handles, and pixel-size badge.
- [ ] **Step 4: Wire mouse tracking** for region drag/resize and window hover/click, limiting the full toolbar to the active display.
- [ ] **Step 5: Add Escape and Command-Z routing** through local event monitors and guarantee monitors/windows are removed on dismissal.
- [ ] **Step 6: Run tests and manually smoke-test panel creation**, then commit with `feat: add multi-display capture overlays`.

### Task 6: Annotation model and editable canvas

**Files:**
- Create: `Wnip/Annotation/Annotation.swift`
- Create: `Wnip/Annotation/AnnotationDocument.swift`
- Create: `Wnip/Annotation/AnnotationCanvas.swift`
- Create: `WnipTests/Annotation/AnnotationDocumentTests.swift`

**Interfaces:**
- Produces: vector annotations for rectangle, ellipse, line, arrow, pen, mosaic, text, highlight, and step; `perform(_:)`, `undo()`, `hitTest(_:)`, `nextStepNumber`.

- [ ] **Step 1: Write failing document tests** for default tool parameters, hit testing, add/move/delete/crop undo, and visible-number-based step sequencing after undo.
- [ ] **Step 2: Verify RED**, implement immutable annotation values plus an undoable command stack, and verify GREEN.
- [ ] **Step 3: Implement the SwiftUI canvas** with drag gestures, text editing, color/width/font controls, selection handles, and tool cursors.
- [ ] **Step 4: Add canvas-to-document interaction tests** for tool dispatch and commit-on-mouse-up behavior.
- [ ] **Step 5: Run all tests and commit** with `feat: add non-destructive annotation editor`.

### Task 7: Rendering, image encoding, naming, save, and clipboard

**Files:**
- Create: `Wnip/Output/ImageRenderer.swift`
- Create: `Wnip/Output/OutputService.swift`
- Create: `Wnip/Output/FilenameResolver.swift`
- Create: `WnipTests/Output/ImageRendererTests.swift`
- Create: `WnipTests/Output/OutputServiceTests.swift`

**Interfaces:**
- Produces: `ImageRendering.render(source:crop:annotations:shadow:)`; `OutputServing.copy(_:)`, `save(_:preferences:)`; collision-free URL resolution.

- [ ] **Step 1: Write failing renderer tests** using small fixture images for crop dimensions, 2x scaling, each vector tool, source-only mosaic pixelation, transparent PNG, and region/window/full-screen shadow policy.
- [ ] **Step 2: Verify RED**, implement CoreGraphics/CoreImage rendering, and verify pixel assertions GREEN.
- [ ] **Step 3: Write failing output tests** for PNG/JPEG quality, default timestamp naming, unsafe-character cleanup, `-2`/`-3` collision resolution, bookmark failure, unwritable directories, and clipboard failure.
- [ ] **Step 4: Verify RED**, implement encoders, `NSPasteboard` output, security-scoped directory access, and injected save-panel fallback; verify GREEN.
- [ ] **Step 5: Run all tests and commit** with `feat: render and export screenshots`.

### Task 8: Coordinator, menu commands, preferences UI, and completion feedback

**Files:**
- Create: `Wnip/Capture/CaptureCoordinator.swift`
- Create: `Wnip/Preferences/PreferencesView.swift`
- Create: `Wnip/System/CompletionFeedbackService.swift`
- Modify: `Wnip/App/WnipApp.swift`
- Modify: `Wnip/App/AppDelegate.swift`
- Create: `WnipTests/Capture/CaptureCoordinatorTests.swift`

**Interfaces:**
- Consumes: all protocol-backed services from Tasks 3–7.
- Produces: a complete user flow from menu/global shortcut through permission, selection, editing, copy/save/cancel, feedback, and cleanup.

- [ ] **Step 1: Write failing coordinator tests** for the three modes, permission denial/recheck, repeat shortcut replacement, disconnected displays, retryable export failure, output success feedback, and guaranteed overlay cleanup.
- [ ] **Step 2: Verify RED**, implement the coordinator using the session reducer, and verify GREEN.
- [ ] **Step 3: Connect menu items and global shortcut** to coordinator commands; ensure hiding the menu icon preserves the hot key.
- [ ] **Step 4: Implement the single-page General preferences UI** for login, shadow policies, notification/sound, PNG/JPEG and quality, icon visibility, haptics, shortcut recorder, naming rule, and save directory.
- [ ] **Step 5: Implement notifications, sound, and haptics** behind `CompletionFeedbackServing`, respecting all preference flags.
- [ ] **Step 6: Run all automated tests and commit** with `feat: integrate complete screenshot workflow`.

### Task 9: Verification, privacy packaging, and manual acceptance

**Files:**
- Create: `Wnip/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `Wnip/Resources/Info.plist`
- Create: `docs/manual-acceptance.md`
- Modify: `project.yml`

**Interfaces:**
- Produces: a buildable app with privacy strings and a recorded acceptance matrix.

- [ ] **Step 1: Add privacy metadata** for screen capture and configure Hardened Runtime/App Sandbox entitlements needed for user-selected file access.
- [ ] **Step 2: Run static verification**: `xcodegen generate`, `xcodebuild clean build`, and the full test suite; expected result is zero build/test failures and zero warnings owned by Wnip.
- [ ] **Step 3: Execute the manual matrix** from the spec on one and multiple displays, including mixed scaling, all modes/tools, first-denied-then-granted permission, copy, PNG/JPEG save, shortcut conflict, settings relaunch persistence, and display disconnect behavior.
- [ ] **Step 4: Record results and any environment exceptions** in `docs/manual-acceptance.md`; unresolved required rows block release.
- [ ] **Step 5: Inspect exported images** to confirm Wnip UI exclusion, correct Retina dimensions, annotation rasterization, shadow policies, and no cached screenshot files.
- [ ] **Step 6: Commit** with `chore: complete Wnip release verification`.

