import Foundation
import SwiftData

enum WorkoutServiceError: LocalizedError {
    case emptyTemplate
    case scheduleNotReady
    case activeSessionExists
    case missingExerciseReference
    case archivedExercise
    case sessionNotInProgress
    case exerciseAlreadyAdded
    case noIncompleteSet
    case reductionNeedsConfirmation
    case reducedExercisePlanLocked
    case cannotRemoveStartedExercise
    case cannotRemoveLastExercise
    case invalidExerciseOrder
    case replacementNeedsConfirmation
    case replacementSourceChanged
    case pendingChangesBeforeReplacement
    case invalidReplacementPlan

    var errorDescription: String? {
        switch self {
        case .emptyTemplate:
            return "这个训练计划还没有动作，请先在计划页添加动作。"
        case .scheduleNotReady:
            return "这项日程当前不能开始训练，请先调整日程状态。"
        case .activeSessionExists:
            return "已有一场训练正在进行，请先完成或放弃后再开始新的训练。"
        case .missingExerciseReference:
            return "训练菜单中的动作已不在动作库中，请先调整菜单。"
        case .archivedExercise:
            return "训练菜单中包含已归档动作，请先恢复或替换。"
        case .sessionNotInProgress:
            return "这场训练已经结束，不能再修改训练菜单。"
        case .exerciseAlreadyAdded:
            return "这个动作已经在本次训练菜单里。"
        case .noIncompleteSet:
            return "没有可以移除的未完成组。"
        case .reductionNeedsConfirmation:
            return "这组已有输入，请确认后再减组。"
        case .reducedExercisePlanLocked:
            return "该动作有已减组记录，请先撤销减组，再修改该动作的计划。"
        case .cannotRemoveStartedExercise:
            return "这个动作已有填写、开始或完成的记录，不能从本次记录中移除。"
        case .cannotRemoveLastExercise:
            return "本次训练至少需要保留一个动作。"
        case .invalidExerciseOrder:
            return "动作列表已变化，请重新打开列表后调整顺序。"
        case .replacementNeedsConfirmation:
            return "剩余组已有输入，请确认归档这些输入后再替换。"
        case .replacementSourceChanged:
            return "原动作或剩余组已变化，请重新打开替换动作。"
        case .pendingChangesBeforeReplacement:
            return "训练输入尚未保存，请先保存后再替换动作。"
        case .invalidReplacementPlan:
            return "替换动作至少需要设置一组。"
        }
    }
}

struct WorkoutExerciseReplacementReview: Equatable {
    struct SetState: Equatable {
        let id: UUID
        let sessionID: UUID
        let exerciseID: UUID
        let setNumber: Int
        let reductionOrder: Int?
        let targetWeight: Double
        let targetReps: Int
        let actualWeight: Double
        let actualReps: Int
        let rir: Int?
        let isWarmup: Bool
        let isCompleted: Bool
        let startedAt: Date?
        let completedAt: Date?
        let restStartedAt: Date?
        let restEndedAt: Date?
        let restDurationSeconds: Int?
        let targetWeightSideRaw: String?
        let targetRepsSideRaw: String?
        let actualWeightSideRaw: String?
        let actualRepsSideRaw: String?
        let actualEntrySourceRaw: String?
        let sourceHistorySetID: UUID?
        let actualWeightIsBlank: Bool?
        let needsConfirmation: Bool

        @MainActor init(_ log: SetLog) {
            id = log.id
            sessionID = log.sessionID
            exerciseID = log.exerciseID
            setNumber = log.setNumber
            reductionOrder = log.reductionOrder
            targetWeight = log.targetWeight
            targetReps = log.targetReps
            actualWeight = log.actualWeight
            actualReps = log.actualReps
            rir = log.rir
            isWarmup = log.isWarmup
            isCompleted = log.isCompleted
            startedAt = log.startedAt
            completedAt = log.completedAt
            restStartedAt = log.restStartedAt
            restEndedAt = log.restEndedAt
            restDurationSeconds = log.restDurationSeconds
            targetWeightSideRaw = log.targetWeightSideRaw
            targetRepsSideRaw = log.targetRepsSideRaw
            actualWeightSideRaw = log.actualWeightSideRaw
            actualRepsSideRaw = log.actualRepsSideRaw
            actualEntrySourceRaw = log.actualEntrySourceRaw
            sourceHistorySetID = log.sourceHistorySetID
            actualWeightIsBlank = log.actualWeightIsBlank
            needsConfirmation = WorkoutService.reductionNeedsConfirmation(log)
        }
    }

    let sessionID: UUID
    let sourceSessionExerciseID: UUID
    let sourceExerciseID: UUID
    let sourceOrder: Int
    let sourceTargetSets: Int
    let sourcePlannedSetsJSON: String?
    let sourceHasManuallyReducedSets: Bool?
    let sourceStartedAt: Date?
    let sourceCompletedAt: Date?
    let sets: [SetState]

    var remainingSets: [SetState] { sets.filter { $0.reductionOrder == nil && !$0.isCompleted } }
    var defaultSetCount: Int { remainingSets.count }
    var requiresEnteredDataConfirmation: Bool {
        let affectedSets = sets.contains(where: \.isCompleted) ? remainingSets : sets
        return affectedSets.contains(where: \.needsConfirmation)
    }
}

enum BodyWeightSnapshotResolver {
    struct Snapshot: Equatable {
        let weightKg: Double
        let sourceDate: Date?
    }

    static func resolveSnapshot(
        for workoutDate: Date,
        measurements: [BodyMeasurement],
        currentHealthWeightKg: Double?
    ) -> Snapshot? {
        let historical = measurements
            .filter { $0.date <= workoutDate && ($0.weightKg ?? 0) > 0 }
            .max(by: { $0.date < $1.date })
        if let historical, let weightKg = historical.weightKg {
            return Snapshot(weightKg: weightKg, sourceDate: historical.date)
        }
        if let currentHealthWeightKg, currentHealthWeightKg > 0 {
            return Snapshot(weightKg: currentHealthWeightKg, sourceDate: nil)
        }
        return nil
    }

    static func resolve(
        for workoutDate: Date,
        measurements: [BodyMeasurement],
        currentHealthWeightKg: Double?
    ) -> Double? {
        resolveSnapshot(
            for: workoutDate,
            measurements: measurements,
            currentHealthWeightKg: currentHealthWeightKg
        )?.weightKg
    }
}

enum WorkoutExerciseTracking {
    static func startFirstExercise(in exercises: [SessionExercise], at date: Date = .now) {
        guard let first = exercises.min(by: { $0.order < $1.order }) else { return }
        recordInteraction(with: first, at: date)
    }

    static func recordInteraction(with exercise: SessionExercise, at date: Date = .now) {
        if exercise.exerciseStartedAt == nil {
            exercise.exerciseStartedAt = date
        }
    }

    static func updateAfterSetChange(
        exercise: SessionExercise,
        logs: [SetLog],
        followingExercise: SessionExercise?,
        at date: Date = .now
    ) {
        recordInteraction(with: exercise, at: date)
        let isComplete = !logs.isEmpty && logs.allSatisfy(\.isCompleted)
        if isComplete {
            exercise.exerciseCompletedAt = max(date, exercise.exerciseStartedAt ?? date)
            if let followingExercise {
                recordInteraction(with: followingExercise, at: date)
            }
        } else {
            exercise.exerciseCompletedAt = nil
        }
    }
}

