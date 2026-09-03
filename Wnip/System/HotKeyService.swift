import Carbon
import Foundation

struct HotKeyShortcut: Codable, Equatable, Hashable, Sendable {
    static let defaultCapture = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_X),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

enum HotKeyFailure: LocalizedError, Equatable {
    case conflict
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .conflict:
            return "That global shortcut is already in use."
        case .registrationFailed:
            return "The global shortcut could not be registered."
        }
    }
}

protocol HotKeyRegistration: AnyObject {}

@MainActor
protocol HotKeyRegistrar: AnyObject {
    func register(_ shortcut: HotKeyShortcut, handler: @escaping @MainActor () -> Void) throws -> any HotKeyRegistration
    func unregister(_ registration: any HotKeyRegistration)
}

extension HotKeyRegistrar {
    func register(_ shortcut: HotKeyShortcut) throws -> any HotKeyRegistration {
        try register(shortcut, handler: {})
    }
}

@MainActor
protocol HotKeyRegistering: AnyObject {
    var shortcut: HotKeyShortcut? { get }

    func register(_ shortcut: HotKeyShortcut) throws
    func register(_ shortcut: HotKeyShortcut, handler: @escaping @MainActor () -> Void) throws
    func unregister()
}

@MainActor
final class HotKeyService: HotKeyRegistering {
    private let registrar: any HotKeyRegistrar
    private var registration: (any HotKeyRegistration)?
    private var handler: (@MainActor () -> Void)?
    private(set) var shortcut: HotKeyShortcut?

    init() {
        self.registrar = CarbonHotKeyRegistrar.shared
    }

    init(registrar: any HotKeyRegistrar) {
        self.registrar = registrar
    }

    deinit {
        guard let registration else { return }
        let registrar = registrar
        Task { @MainActor in
            registrar.unregister(registration)
        }
    }

    func register(_ shortcut: HotKeyShortcut) throws {
        try register(shortcut, handler: {})
    }

    func register(_ shortcut: HotKeyShortcut, handler: @escaping @MainActor () -> Void) throws {
        if self.shortcut == shortcut {
            self.handler = handler
            return
        }

        // Register first so a conflict cannot discard the shortcut already
        // serving the user. Only after success do we retire the old token.
        let replacement = try registrar.register(shortcut) { [weak self] in
            self?.handler?()
        }
        if let registration {
            registrar.unregister(registration)
        }
        registration = replacement
        self.shortcut = shortcut
        self.handler = handler
    }

    func unregister() {
        guard let registration else { return }
        registrar.unregister(registration)
        self.registration = nil
        handler = nil
        shortcut = nil
    }
}

@MainActor
final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    static let shared = CarbonHotKeyRegistrar()

    private var nextIdentifier: UInt32 = 1

    private init() {}

    func register(_ shortcut: HotKeyShortcut, handler: @escaping @MainActor () -> Void) throws -> any HotKeyRegistration {
        try installEventHandlerIfNeeded()

        let identifier = EventHotKeyID(signature: OSType(0x574E4950), id: nextIdentifier)
        nextIdentifier &+= 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            if status == eventHotKeyExistsErr {
                throw HotKeyFailure.conflict
            }
            throw HotKeyFailure.registrationFailed(status)
        }
        handlers[identifier.id] = handler
        return CarbonRegistration(identifier: identifier.id, reference: reference)
    }

    func unregister(_ registration: any HotKeyRegistration) {
        guard let registration = registration as? CarbonRegistration else { return }
        UnregisterEventHotKey(registration.reference)
        handlers.removeValue(forKey: registration.identifier)
    }

    private var eventHandler: EventHandlerRef?
    private var handlers: [UInt32: @MainActor () -> Void] = [:]

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        guard status == noErr else {
            throw HotKeyFailure.registrationFailed(status)
        }
    }

    fileprivate func handlePress(identifier: UInt32) {
        handlers[identifier]?()
    }

    private final class CarbonRegistration: HotKeyRegistration {
        let identifier: UInt32
        let reference: EventHotKeyRef

        init(identifier: UInt32, reference: EventHotKeyRef) {
            self.identifier = identifier
            self.reference = reference
        }
    }
}

private func carbonHotKeyEventHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let identifier = carbonHotKeyIdentifier(from: event) else { return noErr }
    Task { @MainActor in
        CarbonHotKeyRegistrar.shared.handlePress(identifier: identifier)
    }
    return noErr
}

private func carbonHotKeyIdentifier(from event: EventRef) -> UInt32? {
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    return status == noErr ? identifier.id : nil
}
