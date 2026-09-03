import XCTest
@testable import Wnip

final class HotKeyServiceTests: XCTestCase {
    func testRegisteringShortcutMakesItCurrent() throws {
        let registrar = RecordingRegistrar()
        let service = HotKeyService(registrar: registrar)
        let shortcut = HotKeyShortcut(keyCode: 7, modifiers: 3)

        try service.register(shortcut)

        XCTAssertEqual(service.shortcut, shortcut)
        XCTAssertEqual(registrar.activeShortcuts, [shortcut])
    }

    func testConflictingShortcutPreservesThePreviouslyRegisteredShortcut() throws {
        let previousShortcut = HotKeyShortcut(keyCode: 7, modifiers: 3)
        let conflictingShortcut = HotKeyShortcut(keyCode: 8, modifiers: 3)
        let registrar = RecordingRegistrar(conflictingShortcuts: [conflictingShortcut])
        let service = HotKeyService(registrar: registrar)
        try service.register(previousShortcut)

        XCTAssertThrowsError(try service.register(conflictingShortcut))

        XCTAssertEqual(service.shortcut, previousShortcut)
        XCTAssertEqual(registrar.activeShortcuts, [previousShortcut])
    }

    func testRegisteredShortcutForwardsItsPressToTheCaller() throws {
        let registrar = RecordingRegistrar()
        let service = HotKeyService(registrar: registrar)
        let shortcut = HotKeyShortcut(keyCode: 7, modifiers: 3)
        var invocationCount = 0

        try service.register(shortcut) {
            invocationCount += 1
        }
        registrar.trigger(shortcut)

        XCTAssertEqual(invocationCount, 1)
    }
}

private final class RecordingRegistrar: HotKeyRegistrar {
    private final class Registration: HotKeyRegistration {
        let shortcut: HotKeyShortcut

        init(shortcut: HotKeyShortcut) {
            self.shortcut = shortcut
        }
    }

    private let conflictingShortcuts: Set<HotKeyShortcut>
    private(set) var activeShortcuts: [HotKeyShortcut] = []
    private var handlers: [HotKeyShortcut: () -> Void] = [:]

    init(conflictingShortcuts: Set<HotKeyShortcut> = []) {
        self.conflictingShortcuts = conflictingShortcuts
    }

    func register(_ shortcut: HotKeyShortcut) throws -> any HotKeyRegistration {
        guard !conflictingShortcuts.contains(shortcut) else {
            throw HotKeyFailure.conflict
        }
        activeShortcuts.append(shortcut)
        return Registration(shortcut: shortcut)
    }

    func unregister(_ registration: any HotKeyRegistration) {
        guard let registration = registration as? Registration else { return }
        activeShortcuts.removeAll { $0 == registration.shortcut }
    }

    func register(_ shortcut: HotKeyShortcut, handler: @escaping () -> Void) throws -> any HotKeyRegistration {
        let registration = try register(shortcut)
        handlers[shortcut] = handler
        return registration
    }

    func trigger(_ shortcut: HotKeyShortcut) {
        handlers[shortcut]?()
    }
}
