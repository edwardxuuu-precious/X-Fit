import Foundation
import SwiftData

struct CardioWorkoutSummary: Equatable {
    let title: String
    let symbolName: String
    let durationSeconds: Int?
    var level: Double? = nil

    var durationValue: String {
        guard let seconds = durationSeconds else { return "—" }
        return seconds % 60 == 0 ? String(seconds / 60) : "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
    var durationUnit: String { durationSeconds.map { $0 % 60 == 0 ? "分钟" : "分:秒" } ?? "分钟" }
    var durationLabel: String {
        guard let seconds = durationSeconds else { return "时长未记录" }
        return seconds % 60 == 0 ? "\(seconds / 60) 分钟" : "\(seconds / 60) 分 \(seconds % 60) 秒"
    }
    var levelLabel: String? { level.map { "Level " + TrainingFormatters.weight($0) } }
    var label: String { ([durationLabel, levelLabel].compactMap { $0 }).joined(separator: " · ") }
}

/// Uses frozen cardio identity and second-based actuals, never a strength load or a guessed clock interval.
enum CardioWorkoutPresentation {
    static func symbol(name: String, muscle: String, equipment: String, unit: ExerciseVolumeUnit) -> String? {
        guard unit == .second, muscle == "心肺", equipment != "跳绳", !name.contains("跳绳") else { return nil }
        if name.contains("椭圆机") { return "figure.elliptical" }
        if name.contains("单车") || name.contains("骑行") { return "figure.indoor.cycle" }
        if name.contains("步行") || name.contains("快走") { return "figure.walk" }
        if name.contains("跑步") { return "figure.run" }
        if equipment.contains("椭圆机") { return "figure.elliptical" }
        if equipment.contains("单车") { return "figure.indoor.cycle" }
        return nil
    }

    static func plan(_ schedule: ScheduledWorkout) -> CardioWorkoutSummary? {
        let items = schedule.planSnapshot
        guard items.count == 1, let item = items.first, item.targetSets == 1, item.plannedSets.count == 1,
              let symbol = symbol(name: item.exerciseName, muscle: item.muscleGroup, equipment: item.equipment, unit: item.volumeUnit) else { return nil }
        let seconds = item.plannedSets.reduce(0) { $0 + max(0, $1.reps) }
        return .init(title: TrainingWorkoutPresentation.upcoming(schedule.templateName).title,
            symbolName: symbol, durationSeconds: seconds > 0 ? seconds : nil)
    }

