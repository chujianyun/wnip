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
