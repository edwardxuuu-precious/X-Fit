import Foundation
import SwiftData

struct DailyPlanPatternTarget: Equatable {
    var pattern: SetPlanPattern
    var patternSource: PlanPatternSource
    var plannedSets: [WorkoutSetPlan]
    var restSeconds: Int
}

struct DailyPlanPatternChange: Equatable {
    let targets: [UUID: DailyPlanPatternTarget]
    let updatedCount: Int
    let overrideCount: Int
}

enum DailyPlanPatternPolicy {
    static func applying(
        _ pattern: SetPlanPattern,
        to targets: [UUID: DailyPlanPatternTarget],
        orderedIDs: [UUID],
        includeLegacyValues: Bool = false
    ) -> DailyPlanPatternChange {
        var updatedTargets = targets
        let inheritedIDs = orderedIDs.filter {
            includeLegacyValues || targets[$0]?.patternSource == .dayDefault
        }

        for id in inheritedIDs {
            guard var target = updatedTargets[id] else { continue }
            target.pattern = pattern
            target.patternSource = .dayDefault
            target.plannedSets = presetPlans(for: target, pattern: pattern)
            updatedTargets[id] = target
        }

        return DailyPlanPatternChange(
            targets: updatedTargets,
            updatedCount: inheritedIDs.count,
            overrideCount: max(0, orderedIDs.count - inheritedIDs.count)
        )
    }

    static func restoring(
        _ target: DailyPlanPatternTarget,
        to pattern: SetPlanPattern
    ) -> DailyPlanPatternTarget {
        var restored = target
        restored.pattern = pattern
        restored.patternSource = .dayDefault
        restored.plannedSets = presetPlans(for: restored, pattern: pattern)
        return restored
    }

    private static func presetPlans(
        for target: DailyPlanPatternTarget,
        pattern: SetPlanPattern
    ) -> [WorkoutSetPlan] {
        guard let first = target.plannedSets.first else {
            return WorkoutSetPlan.preset(pattern, count: 3, baseWeight: 0, baseReps: 8)
        }
        return WorkoutSetPlan.preset(
            pattern,
            count: target.plannedSets.count,
            baseWeight: target.plannedSets.map(\.weight).min() ?? first.weight,
            baseReps: target.plannedSets.map(\.reps).max() ?? first.reps
        )
    }
}

struct DailyPlanPatternLoadResolution: Equatable {
    let dayPattern: SetPlanPattern
    let isLegacyMixed: Bool
    let sources: [UUID: PlanPatternSource]
}

enum DailyPlanPatternMetadataPolicy {
    static func resolve(
        explicitPatternRaw: String?,
        itemPatterns: [(UUID, SetPlanPattern, String?)]
    ) -> DailyPlanPatternLoadResolution {
        if let explicitPattern = explicitPatternRaw.flatMap(SetPlanPattern.init(rawValue:)) {
            let sources = Dictionary(uniqueKeysWithValues: itemPatterns.map { item in
                (item.0, item.2.flatMap(PlanPatternSource.init(rawValue:)) ?? .exerciseOverride)
            })
            return DailyPlanPatternLoadResolution(
                dayPattern: explicitPattern,
                isLegacyMixed: false,
                sources: sources
            )
        }

        let uniquePatterns = Set(itemPatterns.map { $0.1 })
        if uniquePatterns.count == 1, let inferred = uniquePatterns.first {
            return DailyPlanPatternLoadResolution(
                dayPattern: inferred,
                isLegacyMixed: false,
                sources: Dictionary(uniqueKeysWithValues: itemPatterns.map { ($0.0, .dayDefault) })
            )
        }

        return DailyPlanPatternLoadResolution(
            dayPattern: itemPatterns.first?.1 ?? .fixed,
            isLegacyMixed: !itemPatterns.isEmpty,
            sources: Dictionary(uniqueKeysWithValues: itemPatterns.map { ($0.0, .exerciseOverride) })
        )
    }
}

struct DailyPlanExerciseInput {
    let exerciseID: UUID
    let plannedSets: [WorkoutSetPlan]
    let planPattern: SetPlanPattern
    let patternSource: PlanPatternSource
    let restSeconds: Int

    init(
        exerciseID: UUID,
        plannedSets: [WorkoutSetPlan],
        planPattern: SetPlanPattern,
        patternSource: PlanPatternSource = .exerciseOverride,
        restSeconds: Int
    ) {
        self.exerciseID = exerciseID
        self.plannedSets = plannedSets
        self.planPattern = planPattern
        self.patternSource = patternSource
        self.restSeconds = restSeconds
    }

