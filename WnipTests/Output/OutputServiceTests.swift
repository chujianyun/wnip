import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Wnip

@MainActor
final class OutputServiceTests: XCTestCase {
    func testPNGAndJPEGEncodingProduceDecodableData() throws {
        let image = try solidImage().image
        let encoder = ImageEncoder()

        let png = try encoder.encode(image, format: .png, jpegQuality: 0.1)
        let jpegLow = try encoder.encode(image, format: .jpeg, jpegQuality: 0.1)
        let jpegHigh = try encoder.encode(image, format: .jpeg, jpegQuality: 0.95)

        XCTAssertEqual(CGImageSourceGetType(CGImageSourceCreateWithData(png as CFData, nil)!), UTType.png.identifier as CFString)
        XCTAssertEqual(CGImageSourceGetType(CGImageSourceCreateWithData(jpegLow as CFData, nil)!), UTType.jpeg.identifier as CFString)
        XCTAssertNotEqual(jpegLow, jpegHigh)
    }

    func testDefaultFilenameAndUnsafeCharactersAreResolvedLiterally() {
        let date = utcCalendar.date(from: DateComponents(
            year: 2026, month: 9, day: 3, hour: 12, minute: 34, second: 56
        ))!
        let resolver = FilenameResolver(calendar: utcCalendar)

        XCTAssertEqual(resolver.filename(rule: "Wnip-yyyy-MM-dd_HH-mm-ss", date: date, extension: "png"), "Wnip-2026-09-03_12-34-56.png")
        XCTAssertEqual(resolver.filename(rule: "Shot:/\\yyyy", date: date, extension: "jpg"), "Shot---2026.jpg")
    }

    func testCollisionResolutionUsesDashTwoAndDashThreeWithoutOverwriting() throws {
        let directory = try temporaryDirectory()
        let resolver = FilenameResolver(calendar: utcCalendar)
        let first = directory.appendingPathComponent("Shot.png")
        let second = directory.appendingPathComponent("Shot-2.png")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        FileManager.default.createFile(atPath: second.path, contents: Data())

        XCTAssertEqual(resolver.availableURL(in: directory, filename: "Shot.png"), directory.appendingPathComponent("Shot-3.png"))
    }

    func testClipboardFailureIsReported() throws {
        let service = OutputService(pasteboard: RecordingPasteboard(succeeds: false))
        XCTAssertThrowsError(try service.copy(solidImage().image)) { error in
            XCTAssertEqual(error as? OutputFailure, .clipboardFailed)
        }
    }

    func testInvalidBookmarkFallsBackToSavePanelAndWritesFile() throws {
        let directory = try temporaryDirectory()
        let destination = directory.appendingPathComponent("fallback.png")
        let panel = RecordingSavePanel(destination: destination)
        let preferences = AppPreferences(saveDirectoryBookmark: Data([0, 1, 2]))
        let service = OutputService(savePanel: panel, now: {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar.date(from: DateComponents(
                year: 2026, month: 9, day: 3, hour: 12, minute: 34, second: 56
            ))!
        })

        let saved = try service.save(solidImage().image, preferences: preferences)

        XCTAssertEqual(saved.url, destination)
        XCTAssertTrue(saved.shouldRememberDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(panel.callCount, 1)
    }

    func testUnwritableDirectoryFallsBackWithoutLosingImage() throws {
        let directory = try temporaryDirectory()
        let destination = directory.appendingPathComponent("chosen.png")
        let panel = RecordingSavePanel(destination: destination)
        let bookmark = try URL(fileURLWithPath: "/System", isDirectory: true).bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        )
        let service = OutputService(savePanel: panel)

        let saved = try service.save(solidImage().image, preferences: AppPreferences(saveDirectoryBookmark: bookmark))

        XCTAssertEqual(saved.url, destination)
        XCTAssertTrue(saved.shouldRememberDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testReachableRememberedDirectorySavesWithoutRequestingANewBookmark() throws {
        let directory = try temporaryDirectory()
        let panel = RecordingSavePanel(destination: nil)
        let bookmark = try directory.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let service = OutputService(savePanel: panel)

        let saved = try service.save(
            solidImage().image,
            preferences: AppPreferences(saveDirectoryBookmark: bookmark)
        )

        XCTAssertEqual(saved.url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertFalse(saved.shouldRememberDirectory)
        XCTAssertEqual(panel.callCount, 0)
    }

    func testCancelledFallbackReportsCancellation() throws {
        let service = OutputService(savePanel: RecordingSavePanel(destination: nil))
        XCTAssertThrowsError(try service.save(solidImage().image, preferences: AppPreferences(saveDirectoryBookmark: Data()))) { error in
            XCTAssertEqual(error as? OutputFailure, .cancelled)
        }
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WnipOutputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func solidImage() throws -> PixelImage {
        try makeImage(width: 64, height: 64, scale: 1) { x, y in
            (UInt8(x * 3), UInt8(y * 3), 100, 255)
        }
    }
}

@MainActor
private final class RecordingPasteboard: PasteboardWriting {
    private let succeeds: Bool
    init(succeeds: Bool) { self.succeeds = succeeds }
    func writePNG(_ data: Data) -> Bool { succeeds && !data.isEmpty }
}

@MainActor
private final class RecordingSavePanel: SavePanelChoosing {
    let destination: URL?
    private(set) var callCount = 0
    init(destination: URL?) { self.destination = destination }
    func chooseDestination(suggestedFilename: String, format: ScreenshotFormat) -> URL? {
        callCount += 1
        return destination
    }
}
