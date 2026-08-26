import Foundation
import UserNotifications

protocol RestNotificationCenter: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removePending(withIdentifiers identifiers: [String]) async
    func removeDelivered(withIdentifiers identifiers: [String]) async
}

private struct SystemRestNotificationCenter: RestNotificationCenter, @unchecked Sendable {
    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePending(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: identifiers
        )
    }

    func removeDelivered(withIdentifiers identifiers: [String]) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: identifiers
        )
    }
}

enum NotificationService {
    static let workoutEnabledKey = "workoutRemindersEnabled"
    static let workoutHourKey = "workoutReminderHour"
    static let workoutMinuteKey = "workoutReminderMinute"
    static let restEnabledKey = "restTimerNotificationsEnabled"

    private static let workoutPrefix = "xfit.workout."
    private static let restPrefix = "xfit.rest."
    @MainActor private(set) static var lastRestSchedulingErrorDescription: String?

    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func syncWorkoutReminders(_ schedules: [ScheduledWorkout]) async {
        guard CloudSyncRuntime.shouldSyncWorkoutReminders() else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(workoutPrefix) }
        )

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: workoutEnabledKey) else { return }

        let hour = defaults.object(forKey: workoutHourKey) as? Int ?? 18
        let minute = defaults.object(forKey: workoutMinuteKey) as? Int ?? 0
        let latest = Date.now.addingDays(30)

        for schedule in schedules where schedule.status == .planned && schedule.plannedDate <= latest {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: schedule.plannedDate)
            components.hour = hour
            components.minute = minute
            guard let reminderDate = Calendar.current.date(from: components), reminderDate > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "今天的训练"
            content.body = "\(schedule.templateName) 已经准备好，打开 X-Fit 开始记录。"
            content.sound = .default
            content.userInfo = ["scheduleID": schedule.id.uuidString]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: workoutPrefix + schedule.id.uuidString,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    static func restRequestIdentifier(sessionID: UUID) -> String {
        restPrefix + sessionID.uuidString
    }

    static func isRestRequestIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(restPrefix)
    }

    static func makeRestEndRequest(sessionID: UUID, at endDate: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = "下一组可以开始了。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, endDate.timeIntervalSinceNow),
            repeats: false
        )
        return UNNotificationRequest(
            identifier: restRequestIdentifier(sessionID: sessionID),
            content: content,
            trigger: trigger
        )
    }

    @MainActor
    static func scheduleRestEnd(sessionID: UUID, at endDate: Date) {
        guard UserDefaults.standard.object(forKey: restEnabledKey) == nil
                || UserDefaults.standard.bool(forKey: restEnabledKey) else { return }
        let request = makeRestEndRequest(sessionID: sessionID, at: endDate)
        lastRestSchedulingErrorDescription = nil

        // Submit immediately from the user's tap. Deferring this call to a new
        // MainActor task can leave the request unscheduled when the app is sent
        // to the background immediately after completing a set. Adding another
        // request with the same identifier replaces the existing request.
        UNUserNotificationCenter.current().add(request) { error in
            Task { @MainActor in
                lastRestSchedulingErrorDescription = error?.localizedDescription
            }
        }
    }

    @MainActor
    static func cancelRestEnd(sessionID: UUID) {
        let identifier = restRequestIdentifier(sessionID: sessionID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier]
        )
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [identifier]
        )
    }

    static func replaceRestEndRequest(
        _ request: UNNotificationRequest,
        identifier: String,
        using center: any RestNotificationCenter
    ) async throws {
        await center.removePending(withIdentifiers: [identifier])
        try await center.add(request)
    }

    static func cancelRestEndRequest(
        identifier: String,
        using center: any RestNotificationCenter
    ) async {
        await center.removePending(withIdentifiers: [identifier])
    }

}