    /// Compatibility for existing callers and legacy weekly targets.
    init(
        exerciseID: UUID,
        targetSets: Int,
        minReps: Int,
        maxReps _: Int,
        targetWeight: Double,
        restSeconds: Int
    ) {
        self.init(
            exerciseID: exerciseID,
            plannedSets: WorkoutSetPlan.preset(
                .fixed,
                count: targetSets,
                baseWeight: targetWeight,
                baseReps: minReps
            ),
            planPattern: .fixed,
            patternSource: .exerciseOverride,
            restSeconds: restSeconds
        )
    }
}

enum DailyPlanServiceError: LocalizedError {
    case emptyMuscleGroups
    case emptyExercises
    case duplicateExercise
    case missingExercise
    case archivedExercise
    case immutableExistingPlan

    var errorDescription: String? {
        switch self {
        case .emptyMuscleGroups:
            return "请至少选择一个今天想训练的肌群。"
        case .emptyExercises:
            return "请至少选择一个动作。"
        case .duplicateExercise:
            return "当天菜单里有重复动作，请先移除重复项。"
        case .missingExercise:
            return "有动作已不在动作库中，请重新选择后再保存。"
        case .archivedExercise:
            return "有动作已归档，请恢复或替换后再保存。"
        case .immutableExistingPlan:
            return "今天的自选菜单已经开始或完成，不能直接覆盖。"
        }
    }
}

