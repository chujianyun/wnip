# Wnip Capture Entrypoints and Shortcut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Wnip's menu and global shortcut to working capture-selection overlays and add a native shortcut recorder to Settings.

**Architecture:** A main-actor `CaptureCoordinator` owns the permission, capture-content, overlay, hot-key, and preferences services. SwiftUI obtains one coordinator from `AppDelegate`, routes menu commands through it, and binds a focused shortcut-recorder control to its persisted shortcut state.

**Tech Stack:** Swift 5, SwiftUI, AppKit, Carbon hot keys, ScreenCaptureKit, XCTest, XcodeGen, macOS 15+

**Spec:** `docs/superpowers/specs/2026-09-03-capture-entrypoints-and-shortcut-design.md`

## Global Constraints

- Minimum supported system remains macOS 15 Sequoia.
- The default global region-capture shortcut remains `⇧⌘X`.
- A failed replacement shortcut must preserve both the old registration and old persisted preference.
- Only selection entry is completed here; annotation, copy, and save remain outside this change.
- Every production behavior begins with a failing automated test.
- After tests, produce a Release app, install it at `/Applications/Wnip.app`, launch it, and verify the live process and UI entry points.

---

### Task 1: Capture Coordinator Selection Flow

**Files:**
- Create: `Wnip/App/CaptureCoordinator.swift`
- Create: `WnipTests/App/CaptureCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ScreenRecordingAuthorizing`, `ScreenCapturing`, `OverlayControlling`, `HotKeyRegistering`, `PreferencesStoring`, `CaptureMode`, `OverlayPresentation`, `OverlayCallbacks`
- Produces: `@MainActor final class CaptureCoordinator: ObservableObject`, `func startCapture(mode: CaptureMode)`, `func cancelCapture()`, `func start()`

- [ ] **Step 1: Write failing coordinator tests**

Create fakes for the five protocols and tests that assert: authorized `startCapture(mode: .region)` requests content and presents `.region`; `.window` and `.fullScreen` preserve their requested mode; denied permission does not present; calling `cancelCapture()` dismisses overlays; a second request cancels the first task before presenting only the newest result.

```swift
@MainActor
func testAuthorizedRegionRequestPresentsRegionOverlay() async {
    let screen = ScreenCaptureFake(content: .fixture)
    let overlay = OverlayFake()
    let coordinator = makeCoordinator(permissionGranted: true, screen: screen, overlay: overlay)

    coordinator.startCapture(mode: .region)
    await coordinator.waitForPendingCaptureForTesting()

    XCTAssertEqual(screen.availableContentCallCount, 1)
    XCTAssertEqual(overlay.presentations.map(\.mode), [.region])
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/CaptureCoordinatorTests`

Expected: build failure because `CaptureCoordinator` and its testing wait hook do not exist.

- [ ] **Step 3: Implement the minimal coordinator**

Implement injected initializers and production defaults. `start()` loads preferences and registers the persisted shortcut with a handler that calls `startCapture(mode: .region)`. `startCapture` cancels the old `Task`, dismisses overlays, checks/request permission, obtains `CaptureContent`, and presents an `OverlayPresentation` with callbacks whose `onCancel` calls `cancelCapture()`. Store a monotonically increasing request ID so stale task completions cannot present.

```swift
@MainActor
final class CaptureCoordinator: ObservableObject {
    @Published private(set) var shortcut: HotKeyShortcut = .defaultCapture
    @Published var presentedError: CaptureCoordinatorError?
    private var captureTask: Task<Void, Never>?
    private var requestID = 0

    func startCapture(mode: CaptureMode) {
        requestID += 1
        let currentID = requestID
        captureTask?.cancel()
        overlay.dismissAll()
        captureTask = Task { [weak self] in
            guard let self else { return }
            guard permission.isAuthorized() || permission.requestAuthorization() else {
                presentedError = .permissionDenied(permission.privacySettingsURL)
                return
            }
            do {
                let content = try await screen.availableContent()
                guard !Task.isCancelled, currentID == requestID else { return }
                overlay.present(
                    OverlayPresentation(mode: mode, displays: content.displays, windows: content.windows),
                    callbacks: OverlayCallbacks(onCancel: { [weak self] in self?.cancelCapture() })
                )
            } catch {
                guard !Task.isCancelled, currentID == requestID else { return }
                presentedError = .captureFailed(error.localizedDescription)
            }
        }
    }
}
```

