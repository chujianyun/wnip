import AppKit
import Carbon
import SwiftUI

enum ShortcutRecorderLogic {
    static func shortcut(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> HotKeyShortcut? {
        var modifiers: UInt32 = 0
        if modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers != 0 else { return nil }
        return HotKeyShortcut(keyCode: UInt32(keyCode), modifiers: modifiers)
    }
}

extension HotKeyShortcut {
    var displayText: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyNames[keyCode, default: "Key \(keyCode)"]
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab", UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Home): "Home",
        UInt32(kVK_End): "End", UInt32(kVK_PageUp): "Page Up",
        UInt32(kVK_PageDown): "Page Down", UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓"
    ]
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: HotKeyShortcut
    let onChange: (HotKeyShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton(shortcut: shortcut, onChange: onChange)
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.shortcut = shortcut
        button.onChange = onChange
    }
}

final class ShortcutRecorderButton: NSButton {
    var shortcut: HotKeyShortcut {
        didSet { if !isRecording { title = shortcut.displayText } }
    }
    var onChange: (HotKeyShortcut) -> Void
    private var isRecording = false

    init(shortcut: HotKeyShortcut, onChange: @escaping (HotKeyShortcut) -> Void) {
        self.shortcut = shortcut
        self.onChange = onChange
        super.init(frame: .zero)
        title = shortcut.displayText
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        title = "Type Shortcut"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            finishRecording()
            return
        }
        guard let recorded = ShortcutRecorderLogic.shortcut(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            NSSound.beep()
            return
        }
        onChange(recorded)
        finishRecording(displaying: recorded)
    }

    override func resignFirstResponder() -> Bool {
        finishRecording()
        return super.resignFirstResponder()
    }

    private func finishRecording(displaying recorded: HotKeyShortcut? = nil) {
        isRecording = false
        title = (recorded ?? shortcut).displayText
    }
}
