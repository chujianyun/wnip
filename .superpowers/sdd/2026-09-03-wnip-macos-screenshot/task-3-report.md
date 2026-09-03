# Task 3 Report: Preferences and System Services

## RED/GREEN evidence

### Preferences and initial hot-key API

RED command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/PreferencesStoreTests -only-testing:WnipTests/HotKeyServiceTests
```

RED output: `** TEST FAILED **`; the test target could not find
`HotKeyRegistrar`, `HotKeyRegistration`, or `HotKeyShortcut`, confirming the
new preferences/hot-key behavior was absent.

GREEN command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/PreferencesStoreTests -only-testing:WnipTests/HotKeyServiceTests
```

GREEN output: `** TEST SUCCEEDED **`; 5 tests executed with 0 failures. This
includes decoding a real replacement security-scoped bookmark and resolving it
back to the replacement directory.

### Hot-key invocation callback

RED command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/HotKeyServiceTests
```

RED output: `** TEST FAILED **`; `extra trailing closure passed in call`,
because `HotKeyService.register(_:handler:)` did not yet exist.

GREEN command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/HotKeyServiceTests
```

GREEN output: `** TEST SUCCEEDED **`; 3 tests executed with 0 failures,
including injected-registrar forwarding of a hot-key event and preservation of
the prior shortcut after a conflict.

### Final verification

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'
```

Output: `** TEST SUCCEEDED **`; 21 tests executed with 0 failures.

## Files changed

- `Wnip/Preferences/PreferencesStore.swift`
- `Wnip/System/PermissionService.swift`
- `Wnip/System/HotKeyService.swift`
- `Wnip/System/LaunchAtLoginService.swift`
- `WnipTests/Preferences/PreferencesStoreTests.swift`
- `WnipTests/System/HotKeyServiceTests.swift`

## Self-review

- `AppPreferences` has the required Command+Shift+X, filename, and JPEG
  quality defaults; `PreferencesStore` uses a namespaced `UserDefaults` key
  and Codable data.
- Bookmark replacement creates a real `.withSecurityScope` bookmark before
  mutating stored preferences. The test resolves the stored bookmark and
  verifies that it targets the replacement directory.
- `HotKeyService` registers a replacement before unregistering the old Carbon
  token, so a conflict cannot remove the existing shortcut. Carbon event
  delivery is routed to the handler passed by the coordinator/UI.
- The permission service only exposes authorization checks/request and the
  Privacy settings URL; it contains no UI presentation. Login-item failures
  are exposed as user-facing `LaunchAtLoginFailure` values.

## Concerns

- The test host emits pre-existing environment diagnostics for
  `com.apple.linkd.autoShortcut` and `/private/var/db/DetachedSignatures`.
  They did not affect compilation or test outcomes. The final suite passed
  all 21 tests.

## Review-fix round 1

### RED/GREEN evidence

RED command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/LaunchAtLoginServiceTests
```

RED output: `** TEST FAILED **`; the test target could not find
`LaunchAtLoginSystemControlling`, proving the controllable system boundary and
the idempotence/error-mapping behavior had not been implemented.

GREEN command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/LaunchAtLoginServiceTests -only-testing:WnipTests/HotKeyServiceTests
```

GREEN output: `** TEST SUCCEEDED **`; 6 tests executed with 0 failures.
`LaunchAtLoginServiceTests` exercises the real `LaunchAtLoginService` through
a controlled protocol boundary: enabled/unregistered requests are no-ops, and
the ServiceManagement approval, already-registered, not-registered, invalid
signature, and service-unavailable error codes map to distinct failures.

Final command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'
```

Final output: `** TEST SUCCEEDED **`; 24 tests executed with 0 failures.

### Fixes and covered files

- `Wnip/System/HotKeyService.swift`: marks the registration boundary, service,
  and Carbon registrar `@MainActor`. The C callback extracts only the hot-key
  identifier while the Carbon event is valid, then uses `Task { @MainActor in
  ... }` before accessing the handler dictionary; it does not use
  `MainActor.assumeIsolated`.
