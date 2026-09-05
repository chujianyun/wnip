import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum ScreenshotFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case png
    case jpeg

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }
}

enum OutputFailure: LocalizedError, Equatable {
    case encodingFailed
    case clipboardFailed
    case cancelled
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "The screenshot could not be encoded."
        case .clipboardFailed:
            return "The clipboard rejected the screenshot."
        case .cancelled:
            return "Saving was cancelled."
        case .writeFailed(let message):
            return message
        }
    }
}

/// Encodes the composited bitmap. JPEG cannot carry alpha, so shadowed exports
/// are flattened onto white before encoding.
struct ImageEncoder: Sendable {
    func encode(_ image: CGImage, format: ScreenshotFormat, jpegQuality: Double) throws -> Data {
        let resolved = format == .jpeg ? flattening(image) : image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            format.contentType.identifier as CFString,
            1,
            nil
        ) else { throw OutputFailure.encodingFailed }

        let options: [CFString: Any] = format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: min(1, max(0, jpegQuality))]
            : [:]
        CGImageDestinationAddImage(destination, resolved, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw OutputFailure.encodingFailed
        }
        return data as Data
    }

    private func flattening(_ image: CGImage) -> CGImage {
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }
}

@MainActor
protocol PasteboardWriting {
    func writePNG(_ data: Data) -> Bool
}

@MainActor
final class SystemPasteboard: PasteboardWriting {
    nonisolated init() {}

    func writePNG(_ data: Data) -> Bool {
        guard !data.isEmpty, let image = NSImage(data: data) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }
}

@MainActor
protocol SavePanelChoosing {
    func chooseDestination(suggestedFilename: String, format: ScreenshotFormat) -> URL?
}

@MainActor
final class SavePanelChooser: SavePanelChoosing {
    nonisolated init() {}

    func chooseDestination(suggestedFilename: String, format: ScreenshotFormat) -> URL? {
        let panel = NSSavePanel()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
protocol OutputServing: AnyObject {
    func copy(_ image: CGImage) throws
    func save(_ image: CGImage, preferences: AppPreferences) throws -> ScreenshotSaveResult
}

struct ScreenshotSaveResult: Equatable, Sendable {
    let url: URL
    let shouldRememberDirectory: Bool
}

@MainActor
final class OutputService: OutputServing {
    private let encoder: ImageEncoder
    private let resolver: FilenameResolver
    private let pasteboard: any PasteboardWriting
    private let savePanel: any SavePanelChoosing
    private let fileManager: FileManager
    private let now: @MainActor () -> Date

    init(
        encoder: ImageEncoder = ImageEncoder(),
        resolver: FilenameResolver = FilenameResolver(),
        pasteboard: any PasteboardWriting = SystemPasteboard(),
        savePanel: any SavePanelChoosing = SavePanelChooser(),
        fileManager: FileManager = .default,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.encoder = encoder
        self.resolver = resolver
        self.pasteboard = pasteboard
        self.savePanel = savePanel
        self.fileManager = fileManager
        self.now = now
    }

    func copy(_ image: CGImage) throws {
        let data = try encoder.encode(image, format: .png, jpegQuality: 1)
        guard pasteboard.writePNG(data) else {
            throw OutputFailure.clipboardFailed
        }
    }

    /// Writes into the remembered directory when it is still reachable and
    /// writable, and otherwise falls back to the save panel so the composed
    /// image is never lost.
    func save(_ image: CGImage, preferences: AppPreferences) throws -> ScreenshotSaveResult {
        let format = preferences.format
        let data = try encoder.encode(
            image,
            format: format,
            jpegQuality: preferences.jpegQuality
        )
        let filename = resolver.filename(
            rule: preferences.filenameRule,
            date: now(),
            extension: format.fileExtension
        )

        if let saved = saveToBookmarkedDirectory(
            data: data,
            filename: filename,
            bookmark: preferences.saveDirectoryBookmark
        ) {
            return ScreenshotSaveResult(url: saved, shouldRememberDirectory: false)
        }

        guard let destination = savePanel.chooseDestination(
            suggestedFilename: filename,
            format: format
        ) else { throw OutputFailure.cancelled }

        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw OutputFailure.writeFailed(error.localizedDescription)
        }
        return ScreenshotSaveResult(url: destination, shouldRememberDirectory: true)
    }

    private func saveToBookmarkedDirectory(
        data: Data,
        filename: String,
        bookmark: Data?
    ) -> URL? {
        guard let bookmark, !bookmark.isEmpty else { return nil }
        var isStale = false
        guard let directory = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        let isAccessing = directory.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                directory.stopAccessingSecurityScopedResource()
            }
        }
        guard fileManager.fileExists(atPath: directory.path),
              fileManager.isWritableFile(atPath: directory.path) else { return nil }

        let destination = resolver.availableURL(in: directory, filename: filename)
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return nil }
        return destination
    }
}