@MainActor
enum DailyPlanService {
    /// An explicit UUID edits one occurrence. Templates are copied so shared and
    /// historical assets, other same-day projects and imported source packets survive.
    static func update(scheduleID: UUID, muscleGroups: [String], defaultPlanPattern: SetPlanPattern = .fixed,
                       exercises inputs: [DailyPlanExerciseInput], in context: ModelContext,
                       commit: (ModelContext) throws -> Void = { try $0.save() }) throws -> ScheduledWorkout {
        guard !context.hasChanges else { throw ScheduleServiceError.unsavedChanges }
        let groups = muscleGroups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !groups.isEmpty else { throw DailyPlanServiceError.emptyMuscleGroups }
        guard !inputs.isEmpty else { throw DailyPlanServiceError.emptyExercises }
        guard Set(inputs.map(\.exerciseID)).count == inputs.count else { throw DailyPlanServiceError.duplicateExercise }
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        guard let schedule = schedules.first(where: { $0.id == scheduleID }) else { throw DailyPlanServiceError.immutableExistingPlan }
        try ScheduleService.validateUnstarted(schedule, in: context)
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>())
        let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>())
        guard CardioWorkoutPresentation.plan(schedule) == nil,
              !TrainingDateMenuService.cardioScheduleIDs(schedules: schedules, links: links, revisions: revisions).contains(schedule.id) else {
            throw DailyPlanServiceError.immutableExistingPlan
        }
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        for input in inputs {
            guard let exercise = byID[input.exerciseID] else { throw DailyPlanServiceError.missingExercise }
            guard !exercise.isArchived else { throw DailyPlanServiceError.archivedExercise }
            guard !input.plannedSets.isEmpty else { throw DailyPlanServiceError.emptyExercises }
        }
        let capture = try ConfirmedTrainingPlanService.captureScheduleAdjustment(schedule, in: context)
        let before = ScheduleManagementState(schedule)
        let previousSources = capture.weekly.map { ($0.revision, $0.revision.snapshotJSON) }
        let oldTemplate = try context.fetch(FetchDescriptor<WorkoutTemplate>()).first { $0.id == schedule.templateID }
        let oldSnapshots = Dictionary(uniqueKeysWithValues: schedule.planSnapshot.map { ($0.exerciseID, $0) })
        let autosave = context.autosaveEnabled; context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            let template = WorkoutTemplate(name: schedule.templateName, weekday: schedule.plannedDate.weekdayNumber,
                isActive: false, isOneOff: true, plannedForDate: schedule.plannedDate,
                focusMuscleGroups: groups, defaultPlanPattern: defaultPlanPattern)
            template.trainingPreferenceSnapshotJSON = oldTemplate?.trainingPreferenceSnapshotJSON
            context.insert(template)
            var frozen: [ScheduledWorkoutExerciseSnapshot] = []
            for (order, input) in inputs.enumerated() {
                guard let exercise = byID[input.exerciseID], let first = input.plannedSets.first else {
                    throw DailyPlanServiceError.missingExercise
                }
                let previous = oldSnapshots[exercise.id]
                let lower = input.plannedSets.map { $0.prescription?.repsLower ?? $0.reps }.min() ?? first.reps
                let upper = input.plannedSets.map { $0.prescription?.repsUpper ?? $0.reps }.max() ?? first.reps
                let item = TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: order,
                    targetSets: input.plannedSets.count, minReps: lower, maxReps: upper,
                    targetWeight: first.weight, restSeconds: input.restSeconds, plannedSets: input.plannedSets,
                    planPattern: input.planPattern, patternSource: input.patternSource)
                context.insert(item)
                frozen.append(ScheduledWorkoutExerciseSnapshot(id: item.id, exerciseID: exercise.id,
                    exerciseName: previous?.exerciseName ?? exercise.name, muscleGroup: previous?.muscleGroup ?? exercise.muscleGroup,
                    equipment: previous?.equipment ?? exercise.equipment, exerciseNotes: previous?.exerciseNotes ?? exercise.notes,
                    referenceURL: previous?.referenceURL ?? exercise.referenceURL, volumeUnit: previous?.volumeUnit ?? exercise.volumeUnit,
                    order: order, targetSets: input.plannedSets.count, minReps: lower, maxReps: upper,
                    targetWeight: first.weight, restSeconds: input.restSeconds, plannedSets: input.plannedSets,
                    planPattern: input.planPattern, patternSource: input.patternSource))
            }
            schedule.templateID = template.id
            schedule.planSnapshot = frozen
            schedule.updatedAt = .now
            try ConfirmedTrainingPlanService.appendScheduleAdjustment(schedule, capture: capture, kind: "edit")
            _ = try ConfirmedTrainingPlanService.captureScheduleAdjustment(schedule, in: context)
            try commit(context)
            return schedule
        } catch {
            before.restore(schedule)
            for (revision, json) in previousSources { revision.snapshotJSON = json }
            context.rollback()
            throw error
        }
    }

    static func create(
        on date: Date,
        muscleGroups: [String],
        defaultPlanPattern: SetPlanPattern = .fixed,
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
        guard Set(exercises.map(\.exerciseID)).count == exercises.count else {
            throw DailyPlanServiceError.duplicateExercise
        }

        // Read the effective preference before any schedule mutation; historical plans keep their snapshot.
        let preferenceJSON = try TrainingPreferenceService.current(in: context, on: FatLossCalendar.day(date))?.snapshotJSON
        // Validate the entire draft before deleting or skipping any existing plan.
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        let exerciseByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        for item in exercises {
            guard let exercise = exerciseByID[item.exerciseID] else {
                throw DailyPlanServiceError.missingExercise
            }
            guard !exercise.isArchived else {
                throw DailyPlanServiceError.archivedExercise
            }
        }

        let targetDate = date.startOfDay
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let templateItems = try context.fetch(FetchDescriptor<TemplateExercise>())
        let templateByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })

        // Editing a strength menu must preserve the other training projects of this day.
        let cardioIDs = TrainingDateMenuService.cardioScheduleIDs(schedules: schedules,
            links: try context.fetch(FetchDescriptor<ProgramWorkoutLink>()),
            revisions: try context.fetch(FetchDescriptor<TrainingProgramRevision>()))

        let existingOneOffs = schedules.filter {
            $0.plannedDate.isSameDay(as: targetDate)
                && !cardioIDs.contains($0.id)
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
                    && !cardioIDs.contains(schedule.id)
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
            focusMuscleGroups: normalizedGroups,
            defaultPlanPattern: defaultPlanPattern
        )
        template.trainingPreferenceSnapshotJSON = preferenceJSON
        context.insert(template)

        for (index, item) in exercises.enumerated() {
            let plans = item.plannedSets.isEmpty
                ? [WorkoutSetPlan(weight: 0, reps: 1)]
                : item.plannedSets
            context.insert(
                TemplateExercise(
                    templateID: template.id,
                    exerciseID: item.exerciseID,
                    order: index,
                    targetSets: plans.count,
                    minReps: plans.map(\.reps).min() ?? 1,
                    maxReps: plans.map(\.reps).max() ?? 1,
                    targetWeight: plans.first?.weight ?? 0,
                    restSeconds: max(30, item.restSeconds),
                    plannedSets: plans,
                    planPattern: item.planPattern,
                    patternSource: item.patternSource
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
        try ScheduleService.freezePlanSnapshot(for: schedule, in: context)
        try context.save()

        let refreshedSchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        Task {
            await NotificationService.syncWorkoutReminders(refreshedSchedules)
        }
        return schedule
    }
}
