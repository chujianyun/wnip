import AppKit

/// Keeps each PNG in a separate temporary folder for Preview's document lifetime.
@MainActor
struct PreviewService {
    var directory: URL = FileManager.default.temporaryDirectory
    var openDocument: (URL) async throws -> Void = { document in
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
            throw OutputFailure.writeFailed("找不到 macOS 预览应用。")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.open([document], withApplicationAt: application, configuration: configuration)
    }

    func open(_ image: CGImage) async throws {
        let data = try ImageEncoder().encode(image, format: .png, jpegQuality: 1)
        let folder = directory.appendingPathComponent("Wnip-Preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let document = folder.appendingPathComponent("Wnip-Screenshot.png")
        do {
            try data.write(to: document, options: .atomic)
            try await openDocument(document)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
