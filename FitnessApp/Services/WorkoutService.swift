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
    case cannotRemoveStartedExercise
    case cannotRemoveLastExercise

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
        case .cannotRemoveStartedExercise:
            return "这个动作已经完成了训练组，不能从本次记录中移除。"
        case .cannotRemoveLastExercise:
            return "本次训练至少需要保留一个动作。"
        }
    }
}

enum BodyWeightSnapshotResolver {
    static func resolve(
        for workoutDate: Date,
        measurements: [BodyMeasurement],
        currentHealthWeightKg: Double?
    ) -> Double? {
        let historical = measurements
            .filter { $0.date <= workoutDate && ($0.weightKg ?? 0) > 0 }
            .sorted { $0.date > $1.date }
            .compactMap(\.weightKg)
            .first
        if let historical { return historical }
        if let currentHealthWeightKg, currentHealthWeightKg > 0 { return currentHealthWeightKg }
        return nil
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
            if snapshot.bodyWeightKgSnapshot == nil,
               let session = sessionByID[snapshot.sessionID] {
                snapshot.bodyWeightKgSnapshot = BodyWeightSnapshotResolver.resolve(
                    for: session.startedAt,
                    measurements: measurements,
                    currentHealthWeightKg: nil
                )
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
        guard schedule.status == .planned else {
            throw WorkoutServiceError.scheduleNotReady
        }

        let templateID = schedule.templateID
        let descriptor = FetchDescriptor<TemplateExercise>(
            predicate: #Predicate { $0.templateID == templateID },
            sortBy: [SortDescriptor(\.order)]
        )
        let plannedExercises = try context.fetch(descriptor)
        guard !plannedExercises.isEmpty else { throw WorkoutServiceError.emptyTemplate }
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
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let bodyWeightKg = BodyWeightSnapshotResolver.resolve(
            for: schedule.plannedDate,
            measurements: measurements,
            currentHealthWeightKg: currentHealthWeightKg
        )
        let session = WorkoutSession(
            scheduledWorkoutID: schedule.id,
            templateID: templateID,
            templateName: schedule.templateName,
            plannedDate: schedule.plannedDate,
            startedAt: sessionStart,
            defaultPlanPattern: sourceTemplate?.defaultPlanPatternRaw.flatMap(SetPlanPattern.init(rawValue:))
        )
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
                exerciseNotes: exercise.notes,
                referenceURL: exercise.referenceURL,
                volumeUnit: exercise.volumeUnit,
                plannedSets: plannedSets,
                planPattern: planned.planPattern,
                patternSource: planned.patternSource,
                exerciseStartedAt: planned.order == plannedExercises.map(\.order).min() ? sessionStart : nil,
                bodyWeightKgSnapshot: exercise.volumeUnit == .bodyweight ? bodyWeightKg : nil
            )
            context.insert(snapshot)

            for (index, setPlan) in plannedSets.enumerated() {
                context.insert(
                    SetLog(
                        sessionID: session.id,
                        sessionExerciseID: snapshot.id,
                        exerciseID: exercise.id,
                        setNumber: index + 1,
                        targetWeight: setPlan.weight,
                        targetReps: setPlan.reps,
                        actualWeight: exercise.volumeUnit == .bodyweight ? (bodyWeightKg ?? 0) : setPlan.weight,
                        actualReps: setPlan.reps,
                        targetWeightSide: setPlan.weightSide,
                        targetRepsSide: setPlan.repsSide
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

        let previous = try context.fetch(FetchDescriptor<SetLog>())
            .filter {
                $0.exerciseID == exercise.id
                    && $0.sessionID != session.id
                    && $0.isCompleted
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .first
        let startingWeight = previous?.actualWeight ?? 0
        let startingReps = previous?.actualReps ?? 8
        let plannedSets = configuration?.plannedSets ?? WorkoutSetPlan.preset(
            .fixed,
            count: 3,
            baseWeight: exercise.volumeUnit.recordsNumericLoad ? startingWeight : 0,
            baseReps: startingReps,
            weightSide: previous?.actualWeightSide ?? .bilateral,
            repsSide: previous?.actualWeightSide ?? .bilateral
        )
        let order = (snapshots.map(\.order).max() ?? -1) + 1
        let existingBodyWeight = snapshots.compactMap(\.bodyWeightKgSnapshot).first
        let localBodyWeight = BodyWeightSnapshotResolver.resolve(
            for: session.startedAt,
            measurements: try context.fetch(FetchDescriptor<BodyMeasurement>()),
            currentHealthWeightKg: nil
        )
        let bodyWeightKg = existingBodyWeight ?? localBodyWeight

        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: order,
            targetSets: plannedSets.count,
            minReps: plannedSets.map(\.reps).min() ?? startingReps,
            maxReps: plannedSets.map(\.reps).max() ?? startingReps,
            targetWeight: plannedSets.first?.weight ?? startingWeight,
            restSeconds: configuration?.restSeconds ?? exercise.defaultRestSeconds,
            muscleGroup: exercise.muscleGroup,
            exerciseNotes: exercise.notes,
            referenceURL: exercise.referenceURL,
            volumeUnit: exercise.volumeUnit,
            plannedSets: plannedSets,
            planPattern: configuration?.pattern ?? .fixed,
            exerciseStartedAt: Date.now,
            bodyWeightKgSnapshot: exercise.volumeUnit == .bodyweight ? bodyWeightKg : nil
        )
        context.insert(snapshot)

        for (index, setPlan) in plannedSets.enumerated() {
            context.insert(
                SetLog(
                    sessionID: session.id,
                    sessionExerciseID: snapshot.id,
                    exerciseID: exercise.id,
                    setNumber: index + 1,
                    targetWeight: setPlan.weight,
                    targetReps: setPlan.reps,
                    actualWeight: exercise.volumeUnit == .bodyweight ? (bodyWeightKg ?? 0) : setPlan.weight,
                    actualReps: setPlan.reps,
                    targetWeightSide: setPlan.weightSide,
                    targetRepsSide: setPlan.repsSide,
                    actualWeightSide: setPlan.weightSide,
                    actualRepsSide: setPlan.repsSide
                )
            )
        }
        try context.save()
        return snapshot
    }

    /// Applies the menu shown in the day builder to an already-running workout.
    /// Completed sets remain historical facts; only unfinished rows are reshaped
    /// to the new plan. This is also the single source of truth for exercise order.
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
        if let defaultPlanPattern {
            session.defaultPlanPattern = defaultPlanPattern
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
        let allLogs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionID == session.id }
        let requestedIDs = Set(inputs.map(\.exerciseID))
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
            guard !exerciseLogs.contains(where: \.isCompleted) else {
                throw WorkoutServiceError.cannotRemoveStartedExercise
            }
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
                        : nil
                )
                context.insert(snapshot)
                snapshots.append(snapshot)
            }

            snapshot.order = lockedOrders[input.exerciseID] ?? movableOrders[input.exerciseID] ?? order

            var exerciseLogs = allLogs
                .filter { $0.sessionExerciseID == snapshot.id }
                .sorted { $0.setNumber < $1.setNumber }
            let exerciseHasStarted = exerciseLogs.contains { $0.isCompleted || $0.startedAt != nil }

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
                    let usedPlanDefaults = log.actualWeight == log.targetWeight
                        && log.actualReps == log.targetReps
                    log.setNumber = index + 1
                    log.targetWeight = plan.weight
                    log.targetReps = plan.reps
                    log.targetWeightSide = plan.weightSide
                    log.targetRepsSide = plan.repsSide
                    if usedPlanDefaults {
                        log.actualWeight = plan.weight
                        log.actualReps = plan.reps
                        log.actualWeightSide = plan.weightSide
                        log.actualRepsSide = plan.repsSide
                    }
                } else {
                    let log = SetLog(
                        sessionID: session.id,
                        sessionExerciseID: snapshot.id,
                        exerciseID: snapshot.exerciseID,
                        setNumber: index + 1,
                        targetWeight: plan.weight,
                        targetReps: plan.reps,
                        actualWeight: catalogExercise.volumeUnit == .bodyweight
                            ? (availableBodyWeight ?? 0)
                            : plan.weight,
                        actualReps: plan.reps,
                        targetWeightSide: plan.weightSide,
                        targetRepsSide: plan.repsSide,
                        actualWeightSide: plan.weightSide,
                        actualRepsSide: plan.repsSide
                    )
                    context.insert(log)
                    exerciseLogs.append(log)
                }
            }

            for log in exerciseLogs.dropFirst(plans.count) where !log.isCompleted && log.startedAt == nil {
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
                            repsSide: log.targetRepsSide
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

    @discardableResult
    static func addSet(
        to exercise: SessionExercise,
        in context: ModelContext
    ) throws -> SetLog {
        try requireInProgressSession(exercise.sessionID, in: context)
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == exercise.id }
            .sorted { $0.setNumber < $1.setNumber }
        let previous = logs.last
        let setNumber = (previous?.setNumber ?? 0) + 1
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
            actualRepsSide: previous?.actualRepsSide
        )
        context.insert(log)
        exercise.targetSets = max(exercise.targetSets, setNumber)
        try context.save()
        return log
    }

    static func removeLastIncompleteSet(
        from exercise: SessionExercise,
        in context: ModelContext
    ) throws {
        try requireInProgressSession(exercise.sessionID, in: context)
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == exercise.id }
            .sorted { $0.setNumber < $1.setNumber }
        guard logs.count > 1,
              let removable = logs.last,
              !removable.isCompleted else {
            throw WorkoutServiceError.noIncompleteSet
        }
        context.delete(removable)
        exercise.targetSets = max(1, logs.count - 1)
        try context.save()
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
        guard !exerciseLogs.contains(where: \.isCompleted) else {
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
            guard let snapshot = snapshotByExerciseID[item.exerciseID] else { return nil }
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