- `Wnip/System/PermissionService.swift`: marks the permission protocol and
  service `@MainActor`, documenting the required calling context for the
  screen-recording system APIs.
- `Wnip/System/LaunchAtLoginService.swift`: adds the injected
  `LaunchAtLoginSystemControlling` boundary, idempotent status checks, and
  actionable mappings for known ServiceManagement error codes.
- `WnipTests/System/HotKeyServiceTests.swift`: runs hot-key tests and the
  injected registrar on the main actor, validating the coordinator-facing
  contract under the new isolation rule.
- `WnipTests/System/LaunchAtLoginServiceTests.swift`: covers both idempotent
  operations and all requested mapped failures against the real public
  service.

### Self-review

- Mutable Carbon state (identifier counter, event handler, registrations, and
  handlers) is isolated to the main actor. The callback copies its primitive
  identifier before hopping, so it never captures the short-lived `EventRef`.
- The default production login-item boundary still calls `SMAppService.mainApp`;
  injection exists only at the system boundary, so tests exercise service
  behavior rather than a mocked mapping helper.
- `setEnabled(true)` when already `.enabled` and `setEnabled(false)` when
  already `.notRegistered` return before calling ServiceManagement.
- `HotKeyService` retains explicit `unregister()` cleanup. Its previous
  deinit cleanup was removed because Swift does not permit a deinitializer to
  invoke a main-actor-isolated method safely.

### Deferred minor suggestions

- Codable decoding of future `AppPreferences` schema fields currently remains
  strict, and stale security-scoped bookmark resolution/refresh is still
  deferred. Neither is required by this review round; both should be handled
  with a versioned preference migration/resolution API when an output consumer
  needs them.

### Review-round concerns

- The same host-only `linkd.autoShortcut` and detached-signature diagnostics
  appeared during Xcode tests. They did not affect the 24 passing tests.

## Review-fix round 2

### RED/GREEN evidence

RED command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/HotKeyServiceTests
```

RED output: `** TEST FAILED **`; the new
`testReleasingRegisteredServiceUnregistersItsShortcut` failed its final active
shortcut assertion after releasing `HotKeyService`.

GREEN command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/HotKeyServiceTests
```

GREEN output: `** TEST SUCCEEDED **`; 4 tests executed with 0 failures,
including the release/lifecycle regression.

Final command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'
```

Final output: `** TEST SUCCEEDED **`; 25 tests executed with 0 failures.

### Changed files and self-review

- `Wnip/System/HotKeyService.swift`: restores lifecycle cleanup. Deinitializing
  a service with a live registration captures only the registrar and token,
  then schedules `unregister` on the main actor. Explicit `unregister()` still
  clears the stored token first, so deinitialization does not schedule a
  duplicate release after normal cleanup.
- `WnipTests/System/HotKeyServiceTests.swift`: adds the focused regression
  test. It registers a shortcut, releases the only service reference, yields
  to the main actor for the cleanup task, and verifies the injected registrar
  no longer considers the shortcut active.

The deinitializer neither accesses Carbon mutable state directly nor uses
`MainActor.assumeIsolated`; the same explicit main-actor hop used for the C
callback preserves round-one isolation guarantees.

### Concerns

- Host-only `linkd.autoShortcut` and detached-signature diagnostics remained
  present during tests but did not affect the 25 passing tests.

## Review-fix round 3

### RED/GREEN evidence

RED command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/HotKeyServiceTests
```

RED output: `** TEST FAILED **`; the new
`testReleasingServiceAllowsImmediateReplacementRegistration` failed with
`XCTAssertNoThrow failed: threw error "conflict"`.

GREEN command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/HotKeyServiceTests
```

GREEN output: `** TEST SUCCEEDED **`; 5 tests executed with 0 failures,
including immediate replacement registration without yielding or sleeping.

Final command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'
```

Final output: `** TEST SUCCEEDED **`; 26 tests executed with 0 failures.

### Changed files and self-review

