import AppKit
import XCTest
@testable import Wnip

@MainActor
final class PreviewServiceTests: XCTestCase {
    func testOpensDistinctDecodablePNGsAndRetainsDocuments() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var documents: [URL] = []
        let service = PreviewService(directory: directory) { url in
            let image = try XCTUnwrap(NSImage(contentsOf: url))
            XCTAssertEqual(image.size, NSSize(width: 20, height: 10))
            documents.append(url)
        }
        let image = try makeImage(width: 20, height: 10, scale: 1) { _, _ in (255, 0, 0, 255) }
        try await service.open(image.image)
        try await service.open(image.image)
        XCTAssertEqual(Set(documents).count, 2)
        XCTAssertTrue(documents.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testLaunchFailureIsReportedAndTemporaryFileRemoved() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = PreviewService(directory: directory) { _ in
            throw OutputFailure.writeFailed("Preview failed")
        }
        let image = try makeImage(width: 20, height: 10, scale: 1) { _, _ in (255, 0, 0, 255) }
        do {
            try await service.open(image.image)
            XCTFail("Expected launch failure")
        } catch {
            XCTAssertEqual(error as? OutputFailure, .writeFailed("Preview failed"))
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }
}
