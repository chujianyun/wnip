import XCTest
@testable import Wnip

final class BackgroundTests: XCTestCase {
    func testCanvasPreservesSourceAndAddsRequestedPadding() throws {
        let layout = try BackgroundLayout(source: CGSize(width: 1000, height: 500), style: BackgroundStyle())
        XCTAssertEqual(layout.size, CGSize(width: 1120, height: 620))
        XCTAssertEqual(layout.screenshot, CGRect(x: 60, y: 60, width: 1000, height: 500))
    }
    func testEveryAspectContainsUnstretchedScreenshot() throws {
        for aspect in BackgroundStyle.Aspect.allCases {
            var style = BackgroundStyle(); style.aspect = aspect
            let layout = try BackgroundLayout(source: CGSize(width: 601, height: 350), style: style)
            XCTAssertEqual(layout.screenshot.size, CGSize(width: 601, height: 350))
            XCTAssertTrue(CGRect(origin: .zero, size: layout.size).contains(layout.screenshot))
            if let ratio = style.aspectRatio { XCTAssertEqual(layout.size.width / layout.size.height, ratio, accuracy: 0.005) }
        }
    }
    func testRejectsInvalidOrExcessiveAllocation() {
        var style = BackgroundStyle(); style.customHeight = 0
        XCTAssertThrowsError(try style.validated())
        style = BackgroundStyle(); style.padding = .nan
        XCTAssertThrowsError(try style.validated())
        XCTAssertThrowsError(try BackgroundLayout(source: CGSize(width: 16000, height: 16000), style: BackgroundStyle()))
        XCTAssertNil(HexRGB("GGFFFF"))
        XCTAssertNotNil(HexRGB("#00aaff"))
    }
}

final class BackgroundRendererTests: XCTestCase {
    func source() throws -> CGImage {
        let context = try BackgroundRenderer.context(100, 80)
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 40, width: 100, height: 40))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 40))
        return try XCTUnwrap(context.makeImage())
    }
    func color(_ image: CGImage, _ x: Int, _ y: Int) throws -> NSColor {
        // Read the renderer's explicit sRGB bytes; NSBitmapImageRep.colorAt may
        // reinterpret them as device RGB and introduce the display profile.
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let offset = y * image.bytesPerRow + x * 4
        return NSColor(srgbRed: CGFloat(bytes[offset]) / 255,
                       green: CGFloat(bytes[offset+1]) / 255,
                       blue: CGFloat(bytes[offset+2]) / 255,
                       alpha: CGFloat(bytes[offset+3]) / 255)
    }
    func testSolidExportKeepsOrientationAndOpaqueBackground() throws {
        var style = BackgroundStyle(); style.kind = .solid; style.solid = "00FF00"; style.padding = 0.25; style.radius = 0; style.shadow = 0
        let image = try BackgroundRenderer().render(source: source(), style: style)
        XCTAssertEqual(image.width, 140); XCTAssertEqual(image.height, 120)
        XCTAssertGreaterThan(try color(image, 2, 2).greenComponent, 0.99)
        XCTAssertGreaterThan(try color(image, 70, 30).redComponent, 0.99)
        XCTAssertGreaterThan(try color(image, 70, 90).blueComponent, 0.99)
        XCTAssertEqual(try color(image, 0, 0).alphaComponent, 1)
    }
    func testAuroraMatchesAllFourCornerColors() throws {
        var style = BackgroundStyle(); style.padding = 0.6; style.shadow = 0
        let image = try BackgroundRenderer().render(source: source(), style: style)
        for (index, point) in [(1,1), (image.width-2,1), (1,image.height-2), (image.width-2,image.height-2)].enumerated() {
            let actual = try color(image, point.0, point.1), expected = try XCTUnwrap(HexRGB(style.colors[index]))
            XCTAssertEqual(actual.redComponent, expected.r, accuracy: 0.025)
            XCTAssertEqual(actual.greenComponent, expected.g, accuracy: 0.025)
            XCTAssertEqual(actual.blueComponent, expected.b, accuracy: 0.025)
        }
    }
    func testAllPresetsAndLinearAnglesRender() throws {
        for preset in GradientPreset.all {
            for angle in [0.0, 90, 180, 270, 360] {
                var style = BackgroundStyle(); style.colors = preset.colors; style.multiPoint = false; style.angle = angle
                let image = try BackgroundRenderer().render(source: source(), style: style)
                XCTAssertGreaterThan(image.width, 100)
            }
        }
    }
    func testPreviewUsesSameAspectAndColorsAsExport() throws {
        var style = BackgroundStyle(); style.aspect = .portrait
        let full = try BackgroundRenderer().render(source: source(), style: style)
        let preview = try BackgroundRenderer().render(source: source(), style: style, maxDimension: 100)
        XCTAssertEqual(preview.height, 100)
        XCTAssertEqual(Double(full.width)/Double(full.height), Double(preview.width)/100, accuracy: 0.01)
        XCTAssertEqual(try color(full, 1, 1).greenComponent, try color(preview, 1, 1).greenComponent, accuracy: 0.04)
    }
    func testWhiteBorderAndRoundedCorner() throws {
        var style = BackgroundStyle(); style.kind = .solid; style.solid = "00FF00"; style.radius = 0.15; style.border = 0.05; style.padding = 0.25; style.shadow = 0
        let image = try BackgroundRenderer().render(source: source(), style: style)
        let border = try color(image, image.width / 2, 21)
        XCTAssertGreaterThan(border.redComponent, 0.99); XCTAssertGreaterThan(border.blueComponent, 0.99)
        XCTAssertGreaterThan(try color(image, 24, 24).greenComponent, 0.9)
    }
    func testImageBackgroundAspectFillAndPosition() throws {
        var style = BackgroundStyle(); style.kind = .image; style.padding = 0.6; style.shadow = 0; style.imageZoom = 4
        let bg = try source()
        style.imageY = 0
        let top = try BackgroundRenderer().render(source: bg, style: style, background: bg)
        style.imageY = 1
        let bottom = try BackgroundRenderer().render(source: bg, style: style, background: bg)
        XCTAssertGreaterThan(try color(top, 1, 1).redComponent, 0.9)
        XCTAssertGreaterThan(try color(bottom, 1, bottom.height-2).blueComponent, 0.9)
        XCTAssertThrowsError(try BackgroundRenderer().render(source: bg, style: style))
    }
    func testBundledArtworkAvailable() throws {
        for choice in BackgroundArtwork.choices {
            XCTAssertEqual(try BackgroundArtwork.image(id: choice.id).width, 1600)
        }
    }
}