@MainActor
enum WeightedExerciseIdentityMigration {
    private struct Correction {
        let muscleGroup: String
        let equipment: String
    }

    /// Correct only catalog identities that were explicitly verified against the
    /// user's existing data. Historical SessionExercise snapshots remain unchanged.
    private static let confirmedCorrections: [String: Correction] = [
        "传统硬拉": Correction(muscleGroup: "腿部", equipment: "杠铃"),
        "哑铃侧边蹲": Correction(muscleGroup: "腿部", equipment: "哑铃"),
        "地雷杆转体": Correction(muscleGroup: "核心", equipment: "地雷杆"),
        "地雷杆泽奇蹲": Correction(muscleGroup: "腿部", equipment: "地雷杆")
    ]

    static func applyConfirmedCorrections(in context: ModelContext) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        for exercise in exercises {
            guard let correction = confirmedCorrections[exercise.name] else { continue }
            let needsUpdate = exercise.muscleGroup != correction.muscleGroup
                || exercise.equipment != correction.equipment
                || exercise.volumeUnit != .kilogram
            guard needsUpdate else { continue }
            exercise.muscleGroup = correction.muscleGroup
            exercise.equipment = correction.equipment
            exercise.volumeUnit = .kilogram
            exercise.updatedAt = .now
        }
    }
}

@MainActor
enum BodyweightVolumeMigration {
    private static let canonicalIDs: Set<String> = [
        "bodyweight_leg_raise",
        "bodyweight_pull_up"
    ]
    private static let confirmedNames: Set<String> = [
        "举腿", "引体向上", "仰卧起坐", "蜘蛛跳", "跳箱", "侧边提髋", "保加利亚横向踮脚跳"
    ]

    static func applyConfirmedAllowlist(in context: ModelContext) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let confirmedIDs = Set(exercises.compactMap { exercise -> UUID? in
            guard canonicalIDs.contains(exercise.terminologyCanonicalID ?? "")
                    || confirmedNames.contains(exercise.name) else { return nil }
            exercise.volumeUnit = .bodyweight
            return exercise.id
        })
        guard !confirmedIDs.isEmpty else { return }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())

        for snapshot in snapshots where confirmedIDs.contains(snapshot.exerciseID) {
            snapshot.volumeUnit = .bodyweight
            if snapshot.bodyWeightSnapshotSourceDate == nil,
               let session = sessionByID[snapshot.sessionID],
               let weight = snapshot.bodyWeightKgSnapshot,
               let matchingMeasurement = measurements
                .filter({ $0.date <= session.startedAt && $0.weightKg == weight })
                .max(by: { $0.date < $1.date }) {
                snapshot.bodyWeightSnapshotSourceDate = matchingMeasurement.date
            }
            if snapshot.bodyWeightKgSnapshot == nil,
               let session = sessionByID[snapshot.sessionID] {
                let bodyWeight = BodyWeightSnapshotResolver.resolveSnapshot(
                    for: session.startedAt,
                    measurements: measurements,
                    currentHealthWeightKg: nil
                )
                snapshot.bodyWeightKgSnapshot = bodyWeight?.weightKg
                snapshot.bodyWeightSnapshotSourceDate = bodyWeight?.sourceDate
            }
            guard let bodyWeight = snapshot.bodyWeightKgSnapshot else { continue }
            for log in logs where log.sessionExerciseID == snapshot.id {
                log.actualWeight = bodyWeight
                if log.targetWeight <= 0 { log.targetWeight = bodyWeight }
            }
        }
    }

    static func applyHealthWeightFallbacks(
        in context: ModelContext,
        historicalWeightKg: (Date) -> Double?,
        currentWeightKg: Double?
    ) throws {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let latestLocalMeasurement = measurements
            .filter { ($0.weightKg ?? 0) > 0 }
            .max(by: { $0.date < $1.date })?
            .weightKg
        let latestStoredSnapshotWeight = snapshots.compactMap { snapshot -> (Date, Double)? in
            guard let weight = snapshot.bodyWeightKgSnapshot,
                  weight.isFinite,
                  weight > 0,
                  let session = sessionByID[snapshot.sessionID] else { return nil }
            return (session.startedAt, weight)
        }
        .max(by: { $0.0 < $1.0 })?
        .1
        let validatedCurrentHealthWeight = currentWeightKg.flatMap { weight in
            weight.isFinite && weight > 0 ? weight : nil
        }
        let currentFallbackWeight = validatedCurrentHealthWeight
            ?? latestLocalMeasurement
            ?? latestStoredSnapshotWeight

        for snapshot in snapshots where snapshot.volumeUnit == .bodyweight
            && snapshot.bodyWeightKgSnapshot == nil {
            guard let session = sessionByID[snapshot.sessionID] else { continue }
            let weight = BodyWeightSnapshotResolver.resolve(
                for: session.startedAt,
                measurements: measurements,
                currentHealthWeightKg: historicalWeightKg(session.startedAt)
            ) ?? currentFallbackWeight
            guard let weight, weight.isFinite, weight > 0 else { continue }
            snapshot.bodyWeightKgSnapshot = weight
            if let localMeasurement = measurements
                .filter({ $0.date <= session.startedAt && $0.weightKg == weight })
                .max(by: { $0.date < $1.date }) {
                snapshot.bodyWeightSnapshotSourceDate = localMeasurement.date
            }
            for log in logs where log.sessionExerciseID == snapshot.id {
                log.actualWeight = weight
                if log.targetWeight <= 0 { log.targetWeight = weight }
            }
        }
    }

    static func backfillMissingSnapshotsFromHealth(in context: ModelContext) async throws {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let dates = Set(snapshots.compactMap { snapshot -> Date? in
            guard snapshot.volumeUnit == .bodyweight,
                  snapshot.bodyWeightKgSnapshot == nil else { return nil }
            return sessionByID[snapshot.sessionID]?.startedAt
        })
        guard !dates.isEmpty else { return }

        let healthEnabled = UserDefaults.standard.bool(forKey: HealthKitService.enabledKey)
        var historicalWeights: [Date: Double] = [:]
        var currentWeight: Double?
        if healthEnabled {
            for date in dates {
                if let weight = try? await HealthKitService.shared.weightKg(onOrBefore: date),
                   weight.isFinite, weight > 0 {
                    historicalWeights[date] = weight
                }
            }
            currentWeight = try? await HealthKitService.shared.latestBodySnapshot()?.weightKg
        }
        try applyHealthWeightFallbacks(
            in: context,
            historicalWeightKg: { historicalWeights[$0] },
            currentWeightKg: currentWeight
        )
        try context.save()
    }
}

enum WorkoutRestTracking {
    static func shouldBeginRest(after completedLog: SetLog, logs: [SetLog]) -> Bool {
        completedLog.isCompleted
            && logs.contains { $0.id != completedLog.id && !$0.isCompleted }
    }

    static func clearRest(on log: SetLog) {
        log.restStartedAt = nil
        log.restEndedAt = nil
        log.restDurationSeconds = nil
    }

