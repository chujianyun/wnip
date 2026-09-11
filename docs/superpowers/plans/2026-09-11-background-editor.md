# Screenshot Background Editor Implementation Plan

**Goal:** Add a menu capture entry that opens a live background editor after annotation, with reliable full-resolution export and saved defaults.
**Architecture:** CaptureCoordinator routes a per-capture intent to a retained editor window. BackgroundStyle and BackgroundRenderer own layout and compositing. A separate defaults/assets store keeps the existing preferences schema unchanged.
**Tech Stack:** Swift, SwiftUI, AppKit, CoreGraphics, ImageIO; macOS 15+; no new dependencies.
**Spec:** User-approved design in this task, 2026-09-11.

## Constraints
- Region/window/full-screen entry; annotation completes before background editing.
- Solid/gradient/image backgrounds, six gradients including teal multi-corner aurora, bundled image choices and local PNG/JPEG/HEIC import.
- Auto/1:1/4:3/3:2/16:9/9:16/custom canvas; preserve source aspect; padding, radius, shadow and white border.
- Explicit save/reset defaults; persist imported background independently of source path.
- Shared preview/export renderer, bounded memory, source pixels used for export.
- Preserve pre-existing unstaged/staged work. Deliver only this feature. Tests/build → stop all Wnip → replace /Applications/Wnip.app → open exact path and inspect UI → commit/merge/push main.

## Execution
- [x] Model/renderer: BackgroundStyle.swift (validated settings, preset colors, layout), BackgroundRenderer.swift (opaque sRGB background, image aspect fill, clipped screenshot and shadow). Add pixel/layout tests for aspect ratios, corners, image direction and invalid values.
- [x] Defaults/assets: BackgroundStore.swift stores JSON defaults and normalized imported images in Application Support. Test reload, reset and source-file removal; recover missing image with an explicit message.
- [x] Window/UI: BackgroundEditor.swift and BackgroundEditorView.swift, retained NSWindow, source and preview model, debounced rendering, scrolling controls, import, copy/save, default/reset and error state. Keep source after cancelled/failed export.
- [x] Routing: modify WnipApp, CaptureCoordinator, OverlayPresentation and AnnotationToolbar to add capture intent and a clear next-step action without changing ordinary capture output. Test all capture modes and cancellation.
- [ ] Verify: xcodegen generate; xcodebuild test for arm64; signed Release build with installed identity; visual/function inspection of canonical installed app; write docs/test-reports/2026-09-11-background-editor.md.
- [ ] Delivery: validate previous signature requirement against candidate, stop exact verified Wnip processes, complete bundle replacement and launch; commit only feature, merge main preserving pre-existing edits, push and verify SHA.

Execution note: 185 automated tests passed; Release installed and running. UI inspection is blocked by status-menu automation. User explicitly requested proceeding with remote push and GitHub v0.2.0 publication with that verification limit recorded.
