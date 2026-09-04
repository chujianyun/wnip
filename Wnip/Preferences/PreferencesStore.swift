import Foundation

struct AppPreferences: Codable, Equatable, Sendable {
    static let defaultFilenameRule = "Wnip-yyyy-MM-dd_HH-mm-ss"
    static let defaultJPEGQuality = 0.9

    var regionShortcut: HotKeyShortcut
    var windowShortcut: HotKeyShortcut
    var filenameRule: String
    var jpegQuality: Double
    var saveDirectoryBookmark: Data?

    init(
        regionShortcut: HotKeyShortcut = .defaultRegionCapture,
        windowShortcut: HotKeyShortcut = .defaultWindowCapture,
        filenameRule: String = AppPreferences.defaultFilenameRule,
        jpegQuality: Double = AppPreferences.defaultJPEGQuality,
        saveDirectoryBookmark: Data? = nil
    ) {
        self.regionShortcut = regionShortcut
        self.windowShortcut = windowShortcut
        self.filenameRule = filenameRule
        self.jpegQuality = jpegQuality
        self.saveDirectoryBookmark = saveDirectoryBookmark
    }

    private enum CodingKeys: String, CodingKey {
        case regionShortcut
        case windowShortcut
        case shortcut
        case filenameRule
        case jpegQuality
        case saveDirectoryBookmark
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        regionShortcut = try container.decodeIfPresent(HotKeyShortcut.self, forKey: .regionShortcut)
            ?? container.decodeIfPresent(HotKeyShortcut.self, forKey: .shortcut)
            ?? .defaultRegionCapture
        if let storedWindowShortcut = try container.decodeIfPresent(
            HotKeyShortcut.self,
            forKey: .windowShortcut
        ) {
            windowShortcut = storedWindowShortcut
        } else {
            windowShortcut = regionShortcut == .defaultWindowCapture
                ? .defaultRegionCapture
                : .defaultWindowCapture
        }
        filenameRule = try container.decodeIfPresent(String.self, forKey: .filenameRule)
            ?? Self.defaultFilenameRule
        jpegQuality = try container.decodeIfPresent(Double.self, forKey: .jpegQuality)
            ?? Self.defaultJPEGQuality
        saveDirectoryBookmark = try container.decodeIfPresent(Data.self, forKey: .saveDirectoryBookmark)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(regionShortcut, forKey: .regionShortcut)
        try container.encode(windowShortcut, forKey: .windowShortcut)
        try container.encode(filenameRule, forKey: .filenameRule)
        try container.encode(jpegQuality, forKey: .jpegQuality)
        try container.encodeIfPresent(saveDirectoryBookmark, forKey: .saveDirectoryBookmark)
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
