import AppKit
import XCTest
@testable import Wnip

final class WindowCaptureSourceTests: XCTestCase {
    func testSnapshotIncludesPopoverBeyondHostAndKeepsTransparentSurroundings() throws {
        let display = DisplayDescriptor(id: 2, frame: CGRect(x: -100, y: 50, width: 100, height: 100), scale: 2)
        let host = CGRect(x: -90, y: 70, width: 40, height: 60)
        let popup = CGRect(x: -60, y: 100, width: 40, height: 40)
        let image = try isolatedImage(display: display, rectangles: [(host, .red), (popup, .green)])
        let snapshot = try WindowCaptureSource.snapshot(image, windowFrame: host, display: display)

        XCTAssertEqual(snapshot.frame, host.union(popup))
        XCTAssertEqual(snapshot.image.image.width, 140)
        XCTAssertEqual(snapshot.image.image.height, 140)
        let canvas = try WindowCaptureSource.canvas(snapshot.image, windowFrame: snapshot.frame, display: display)
        let bitmap = NSBitmapImageRep(cgImage: canvas.image)
        let popupColor = try XCTUnwrap(bitmap.colorAt(x: 140, y: 40)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(popupColor.greenComponent, 0.9)
        XCTAssertLessThan(popupColor.redComponent, 0.1)
        let hostColor = try XCTUnwrap(bitmap.colorAt(x: 40, y: 140)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(hostColor.redComponent, 0.9)
        XCTAssertEqual(bitmap.colorAt(x: 140, y: 140)?.alphaComponent, 0)
        XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0)
    }

    func testSnapshotWithoutPopoverPreservesHostBoundsAndScale() throws {
        let display = DisplayDescriptor(id: 1, frame: CGRect(x: 100, y: -50, width: 100, height: 100), scale: 2)
        let host = CGRect(x: 110, y: -40, width: 40, height: 60)
        let image = try isolatedImage(display: display, rectangles: [(host.insetBy(dx: 1, dy: 1), .red)])
        let snapshot = try WindowCaptureSource.snapshot(image, windowFrame: host, display: display)
        XCTAssertEqual(snapshot.frame, host, "Transparent window edges must not shrink its frame")
        XCTAssertEqual(snapshot.image.scale, 2)
        XCTAssertEqual(snapshot.image.image.width, 80)
        XCTAssertEqual(snapshot.image.image.height, 120)
    }

    func testEmptyIsolatedCaptureFailsInsteadOfExportingDesktop() throws {
        let display = DisplayDescriptor(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        let image = try isolatedImage(display: display, rectangles: [])
        XCTAssertThrowsError(try WindowCaptureSource.snapshot(image, windowFrame: display.frame, display: display)) {
            XCTAssertEqual($0 as? CaptureFailure, .unavailable)
        }
    }

    private func isolatedImage(display: DisplayDescriptor, rectangles: [(CGRect, NSColor)]) throws -> PixelImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(display.frame.width * display.scale),
            height: Int(display.frame.height * display.scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: display.scale, y: display.scale)
        for (rect, color) in rectangles {
            context.setFillColor(color.cgColor)
            context.fill(rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY))
        }
        return PixelImage(image: try XCTUnwrap(context.makeImage()), scale: display.scale)
    }

    func testRetinaWindowOnNegativeOriginDisplayKeepsOrientationAndTransparentSurroundings() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 60,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 30, width: 40, height: 30))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let image = PixelImage(image: try XCTUnwrap(context.makeImage()), scale: 2)
        let display = DisplayDescriptor(id: 2, frame: CGRect(x: -100, y: 50, width: 100, height: 100), scale: 2)
        let frame = CGRect(x: -90, y: 110, width: 20, height: 30)
        let canvas = try WindowCaptureSource.canvas(image, windowFrame: frame, display: display)
        XCTAssertEqual(canvas.image.width, 200)
        XCTAssertEqual(canvas.image.height, 200)
        XCTAssertEqual(canvas.scale, 2)
        let crop = try ScreenshotCrop.crop(canvas, selection: frame, display: display)
        XCTAssertEqual(crop.image.width, 40)
        XCTAssertEqual(crop.image.height, 60)
        let bitmap = NSBitmapImageRep(cgImage: crop.image)
        let top = try XCTUnwrap(bitmap.colorAt(x: 20, y: 5)?.usingColorSpace(.deviceRGB))
        let bottom = try XCTUnwrap(bitmap.colorAt(x: 20, y: 55)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(top.redComponent, 0.9)
        XCTAssertLessThan(top.greenComponent, 0.1)
        XCTAssertGreaterThan(bottom.greenComponent, 0.9)
        XCTAssertLessThan(bottom.redComponent, 0.1)
        XCTAssertEqual(NSBitmapImageRep(cgImage: canvas.image).colorAt(x: 0, y: 0)?.alphaComponent, 0)
    }
}