    static func actual(_ session: WorkoutSession, exercises: [SessionExercise], logs: [SetLog]) -> CardioWorkoutSummary? {
        let items = exercises.filter { $0.sessionID == session.id }
        guard items.count == 1, let item = items.first,
              let symbol = symbol(name: item.exerciseName, muscle: item.muscleGroup,
                  equipment: item.equipmentSnapshot ?? "", unit: item.volumeUnit) else { return nil }
        let actuals = logs.filter { $0.sessionID == session.id && $0.sessionExerciseID == item.id && $0.isCompleted && !$0.isWarmup }
        let seconds = actuals.reduce(0) { $0 + max(0, $1.actualReps) }
        return .init(title: TrainingWorkoutPresentation.upcoming(session.templateName).title,
            symbolName: symbol, durationSeconds: seconds > 0 ? seconds : nil, level: session.cardioResistanceLevel)
    }
}

@MainActor
enum CardioWorkoutService {
    /// Repeating the same completion returns its record. Changes require an explicit edit of that record.
    @discardableResult
    static func record(schedule: ScheduledWorkout, seconds: Int, level: Double?, editingSessionID: UUID? = nil,
                       in context: ModelContext) throws -> UUID {
        guard (1...86_400).contains(seconds), level.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw WellnessToolError.invalidValue("请填写有效的实际时长和 Level。")
        }
        let day = TrainingScheduleDate.localDay(schedule)
        guard TrainingLocalDate.date(day) != nil, day <= TrainingLocalDate.key(.now),
              CardioWorkoutPresentation.plan(schedule) != nil,
              let plan = schedule.planSnapshot.first, plan.targetSets == 1, plan.plannedSets.count == 1 else {
            throw WellnessToolError.invalidValue("只能记录已到日期的单段有氧安排。")
        }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).filter {
            $0.scheduledWorkoutID == schedule.id && $0.status != .discarded
        }
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())
        if let existing = sessions.first {
            guard sessions.count == 1, existing.status == .completed,
                  let summary = CardioWorkoutPresentation.actual(existing, exercises: snapshots, logs: logs) else {
                throw WellnessToolError.invalidValue("这项安排已有其他实际记录，请先查看原记录。")
            }
            guard TrainingHistoryDate.localDay(existing, schedule: schedule) == day else {
                throw WellnessToolError.invalidValue("实际记录与所选日期不一致。")
            }
            if editingSessionID == nil {
                guard summary.durationSeconds == seconds, summary.level == level else {
                    throw WellnessToolError.invalidValue("这次训练已记录，请从训练总结修改原记录。")
                }
                return existing.id
            }
            let ownLogs = logs.filter { $0.sessionID == existing.id && !$0.isWarmup }
            guard editingSessionID == existing.id, ownLogs.count == 1, let log = ownLogs.first else {
                throw WellnessToolError.invalidValue("请在原分段记录中修改这次训练。")
            }
            let previous = (log.actualReps, log.actualEntrySourceRaw, existing.cardioResistanceLevel)
            log.actualReps = seconds
            log.actualEntrySource = .manual
            existing.cardioResistanceLevel = level
            do { try context.save() }
            catch {
                log.actualReps = previous.0; log.actualEntrySourceRaw = previous.1
                existing.cardioResistanceLevel = previous.2
                throw error
            }
            return existing.id
        }
        guard editingSessionID == nil, schedule.status == .planned,
              try !ConfirmedDailyTrainingPlanService.isSuperseded(schedule.id, in: context) else {
            throw WellnessToolError.invalidValue("安排状态已改变，请返回训练菜单核对。")
        }
        let date = TrainingScheduleDate.displayDate(schedule)
        let session = WorkoutSession(scheduledWorkoutID: schedule.id, templateID: schedule.templateID,
            templateName: schedule.templateName, plannedDate: date, startedAt: date,
            isStartTimeKnown: false, status: .completed)
        TrainingHistoryDate.capture(session, date: date, schedule: schedule)
        session.cardioResistanceLevel = level
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: plan.exerciseID,
            exerciseName: plan.exerciseName, order: plan.order, targetSets: plan.targetSets,
            minReps: plan.minReps, maxReps: plan.maxReps, targetWeight: plan.targetWeight,
            restSeconds: plan.restSeconds, muscleGroup: plan.muscleGroup, exerciseNotes: plan.exerciseNotes,
            referenceURL: plan.referenceURL, volumeUnit: plan.volumeUnit, plannedSets: plan.plannedSets,
            planPattern: plan.planPattern, patternSource: plan.patternSource, equipmentSnapshot: plan.equipment)
        let log = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: plan.exerciseID,
            setNumber: 1, targetWeight: plan.targetWeight, targetReps: plan.plannedSets[0].reps,
            actualWeight: 0, actualReps: seconds, isCompleted: true,
            targetWeightSide: .unknown, targetRepsSide: .unknown, actualWeightSide: .unknown,
            actualRepsSide: .unknown, actualEntrySource: .manual, actualWeightIsBlank: true)
        let previousStatus = schedule.statusRaw, previousUpdate = schedule.updatedAt
        context.insert(session); context.insert(snapshot); context.insert(log)
        schedule.status = .completed; schedule.updatedAt = .now
        do { try context.save() }
        catch {
            context.delete(log); context.delete(snapshot); context.delete(session)
            schedule.statusRaw = previousStatus; schedule.updatedAt = previousUpdate
            throw error
        }
        return session.id
    }
}