    static func activeLogs(in logs: [SetLog]) -> [SetLog] {
        logs
            .filter { $0.restStartedAt != nil && $0.restEndedAt == nil }
            .sorted {
                let left = $0.restStartedAt ?? .distantPast
                let right = $1.restStartedAt ?? .distantPast
                if left == right { return $0.id.uuidString < $1.id.uuidString }
                return left < right
            }
    }

    static func activeLog(in logs: [SetLog]) -> SetLog? {
        activeLogs(in: logs).last
    }

    /// Keeps the newest active interval and clears every stale provisional interval.
    /// Returns `true` when corrupted state was repaired.
    @discardableResult
    static func reconcile(session: WorkoutSession, logs: [SetLog]) -> Bool {
        let active = activeLogs(in: logs)
        var changed = false
        if active.count > 1 {
            for stale in active.dropLast() {
                clearRest(on: stale)
            }
            changed = true
        }
        if session.restMode == .freestyle, session.restEndDate != nil {
            session.restEndDate = nil
            changed = true
        }
        return changed
    }

    static func begin(
        after log: SetLog,
        session: WorkoutSession,
        logs: [SetLog],
        plannedRestSeconds: Int,
        at date: Date = .now
    ) {
        abandon(session: session, logs: logs)
        log.restStartedAt = date
        log.restEndedAt = nil
        log.restDurationSeconds = nil
        session.restEndDate = session.restMode == .countdown
            ? date.addingTimeInterval(TimeInterval(max(0, plannedRestSeconds)))
            : nil
    }

    @discardableResult
    static func startSet(
        _ log: SetLog,
        session: WorkoutSession,
        logs: [SetLog],
        at date: Date = .now
    ) -> Int? {
        let recordedRest = finish(session: session, logs: logs, at: date)
        for other in logs where other.id != log.id && !other.isCompleted && other.startedAt != nil {
            other.startedAt = nil
        }
        log.startedAt = date
        return recordedRest
    }

    @discardableResult
    static func finish(
        session: WorkoutSession,
        logs: [SetLog],
        at date: Date = .now
    ) -> Int? {
        reconcile(session: session, logs: logs)
        guard let log = activeLog(in: logs), let startedAt = log.restStartedAt else {
            session.restEndDate = nil
            return nil
        }
        let normalizedEnd = max(date, startedAt)
        let duration = Int(normalizedEnd.timeIntervalSince(startedAt).rounded())
        log.restEndedAt = normalizedEnd
        log.restDurationSeconds = duration
        session.restEndDate = nil
        return duration
    }

    static func abandon(session: WorkoutSession, logs: [SetLog]) {
        for log in activeLogs(in: logs) {
            clearRest(on: log)
        }
        session.restEndDate = nil
    }
}

@MainActor
enum WorkoutService {
    static func startUsingAvailableBodyWeight(
        schedule: ScheduledWorkout,
        in context: ModelContext
    ) async throws -> UUID {
        let healthWeight: Double?
        if UserDefaults.standard.bool(forKey: HealthKitService.enabledKey) {
            let historicalWeight = try? await HealthKitService.shared.weightKg(onOrBefore: schedule.plannedDate)
            let currentWeight = try? await HealthKitService.shared.latestBodySnapshot()?.weightKg
            healthWeight = historicalWeight ?? currentWeight
        } else {
            healthWeight = nil
        }
        return try start(
            schedule: schedule,
            currentHealthWeightKg: healthWeight,
            in: context
        )
    }

    static func start(
        schedule: ScheduledWorkout,
        currentHealthWeightKg: Double? = nil,
        in context: ModelContext
    ) throws -> UUID {
        if let active = try activeSession(in: context) {
            guard active.scheduledWorkoutID == schedule.id else {
                throw WorkoutServiceError.activeSessionExists
            }
            return active.id
        }
        guard schedule.status == .planned,
              try !ConfirmedDailyTrainingPlanService.isSuperseded(schedule.id, in: context) else {
            throw WorkoutServiceError.scheduleNotReady
        }

        let templateID = schedule.templateID
        let descriptor = FetchDescriptor<TemplateExercise>(
            predicate: #Predicate { $0.templateID == templateID },
            sortBy: [SortDescriptor(\.order)]
        )
        let plannedExercises = try context.fetch(descriptor)
        guard !plannedExercises.isEmpty else { throw WorkoutServiceError.emptyTemplate }
        let frozenPlan = schedule.planSnapshot
        let sourceTemplate = try context.fetch(FetchDescriptor<WorkoutTemplate>())
            .first { $0.id == templateID }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        for planned in plannedExercises {
            guard let exercise = exerciseByID[planned.exerciseID] else {
                throw WorkoutServiceError.missingExerciseReference
            }
            guard !exercise.isArchived else {
                throw WorkoutServiceError.archivedExercise
            }
        }
        let sessionStart = Date.now
        let historySessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let historySnapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let historyLogs = try context.fetch(FetchDescriptor<SetLog>())
        let historySchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let bodyWeight = BodyWeightSnapshotResolver.resolveSnapshot(
            for: schedule.plannedDate,
            measurements: measurements,
            currentHealthWeightKg: currentHealthWeightKg
        )
        let session = WorkoutSession(
            scheduledWorkoutID: schedule.id,
            templateID: templateID,
            templateName: schedule.templateName,
            plannedDate: TrainingScheduleDate.displayDate(schedule),
            startedAt: sessionStart,
            defaultPlanPattern: sourceTemplate?.defaultPlanPatternRaw.flatMap(SetPlanPattern.init(rawValue:))
        )
        TrainingHistoryDate.capture(session, date: TrainingScheduleDate.displayDate(schedule), schedule: schedule)
        context.insert(session)

        for planned in plannedExercises {
            guard let exercise = exerciseByID[planned.exerciseID] else {
                throw WorkoutServiceError.missingExerciseReference
            }

            let plannedSets = planned.plannedSets

            let snapshot = SessionExercise(
                sessionID: session.id,
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                order: planned.order,
                targetSets: planned.targetSets,
                minReps: planned.minReps,
                maxReps: planned.maxReps,
                targetWeight: planned.targetWeight,
                restSeconds: planned.restSeconds,
                muscleGroup: exercise.muscleGroup,
                exerciseNotes: frozenPlan.first(where: { $0.exerciseID == exercise.id })?.exerciseNotes ?? exercise.notes,
                referenceURL: exercise.referenceURL,
                volumeUnit: exercise.volumeUnit,
                plannedSets: plannedSets,
                planPattern: planned.planPattern,
                patternSource: planned.patternSource,
                exerciseStartedAt: planned.order == plannedExercises.map(\.order).min() ? sessionStart : nil,
                bodyWeightKgSnapshot: exercise.volumeUnit == .bodyweight ? bodyWeight?.weightKg : nil,
                bodyWeightSnapshotSourceDate: exercise.volumeUnit == .bodyweight ? bodyWeight?.sourceDate : nil,
                equipmentSnapshot: frozenPlan.first(where: { $0.exerciseID == exercise.id })?.equipment ?? exercise.equipment
            )
            context.insert(snapshot)

            let reference = WorkoutHistoryResolver.latest(exerciseID: exercise.id, unit: exercise.volumeUnit,
                equipment: snapshot.equipmentSnapshot, before: sessionStart, sessions: historySessions,
                snapshots: historySnapshots, logs: historyLogs, schedules: historySchedules)
            let keepsBlank = snapshot.exerciseNotes.contains("重量待当天热身确定")
                || snapshot.exerciseNotes.contains("重量留空")

            for (index, setPlan) in plannedSets.enumerated() {
                let policy: WorkoutActualDefaultPolicy = keepsBlank ? .blank : setPlan.actualDefaultPolicy
                let initial = WorkoutInitialActual.resolve(fallback: WorkoutInitialActual(
                    weight: exercise.volumeUnit == .bodyweight ? (bodyWeight?.weightKg ?? 0) : (policy == .blank ? 0 : setPlan.weight),
                    reps: schedule.confirmedDailyImportJSON != nil && policy == .blank ? 0 : setPlan.reps,
                    weightSide: setPlan.weightSide, repsSide: setPlan.repsSide,
                    source: policy == .blank ? .blank : .plan, sourceHistorySetID: nil,
                    weightIsBlank: policy == .blank), unit: exercise.volumeUnit,
                    selection: .automatic(reference: reference, setIndex: index))
                context.insert(
                    SetLog(
                        sessionID: session.id,
                        sessionExerciseID: snapshot.id,
                        exerciseID: exercise.id,
                        setNumber: index + 1,
                        targetWeight: setPlan.weight,
                        targetReps: setPlan.reps,
                        actualWeight: initial.weight,
                        actualReps: initial.reps,
                        targetWeightSide: setPlan.weightSide,
                        targetRepsSide: setPlan.repsSide,
                        actualWeightSide: initial.weightSide,
                        actualRepsSide: initial.repsSide,
                        actualEntrySource: initial.source,
                        sourceHistorySetID: initial.sourceHistorySetID,
                        actualWeightIsBlank: initial.weightIsBlank
                    )
                )
            }
        }

        schedule.status = .inProgress
        try context.save()
        return session.id
    }

