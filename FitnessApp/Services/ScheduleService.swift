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
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let today = Date.now.startOfDay
        _ = days

        for template in templates where !template.isOneOff {
            template.isActive = false
        }

        for schedule in schedules where schedule.plannedDate >= today && schedule.status == .planned {
            guard let template = templates.first(where: { $0.id == schedule.templateID }) else {
                context.delete(schedule)
                continue
            }
            schedule.templateName = template.name

            if !schedule.isManuallyScheduled && schedule.originalPlannedDate == nil {
                context.delete(schedule)
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
        let templateID = schedule.templateID
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let templateItems = try context.fetch(FetchDescriptor<TemplateExercise>())
        if FatLossBackupService.isRegistered(ProgramWorkoutLink.self, in: context) {
            let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>())
            links.filter { $0.scheduledWorkoutID == schedule.id }.forEach(context.delete)
        }
        context.delete(schedule)
        if let template = templates.first(where: { $0.id == templateID && $0.isOneOff }) {
            templateItems
                .filter { $0.templateID == templateID }
                .forEach(context.delete)
            context.delete(template)
        }
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
