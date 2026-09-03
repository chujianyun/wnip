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

    func testEveryInvalidPhaseEventPairIsIgnoredWithoutMutatingState() {
        let phases: [CapturePhase] = [
            .idle,
            .requestingPermission(.region),
            .selecting(.region),
            .editing(.region),
            .exporting(.region),
            .completed,
            .cancelled,
            .failed(.unavailable)
        ]
        let events: [CaptureEvent] = [
            .start(.window),
            .permissionGranted,
            .permissionDenied,
            .selectionConfirmed,
            .exportRequested,
            .exportSucceeded,
            .exportFailed(.captureFailed("Disk full")),
            .failed(.unavailable),
            .cancel
        ]

        for phase in phases {
            for event in events where !isValid(event, from: phase) {
                var session = CaptureSession(phase: phase)

                XCTAssertEqual(session.handle(event), .ignored, "Expected \(event) to be ignored from \(phase)")
                XCTAssertEqual(session.phase, phase, "Ignored \(event) mutated \(phase)")
            }
        }
    }

    private func isValid(_ event: CaptureEvent, from phase: CapturePhase) -> Bool {
        switch (phase, event) {
        case (.idle, .start), (.completed, .start), (.cancelled, .start), (.failed, .start):
            return true
        case (.requestingPermission, .start), (.requestingPermission, .permissionGranted),
             (.requestingPermission, .permissionDenied), (.requestingPermission, .failed),
             (.requestingPermission, .cancel):
            return true
        case (.selecting, .start), (.selecting, .selectionConfirmed), (.selecting, .failed),
             (.selecting, .cancel):
            return true
        case (.editing, .start), (.editing, .exportRequested), (.editing, .failed),
             (.editing, .cancel):
            return true
        case (.exporting, .start), (.exporting, .exportSucceeded), (.exporting, .exportFailed),
             (.exporting, .failed), (.exporting, .cancel):
            return true
        default:
            return false
        }
    }
}
