import Foundation
import ServiceManagement

protocol LaunchAtLoginControlling {
    var isEnabled: Bool { get }

    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginFailure: LocalizedError, Equatable {
    case requiresApproval
    case serviceFailure(String)

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Allow Wnip in Login Items to enable launch at login."
        case .serviceFailure(let message):
            return "Launch at login could not be updated: \(message)"
        }
    }
}

final class LaunchAtLoginService: LaunchAtLoginControlling {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> LaunchAtLoginFailure {
        if SMAppService.mainApp.status == .requiresApproval {
            return .requiresApproval
        }
        return .serviceFailure(error.localizedDescription)
    }
}
