import XCTest
@testable import Wnip

final class CaptureSessionTests: XCTestCase {
    func testNormalFlowMovesThroughAllCapturePhases() {
        var session = CaptureSession()

        XCTAssertEqual(session.handle(.start(.region)), .transitioned(to: .requestingPermission(.region)))
        XCTAssertEqual(session.handle(.permissionGranted), .transitioned(to: .selecting(.region)))
        XCTAssertEqual(session.handle(.selectionConfirmed), .transitioned(to: .editing(.region)))
        XCTAssertEqual(session.handle(.exportRequested), .transitioned(to: .exporting(.region)))
        XCTAssertEqual(session.handle(.exportSucceeded), .transitioned(to: .completed))
        XCTAssertEqual(session.phase, .completed)
    }

    func testCancellationIsAcceptedFromEveryActivePhase() {
        let activePhases: [(CaptureSession, CaptureEvent)] = [
            (CaptureSession(phase: .requestingPermission(.region)), .cancel),
            (CaptureSession(phase: .selecting(.window)), .cancel),
            (CaptureSession(phase: .editing(.fullScreen)), .cancel),
            (CaptureSession(phase: .exporting(.region)), .cancel)
        ]

        for (var session, event) in activePhases {
            XCTAssertEqual(session.handle(event), .transitioned(to: .cancelled))
            XCTAssertEqual(session.phase, .cancelled)
        }
    }

    func testExportFailureReturnsToEditingAndReportsRecoverableFailure() {
        var session = CaptureSession(phase: .exporting(.region))

        XCTAssertEqual(
            session.handle(.exportFailed(.captureFailed("Disk full"))),
            .recovered(.captureFailed("Disk full"), to: .editing(.region))
        )
        XCTAssertEqual(session.phase, .editing(.region))
    }

    func testRepeatedStartCancelsActiveSessionBeforeStartingReplacement() {
        var session = CaptureSession(phase: .selecting(.region))

        XCTAssertEqual(
            session.handle(.start(.window)),
            .replaced(cancelled: .selecting(.region), with: .requestingPermission(.window))
        )
        XCTAssertEqual(session.phase, .requestingPermission(.window))
    }

    func testEveryInvalidEventIsIgnoredWithoutMutatingState() {
        let invalidTransitions: [(CapturePhase, CaptureEvent)] = [
            (.idle, .permissionGranted),
            (.idle, .cancel),
            (.requestingPermission(.region), .selectionConfirmed),
            (.requestingPermission(.region), .exportRequested),
            (.selecting(.region), .permissionGranted),
            (.selecting(.region), .exportSucceeded),
            (.editing(.region), .permissionGranted),
            (.editing(.region), .selectionConfirmed),
            (.editing(.region), .exportSucceeded),
            (.editing(.region), .exportFailed(.captureFailed("Disk full"))),
            (.exporting(.region), .permissionGranted),
            (.exporting(.region), .selectionConfirmed),
            (.exporting(.region), .exportRequested),
            (.completed, .permissionGranted),
            (.completed, .cancel),
            (.cancelled, .selectionConfirmed),
            (.cancelled, .cancel),
            (.failed(.unavailable), .exportRequested),
            (.failed(.unavailable), .cancel)
        ]

        for (phase, event) in invalidTransitions {
            var session = CaptureSession(phase: phase)
            XCTAssertEqual(session.handle(event), .ignored)
            XCTAssertEqual(session.phase, phase)
        }
    }
}
