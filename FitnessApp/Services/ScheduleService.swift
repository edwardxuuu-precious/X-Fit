import Foundation
import SwiftData

enum ScheduleServiceError: LocalizedError, Equatable {
    case immutableSchedule
    case duplicateSchedule

    var errorDescription: String? {
        switch self {
        case .immutableSchedule:
            return "已经开始或完成的训练不能再调整日期。"
        case .duplicateSchedule:
            return "这一天已经安排了同一个训练计划。"
        }
    }
}

@MainActor
enum ScheduleService {
    static func refreshUpcoming(in context: ModelContext, days: Int = 14) throws {
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let activeTemplates = templates.filter(\.isActive)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let today = Date.now.startOfDay

        for schedule in schedules where schedule.plannedDate >= today && schedule.status == .planned {
            let isOverride = schedule.isManuallyScheduled || schedule.originalPlannedDate != nil
            guard let template = templates.first(where: { $0.id == schedule.templateID }) else {
                context.delete(schedule)
                continue
            }
            schedule.templateName = template.name

            if !isOverride, (!template.isActive || template.weekday != schedule.plannedDate.weekdayNumber) {
                context.delete(schedule)
            }
        }

        for offset in 0..<days {
            let date = today.addingDays(offset)
            for template in activeTemplates where template.weekday == date.weekdayNumber {
                let alreadyExists = schedules.contains {
                    $0.templateID == template.id && (
                        $0.plannedDate.isSameDay(as: date)
                        || $0.originalPlannedDate?.isSameDay(as: date) == true
                    )
                }
                if !alreadyExists {
                    context.insert(
                        ScheduledWorkout(
                            templateID: template.id,
                            templateName: template.name,
                            plannedDate: date
                        )
                    )
                }
            }
        }
    }

    static func addManual(
        template: WorkoutTemplate,
        on date: Date,
        in context: ModelContext
    ) throws -> ScheduledWorkout {
        let targetDate = date.startOfDay
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        guard !schedules.contains(where: {
            $0.templateID == template.id && $0.plannedDate.isSameDay(as: targetDate)
        }) else {
            throw ScheduleServiceError.duplicateSchedule
        }

        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: targetDate,
            isManuallyScheduled: true
        )
        context.insert(schedule)
        try context.save()
        syncNotifications(in: context)
        return schedule
    }

    static func reschedule(
        _ schedule: ScheduledWorkout,
        to date: Date,
        in context: ModelContext
    ) throws {
        guard schedule.status == .planned || schedule.status == .skipped else {
            throw ScheduleServiceError.immutableSchedule
        }

        let targetDate = date.startOfDay
        let scheduleID = schedule.id
        let templateID = schedule.templateID
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        guard !schedules.contains(where: {
            $0.id != scheduleID
                && $0.templateID == templateID
                && $0.plannedDate.isSameDay(as: targetDate)
        }) else {
            throw ScheduleServiceError.duplicateSchedule
        }

        if schedule.originalPlannedDate == nil {
            schedule.originalPlannedDate = schedule.plannedDate
        }
        schedule.plannedDate = targetDate
        schedule.status = .planned
        schedule.skipReason = ""
        schedule.updatedAt = .now
        try context.save()
        syncNotifications(in: context)
    }

    static func skip(
        _ schedule: ScheduledWorkout,
        reason: String,
        in context: ModelContext
    ) throws {
        guard schedule.status == .planned else {
            throw ScheduleServiceError.immutableSchedule
        }
        schedule.status = .skipped
        schedule.skipReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.reminderDate = nil
        schedule.updatedAt = .now
        try context.save()
        syncNotifications(in: context)
    }

    static func restore(
        _ schedule: ScheduledWorkout,
        in context: ModelContext
    ) throws {
        guard schedule.status == .skipped else {
            throw ScheduleServiceError.immutableSchedule
        }
        schedule.status = .planned
        schedule.skipReason = ""
        schedule.updatedAt = .now
        try context.save()
        syncNotifications(in: context)
    }

    static func deleteManual(
        _ schedule: ScheduledWorkout,
        in context: ModelContext
    ) throws {
        guard schedule.isManuallyScheduled, schedule.status == .planned || schedule.status == .skipped else {
            throw ScheduleServiceError.immutableSchedule
        }
        context.delete(schedule)
        try context.save()
        syncNotifications(in: context)
    }

    private static func syncNotifications(in context: ModelContext) {
        guard let allSchedules = try? context.fetch(FetchDescriptor<ScheduledWorkout>()) else { return }
        Task {
            await NotificationService.syncWorkoutReminders(allSchedules)
        }
    }
}
