import XCTest
@testable import Wnip

final class CaptureTypesTests: XCTestCase {
    func testDisplayConvertsGlobalPointsToLocalPixels() {
        let display = DisplayDescriptor(id: 7, frame: CGRect(x: -1440, y: 0, width: 1440, height: 900), scale: 2)
        XCTAssertEqual(display.pixelRect(forGlobalRect: CGRect(x: -1340, y: 100, width: 200, height: 50)),
                       CGRect(x: 200, y: 1500, width: 400, height: 100))
    }
}