- [ ] **Step 4: Run focused and full tests**

Run the focused command from Step 2, then:

`xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'`

Expected: all tests pass.

- [ ] **Step 5: Commit the coordinator**

```bash
git add Wnip/App/CaptureCoordinator.swift WnipTests/App/CaptureCoordinatorTests Wnip.xcodeproj/project.pbxproj
git commit -m "feat: coordinate capture selection entrypoints"
```

---

### Task 2: Shortcut Parsing and Transactional Update

**Files:**
- Create: `Wnip/System/ShortcutRecorder.swift`
- Modify: `Wnip/App/CaptureCoordinator.swift`
- Create: `WnipTests/System/ShortcutRecorderTests.swift`
- Modify: `WnipTests/App/CaptureCoordinatorTests.swift`

**Interfaces:**
- Consumes: `HotKeyShortcut`, `HotKeyRegistering`, `PreferencesStoring`
- Produces: `enum ShortcutRecordingResult`, `ShortcutRecorder.parse(keyCode:modifiers:)`, `CaptureCoordinator.updateShortcut(_:) throws`, `CaptureCoordinator.shortcutLabel`

- [ ] **Step 1: Write failing shortcut parser tests**

Test that key code `7` plus Command and Shift produces a shortcut, modifier-only key codes and no-modifier events are ignored, and key code `53` returns cancel.

```swift
func testCommandShiftXProducesShortcut() {
    let result = ShortcutRecorder.parse(
        keyCode: 7,
        modifiers: [.command, .shift]
    )
    XCTAssertEqual(result, .shortcut(.defaultCapture))
}
```

- [ ] **Step 2: Run parser tests and verify RED**

Run: `xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/ShortcutRecorderTests`

Expected: build failure because `ShortcutRecorder` is undefined.

- [ ] **Step 3: Implement event parsing and labels**

Map `NSEvent.ModifierFlags` to Carbon flags, require at least one of Command/Option/Control/Shift, return `.cancel` for Escape, and ignore modifier-only key codes. Add a display formatter using ordered glyphs `⌃⌥⇧⌘` plus the key equivalent for common letter, digit, arrow, Space, Return, and function keys.

- [ ] **Step 4: Write failing transactional update tests**

Assert that `updateShortcut` registers first and persists only after success. Configure the fake registrar to throw `HotKeyFailure.conflict`; assert the coordinator's shortcut, stored preferences, and original fake registration remain unchanged.

- [ ] **Step 5: Run coordinator update tests and verify RED**

Run: `xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/CaptureCoordinatorTests`

Expected: build failure because `updateShortcut(_:)` is undefined.

- [ ] **Step 6: Implement transactional shortcut replacement**

```swift
func updateShortcut(_ replacement: HotKeyShortcut) throws {
    try hotKey.register(replacement) { [weak self] in
        self?.startCapture(mode: .region)
    }
    var updated = preferences
    updated.shortcut = replacement
    do {
        try preferencesStore.save(updated)
        preferences = updated
        shortcut = replacement
    } catch {
        try? hotKey.register(shortcut) { [weak self] in
            self?.startCapture(mode: .region)
        }
        throw error
    }
}
```

- [ ] **Step 7: Run focused and full tests**

Run both focused suites, then the full `xcodebuild test` command from Task 1.

Expected: all tests pass.

- [ ] **Step 8: Commit shortcut domain behavior**

```bash
git add Wnip/System/ShortcutRecorder.swift Wnip/App/CaptureCoordinator.swift WnipTests/System/ShortcutRecorderTests.swift WnipTests/App/CaptureCoordinatorTests.swift Wnip.xcodeproj/project.pbxproj
git commit -m "feat: record and persist capture shortcut"
```

---

### Task 3: Wire Menu Commands and Settings UI

**Files:**
- Modify: `Wnip/App/AppDelegate.swift`
- Modify: `Wnip/App/WnipApp.swift`
- Create: `Wnip/Preferences/PreferencesView.swift`
- Create: `Wnip/Preferences/ShortcutRecorderView.swift`
- Create: `WnipTests/App/AppDelegateTests.swift`

