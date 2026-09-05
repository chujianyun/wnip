import AppKit
import XCTest
@testable import Wnip

@MainActor
final class PinnedImageControllerTests: XCTestCase {
    func testRetinaImagePreservesPointSizeAndNegativeDisplayCoordinates() throws {
        let image = try makeImage(width: 400, height: 200, scale: 2)
        let selection = CGRect(x: -800, y: 200, width: 200, height: 100)
        let frame = PinnedImageController.frame(for: image, near: selection,
            visibleFrame: CGRect(x: -1200, y: 0, width: 1200, height: 800))
        XCTAssertEqual(frame, selection)
    }

    func testOversizedImageFitsVisibleScreenAndTinyImageKeepsCloseButtonAccessible() throws {
        let visibleFrame = CGRect(x: 0, y: 24, width: 1000, height: 700)
        let large = try makeImage(width: 2000, height: 1000, scale: 1)
        let frame = PinnedImageController.frame(for: large,
            near: CGRect(x: 1800, y: 1000, width: 2000, height: 1000), visibleFrame: visibleFrame)
        XCTAssertTrue(visibleFrame.contains(frame))
        XCTAssertEqual(frame.width / frame.height, 2)
        let tiny = try makeImage(width: 1, height: 1, scale: 2)
        let tinyFrame = PinnedImageController.frame(for: tiny, near: .zero, visibleFrame: visibleFrame)
        XCTAssertGreaterThanOrEqual(tinyFrame.width, 36)
        XCTAssertGreaterThanOrEqual(tinyFrame.height, 36)
        XCTAssertTrue(visibleFrame.contains(tinyFrame))
    }

    func testPinsStayAboveNormalWindowsAndCloseIndependently() throws {
        let controller = PinnedImageController()
        let image = try makeImage(width: 200, height: 100, scale: 1)
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        controller.present(image, near: frame)
        controller.present(image, near: frame)
        XCTAssertEqual(controller.panels.count, 2)
        let first = try XCTUnwrap(controller.panels.first)
        let second = try XCTUnwrap(controller.panels.last)
        XCTAssertGreaterThan(first.level.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertFalse(first.hidesOnDeactivate)
        XCTAssertTrue(first.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(first.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertNotNil((first.contentView as? NSImageView)?.image)
        let close = try XCTUnwrap(first.contentView?.subviews.compactMap { $0 as? NSButton }.first)
        close.performClick(nil)
        XCTAssertEqual(controller.panels.count, 1)
        XCTAssertTrue(second.isVisible)
        XCTAssertFalse(first.isVisible)
        second.cancelOperation(nil)
        XCTAssertTrue(controller.panels.isEmpty)
    }

    private func makeImage(width: Int, height: Int, scale: CGFloat) throws -> PixelImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return PixelImage(image: try XCTUnwrap(context.makeImage()), scale: scale)
    }
}