- `Wnip/System/HotKeyService.swift`: changes the service deinitializer to an
  `isolated deinit`. Xcode 17F113 accepts this under the project’s Swift 5
  language mode, and the deinitializer synchronously calls the main-actor
  registrar before the service is released. No unstructured cleanup task
  remains.
- `WnipTests/System/HotKeyServiceTests.swift`: removes the lifecycle test’s
  `Task.yield()` loop and adds a regression that releases a registered service
  and immediately registers the identical shortcut through a replacement
  service. The recording registrar now rejects duplicate active shortcuts, so
  the regression observes the actual cleanup ordering.

The public hot-key service and registrar remain main-actor isolated. The
Carbon callback continues to use its explicit main-actor task hop; only
already-isolated deinitialization synchronously invokes the registrar.

### Concerns

- Host-only `linkd.autoShortcut` and detached-signature diagnostics remained
  present during tests but did not affect the 26 passing tests.

## Review-fix round 4

### RED/GREEN evidence

RED command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/HotKeyServiceTests
```

RED output: `** TEST FAILED **`; the focused ownership regressions failed to
compile with `type 'HotKeyService' has no member 'shutdown'` and `type
'HotKeyService' has no member 'replace'`. This proved that callers had no
single, main-actor-isolated operation that released the old registration before
discarding or replacing the service.

GREEN command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS' -only-testing:WnipTests/HotKeyServiceTests
```

GREEN output: `** TEST SUCCEEDED **`; 5 tests executed with 0 failures. The
replacement regression uses a duplicate-rejecting registrar and immediately
registers the same shortcut on the replacement, with no sleep or actor yield.
The existing conflict rollback test also remains green.

Final command:

```sh
xcodegen generate && xcodebuild test -project Wnip.xcodeproj -scheme Wnip -destination 'platform=macOS'
```

Final output: `** TEST SUCCEEDED **`; 26 tests executed with 0 failures.

Build/install command:

```sh
xcodebuild install -project Wnip.xcodeproj -scheme Wnip -configuration Debug -destination 'platform=macOS' DSTROOT=/tmp/wnip-task3-round4.03DayS INSTALL_PATH=/Applications
```

Output: `** INSTALL SUCCEEDED **`; the built app was installed at
`/tmp/wnip-task3-round4.03DayS/Applications/Wnip.app`. Launching that app's
executable produced a live `Wnip` process (PID 58635) with bundle identifier
`com.wnip.app`; it was then stopped after the smoke check.

### Changed files and self-review

- `Wnip/System/HotKeyService.swift`: replaces the Swift 6.2-only `isolated
  deinit` assumption with explicit `replace(_:with:)` and `shutdown(_:)`
  ownership operations. Because `HotKeyService` is `@MainActor`, each operation
  synchronously unregisters before updating the owner's reference. A same-object
  replacement is a no-op. Plain `deinit` retains only asynchronous best-effort
  cleanup and is explicitly documented as unsuitable for ordering.
- `WnipTests/System/HotKeyServiceTests.swift`: replaces tests that incorrectly
  treated final release as a synchronous lifecycle boundary with focused tests
  for deterministic shutdown and immediate same-shortcut replacement.

The regression's mutation check is direct: deleting `current?.unregister()`
from `replace(_:with:)` makes immediate registration throw `conflict`.
`unregister()` clears the stored registration before the old instance is
released, so its best-effort deinitializer cannot schedule duplicate cleanup.
No compiler or language-version setting changed; `project.yml` remains on
Swift 5.0 and macOS 15.

### Concerns

- Future coordinators must use `HotKeyService.replace`/`shutdown` at ownership
  boundaries. Directly assigning `nil` or replacing a service reference still
  receives only best-effort asynchronous deinitializer cleanup, by design;
  Swift does not guarantee synchronous arbitrary off-actor destruction.
- The existing host-only `com.apple.linkd.autoShortcut` and detached-signature
  diagnostics remained during tests. The install build also reports the
  pre-existing missing App Category warning. None affected test, install, or
  launch results.