**Interfaces:**
- Consumes: `CaptureCoordinator.start()`, `startCapture(mode:)`, `updateShortcut(_:)`, `shortcutLabel`, `presentedError`
- Produces: one process-lifetime coordinator, functional menu actions, a focusable AppKit-backed recorder, and actionable permission/shortcut error UI

- [ ] **Step 1: Write a failing lifecycle ownership test**

Verify that `AppDelegate` exposes one stable coordinator instance and `applicationDidFinishLaunching` calls `start()` exactly once through an injected lifecycle abstraction.

- [ ] **Step 2: Run the lifecycle test and verify RED**

Run: `xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/AppDelegateTests`

Expected: build failure because lifecycle injection and the coordinator property do not exist.

- [ ] **Step 3: Give AppDelegate process-lifetime ownership**

Add `let coordinator = CaptureCoordinator()` and call `coordinator.start()` after setting accessory activation policy. Keep a test initializer that accepts a coordinator conforming to a narrow `CaptureCoordinating` protocol.

- [ ] **Step 4: Implement the recorder control**

Create `ShortcutRecorderView: NSViewRepresentable` backed by an `NSView` that accepts first responder, handles `keyDown(with:)`, passes parsed shortcuts to a closure, and exits recording on Escape. Draw its focus state with SwiftUI around the representable; do not install a global event monitor while editing.

- [ ] **Step 5: Replace empty menu closures and placeholder Settings**

Bind menu actions directly to the AppDelegate coordinator:

```swift
Button("Capture Region") { appDelegate.coordinator.startCapture(mode: .region) }
Button("Capture Window") { appDelegate.coordinator.startCapture(mode: .window) }
Button("Capture Full Screen") { appDelegate.coordinator.startCapture(mode: .fullScreen) }
```

Use `PreferencesView(coordinator: appDelegate.coordinator)` in `Settings`. Show the current shortcut, recorder state, conflict text, and a button that opens `permission.privacySettingsURL` for permission denial.

- [ ] **Step 6: Run focused and full tests**

Run the lifecycle suite, shortcut suite, coordinator suite, and finally the full test command.

Expected: all tests pass and the app target compiles without warnings introduced by these files.

- [ ] **Step 7: Commit UI wiring**

```bash
git add Wnip/App/AppDelegate.swift Wnip/App/WnipApp.swift Wnip/Preferences/PreferencesView.swift Wnip/Preferences/ShortcutRecorderView.swift WnipTests/App/AppDelegateTests.swift Wnip.xcodeproj/project.pbxproj
git commit -m "feat: wire capture menu and shortcut settings"
```

---

### Task 4: Release, Install, Launch, and Runtime Verification

**Files:**
- Modify only if verification reveals an issue in files from Tasks 1-3.

**Interfaces:**
- Consumes: completed Wnip application
- Produces: installed and running `/Applications/Wnip.app`

- [ ] **Step 1: Regenerate and run the complete suite**

Run:

```bash
xcodegen generate
xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'
```

Expected: `** TEST SUCCEEDED **` with zero failures.

- [ ] **Step 2: Produce a clean Release build**

Run:

```bash
xcodebuild -project Wnip.xcodeproj -scheme Wnip -configuration Release -destination 'platform=macOS' -derivedDataPath build/DerivedData clean build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Replace the installed app and launch it**

Quit a running Wnip instance, move an existing `/Applications/Wnip.app` to a uniquely named item in `/Users/wuming/.Trash`, copy the Release bundle with `ditto`, and run `open -a /Applications/Wnip.app`.

- [ ] **Step 4: Verify the running bundle**

Run `pgrep -fl '/Applications/Wnip.app/Contents/MacOS/Wnip'`, `codesign --verify --deep --strict --verbose=2 /Applications/Wnip.app`, and confirm `AppIcon.icns` plus `Assets.car` exist.

- [ ] **Step 5: Verify live interactions**

Use macOS UI automation or direct manual interaction to verify: opening Settings shows the recorder; clicking Region creates overlay windows; Escape dismisses them; pressing `⇧⌘X` creates overlays; Window and Full Screen commands enter their distinct modes. If Screen Recording permission is unavailable, verify the permission alert and System Settings action instead, then authorize and repeat.

- [ ] **Step 6: Record final evidence**

Report the exact test count, build result, installed path, running PID, and which live entry-point checks passed. Preserve unrelated pre-existing worktree changes.