final class BackgroundStoreTests: XCTestCase {
    func testDefaultsRoundTripAndReset() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BackgroundStore(directory: folder)
        XCTAssertEqual(try store.load(), BackgroundStyle())
        var style = BackgroundStyle(); style.aspect = .portrait; style.padding = 0.4; style.colors = GradientPreset.all[3].colors
        try store.save(style)
        XCTAssertEqual(try BackgroundStore(directory: folder).load(), style)
        try store.save(BackgroundStyle()); XCTAssertEqual(try store.load(), BackgroundStyle())
    }
    func testImportedImageSurvivesSourceRemoval() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = folder.appendingPathComponent("input.png")
        let image = try BackgroundRendererTests().source()
        try ImageEncoder().encode(image, format: .png, jpegQuality: 1).write(to: original)
        let store = BackgroundStore(directory: folder.appendingPathComponent("store"))
        let id = try store.importImage(original)
        try FileManager.default.removeItem(at: original)
        var style = BackgroundStyle(); style.kind = .image; style.imageID = id
        try store.save(style)
        XCTAssertEqual(try store.image(id: store.load().imageID).width, image.width)
        XCTAssertThrowsError(try store.image(id: "../input"))
    }
    func testInvalidDefaultsDoNotOverwriteExistingDefault() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BackgroundStore(directory: folder)
        try store.save(BackgroundStyle())
        var style = BackgroundStyle(); style.colors = ["bad"]
        XCTAssertThrowsError(try store.save(style))
        XCTAssertEqual(try store.load(), BackgroundStyle())
        style = BackgroundStyle(); style.kind = .image; style.imageID = UUID().uuidString
        XCTAssertThrowsError(try store.save(style))
    }
}

@MainActor
final class BackgroundEditorModelTests: XCTestCase {
    func testCancelledAndFailedSaveKeepEditableSourceAndSettings() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var attempts = 0
        let source = try BackgroundRendererTests().source()
        let model = BackgroundEditorModel(source: source, store: BackgroundStore(directory: folder)) { _, save in
            XCTAssertTrue(save)
            attempts += 1
            if attempts == 1 { throw OutputFailure.cancelled }
            throw BackgroundFailure.renderFailed
        }
        model.style.padding = 0.25
        model.export(save: true)
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.message, "已取消保存，可以继续编辑")
        XCTAssertEqual(model.style.padding, 0.25)
        XCTAssertTrue(model.source === source)
        model.export(save: true)
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.busy)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(model.style.padding, 0.25)
    }
    func testExportUsesOriginalPixelsAndBlocksDuplicateClick() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var exported: CGImage?, calls = 0
        let model = BackgroundEditorModel(source: try BackgroundRendererTests().source(), store: BackgroundStore(directory: folder)) { image, _ in
            exported = image; calls += 1; return "已复制图片"
        }
        model.export(save: false); model.export(save: false)
        for _ in 0..<200 where model.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.busy); XCTAssertEqual(calls, 1)
        XCTAssertEqual(exported?.width, 120); XCTAssertEqual(exported?.height, 100)
    }
    func testRapidPreviewChangesShowFinalStyle() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = BackgroundEditorModel(source: try BackgroundRendererTests().source(), store: BackgroundStore(directory: folder)) { _, _ in "" }
        for preset in GradientPreset.all { model.applyPreset(preset) }
        model.style.kind = .solid; model.style.solid = "00FF00"; model.style.shadow = 0
        for _ in 0..<200 where model.rendering { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(model.rendering)
        let preview = try XCTUnwrap(model.preview)
        let color = try BackgroundRendererTests().color(preview, 0, 0)
        XCTAssertGreaterThan(color.greenComponent, 0.99)
        XCTAssertLessThan(color.redComponent, 0.01)
    }
    func testTemporaryChangesDoNotOverwriteSavedDefault() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BackgroundStore(directory: folder)
        let model = BackgroundEditorModel(source: try BackgroundRendererTests().source(), store: store) { _, _ in "" }
        model.style.padding = 0.4
        XCTAssertEqual(try store.load().padding, 0.12)
        model.saveDefault()
        XCTAssertEqual(try store.load().padding, 0.4)
        model.style.padding = 0.1
        XCTAssertEqual(try store.load().padding, 0.4)
        model.resetDefault()
        XCTAssertEqual(try store.load(), BackgroundStyle())
    }
}
