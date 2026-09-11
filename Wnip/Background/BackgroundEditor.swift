import AppKit
import SwiftUI
import UniformTypeIdentifiers

typealias BackgroundExport = @MainActor (CGImage, Bool) throws -> String

@MainActor
protocol BackgroundEditorPresenting: AnyObject {
    func present(source: CGImage, onExport: @escaping BackgroundExport)
}

@MainActor
final class BackgroundEditorController: NSObject, BackgroundEditorPresenting, NSWindowDelegate {
    private var window: NSWindow?
    func present(source: CGImage, onExport: @escaping BackgroundExport) {
        // Keep an existing document reachable when another capture is started.
        if window?.isVisible == true {
            let additional = BackgroundEditorController()
            Self.additionalWindows.append(additional)
            additional.present(source: source, onExport: onExport)
            return
        }
        let model = BackgroundEditorModel(source: source, onExport: onExport)
        let view = BackgroundEditorView(model: model, onClose: { [weak self] in self?.window?.close() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 740),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "截图加背景"
        window.minSize = NSSize(width: 860, height: 610)
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    private static var additionalWindows: [BackgroundEditorController] = []
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
        Self.additionalWindows.removeAll { $0 === self }
    }
}

@MainActor
final class BackgroundEditorModel: ObservableObject {
    @Published var style: BackgroundStyle { didSet { if style != oldValue { refresh() } } }
    @Published private(set) var preview: CGImage?
    @Published private(set) var dimensions = ""
    @Published private(set) var busy = false
    @Published private(set) var rendering = false
    @Published var message = ""
    @Published var error: String?
    let source: CGImage
    private let store: BackgroundStore
    private let onExport: BackgroundExport
    private var previewTask: Task<Void, Never>?
    private var cachedImage: (id: String, image: CGImage)?

    init(source: CGImage, store: BackgroundStore = BackgroundStore(), onExport: @escaping BackgroundExport) {
        self.source = source; self.store = store; self.onExport = onExport
        do { style = try store.load() }
        catch { style = BackgroundStyle(); self.error = "默认样式读取失败，已使用初始样式：\(error.localizedDescription)" }
        if style.kind == .image, (try? store.image(id: style.imageID)) == nil {
            style = BackgroundStyle()
            error = BackgroundFailure.missingImage.localizedDescription
        }
        refresh()
    }
    private func background() throws -> CGImage? {
        guard style.kind == .image else { return nil }
        if cachedImage?.id == style.imageID { return cachedImage?.image }
        let image = try store.image(id: style.imageID)
        cachedImage = (style.imageID, image)
        return image
    }
    func refresh() {
        previewTask?.cancel()
        rendering = true
        let style = style, source = source
        do {
            let background = try background()
            let layout = try BackgroundLayout(source: CGSize(width: source.width, height: source.height), style: style)
            dimensions = "\(Int(layout.size.width)) × \(Int(layout.size.height)) px"
            previewTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(70))
                    let image = try await Task.detached(priority: .userInitiated) {
                        try BackgroundRenderer().render(source: source, style: style, background: background, maxDimension: 1400)
                    }.value
                    try Task.checkCancellation()
                    self?.preview = image
                    self?.rendering = false
                } catch is CancellationError { }
                catch { self?.error = error.localizedDescription; self?.preview = nil; self?.rendering = false }
            }
        } catch {
            self.error = error.localizedDescription
            preview = nil; rendering = false
        }
    }
    func applyPreset(_ preset: GradientPreset) {
        var next = style; next.kind = .gradient; next.colors = preset.colors; next.multiPoint = true
        style = next
    }
    func importImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let id = try store.importImage(url)
            var next = style; next.imageID = id; next.kind = .image; next.imageZoom = 1; next.imageX = 0.5; next.imageY = 0.5
            style = next; message = "背景图已导入并保存在本机"
        } catch { self.error = error.localizedDescription }
    }
    func saveDefault() {
        do { try store.save(style); message = "已设为默认，下次截图加背景时自动使用" }
        catch { self.error = error.localizedDescription }
    }
    func resetDefault() {
        do { let initial = BackgroundStyle(); try store.save(initial); style = initial; message = "已恢复初始默认样式" }
        catch { self.error = error.localizedDescription }
    }
    func export(save: Bool) {
        guard !busy else { return }
        do {
            let background = try background(), style = style, source = source
            busy = true
            Task { [weak self] in
                guard let self else { return }
                defer { busy = false }
                do {
                    let image = try await Task.detached(priority: .userInitiated) {
                        try BackgroundRenderer().render(source: source, style: style, background: background)
                    }.value
                    message = try onExport(image, save)
                } catch OutputFailure.cancelled { message = "已取消保存，可以继续编辑" }
                catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }
}
