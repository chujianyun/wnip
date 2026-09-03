import Foundation

struct AppPreferences: Codable, Equatable, Sendable {
    static let defaultFilenameRule = "Wnip-yyyy-MM-dd_HH-mm-ss"
    static let defaultJPEGQuality = 0.9

    var shortcut: HotKeyShortcut
    var filenameRule: String
    var jpegQuality: Double
    var saveDirectoryBookmark: Data?

    init(
        shortcut: HotKeyShortcut = .defaultCapture,
        filenameRule: String = AppPreferences.defaultFilenameRule,
        jpegQuality: Double = AppPreferences.defaultJPEGQuality,
        saveDirectoryBookmark: Data? = nil
    ) {
        self.shortcut = shortcut
        self.filenameRule = filenameRule
        self.jpegQuality = jpegQuality
        self.saveDirectoryBookmark = saveDirectoryBookmark
    }
}

protocol PreferencesStoring {
    func load() throws -> AppPreferences
    func save(_ preferences: AppPreferences) throws
    func replaceSaveDirectoryBookmark(for directory: URL) throws
}

enum PreferencesStoreFailure: LocalizedError, Equatable {
    case invalidStoredPreferences

    var errorDescription: String? {
        switch self {
        case .invalidStoredPreferences:
            return "Saved preferences could not be read."
        }
    }
}

final class PreferencesStore: PreferencesStoring {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard, key: String = "com.wnip.preferences.appPreferences") {
        self.defaults = defaults
        self.key = key
    }

    func load() throws -> AppPreferences {
        guard let data = defaults.data(forKey: key) else { return AppPreferences() }

        do {
            return try decoder.decode(AppPreferences.self, from: data)
        } catch {
            throw PreferencesStoreFailure.invalidStoredPreferences
        }
    }

    func save(_ preferences: AppPreferences) throws {
        defaults.set(try encoder.encode(preferences), forKey: key)
    }

    func replaceSaveDirectoryBookmark(for directory: URL) throws {
        let bookmark = try directory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var preferences = try load()
        preferences.saveDirectoryBookmark = bookmark
        try save(preferences)
    }
}
