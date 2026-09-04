import AppKit
import Carbon
import XCTest
@testable import Wnip

@MainActor
final class ShortcutRecorderTests: XCTestCase {
    func testRecordedShortcutKeepsSupportedModifiersAndHardwareKeyCode() {
        let shortcut = ShortcutRecorderLogic.shortcut(
            keyCode: UInt16(kVK_ANSI_R),
            modifierFlags: [.command, .shift, .capsLock]
        )

        XCTAssertEqual(
            shortcut,
            HotKeyShortcut(
                keyCode: UInt32(kVK_ANSI_R),
                modifiers: UInt32(cmdKey | shiftKey)
            )
        )
    }

    func testRecordingAKeyWithoutModifiersIsRejected() {
        XCTAssertNil(
            ShortcutRecorderLogic.shortcut(
                keyCode: UInt16(kVK_ANSI_R),
                modifierFlags: []
            )
        )
    }

    func testDefaultShortcutLabelsUseMacModifierSymbolsAndKeyNames() {
        XCTAssertEqual(HotKeyShortcut.defaultRegionCapture.displayText, "⇧⌘X")
        XCTAssertEqual(HotKeyShortcut.defaultWindowCapture.displayText, "⇧⌘W")
    }

    func testClosingSettingsWindowEndsActiveShortcutRecording() {
        var recordingStates: [Bool] = []
        let button = ShortcutRecorderButton(
            shortcut: .defaultRegionCapture,
            onChange: { _ in },
            onRecordingChanged: { recordingStates.append($0) }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = button

        button.startRecording()
        window.close()

        XCTAssertEqual(recordingStates, [true, false])
    }
}
