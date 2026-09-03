import ServiceManagement
import XCTest
@testable import Wnip

@MainActor
final class LaunchAtLoginServiceTests: XCTestCase {
    func testEnablingAnEnabledServiceDoesNotRegisterAgain() throws {
        let boundary = ControlledLaunchAtLoginBoundary(status: .enabled)
        let service = LaunchAtLoginService(boundary: boundary)

        try service.setEnabled(true)

        XCTAssertEqual(boundary.registerCallCount, 0)
        XCTAssertEqual(boundary.unregisterCallCount, 0)
    }

    func testDisablingAnUnregisteredServiceDoesNotUnregisterAgain() throws {
        let boundary = ControlledLaunchAtLoginBoundary(status: .notRegistered)
        let service = LaunchAtLoginService(boundary: boundary)

        try service.setEnabled(false)

        XCTAssertEqual(boundary.registerCallCount, 0)
        XCTAssertEqual(boundary.unregisterCallCount, 0)
    }

    func testMapsServiceManagementErrorsToActionableFailures() {
        let cases: [(Int, LaunchAtLoginFailure)] = [
            (Int(kSMErrorLaunchDeniedByUser), .requiresApproval),
            (Int(kSMErrorAlreadyRegistered), .alreadyRegistered),
            (Int(kSMErrorJobNotFound), .notRegistered),
            (Int(kSMErrorInvalidSignature), .invalidSignature),
            (Int(kSMErrorServiceUnavailable), .serviceUnavailable)
        ]

        for (code, expectedFailure) in cases {
            let boundary = ControlledLaunchAtLoginBoundary(
                status: .notRegistered,
                registerError: NSError(domain: SMAppServiceErrorDomain, code: code)
            )
            let service = LaunchAtLoginService(boundary: boundary)

            XCTAssertThrowsError(try service.setEnabled(true)) { error in
                XCTAssertEqual(error as? LaunchAtLoginFailure, expectedFailure)
            }
        }
    }
}

@MainActor
private final class ControlledLaunchAtLoginBoundary: LaunchAtLoginSystemControlling {
    var status: SMAppService.Status
    let registerError: Error?
    let unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(
        status: SMAppService.Status,
        registerError: Error? = nil,
        unregisterError: Error? = nil
    ) {
        self.status = status
        self.registerError = registerError
        self.unregisterError = unregisterError
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}
