enum CapturePhase: Equatable {
    case idle
    case requestingPermission(CaptureMode)
    case selecting(CaptureMode)
    case editing(CaptureMode)
    case exporting(CaptureMode)
    case completed
    case cancelled
    case failed(CaptureFailure)

    var isActive: Bool {
        switch self {
        case .requestingPermission, .selecting, .editing, .exporting:
            return true
        case .idle, .completed, .cancelled, .failed:
            return false
        }
    }
}

enum CaptureEvent: Equatable {
    case start(CaptureMode)
    case permissionGranted
    case permissionDenied
    case selectionConfirmed
    case exportRequested
    case exportSucceeded
    case exportFailed(CaptureFailure)
    case failed(CaptureFailure)
    case cancel
}

enum CaptureTransition: Equatable {
    case transitioned(to: CapturePhase)
    case recovered(CaptureFailure, to: CapturePhase)
    case replaced(cancelled: CapturePhase, with: CapturePhase)
    case ignored
}

struct CaptureSession: Equatable {
    private(set) var phase: CapturePhase

    init(phase: CapturePhase = .idle) {
        self.phase = phase
    }

    @discardableResult
    mutating func handle(_ event: CaptureEvent) -> CaptureTransition {
        if case .start(let mode) = event {
            let replacement = CapturePhase.requestingPermission(mode)
            if phase.isActive {
                let previous = phase
                phase = replacement
                return .replaced(cancelled: previous, with: replacement)
            }
            phase = replacement
            return .transitioned(to: replacement)
        }

        if event == .cancel, phase.isActive {
            phase = .cancelled
            return .transitioned(to: .cancelled)
        }

        let nextPhase: CapturePhase?
        switch (phase, event) {
        case (.requestingPermission(let mode), .permissionGranted):
            nextPhase = .selecting(mode)
        case (.requestingPermission, .permissionDenied):
            nextPhase = .failed(.permissionDenied)
        case (.selecting(let mode), .selectionConfirmed):
            nextPhase = .editing(mode)
        case (.editing(let mode), .exportRequested):
            nextPhase = .exporting(mode)
        case (.exporting, .exportSucceeded):
            nextPhase = .completed
        case (_, .failed(let failure)) where phase.isActive:
            nextPhase = .failed(failure)
        case (.exporting(let mode), .exportFailed(let failure)):
            let editing = CapturePhase.editing(mode)
            phase = editing
            return .recovered(failure, to: editing)
        default:
            nextPhase = nil
        }

        guard let nextPhase else { return .ignored }
        phase = nextPhase
        return .transitioned(to: nextPhase)
    }
}
