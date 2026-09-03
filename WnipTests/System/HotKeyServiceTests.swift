import XCTest
@testable import Wnip

@MainActor
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

    func testReleasingRegisteredServiceUnregistersItsShortcut() throws {
        let registrar = RecordingRegistrar()
        let shortcut = HotKeyShortcut(keyCode: 7, modifiers: 3)
        var service: HotKeyService? = HotKeyService(registrar: registrar)
        try service?.register(shortcut)
        XCTAssertEqual(registrar.activeShortcuts, [shortcut])

        service = nil

        XCTAssertTrue(registrar.activeShortcuts.isEmpty)
    }

    func testReleasingServiceAllowsImmediateReplacementRegistration() throws {
        let registrar = RecordingRegistrar()
        let shortcut = HotKeyShortcut(keyCode: 7, modifiers: 3)
        var firstService: HotKeyService? = HotKeyService(registrar: registrar)
        try firstService?.register(shortcut)

        firstService = nil
        let replacementService = HotKeyService(registrar: registrar)

        XCTAssertNoThrow(try replacementService.register(shortcut))
    }
}

@MainActor
private final class RecordingRegistrar: HotKeyRegistrar {
    private final class Registration: HotKeyRegistration {
        let shortcut: HotKeyShortcut

        init(shortcut: HotKeyShortcut) {
            self.shortcut = shortcut
        }
    }

    private let conflictingShortcuts: Set<HotKeyShortcut>
    private(set) var activeShortcuts: [HotKeyShortcut] = []
    private var handlers: [HotKeyShortcut: @MainActor () -> Void] = [:]

    init(conflictingShortcuts: Set<HotKeyShortcut> = []) {
        self.conflictingShortcuts = conflictingShortcuts
    }

    func register(_ shortcut: HotKeyShortcut) throws -> any HotKeyRegistration {
        guard !conflictingShortcuts.contains(shortcut), !activeShortcuts.contains(shortcut) else {
            throw HotKeyFailure.conflict
        }
        activeShortcuts.append(shortcut)
        return Registration(shortcut: shortcut)
    }

    func unregister(_ registration: any HotKeyRegistration) {
        guard let registration = registration as? Registration else { return }
        activeShortcuts.removeAll { $0 == registration.shortcut }
    }

    func register(_ shortcut: HotKeyShortcut, handler: @escaping @MainActor () -> Void) throws -> any HotKeyRegistration {
        let registration = try register(shortcut)
        handlers[shortcut] = handler
        return registration
    }

    func trigger(_ shortcut: HotKeyShortcut) {
        handlers[shortcut]?()
    }
}
