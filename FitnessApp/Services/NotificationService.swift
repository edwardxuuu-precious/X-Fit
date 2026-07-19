import Foundation
import UserNotifications

enum NotificationService {
    static let workoutEnabledKey = "workoutRemindersEnabled"
    static let workoutHourKey = "workoutReminderHour"
    static let workoutMinuteKey = "workoutReminderMinute"
    static let restEnabledKey = "restTimerNotificationsEnabled"

    private static let workoutPrefix = "xfit.workout."
    private static let restPrefix = "xfit.rest."

    static func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func syncWorkoutReminders(_ schedules: [ScheduledWorkout]) async {
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

    static func scheduleRestEnd(sessionID: UUID, at endDate: Date) {
        guard UserDefaults.standard.object(forKey: restEnabledKey) == nil
                || UserDefaults.standard.bool(forKey: restEnabledKey) else { return }

        let content = UNMutableNotificationContent()
        content.title = "休息结束"
        content.body = "下一组可以开始了。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, endDate.timeIntervalSinceNow),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: restPrefix + sessionID.uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelRestEnd(sessionID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [restPrefix + sessionID.uuidString]
        )
    }
}
