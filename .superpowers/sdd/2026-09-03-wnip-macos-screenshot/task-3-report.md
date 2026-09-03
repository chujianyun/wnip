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
