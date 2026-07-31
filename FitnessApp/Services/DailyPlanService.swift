import Foundation
import SwiftData

struct DailyPlanExerciseInput {
    let exerciseID: UUID
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let targetWeight: Double
    let restSeconds: Int
}

enum DailyPlanServiceError: LocalizedError {
    case emptyMuscleGroups
    case emptyExercises
    case immutableExistingPlan

    var errorDescription: String? {
        switch self {
        case .emptyMuscleGroups:
            return "请至少选择一个今天想训练的肌群。"
        case .emptyExercises:
            return "请至少选择一个动作。"
        case .immutableExistingPlan:
            return "今天的自选菜单已经开始或完成，不能直接覆盖。"
        }
    }
}

@MainActor
enum DailyPlanService {
    static func create(
        on date: Date,
        muscleGroups: [String],
        exercises: [DailyPlanExerciseInput],
        replaceExistingPlans: Bool,
        in context: ModelContext
    ) throws -> ScheduledWorkout {
        let normalizedGroups = muscleGroups
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedGroups.isEmpty else {
            throw DailyPlanServiceError.emptyMuscleGroups
        }
        guard !exercises.isEmpty else {
            throw DailyPlanServiceError.emptyExercises
        }

        let targetDate = date.startOfDay
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let templateItems = try context.fetch(FetchDescriptor<TemplateExercise>())
        let templateByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })

        let existingOneOffs = schedules.filter {
            $0.plannedDate.isSameDay(as: targetDate)
                && templateByID[$0.templateID]?.isOneOff == true
        }
        guard existingOneOffs.allSatisfy({ $0.status == .planned || $0.status == .skipped }) else {
            throw DailyPlanServiceError.immutableExistingPlan
        }

        for schedule in existingOneOffs {
            let templateID = schedule.templateID
            context.delete(schedule)
            templateItems
                .filter { $0.templateID == templateID }
                .forEach(context.delete)
            if let template = templateByID[templateID] {
                context.delete(template)
            }
        }

        if replaceExistingPlans {
            for schedule in schedules where schedule.plannedDate.isSameDay(as: targetDate)
                    && schedule.status == .planned
                    && !existingOneOffs.contains(where: { $0.id == schedule.id }) {
                schedule.status = .skipped
                schedule.skipReason = "已用当天自选菜单替代"
                schedule.updatedAt = .now
            }
        }

        let titleGroups = normalizedGroups.prefix(3).joined(separator: " + ")
        let template = WorkoutTemplate(
            name: "\(titleGroups) · 当天菜单",
            weekday: targetDate.weekdayNumber,
            isActive: false,
            isOneOff: true,
            plannedForDate: targetDate,
            focusMuscleGroups: normalizedGroups
        )
        context.insert(template)

        for (index, item) in exercises.enumerated() {
            context.insert(
                TemplateExercise(
                    templateID: template.id,
                    exerciseID: item.exerciseID,
                    order: index,
                    targetSets: max(1, item.targetSets),
                    minReps: max(1, item.minReps),
                    maxReps: max(max(1, item.minReps), item.maxReps),
                    targetWeight: max(0, item.targetWeight),
                    restSeconds: max(30, item.restSeconds)
                )
            )
        }

        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: targetDate,
            isManuallyScheduled: true
        )
        context.insert(schedule)
        try context.save()

        let refreshedSchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        Task {
            await NotificationService.syncWorkoutReminders(refreshedSchedules)
        }
        return schedule
    }
}
