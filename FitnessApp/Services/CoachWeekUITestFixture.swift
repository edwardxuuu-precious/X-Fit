#if DEBUG
import Foundation
import SwiftData

/// Synthetic, in-memory UI data. Never enabled by a normal launch or a persistent test store.
@MainActor
enum CoachWeekUITestFixture {
    static let argument = "--ui-testing-coach-week"
    static let startDay = "2026-11-16"
    static let retainedScheduleID = UUID(uuidString: "7F942CE4-1372-445E-AC38-87EBE06D8604")!

    static func prepare(in context: ModelContext) throws {
        guard CommandLine.arguments.contains(argument), CloudSyncRuntime.isUITesting,
              !CloudSyncRuntime.usesPersistentUITestStore else { return }
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        if try TrainingPreferenceService.current(in: context,
                on: TrainingLocalDate.date(startDay, timeZone: .current) ?? .now) == nil {
            var preference = TrainingPreferenceSnapshot.weekdayFocused
            preference.revisionCode = "UI-COACH-WEEK-PREFERENCE"
            preference.preferredSetPlanPattern = .pyramidUp
            context.insert(try TrainingPreferenceRevision(snapshot: preference, revision: 1,
                effectiveAt: TrainingLocalDate.date("2026-10-01", timeZone: .current) ?? .now,
                reason: "独立 UI 测试合成偏好"))
        }
        let additions: [(String, String, String, ExerciseVolumeUnit)] = [
            ("器械坐姿推胸", "胸部", "器械", .kilogram),
            ("蝴蝶机夹胸", "胸部", "器械", .kilogram),
            ("站姿绳索夹胸", "胸部", "龙门架", .kilogram),
            ("杠铃划船", "背部", "杠铃", .kilogram),
            ("引体向上", "背部", "自重", .bodyweight),
            ("胸托划船", "背部", "器械", .kilogram),
            ("坐姿腿弯举", "腿部", "器械", .kilogram),
            ("腿屈伸", "腿部", "器械", .kilogram),
            ("臀推", "臀部", "杠铃", .kilogram),
            ("哑铃侧平举", "肩部", "哑铃", .kilogram),
            ("坐姿哑铃侧平举", "肩部", "哑铃", .kilogram),
            ("器械反向飞鸟", "肩部", "器械", .kilogram),
            ("垫高绳索站姿侧屈", "核心", "龙门架", .kilogram),
            ("站姿水平伐木", "核心", "龙门架", .kilogram),
            ("绳索跪姿卷腹", "核心", "龙门架", .kilogram),
            ("负重仰卧起坐", "核心", "负重片", .kilogram),
            ("固定单车", "心肺", "单车", .second)
        ]
        for (name, muscle, equipment, unit) in additions where
            !(CommandLine.arguments.contains("--ui-testing-coach-week-missing-cardio") && name == "固定单车") &&
            !(CommandLine.arguments.contains("--ui-testing-coach-week-no-core") && muscle == "核心") &&
            !existing.contains(where: {
            $0.name == name && $0.equipment == equipment && $0.volumeUnit == unit
        }) {
            context.insert(Exercise(name: name, muscleGroup: muscle, equipment: equipment,
                                    isBuiltIn: false, notes: "独立 UI 测试合成动作", volumeUnit: unit))
        }
        let shoulder: [(String, String)] = [
            ("UI器械肩推A", "machine_shoulder_press"),
            ("UI器械肩推B", "machine_shoulder_press"),
            ("UI哑铃肩推A", "seated_dumbbell_shoulder_press"),
            ("UI哑铃肩推B", "seated_dumbbell_shoulder_press"),
            ("UI反向飞鸟A", "machine_reverse_fly"),
            ("UI反向飞鸟B", "machine_reverse_fly")
        ]
        for (name, role) in shoulder where !existing.contains(where: { $0.name == name }) {
            context.insert(Exercise(name: name, muscleGroup: "肩部", equipment: "器械",
                                    isBuiltIn: false, notes: "独立 UI 测试合成动作", volumeUnit: .kilogram,
                                    terminologyCanonicalID: role, terminologyDecision: .accepted))
        }
        let legs: [(String, String)] = [
            ("UI腿部复合A", "landmine_zercher_squat"),
            ("UI腿部复合B", "dumbbell_side_lunge"),
            ("UI腿部髋铰链", "barbell_conventional_deadlift")
        ]
        for (name, role) in legs where !existing.contains(where: { $0.name == name }) {
            context.insert(Exercise(name: name, muscleGroup: "腿部", equipment: "器械",
                                    isBuiltIn: false, notes: "独立 UI 测试合成动作", volumeUnit: .kilogram,
                                    terminologyCanonicalID: role, terminologyDecision: .accepted))
        }
        if CommandLine.arguments.contains("--ui-testing-coach-week-preserved-unknown"),
           try !context.fetch(FetchDescriptor<ScheduledWorkout>()).contains(where: { $0.id == retainedScheduleID }),
           let monday = TrainingLocalDate.date(startDay, timeZone: .current) {
            let schedule = ScheduledWorkout(templateID: UUID(), templateName: "本人既有安排 · 任务待核",
                                            plannedDate: monday, isManuallyScheduled: true)
            schedule.id = retainedScheduleID
            schedule.plannedLocalDay = startDay
            schedule.plannedTimeZoneIdentifier = TimeZone.current.identifier
            // Intentionally no planSnapshot or completed sets: the review must not invent history.
            context.insert(schedule)
        }
        try context.save()
    }
}
#endif
