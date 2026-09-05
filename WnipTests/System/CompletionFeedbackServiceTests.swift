import XCTest
@testable import Wnip

@MainActor
final class CompletionFeedbackServiceTests: XCTestCase {
    func testEnabledFeedbackChannelsReceiveCompletionEvent() {
        var notifications: [CompletionFeedbackEvent] = []
        var sounds: [CompletionFeedbackEvent] = []
        var haptics: [CompletionFeedbackEvent] = []
        let service = CompletionFeedbackService(
            notify: { notifications.append($0) },
            playSound: { sounds.append($0) },
            performHaptic: { haptics.append($0) }
        )

        service.perform(
            .saved,
            preferences: AppPreferences(
                completionNotificationEnabled: true,
                completionSoundEnabled: true,
                hapticFeedbackEnabled: true
            )
        )

        XCTAssertEqual(notifications, [.saved])
        XCTAssertEqual(sounds, [.saved])
        XCTAssertEqual(haptics, [.saved])
    }

    func testDisabledFeedbackChannelsStaySilent() {
        var callCount = 0
        let service = CompletionFeedbackService(
            notify: { _ in callCount += 1 },
            playSound: { _ in callCount += 1 },
            performHaptic: { _ in callCount += 1 }
        )

        service.perform(
            .copied,
            preferences: AppPreferences(
                completionNotificationEnabled: false,
                completionSoundEnabled: false,
                hapticFeedbackEnabled: false
            )
        )

        XCTAssertEqual(callCount, 0)
    }
}
