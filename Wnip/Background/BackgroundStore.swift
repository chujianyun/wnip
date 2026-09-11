import AppKit
import ImageIO
import UniformTypeIdentifiers

final class BackgroundStore {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wnip/Backgrounds", isDirectory: true)
    }
    func load() throws -> BackgroundStyle {
        let url = directory.appendingPathComponent("defaults.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return BackgroundStyle() }
        return try JSONDecoder().decode(BackgroundStyle.self, from: Data(contentsOf: url)).validated()
    }
    func save(_ style: BackgroundStyle) throws {
        _ = try style.validated()
        if style.kind == .image { _ = try image(id: style.imageID) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(style).write(to: directory.appendingPathComponent("defaults.json"), options: .atomic)
    }
    func image(id: String) throws -> CGImage {
        if id.hasPrefix("builtin:") { return try BackgroundArtwork.image(id: id) }
        guard UUID(uuidString: id) != nil else { throw BackgroundFailure.missingImage }
        return try Self.decode(directory.appendingPathComponent(id).appendingPathExtension("png"))
    }
    func importImage(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let image = try Self.decode(url)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw BackgroundFailure.invalidImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BackgroundFailure.invalidImage }
        try (data as Data).write(to: directory.appendingPathComponent(id).appendingPathExtension("png"), options: .atomic)
        return id
    }
    private static func decode(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width * height <= 100_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 6000
              ] as CFDictionary) else { throw BackgroundFailure.invalidImage }
        return image
    }
}
