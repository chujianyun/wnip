import Foundation
import XCTest
@testable import Wnip

final class PreferencesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsUseTheDocumentedCaptureShortcutFilenameRuleAndJPEGQuality() throws {
        let store = PreferencesStore(defaults: defaults)

        let preferences = try store.load()

        XCTAssertEqual(preferences.regionShortcut, .defaultRegionCapture)
        XCTAssertEqual(preferences.windowShortcut, .defaultWindowCapture)
        XCTAssertEqual(preferences.filenameRule, "Wnip-yyyy-MM-dd_HH-mm-ss")
        XCTAssertEqual(preferences.jpegQuality, 0.9)
        XCTAssertNil(preferences.saveDirectoryBookmark)
    }

    func testSavesCodablePreferencesAcrossStoreInstances() throws {
        let preferences = AppPreferences(
            regionShortcut: HotKeyShortcut(keyCode: 12, modifiers: 34),
            windowShortcut: HotKeyShortcut(keyCode: 13, modifiers: 35),
            filenameRule: "Shot-yyyy",
            jpegQuality: 0.42,
            saveDirectoryBookmark: Data([0xA, 0xB])
        )

        try PreferencesStore(defaults: defaults).save(preferences)

        XCTAssertEqual(try PreferencesStore(defaults: defaults).load(), preferences)
    }

    func testLoadsLegacyShortcutAsRegionShortcutAndUsesDefaultWindowShortcut() throws {
        let legacyShortcut = HotKeyShortcut(keyCode: 14, modifiers: 36)
        let legacyJSON = """
        {
          "shortcut": { "keyCode": 14, "modifiers": 36 },
          "filenameRule": "Legacy-yyyy",
          "jpegQuality": 0.75
        }
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: "com.wnip.preferences.appPreferences")

        let preferences = try PreferencesStore(defaults: defaults).load()

        XCTAssertEqual(preferences.regionShortcut, legacyShortcut)
        XCTAssertEqual(preferences.windowShortcut, .defaultWindowCapture)
        XCTAssertEqual(preferences.filenameRule, "Legacy-yyyy")
        XCTAssertEqual(preferences.jpegQuality, 0.75)
    }

    func testReplacingSaveDirectoryStoresTheNewSecurityScopedBookmark() throws {
        let firstDirectory = try makeDirectory(named: "first")
        let replacementDirectory = try makeDirectory(named: "replacement")
        let store = PreferencesStore(defaults: defaults)

        try store.replaceSaveDirectoryBookmark(for: firstDirectory)
        try store.replaceSaveDirectoryBookmark(for: replacementDirectory)

        let bookmark = try XCTUnwrap(store.load().saveDirectoryBookmark)
        var isStale = false
        let resolvedDirectory = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        XCTAssertFalse(isStale)
        XCTAssertEqual(resolvedDirectory.standardizedFileURL, replacementDirectory.standardizedFileURL)
    }

    private func makeDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreferencesStoreTests-\(UUID().uuidString)")
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
