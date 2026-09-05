import AppKit
import Foundation
@preconcurrency import UserNotifications

enum CompletionFeedbackEvent: Equatable, Sendable {
    case copied
    case saved

    var notificationBody: String {
        switch self {
        case .copied:
            return "Screenshot copied to the clipboard."
        case .saved:
            return "Screenshot saved."
        }
    }
}

@MainActor
protocol CompletionFeedbackServing: AnyObject {
    func perform(_ event: CompletionFeedbackEvent, preferences: AppPreferences)
}

@MainActor
final class CompletionFeedbackService: CompletionFeedbackServing {
    typealias EventHandler = @MainActor (CompletionFeedbackEvent) -> Void

    private let notify: EventHandler
    private let playSound: EventHandler
    private let performHaptic: EventHandler

    init(
        notify: @escaping EventHandler = { event in
            CompletionFeedbackService.postNotification(for: event)
        },
        playSound: @escaping EventHandler = { _ in
            if NSSound(named: "Glass")?.play() != true {
                NSSound.beep()
            }
        },
        performHaptic: @escaping EventHandler = { _ in
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment,
                performanceTime: .now
            )
        }
    ) {
        self.notify = notify
        self.playSound = playSound
        self.performHaptic = performHaptic
    }

    func perform(_ event: CompletionFeedbackEvent, preferences: AppPreferences) {
        if preferences.completionSoundEnabled {
            playSound(event)
        }
        if preferences.hapticFeedbackEnabled {
            performHaptic(event)
        }
        if preferences.completionNotificationEnabled {
            notify(event)
        }
    }

    private static func postNotification(for event: CompletionFeedbackEvent) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                addNotification(for: event, to: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    guard granted else { return }
                    addNotification(for: event, to: center)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private nonisolated static func addNotification(
        for event: CompletionFeedbackEvent,
        to center: UNUserNotificationCenter
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Wnip"
        content.body = event.notificationBody
        center.add(
            UNNotificationRequest(
                identifier: "com.wnip.capture.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
    }
}
