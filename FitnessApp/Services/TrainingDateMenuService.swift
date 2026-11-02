import Foundation
import SwiftData

struct JumpRopeMenuPlan: Codable, Equatable {
    var targetCount: Int?
    var activeSeconds: Int?
    var elapsedSeconds: Int?
    var notes: String

    var isValid: Bool {
        JumpRopeDurationValidation.isValidRecord(count: targetCount, active: activeSeconds, elapsed: elapsedSeconds)
    }

    var summary: String {
        Self.summary(count: targetCount, active: activeSeconds, elapsed: elapsedSeconds)
    }

    static func summary(count: Int?, active: Int?, elapsed: Int?) -> String {
        var parts: [String] = []
        if let count { parts.append("\(count) 次") }
        if let active { parts.append("有效 \(duration(active))") }
        if let elapsed { parts.append("含休息 \(duration(elapsed))") }
        return parts.isEmpty ? "目标未记录" : parts.joined(separator: " · ")
    }

    private static func duration(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) 分钟" : "\(seconds) 秒"
    }
}

@MainActor
enum TrainingDateMenuService {
    static func isJumpRope(_ schedule: ScheduledWorkout, links: [ProgramWorkoutLink],
                           revisions: [TrainingProgramRevision], exercises: [Exercise]) -> Bool {
        if schedule.jumpRopePlan != nil { return true }
        if let cardio = TrainingPlanPresentation.cardioDraft(scheduleID: schedule.id, links: links, revisions: revisions) {
            return TrainingPlanPresentation.isJumpRope(cardio, exercises: exercises)
        }
        return hasJumpRopeSnapshot(schedule)
    }

    static func cardioScheduleIDs(schedules: [ScheduledWorkout], links: [ProgramWorkoutLink],
                                  revisions: [TrainingProgramRevision]) -> Set<UUID> {
        Set(schedules.filter {
            $0.jumpRopePlan != nil || hasJumpRopeSnapshot($0) || TrainingPlanPresentation.cardioDraft(scheduleID: $0.id,
                links: links, revisions: revisions) != nil
        }.map(\.id))
    }

    private static func hasJumpRopeSnapshot(_ schedule: ScheduledWorkout) -> Bool {
        let items = schedule.planSnapshot
        return !items.isEmpty && items.allSatisfy {
            $0.equipment == "跳绳" && ($0.volumeUnit == .second || $0.volumeUnit == .count)
        }
    }

    @discardableResult
    static func saveJumpRopePlan(_ plan: JumpRopeMenuPlan, localDay: String,
                                  editing schedule: ScheduledWorkout? = nil,
                                  in context: ModelContext) throws -> ScheduledWorkout {
        guard let date = TrainingLocalDate.date(localDay), plan.isValid else {
            throw WellnessToolError.invalidValue("请填写次数或时长，有效时长不能超过总时长。")
        }
        if let schedule {
            guard schedule.jumpRopePlan != nil, schedule.status == .planned,
                  TrainingScheduleDate.localDay(schedule) == localDay else {
                throw WellnessToolError.invalidValue("只能调整这一天尚未完成的手动跳绳安排。")
            }
            let hadChanges = context.hasChanges
            let pending = Set(context.insertedModelsArray.map { ObjectIdentifier($0) })
            let previous = schedule.jumpRopePlanJSON
            let previousUpdate = schedule.updatedAt
            schedule.jumpRopePlan = plan
            schedule.updatedAt = .now
            do {
                if let before = previous.flatMap({ $0.data(using: .utf8) }).flatMap({ try? JSONDecoder().decode(JumpRopeMenuPlan.self, from: $0) }) {
                    try ConfirmedDailyTrainingPlanService.appendRopeAdjustment(schedule: schedule, before: before, in: context)
                }
                try context.save()
            }
            catch {
                schedule.jumpRopePlanJSON = previous
                schedule.updatedAt = previousUpdate
                if !hadChanges { context.rollback() }
                else {
                    for model in context.insertedModelsArray where !pending.contains(ObjectIdentifier(model)) {
                        context.delete(model)
                    }
                }
                throw error
            }
            return schedule
        }
        let template = WorkoutTemplate(name: "跳绳", weekday: date.weekdayNumber,
            isActive: false, isOneOff: true, plannedForDate: date)
        let added = ScheduledWorkout(templateID: template.id, templateName: "跳绳",
            plannedDate: date, isManuallyScheduled: true)
        added.jumpRopePlan = plan
        context.insert(template)
        context.insert(added)
        do { try context.save() }
        catch {
            context.delete(added)
            context.delete(template)
            throw error
        }
        return added
    }

    @discardableResult
    static func recordJumpRope(schedule: ScheduledWorkout, count: Int?, active: Int?, elapsed: Int?,
                               at date: Date, totalSetCount: Int? = nil, recordedTimeKnown: Bool = true,
                               in context: ModelContext) throws -> UUID {
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>())
        let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>())
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        guard isJumpRope(schedule, links: links, revisions: revisions, exercises: exercises) else {
            throw WellnessToolError.invalidValue("所选项目不是跳绳安排。")
        }
        guard date <= .now else {
            throw WellnessToolError.invalidValue("未来的安排尚不能记录完成。")
        }
        return try WellnessToolService.recordJumpRope(count: count, activeDurationSeconds: active,
            elapsedDurationSeconds: elapsed, at: date, scheduledWorkoutID: schedule.id,
            totalSetCount: totalSetCount, recordedTimeKnown: recordedTimeKnown, in: context).recordID!
    }
}
