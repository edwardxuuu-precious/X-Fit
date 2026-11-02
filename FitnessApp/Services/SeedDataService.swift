import Foundation
import SwiftData

@MainActor
enum SeedDataService {
    static func prepareIfNeeded(
        in context: ModelContext,
        allowInitialSeed: Bool = true
    ) throws {
        let exerciseDescriptor = FetchDescriptor<Exercise>()
        let existingExercises = try context.fetch(exerciseDescriptor)
        var hasExercises = !existingExercises.isEmpty

        if existingExercises.isEmpty, allowInitialSeed {
            try seedStarterProgram(in: context)
            hasExercises = true
        }

        if hasExercises, try context.fetch(FetchDescriptor<NutritionTarget>()).isEmpty {
            context.insert(NutritionTarget())
        }

        try WeightedExerciseIdentityMigration.applyConfirmedCorrections(in: context)
        try ExerciseCatalogService.consolidateConfirmedSquatDuplicate(in: context)
        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)
        try BodyweightVolumeMigration.applyConfirmedAllowlist(in: context)
        // A cloud-restore placeholder must remain empty when initial seeding is
        // disabled. Supplements extend an existing catalog; they cannot seed one.
        if hasExercises {
            _ = try ExerciseCatalogService.ensureNotesCatalogSupplement(in: context)
        }
        try ExerciseTerminologyService.stageCatalogCandidates(in: context)
        normalizeImportedWorkoutNames(in: context)
        if TrainingPreferenceService.isRegistered(in: context) {
            _ = try TrainingPreferenceService.ensureConfirmedProfile(in: context)
            _ = try TrainingPreferenceService.ensurePyramidPreference(in: context)
            #if DEBUG
            if !CloudSyncRuntime.isUITesting || CommandLine.arguments.contains("--ui-testing-coach-week-alternating") {
                _ = try TrainingPreferenceService.ensureAlternatingPreference(in: context)
            }
            #else
            _ = try TrainingPreferenceService.ensureAlternatingPreference(in: context)
            #endif
            if context.container.schema.entities.contains(where: {
                $0.name == String(describing: FatLossProgram.self)
            }), let program = try FatLossService.activeProgram(in: context) {
                _ = try TrainingPreferenceService.ensureProgramRevision(
                    programID: program.id,
                    effectiveDate: program.startDate,
                    in: context
                )
            }
        }
        try ScheduleService.refreshUpcoming(in: context)
        try context.save()
    }

    static func normalizedImportedWorkoutName(_ name: String) -> String {
        let suffixes = [" (Notes)", "（Notes）"]
        for suffix in suffixes where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name
    }

    private static func normalizeImportedWorkoutNames(in context: ModelContext) {
        guard let sessions = try? context.fetch(FetchDescriptor<WorkoutSession>()) else { return }
        for session in sessions where !session.importIdentifier.isEmpty {
            session.templateName = normalizedImportedWorkoutName(session.templateName)
        }
    }

    private static func seedStarterProgram(in context: ModelContext) throws {
        let exercises = [
            Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃", defaultRestSeconds: 120),
            Exercise(name: "上斜哑铃卧推", muscleGroup: "胸部", equipment: "哑铃", defaultRestSeconds: 90),
            Exercise(name: "坐姿推举", muscleGroup: "肩部", equipment: "哑铃", defaultRestSeconds: 90),
            Exercise(name: "绳索下压", muscleGroup: "手臂", equipment: "龙门架", defaultRestSeconds: 60),
            Exercise(name: "高位下拉", muscleGroup: "背部", equipment: "器械", defaultRestSeconds: 90),
            Exercise(name: "坐姿划船", muscleGroup: "背部", equipment: "器械", defaultRestSeconds: 90),
            Exercise(name: "面拉", muscleGroup: "肩部", equipment: "龙门架", defaultRestSeconds: 60),
            Exercise(name: "哑铃弯举", muscleGroup: "手臂", equipment: "哑铃", defaultRestSeconds: 60),
            Exercise(name: "深蹲", muscleGroup: "腿部", equipment: "杠铃", defaultRestSeconds: 150),
            Exercise(name: "罗马尼亚硬拉", muscleGroup: "腿部", equipment: "杠铃", defaultRestSeconds: 120),
            Exercise(name: "腿举", muscleGroup: "腿部", equipment: "器械", defaultRestSeconds: 90),
            Exercise(name: "站姿提踵", muscleGroup: "小腿", equipment: "器械", defaultRestSeconds: 60)
        ]
        exercises.forEach(context.insert)

        let todayWeekday = Date.now.weekdayNumber
        let push = WorkoutTemplate(name: "推 · 胸肩三头", weekday: todayWeekday, isActive: false)
        let pull = WorkoutTemplate(name: "拉 · 背部二头", weekday: Date.now.addingDays(2).weekdayNumber, isActive: false)
        let legs = WorkoutTemplate(name: "腿 · 下肢力量", weekday: Date.now.addingDays(4).weekdayNumber, isActive: false)
        [push, pull, legs].forEach(context.insert)

        add(push, exercises: [
            (exercises[0], 3, 8, 12, 40, 120),
            (exercises[1], 3, 8, 12, 16, 90),
            (exercises[2], 3, 8, 12, 12, 90),
            (exercises[3], 3, 10, 15, 15, 60)
        ], to: context)

        add(pull, exercises: [
            (exercises[4], 3, 8, 12, 35, 90),
            (exercises[5], 3, 8, 12, 35, 90),
            (exercises[6], 3, 12, 15, 12.5, 60),
            (exercises[7], 3, 10, 15, 10, 60)
        ], to: context)

        add(legs, exercises: [
            (exercises[8], 3, 6, 10, 50, 150),
            (exercises[9], 3, 8, 12, 45, 120),
            (exercises[10], 3, 10, 15, 60, 90),
            (exercises[11], 4, 10, 15, 30, 60)
        ], to: context)
    }

    private static func add(
        _ template: WorkoutTemplate,
        exercises: [(Exercise, Int, Int, Int, Double, Int)],
        to context: ModelContext
    ) {
        for (index, item) in exercises.enumerated() {
            context.insert(
                TemplateExercise(
                    templateID: template.id,
                    exerciseID: item.0.id,
                    order: index,
                    targetSets: item.1,
                    minReps: item.2,
                    maxReps: item.3,
                    targetWeight: item.4,
                    restSeconds: item.5
                )
            )
        }
    }
}