    @discardableResult
    static func addExercise(
        _ exercise: Exercise,
        to session: WorkoutSession,
        configuration: ExerciseSetupDraft? = nil,
        in context: ModelContext
    ) throws -> SessionExercise {
        guard session.status == .inProgress else {
            throw WorkoutServiceError.sessionNotInProgress
        }
        guard !exercise.isArchived else {
            throw WorkoutServiceError.archivedExercise
        }
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == session.id }
        guard !snapshots.contains(where: { $0.exerciseID == exercise.id }) else {
            throw WorkoutServiceError.exerciseAlreadyAdded
        }

        let snapshot = try insertExercise(exercise, to: session, configuration: configuration,
            order: (snapshots.map(\.order).max() ?? -1) + 1, snapshots: snapshots, in: context)
        try context.save()
        return snapshot
    }

    private static func insertExercise(
        _ exercise: Exercise,
        to session: WorkoutSession,
        configuration: ExerciseSetupDraft?,
        order: Int,
        snapshots: [SessionExercise],
        in context: ModelContext
    ) throws -> SessionExercise {

        let draft: ExerciseSetupDraft
        if let configuration {
            draft = configuration
        } else {
            draft = ExerciseSetupDraft.suggested(
                for: exercise,
                sessions: try context.fetch(FetchDescriptor<WorkoutSession>()),
                sessionExercises: try context.fetch(FetchDescriptor<SessionExercise>()),
                setLogs: try context.fetch(FetchDescriptor<SetLog>()),
                schedules: try context.fetch(FetchDescriptor<ScheduledWorkout>())
            )
        }
        let plannedSets = draft.plannedSets
        let startingWeight = plannedSets.first?.weight ?? 0
        let startingReps = plannedSets.first?.reps ?? 8
        let existingBodyWeight = snapshots.compactMap(\.bodyWeightKgSnapshot).first
        let localBodyWeight = BodyWeightSnapshotResolver.resolveSnapshot(
            for: session.startedAt,
            measurements: try context.fetch(FetchDescriptor<BodyMeasurement>()),
            currentHealthWeightKg: nil
        )
        let existingSourceDate = snapshots.first(where: { $0.bodyWeightKgSnapshot != nil })?.bodyWeightSnapshotSourceDate
        let bodyWeightKg = existingBodyWeight ?? localBodyWeight?.weightKg
        let bodyWeightSourceDate = existingBodyWeight == nil ? localBodyWeight?.sourceDate : existingSourceDate

        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: order,
            targetSets: plannedSets.count,
            minReps: plannedSets.map(\.reps).min() ?? startingReps,
            maxReps: plannedSets.map(\.reps).max() ?? startingReps,
            targetWeight: plannedSets.first?.weight ?? startingWeight,
            restSeconds: draft.restSeconds,
            muscleGroup: exercise.muscleGroup,
            exerciseNotes: exercise.notes,
            referenceURL: exercise.referenceURL,
            volumeUnit: exercise.volumeUnit,
            plannedSets: plannedSets,
            planPattern: configuration?.pattern ?? .fixed,
            exerciseStartedAt: Date.now,
            bodyWeightKgSnapshot: exercise.volumeUnit == .bodyweight ? bodyWeightKg : nil,
            bodyWeightSnapshotSourceDate: exercise.volumeUnit == .bodyweight ? bodyWeightSourceDate : nil,
            equipmentSnapshot: exercise.equipment
        )
        context.insert(snapshot)

        let reference = configuration == nil ? WorkoutHistoryResolver.latest(
            exerciseID: exercise.id, unit: exercise.volumeUnit, equipment: exercise.equipment,
            before: session.startedAt, excludingSessionID: session.id,
            sessions: try context.fetch(FetchDescriptor<WorkoutSession>()),
            snapshots: try context.fetch(FetchDescriptor<SessionExercise>()),
            logs: try context.fetch(FetchDescriptor<SetLog>()),
            schedules: try context.fetch(FetchDescriptor<ScheduledWorkout>())) : nil
        for (index, setPlan) in plannedSets.enumerated() {
            let isBlank = setPlan.actualDefaultPolicy == .blank && (configuration == nil || setPlan.weight == 0)
            let initial = WorkoutInitialActual.resolve(fallback: WorkoutInitialActual(
                weight: exercise.volumeUnit == .bodyweight ? (bodyWeightKg ?? 0) : (isBlank ? 0 : setPlan.weight),
                reps: setPlan.reps, weightSide: setPlan.weightSide, repsSide: setPlan.repsSide,
                source: isBlank ? .blank : .plan, sourceHistorySetID: nil,
                weightIsBlank: isBlank), unit: exercise.volumeUnit,
                selection: configuration == nil ? .automatic(reference: reference, setIndex: index) : .confirmedSetup)
            context.insert(
                SetLog(
                    sessionID: session.id,
                    sessionExerciseID: snapshot.id,
                    exerciseID: exercise.id,
                    setNumber: index + 1,
                    targetWeight: setPlan.weight,
                    targetReps: setPlan.reps,
                    actualWeight: initial.weight,
                    actualReps: initial.reps,
                    targetWeightSide: setPlan.weightSide,
                    targetRepsSide: setPlan.repsSide,
                    actualWeightSide: initial.weightSide,
                    actualRepsSide: initial.repsSide,
                    actualEntrySource: initial.source,
                    sourceHistorySetID: initial.sourceHistorySetID,
                    actualWeightIsBlank: initial.weightIsBlank
                )
            )
        }
        return snapshot
    }

    static func replacementReview(
        sessionID: UUID,
        sourceSessionExerciseID: UUID,
        in context: ModelContext
    ) throws -> WorkoutExerciseReplacementReview {
        guard !context.hasChanges else { throw WorkoutServiceError.pendingChangesBeforeReplacement }
        try requireInProgressSession(sessionID, in: context)
        guard let source = try context.fetch(FetchDescriptor<SessionExercise>()).first(where: {
            $0.id == sourceSessionExerciseID && $0.sessionID == sessionID
        }) else { throw WorkoutServiceError.replacementSourceChanged }
        let rows = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == source.id }
            .sorted { ($0.setNumber, $0.id.uuidString) < ($1.setNumber, $1.id.uuidString) }
        guard rows.allSatisfy({ $0.sessionID == sessionID && $0.exerciseID == source.exerciseID }) else {
            throw WorkoutServiceError.replacementSourceChanged
        }
        let review = WorkoutExerciseReplacementReview(
            sessionID: sessionID, sourceSessionExerciseID: source.id, sourceExerciseID: source.exerciseID,
            sourceOrder: source.order, sourceTargetSets: source.targetSets,
            sourcePlannedSetsJSON: source.plannedSetsJSON,
            sourceHasManuallyReducedSets: source.hasManuallyReducedSets,
            sourceStartedAt: source.exerciseStartedAt, sourceCompletedAt: source.exerciseCompletedAt,
            sets: rows.map(WorkoutExerciseReplacementReview.SetState.init)
        )
        guard review.defaultSetCount > 0 else { throw WorkoutServiceError.noIncompleteSet }
        return review
    }

    @discardableResult
    static func replaceRemainingExercise(
        review: WorkoutExerciseReplacementReview,
        with exercise: Exercise,
        configuration: ExerciseSetupDraft,
        confirmingEnteredData: Bool = false,
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> SessionExercise {
        let current = try replacementReview(sessionID: review.sessionID,
            sourceSessionExerciseID: review.sourceSessionExerciseID, in: context)
        guard current == review else { throw WorkoutServiceError.replacementSourceChanged }
        guard confirmingEnteredData || !review.requiresEnteredDataConfirmation else {
            throw WorkoutServiceError.replacementNeedsConfirmation
        }
        guard !configuration.plannedSets.isEmpty else { throw WorkoutServiceError.invalidReplacementPlan }
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == review.sessionID }
        guard !snapshots.contains(where: { $0.exerciseID == exercise.id }) else {
            throw WorkoutServiceError.exerciseAlreadyAdded
        }
        guard let selected = try context.fetch(FetchDescriptor<Exercise>()).first(where: { $0.id == exercise.id }) else {
            throw WorkoutServiceError.missingExerciseReference
        }
        guard !selected.isArchived else { throw WorkoutServiceError.archivedExercise }
        guard let session = try context.fetch(FetchDescriptor<WorkoutSession>()).first(where: { $0.id == review.sessionID }),
              let source = snapshots.first(where: { $0.id == review.sourceSessionExerciseID }) else {
            throw WorkoutServiceError.replacementSourceChanged
        }
        let rows = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionExerciseID == source.id }
        let preservesSource = rows.contains(where: \.isCompleted)
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            let replacement = try insertExercise(selected, to: session, configuration: configuration,
                order: source.order, snapshots: snapshots, in: context)
            if preservesSource {
                if source.plannedSetsJSON == nil { source.plannedSets = source.plannedSets }
                var reduction = max(0, rows.compactMap(\.reductionOrder).max() ?? 0)
                for row in rows.sorted(by: { ($0.setNumber, $0.id.uuidString) < ($1.setNumber, $1.id.uuidString) })
                    where row.reductionOrder == nil && !row.isCompleted {
                    reduction += 1
                    row.reductionOrder = reduction
                }
                source.targetSets = rows.filter { $0.reductionOrder == nil && $0.isCompleted }.count
                source.hasManuallyReducedSets = true
                let ordered = snapshots.sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
                var nextOrder = source.order + 1
                replacement.order = nextOrder
                for following in ordered.drop(while: { $0.id != source.id }).dropFirst() {
                    nextOrder = max(nextOrder + 1, following.order)
                    if following.order != nextOrder { following.order = nextOrder }
                }
            } else {
                rows.forEach(context.delete)
                context.delete(source)
            }
            try save(context)
            return replacement
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Applies the menu shown in the day builder to an already-running workout.
    /// Completed sets remain historical facts; only unfinished rows are reshaped
    /// to the new plan. Pure session reordering uses reorderExercises without
    /// changing any plan or actual rows.
    static func syncMenu(
        _ inputs: [DailyPlanExerciseInput],
        to session: WorkoutSession,
        muscleGroups: [String]? = nil,
        defaultPlanPattern: SetPlanPattern? = nil,
        in context: ModelContext
    ) throws {
        guard session.status == .inProgress else {
            throw WorkoutServiceError.sessionNotInProgress
        }
        guard !inputs.isEmpty else {
            throw WorkoutServiceError.emptyTemplate
        }
        guard Set(inputs.map(\.exerciseID)).count == inputs.count else {
            throw DailyPlanServiceError.duplicateExercise
        }
        let normalizedMuscleGroups = muscleGroups?.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        if muscleGroups != nil, normalizedMuscleGroups?.isEmpty != false {
            throw DailyPlanServiceError.emptyMuscleGroups
        }
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        let exerciseByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        for input in inputs {
            guard let exercise = exerciseByID[input.exerciseID] else {
                throw WorkoutServiceError.missingExerciseReference
            }
            guard !exercise.isArchived else {
                throw WorkoutServiceError.archivedExercise
            }
        }

        var snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == session.id }
        let bodyMeasurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let availableBodyWeight = snapshots.compactMap(\.bodyWeightKgSnapshot).first
            ?? BodyWeightSnapshotResolver.resolve(
                for: session.startedAt,
                measurements: bodyMeasurements,
                currentHealthWeightKg: nil
            )
        let availableBodyWeightSourceDate = snapshots.first(where: { $0.bodyWeightKgSnapshot != nil })?.bodyWeightSnapshotSourceDate
            ?? BodyWeightSnapshotResolver.resolveSnapshot(
                for: session.startedAt,
                measurements: bodyMeasurements,
                currentHealthWeightKg: nil
            )?.sourceDate
        let historyLogs = try context.fetch(FetchDescriptor<SetLog>())
        let historySessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let historySnapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let historySchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let allLogs = historyLogs.filter { $0.sessionID == session.id }
        let requestedIDs = Set(inputs.map(\.exerciseID))
        let removedSnapshotIDs = Set(snapshots.filter { !requestedIDs.contains($0.exerciseID) }.map(\.id))
        guard !allLogs.contains(where: {
            removedSnapshotIDs.contains($0.sessionExerciseID)
                && ($0.isCompleted || $0.startedAt != nil || $0.actualEntrySource == .manual || $0.reductionOrder != nil)
        }) else {
            throw WorkoutServiceError.cannotRemoveStartedExercise
        }
        for snapshot in snapshots where allLogs.contains(where: { $0.sessionExerciseID == snapshot.id && $0.reductionOrder != nil }) {
            guard let input = inputs.first(where: { $0.exerciseID == snapshot.exerciseID }) else { continue }
            guard input.plannedSets == snapshot.plannedSets,
                  max(30, input.restSeconds) == snapshot.restSeconds,
                  input.planPattern == snapshot.planPattern,
                  input.patternSource == snapshot.patternSource else {
                throw WorkoutServiceError.reducedExercisePlanLocked
            }
        }
        // Reject every protected removal before mutating defaults, plans or other rows.
        if let defaultPlanPattern {
            session.defaultPlanPattern = defaultPlanPattern
        }
        let startedExerciseIDs = Set(snapshots.compactMap { snapshot -> UUID? in
            let hasStarted = allLogs.contains {
                $0.sessionExerciseID == snapshot.id && ($0.isCompleted || $0.startedAt != nil)
            }
            return hasStarted ? snapshot.exerciseID : nil
        })
        let lockedOrders = Dictionary(uniqueKeysWithValues: snapshots.compactMap { snapshot in
            startedExerciseIDs.contains(snapshot.exerciseID)
                ? (snapshot.exerciseID, snapshot.order)
                : nil
        })
        let availableOrders = (0..<inputs.count).filter { !Set(lockedOrders.values).contains($0) }
        let movableIDs = inputs.map(\.exerciseID).filter { !startedExerciseIDs.contains($0) }
        let movableOrders = Dictionary(uniqueKeysWithValues: zip(movableIDs, availableOrders))

        for snapshot in snapshots where !requestedIDs.contains(snapshot.exerciseID) {
            let exerciseLogs = allLogs.filter { $0.sessionExerciseID == snapshot.id }
            exerciseLogs.forEach(context.delete)
            context.delete(snapshot)
        }
        snapshots.removeAll { !requestedIDs.contains($0.exerciseID) }

        for (order, input) in inputs.enumerated() {
            let plans = input.plannedSets.isEmpty
                ? [WorkoutSetPlan(weight: 0, reps: 1)]
                : input.plannedSets
            let catalogExercise = exerciseByID[input.exerciseID]!
            let snapshot: SessionExercise

            if let existing = snapshots.first(where: { $0.exerciseID == input.exerciseID }) {
                snapshot = existing
            } else {
                snapshot = SessionExercise(
                    sessionID: session.id,
                    exerciseID: catalogExercise.id,
                    exerciseName: catalogExercise.name,
                    order: order,
                    targetSets: plans.count,
                    minReps: plans.map(\.reps).min() ?? 1,
                    maxReps: plans.map(\.reps).max() ?? 1,
                    targetWeight: plans.first?.weight ?? 0,
                    restSeconds: input.restSeconds,
                    muscleGroup: catalogExercise.muscleGroup,
                    exerciseNotes: catalogExercise.notes,
                    referenceURL: catalogExercise.referenceURL,
                    volumeUnit: catalogExercise.volumeUnit,
                    plannedSets: plans,
                    planPattern: input.planPattern,
                    patternSource: input.patternSource,
                    bodyWeightKgSnapshot: catalogExercise.volumeUnit == .bodyweight
                        ? availableBodyWeight
                        : nil,
                    bodyWeightSnapshotSourceDate: catalogExercise.volumeUnit == .bodyweight
                        ? availableBodyWeightSourceDate
                        : nil,
                    equipmentSnapshot: catalogExercise.equipment
                )
                context.insert(snapshot)
                snapshots.append(snapshot)
            }

            snapshot.order = lockedOrders[input.exerciseID] ?? movableOrders[input.exerciseID] ?? order

            var exerciseLogs = allLogs
                .filter { $0.sessionExerciseID == snapshot.id }
                .sorted { $0.setNumber < $1.setNumber }
            let exerciseHasStarted = exerciseLogs.contains { $0.isCompleted || $0.startedAt != nil }

            if exerciseLogs.contains(where: { $0.reductionOrder != nil }) { continue }
            let reference = WorkoutHistoryResolver.latest(exerciseID: snapshot.exerciseID,
                unit: snapshot.volumeUnit, equipment: snapshot.equipmentSnapshot, before: session.startedAt,
                excludingSessionID: session.id, sessions: historySessions, snapshots: historySnapshots,
                logs: historyLogs, schedules: historySchedules)

            snapshot.restSeconds = max(30, input.restSeconds)
            snapshot.planPattern = input.planPattern
            snapshot.patternSource = input.patternSource

            if !exerciseHasStarted {
                snapshot.targetSets = plans.count
                snapshot.minReps = plans.map(\.reps).min() ?? 1
                snapshot.maxReps = plans.map(\.reps).max() ?? 1
                snapshot.targetWeight = plans.first?.weight ?? 0
                snapshot.plannedSets = plans
            }

            for (index, plan) in plans.enumerated() {
                if exerciseLogs.indices.contains(index) {
                    let log = exerciseLogs[index]
                    guard !log.isCompleted, log.startedAt == nil else { continue }
                    let usedPlanDefaults = log.actualEntrySource == .plan
                        && log.actualWeight == log.targetWeight
                        && log.actualReps == log.targetReps
                        && log.actualWeightSide == log.targetWeightSide
                        && log.actualRepsSide == log.targetRepsSide
                    log.setNumber = index + 1
                    log.targetWeight = plan.weight
                    log.targetReps = plan.reps
                    log.targetWeightSide = plan.weightSide
                    log.targetRepsSide = plan.repsSide
                    if usedPlanDefaults {
                        log.actualWeight = plan.actualDefaultPolicy == .blank ? 0 : plan.weight
                        log.actualReps = plan.reps
                        log.actualWeightSide = plan.weightSide
                        log.actualRepsSide = plan.repsSide
                        log.actualEntrySource = plan.actualDefaultPolicy == .blank ? .blank : .plan
                        log.actualWeightIsBlank = plan.actualDefaultPolicy == .blank
                    }
                } else {
                    let initial = WorkoutInitialActual.resolve(fallback: WorkoutInitialActual(
                        weight: catalogExercise.volumeUnit == .bodyweight ? (availableBodyWeight ?? 0) : (plan.actualDefaultPolicy == .blank ? 0 : plan.weight),
                        reps: plan.reps, weightSide: plan.weightSide, repsSide: plan.repsSide,
                        source: plan.actualDefaultPolicy == .blank ? .blank : .plan, sourceHistorySetID: nil,
                        weightIsBlank: plan.actualDefaultPolicy == .blank), unit: snapshot.volumeUnit,
                        selection: .automatic(reference: reference, setIndex: index))
                    let log = SetLog(
                        sessionID: session.id,
                        sessionExerciseID: snapshot.id,
                        exerciseID: snapshot.exerciseID,
                        setNumber: index + 1,
                        targetWeight: plan.weight,
                        targetReps: plan.reps,
                        actualWeight: initial.weight,
                        actualReps: initial.reps,
                        targetWeightSide: plan.weightSide,
                        targetRepsSide: plan.repsSide,
                        actualWeightSide: initial.weightSide,
                        actualRepsSide: initial.repsSide,
                        actualEntrySource: initial.source,
                        sourceHistorySetID: initial.sourceHistorySetID,
                        actualWeightIsBlank: initial.weightIsBlank
                    )
                    context.insert(log)
                    exerciseLogs.append(log)
                }
            }

            for log in exerciseLogs.dropFirst(plans.count)
                where !log.isCompleted && log.startedAt == nil && log.actualEntrySource != .manual {
                context.delete(log)
            }

            if exerciseHasStarted {
                let protectedLogs = exerciseLogs.filter { $0.isCompleted || $0.startedAt != nil }
                let protectedUpperBound = protectedLogs.map(\.setNumber).max() ?? 0
                let mergedCount = max(plans.count, protectedUpperBound)
                let originalPlans = snapshot.plannedSets
                let mergedPlans = (0..<mergedCount).map { index -> WorkoutSetPlan in
                    if let log = exerciseLogs.first(where: {
                        $0.setNumber == index + 1 && ($0.isCompleted || $0.startedAt != nil)
                    }) {
                        return WorkoutSetPlan(
                            weight: log.targetWeight,
                            reps: log.targetReps,
                            weightSide: log.targetWeightSide,
                            repsSide: log.targetRepsSide,
                            actualDefaultPolicy: originalPlans.indices.contains(index) ? originalPlans[index].actualDefaultPolicy : nil
                        )
                    }
                    if plans.indices.contains(index) { return plans[index] }
                    if originalPlans.indices.contains(index) { return originalPlans[index] }
                    return WorkoutSetPlan(weight: snapshot.targetWeight, reps: snapshot.minReps)
                }
                snapshot.plannedSets = mergedPlans
                snapshot.targetSets = mergedPlans.count
                snapshot.minReps = mergedPlans.map(\.reps).min() ?? 1
                snapshot.maxReps = mergedPlans.map(\.reps).max() ?? 1
                snapshot.targetWeight = mergedPlans.first?.weight ?? snapshot.targetWeight
            }
        }

        if let normalizedMuscleGroups {
            let titleGroups = normalizedMuscleGroups.prefix(3).joined(separator: " + ")
            let updatedTitle = "\(titleGroups) · 当天菜单"
            session.templateName = updatedTitle
            if let scheduledWorkoutID = session.scheduledWorkoutID {
                let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
                if let schedule = schedules.first(where: { $0.id == scheduledWorkoutID }) {
                    schedule.templateName = updatedTitle
                    schedule.updatedAt = .now
                }
            }
        }

        try context.save()
    }

    /// Changes only this in-progress session's presentation order. Exercise and set
    /// identities, original prescriptions, actuals, and timing never move between rows.
    static func reorderExercises(
        sessionID: UUID,
        orderedSessionExerciseIDs: [UUID],
        in context: ModelContext
    ) throws {
        try requireInProgressSession(sessionID, in: context)
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>(
            predicate: #Predicate { $0.sessionID == sessionID }
        ))
        let existingIDs = Set(snapshots.map(\.id))
        guard !snapshots.isEmpty,
              existingIDs.count == snapshots.count,
              orderedSessionExerciseIDs.count == snapshots.count,
              Set(orderedSessionExerciseIDs) == existingIDs else {
            throw WorkoutServiceError.invalidExerciseOrder
        }
        let snapshotsByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        let previousOrders = snapshots.map { ($0, $0.order) }
        for (order, id) in orderedSessionExerciseIDs.enumerated() {
            snapshotsByID[id]?.order = order
        }
        do {
            try context.save()
        } catch {
            // Do not roll back the whole context: pending workout input belongs to
            // its own save flow. Restore only the fields this operation owns.
            for (snapshot, order) in previousOrders { snapshot.order = order }
            throw error
        }
    }

    @discardableResult
    static func addSet(
        to exercise: SessionExercise,
        in context: ModelContext
    ) throws -> SetLog {
        try requireInProgressSession(exercise.sessionID, in: context)
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == exercise.id }
            .sorted { $0.setNumber < $1.setNumber }
        let previous = logs.last { $0.reductionOrder == nil }
        let setNumber = (logs.map(\.setNumber).max() ?? 0) + 1
        let log = SetLog(
            sessionID: exercise.sessionID,
            sessionExerciseID: exercise.id,
            exerciseID: exercise.exerciseID,
            setNumber: setNumber,
            targetWeight: previous?.targetWeight ?? exercise.targetWeight,
            targetReps: previous?.targetReps ?? exercise.minReps,
            actualWeight: previous?.actualWeight ?? exercise.targetWeight,
            actualReps: previous?.actualReps ?? exercise.minReps,
            targetWeightSide: previous?.targetWeightSide ?? .bilateral,
            targetRepsSide: previous?.targetRepsSide ?? .bilateral,
            actualWeightSide: previous?.actualWeightSide,
            actualRepsSide: previous?.actualRepsSide,
            actualEntrySource: previous?.actualEntrySource ?? .plan,
            sourceHistorySetID: previous?.sourceHistorySetID,
            actualWeightIsBlank: previous?.actualWeightIsBlank
        )
        let oldTarget = exercise.targetSets
        let oldPlan = exercise.plannedSetsJSON
        let oldCompletion = exercise.exerciseCompletedAt
        if oldPlan == nil { exercise.plannedSets = exercise.plannedSets }
        context.insert(log)
        exercise.targetSets = logs.filter { $0.reductionOrder == nil }.count + 1
        exercise.exerciseCompletedAt = nil
        do { try context.save() } catch {
            context.delete(log)
            exercise.targetSets = oldTarget
            exercise.plannedSetsJSON = oldPlan
            exercise.exerciseCompletedAt = oldCompletion
            throw error
        }
        return log
    }

    static func restorePlanDefaults(for exercise: SessionExercise, in context: ModelContext) throws {
        try requireInProgressSession(exercise.sessionID, in: context)
        let id = exercise.id
        let rows = try context.fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.sessionExerciseID == id }))
        let plans = exercise.plannedSets
        let session = try context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == exercise.sessionID }
        let isConfirmedDaily = try context.fetch(FetchDescriptor<ScheduledWorkout>()).contains {
            $0.id == session?.scheduledWorkoutID && $0.confirmedDailyImportJSON != nil
        }
        let legacyBlank = exercise.exerciseNotes.contains("重量待当天热身确定") || exercise.exerciseNotes.contains("重量留空")
        for row in rows where row.reductionOrder == nil && !row.isCompleted && row.startedAt == nil && !row.isWarmup {
            let index = row.setNumber - 1
            let blank = legacyBlank || (plans.indices.contains(index) && plans[index].actualDefaultPolicy == .blank)
            row.actualWeight = exercise.volumeUnit == .bodyweight ? (exercise.bodyWeightKgSnapshot ?? 0) : (blank ? 0 : row.targetWeight)
            row.actualReps = isConfirmedDaily && blank ? 0 : row.targetReps
            row.actualWeightSide = row.targetWeightSide
            row.actualRepsSide = row.targetRepsSide
            row.actualEntrySource = blank ? .blank : .plan
            row.actualWeightIsBlank = blank
            row.sourceHistorySetID = nil
        }
        try context.save()
    }

    static func reductionCandidate(for exercise: SessionExercise, in context: ModelContext) throws -> SetLog? {
        try requireInProgressSession(exercise.sessionID, in: context)
        return try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == exercise.id && $0.reductionOrder == nil && !$0.isCompleted }
            .max { ($0.setNumber, $0.id.uuidString) < ($1.setNumber, $1.id.uuidString) }
    }

    static func reductionNeedsConfirmation(_ log: SetLog) -> Bool {
        log.actualEntrySource == .manual || log.actualEntrySource == .legacy || log.rir != nil || log.startedAt != nil
    }

    static func reduceSet(from exercise: SessionExercise, candidateID: UUID, confirmingEnteredData: Bool = false, in context: ModelContext) throws {
        guard let candidate = try reductionCandidate(for: exercise, in: context), candidate.id == candidateID else {
            throw WorkoutServiceError.noIncompleteSet
        }
        guard confirmingEnteredData || !reductionNeedsConfirmation(candidate) else {
            throw WorkoutServiceError.reductionNeedsConfirmation
        }
        let rows = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionExerciseID == exercise.id }
        let oldTarget = exercise.targetSets
        let oldFlag = exercise.hasManuallyReducedSets
        let oldPlan = exercise.plannedSetsJSON
        let oldCompletion = exercise.exerciseCompletedAt
        if oldPlan == nil { exercise.plannedSets = exercise.plannedSets }
        candidate.reductionOrder = (rows.compactMap(\.reductionOrder).max() ?? 0) + 1
        exercise.hasManuallyReducedSets = true
        let active = rows.filter { $0.reductionOrder == nil }
        exercise.targetSets = active.count
        if !active.isEmpty && active.allSatisfy(\.isCompleted) {
            exercise.exerciseCompletedAt = oldCompletion ?? max(.now, exercise.exerciseStartedAt ?? .now)
        } else {
            exercise.exerciseCompletedAt = nil
        }
        do { try context.save() } catch {
            candidate.reductionOrder = nil
            exercise.targetSets = oldTarget
            exercise.hasManuallyReducedSets = oldFlag
            exercise.plannedSetsJSON = oldPlan
            exercise.exerciseCompletedAt = oldCompletion
            throw error
        }
    }

    static func restoreReducedSet(for exercise: SessionExercise, in context: ModelContext) throws {
        try requireInProgressSession(exercise.sessionID, in: context)
        let rows = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionExerciseID == exercise.id }
        guard let row = rows.filter({ $0.reductionOrder != nil }).max(by: { $0.reductionOrder! < $1.reductionOrder! }) else {
            throw WorkoutServiceError.noIncompleteSet
        }
        let order = row.reductionOrder
        let oldTarget = exercise.targetSets
        let oldCompletion = exercise.exerciseCompletedAt
        row.reductionOrder = nil
        exercise.targetSets = rows.filter { $0.reductionOrder == nil }.count
        exercise.exerciseCompletedAt = nil
        do { try context.save() } catch {
            row.reductionOrder = order
            exercise.targetSets = oldTarget
            exercise.exerciseCompletedAt = oldCompletion
            throw error
        }
    }

    static func removeExercise(
        _ exercise: SessionExercise,
        from session: WorkoutSession,
        in context: ModelContext
    ) throws {
        guard session.status == .inProgress else {
            throw WorkoutServiceError.sessionNotInProgress
        }
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == session.id }
        guard snapshots.count > 1 else {
            throw WorkoutServiceError.cannotRemoveLastExercise
        }
        let exerciseLogs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == exercise.id }
        guard !exerciseLogs.contains(where: { $0.isCompleted || $0.reductionOrder != nil }) else {
            throw WorkoutServiceError.cannotRemoveStartedExercise
        }

        exerciseLogs.forEach(context.delete)
        context.delete(exercise)
        snapshots
            .filter { $0.id != exercise.id }
            .sorted { $0.order < $1.order }
            .enumerated()
            .forEach { index, snapshot in
                snapshot.order = index
            }
        try context.save()
    }

    private static func requireInProgressSession(
        _ sessionID: UUID,
        in context: ModelContext
    ) throws {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        guard sessions.first(where: { $0.id == sessionID })?.status == .inProgress else {
            throw WorkoutServiceError.sessionNotInProgress
        }
    }

    static func activeSession(in context: ModelContext) throws -> WorkoutSession? {
        let inProgress = WorkoutSessionStatus.inProgress.rawValue
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == inProgress },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    static func finish(
        session: WorkoutSession,
        schedules: [ScheduledWorkout],
        in context: ModelContext
    ) throws {
        let templatePlanUpdates = try persistentTemplatePlanUpdates(
            for: session,
            in: context
        )

        session.status = .completed
        session.completedAt = .now
        session.restEndDate = nil

        if let scheduledID = session.scheduledWorkoutID,
           let schedule = schedules.first(where: { $0.id == scheduledID }) {
            schedule.status = .completed
        }

        templatePlanUpdates.forEach { update in
            update.item.plannedSets = update.plans
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func persistentTemplatePlanUpdates(
        for session: WorkoutSession,
        in context: ModelContext
    ) throws -> [(item: TemplateExercise, plans: [WorkoutSetPlan])] {
        guard let templateID = session.templateID else { return [] }

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        guard let template = templates.first(where: { $0.id == templateID }),
              !template.isOneOff else {
            return []
        }

        let templateItems = try context.fetch(FetchDescriptor<TemplateExercise>())
            .filter { $0.templateID == templateID }
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == session.id }
        let snapshotByExerciseID = Dictionary(
            snapshots.map { ($0.exerciseID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let completedWorkingSets = try context.fetch(FetchDescriptor<SetLog>())
            .filter {
                $0.sessionID == session.id
                    && $0.isCompleted
                    && !$0.isWarmup
                    && $0.actualReps > 0
            }

        return templateItems.compactMap { item in
            guard let snapshot = snapshotByExerciseID[item.exerciseID], snapshot.hasManuallyReducedSets != true else { return nil }
            let matchingSets = completedWorkingSets
                .filter { $0.sessionExerciseID == snapshot.id }
                .sorted { lhs, rhs in
                    if lhs.setNumber != rhs.setNumber { return lhs.setNumber < rhs.setNumber }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            guard !matchingSets.isEmpty else { return nil }

            let plans = matchingSets.map { log in
                WorkoutSetPlan(
                    weight: snapshot.volumeUnit.recordsNumericLoad ? log.actualWeight : 0,
                    reps: log.actualReps,
                    weightSide: log.actualWeightSide,
                    repsSide: log.actualRepsSide
                )
            }
            return (item, plans)
        }
    }

    static func discard(
        session: WorkoutSession,
        schedules: [ScheduledWorkout],
        in context: ModelContext
    ) throws {
        session.status = .discarded
        session.completedAt = .now
        session.restEndDate = nil

        if let scheduledID = session.scheduledWorkoutID,
           let schedule = schedules.first(where: { $0.id == scheduledID }),
           schedule.status == .inProgress {
            schedule.status = .planned
            schedule.updatedAt = .now
        }
        try context.save()
    }
}
