import AppKit
import XCTest
@testable import Wnip

final class AppBrandingTests: XCTestCase {
    func testMenuBarImageLoadsAsTemplateImage() throws {
        let image = try XCTUnwrap(AppBranding.menuBarImage)

        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }
}
