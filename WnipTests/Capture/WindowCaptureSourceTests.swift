import AppKit
import XCTest
@testable import Wnip

final class WindowCaptureSourceTests: XCTestCase {
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
