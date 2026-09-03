import Foundation
import ServiceManagement

@MainActor
protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }

    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginFailure: LocalizedError, Equatable {
    case requiresApproval
    case alreadyRegistered
    case notRegistered
    case invalidSignature
    case serviceUnavailable
    case serviceFailure(String)

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Allow Wnip in Login Items to enable launch at login."
        case .alreadyRegistered:
            return "Launch at login is already enabled."
        case .notRegistered:
            return "Launch at login is already disabled."
        case .invalidSignature:
            return "Wnip must be correctly code signed before launch at login can be enabled."
        case .serviceUnavailable:
            return "The macOS launch-at-login service is currently unavailable."
        case .serviceFailure(let message):
            return "Launch at login could not be updated: \(message)"
        }
    }
}

@MainActor
protocol LaunchAtLoginSystemControlling {
    var status: SMAppService.Status { get }

    func register() throws
    func unregister() throws
}

@MainActor
final class LaunchAtLoginSystemService: LaunchAtLoginSystemControlling {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
final class LaunchAtLoginService: LaunchAtLoginControlling {
    private let boundary: any LaunchAtLoginSystemControlling

    init() {
        self.boundary = LaunchAtLoginSystemService()
    }

    init(boundary: any LaunchAtLoginSystemControlling) {
        self.boundary = boundary
    }

    var isEnabled: Bool {
        boundary.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled, boundary.status == .enabled { return }
        if !enabled, boundary.status == .notRegistered { return }

        do {
            if enabled {
                try boundary.register()
            } else {
                try boundary.unregister()
            }
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> LaunchAtLoginFailure {
        if boundary.status == .requiresApproval {
            return .requiresApproval
        }

        let error = error as NSError
        guard error.domain == SMAppServiceErrorDomain else {
            return .serviceFailure(error.localizedDescription)
        }

        switch error.code {
        case Int(kSMErrorLaunchDeniedByUser):
            return .requiresApproval
        case Int(kSMErrorAlreadyRegistered):
            return .alreadyRegistered
        case Int(kSMErrorJobNotFound):
            return .notRegistered
        case Int(kSMErrorInvalidSignature):
            return .invalidSignature
        case Int(kSMErrorServiceUnavailable):
            return .serviceUnavailable
        default:
            return .serviceFailure(error.localizedDescription)
        }
    }
}
