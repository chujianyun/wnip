import AppKit
import Carbon
import XCTest
@testable import Wnip

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
}
