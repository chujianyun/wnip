import XCTest
@testable import Wnip

final class ScreenCaptureCoordinateMapperTests: XCTestCase {
    func testProducerUsesIDMatchedAppKitFrameForDisplayAboveAndLeftOfMain() {
        let mapper = ScreenCaptureCoordinateMapper(
            mainDisplayHeight: 1080,
            screens: [
                AppKitScreenGeometry(
                    displayID: 2,
                    frame: CGRect(x: -1280, y: 1080, width: 1280, height: 1024),
                    visibleFrame: CGRect(x: -1280, y: 1080, width: 1280, height: 1000),
                    scale: 1
                )
            ]
        )

        let descriptor = mapper.displayDescriptor(
            displayID: 2,
            quartzFrame: CGRect(x: -1280, y: -1024, width: 1280, height: 1024),
            fallbackScale: 2
        )

        XCTAssertEqual(
            descriptor,
            DisplayDescriptor(
                id: 2,
                frame: CGRect(x: -1280, y: 1080, width: 1280, height: 1024),
                scale: 1
            )
        )
    }

    func testProducerConvertsQuartzWindowFrameToAppKitCoordinates() {
        let mapper = ScreenCaptureCoordinateMapper(mainDisplayHeight: 1080, screens: [])

        let frame = mapper.appKitRect(
            fromQuartzRect: CGRect(x: -1200, y: -800, width: 400, height: 300)
        )

        XCTAssertEqual(frame, CGRect(x: -1200, y: 1580, width: 400, height: 300))
    }

    func testProducerScaleFlowsIntoOverlaySelectionPixelsAtTwoX() {
        let mapper = ScreenCaptureCoordinateMapper(
            mainDisplayHeight: 982,
            screens: [
                AppKitScreenGeometry(
                    displayID: 7,
                    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
                    scale: 2
                )
            ]
        )
        let descriptor = mapper.displayDescriptor(
            displayID: 7,
            quartzFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            fallbackScale: 1
        )

        let pixelRect = SelectionModel(
            rect: CGRect(x: 100, y: 100, width: 200, height: 50)
        ).pixelRect(on: descriptor)

        XCTAssertEqual(descriptor.scale, 2)
        XCTAssertEqual(pixelRect, CGRect(x: 200, y: 1664, width: 400, height: 100))
    }

    func testProducerScaleFlowsIntoDisplayedPixelBadgeAtTwoX() {
        let mapper = ScreenCaptureCoordinateMapper(
            mainDisplayHeight: 982,
            screens: [
                AppKitScreenGeometry(
                    displayID: 7,
                    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
                    scale: 2
                )
            ]
        )
        let descriptor = mapper.displayDescriptor(
            displayID: 7,
            quartzFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            fallbackScale: 1
        )

        let label = PixelBadgeContent.label(
            for: CGRect(x: 100, y: 100, width: 200, height: 50),
            on: descriptor
        )

        XCTAssertEqual(label, "400 × 100 px")
    }

    func testUnmatchedDisplayFallsBackToQuartzConversionAndModeScale() {
        let mapper = ScreenCaptureCoordinateMapper(mainDisplayHeight: 1080, screens: [])

        let descriptor = mapper.displayDescriptor(
            displayID: 9,
            quartzFrame: CGRect(x: 1920, y: 1080, width: 1280, height: 720),
            fallbackScale: 1.5
        )

        XCTAssertEqual(
            descriptor,
            DisplayDescriptor(
                id: 9,
                frame: CGRect(x: 1920, y: -720, width: 1280, height: 720),
                scale: 1.5
            )
        )
    }
}
