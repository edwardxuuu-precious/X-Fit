import Foundation
import SwiftData

struct HistoricalSetInput {
    let weight: Double
    let reps: Int
    let rir: Int?
    var startedAt: Date? = nil
    var restDurationSeconds: Int? = nil
    var weightSide: MeasurementSide = .bilateral
    var repsSide: MeasurementSide = .bilateral
}

struct HistoricalExerciseInput {
    let exerciseID: UUID
    let sets: [HistoricalSetInput]
    let performanceNotes: String
}

struct HistoricalWorkoutInput {
    let name: String
    let startedAt: Date
    let durationMinutes: Int?
    let notes: String
    let exercises: [HistoricalExerciseInput]
    var importIdentifier: String = ""
    var scheduledWorkoutID: UUID? = nil
    var trainingLocalDay: String? = nil
    var trainingTimeZoneIdentifier: String? = nil
    var isStartTimeKnown: Bool? = nil
}

struct ScheduledWorkoutBackfillSetInput {
    let existingLogID: UUID?
    let weight: Double
    let reps: Int
    let rir: Int?
    var weightSide: MeasurementSide = .bilateral
    var repsSide: MeasurementSide = .bilateral
}

struct ScheduledWorkoutBackfillExerciseInput {
    let existingSnapshotID: UUID?
    let exerciseID: UUID
    let sets: [ScheduledWorkoutBackfillSetInput]
    let performanceNotes: String
    let feeling: WorkoutFeeling?
    let isWarmup: Bool
}

struct ScheduledWorkoutBackfillInput {
    let scheduleID: UUID
    let existingSessionID: UUID?
    let name: String
    let date: Date
    /// Nil explicitly means the exact start time is unknown.
    let startedAt: Date?
    let durationMinutes: Int?
    let notes: String
    let exercises: [ScheduledWorkoutBackfillExerciseInput]
}

struct ScheduledWorkoutBackfillPreparation {
    let scheduleID: UUID
    let existingSessionID: UUID?
    let name: String
    let date: Date
    let startedAt: Date?
    let durationMinutes: Int?
    let notes: String
    let exercises: [ScheduledWorkoutBackfillExercisePreparation]
}

struct ScheduledWorkoutBackfillExercisePreparation {
    let existingSnapshotID: UUID?
    let exerciseID: UUID
    let sets: [ScheduledWorkoutBackfillSetPreparation]
    let performanceNotes: String
    let feeling: WorkoutFeeling?
    let isWarmup: Bool
    let plannedRestSeconds: Int
    let planNotes: String
}

struct ScheduledWorkoutBackfillSetPreparation {
    let existingLogID: UUID?
    let weight: Double
    let reps: Int
    let rir: Int?
    let weightSide: MeasurementSide
    let repsSide: MeasurementSide
}

enum HistoricalWorkoutServiceError: LocalizedError {
    case emptyName
    case emptyExercises
    case emptySets
    case missingExercise
    case duplicateRecord
    case invalidRestDuration
    case missingSchedule
    case missingSession
    case immutableSchedule
    case supersededSchedule

    var errorDescription: String? {
        switch self {
        case .emptyName: return "请填写训练名称。"
        case .emptyExercises: return "请至少添加一个动作。"
        case .emptySets: return "每个动作至少需要一组完成记录。"
        case .missingExercise: return "补录动作已不存在，请重新选择。"
        case .duplicateRecord: return "相同时间和名称的训练已经存在，请勿重复补录。"
        case .invalidRestDuration:
            return "组后休息必须在 0–\(RestDurationInput.maximumSeconds) 秒之间。"
        case .missingSchedule:
            return "要关联的训练日程已不存在。"
        case .missingSession:
            return "要恢复的历史训练已经不存在。"
        case .immutableSchedule:
            return "正在进行的训练不能通过历史补录修改。"
        case .supersededSchedule:
            return "这项安排已由确认修订替代，请选择当前安排；已有实际记录仍可查看和修改。"
        }
    }
}

@MainActor
enum HistoricalWorkoutService {
    static func prepareScheduledBackfill(
        scheduleID: UUID,
        in context: ModelContext
    ) throws -> ScheduledWorkoutBackfillPreparation {
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        guard let schedule = schedules.first(where: { $0.id == scheduleID }) else {
            throw HistoricalWorkoutServiceError.missingSchedule
        }
        guard schedule.status != .inProgress else {
            throw HistoricalWorkoutServiceError.immutableSchedule
        }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let linkedSession = sessions
            .filter { $0.scheduledWorkoutID == schedule.id }
            .sorted { $0.startedAt > $1.startedAt }
            .first { $0.status == .discarded || $0.status == .completed }
        if let linkedSession {
            if linkedSession.status == .discarded,
               try ConfirmedDailyTrainingPlanService.isSuperseded(schedule.id, in: context) {
                throw HistoricalWorkoutServiceError.supersededSchedule
            }
            let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
                .filter { $0.sessionID == linkedSession.id }
                .sorted { $0.order < $1.order }
            let logs = try context.fetch(FetchDescriptor<SetLog>())
                .filter { $0.sessionID == linkedSession.id }
            return ScheduledWorkoutBackfillPreparation(
                scheduleID: schedule.id,
                existingSessionID: linkedSession.id,
                name: linkedSession.templateName,
                date: TrainingScheduleDate.displayDate(schedule),
                startedAt: linkedSession.status == .completed && linkedSession.isStartTimeKnown
                    ? linkedSession.startedAt
                    : nil,
                durationMinutes: linkedSession.status == .completed
                    ? linkedSession.completedAt.map {
                        max(1, Int($0.timeIntervalSince(linkedSession.startedAt) / 60))
                    }
                    : nil,
                notes: linkedSession.notes,
                exercises: snapshots.map { snapshot in
                    let snapshotLogs = logs.filter { $0.sessionExerciseID == snapshot.id && $0.reductionOrder == nil }
                    let setPreparations = snapshotLogs
                        .sorted { $0.setNumber < $1.setNumber }
                        .map { log in
                            ScheduledWorkoutBackfillSetPreparation(
                                existingLogID: log.id,
                                weight: log.isCompleted ? log.actualWeight : log.targetWeight,
                                reps: log.isCompleted ? log.actualReps : log.targetReps,
                                rir: log.isCompleted ? log.rir : nil,
                                weightSide: log.isCompleted ? log.actualWeightSide : log.targetWeightSide,
                                repsSide: log.isCompleted ? log.actualRepsSide : log.targetRepsSide
                            )
                        }
                    return ScheduledWorkoutBackfillExercisePreparation(
                        existingSnapshotID: snapshot.id,
                        exerciseID: snapshot.exerciseID,
                        sets: setPreparations.isEmpty && snapshot.hasManuallyReducedSets != true
                            ? snapshot.plannedSets.map {
                                ScheduledWorkoutBackfillSetPreparation(
                                    existingLogID: nil,
                                    weight: $0.weight,
                                    reps: $0.reps,
                                    rir: nil,
                                    weightSide: $0.weightSide,
                                    repsSide: $0.repsSide
                                )
                            }
                            : setPreparations,
                        performanceNotes: snapshot.performanceNotes,
                        feeling: snapshot.feeling,
                        isWarmup: !snapshotLogs.isEmpty && snapshotLogs.allSatisfy { $0.isWarmup },
                        plannedRestSeconds: snapshot.restSeconds,
                        planNotes: snapshot.exerciseNotes
                    )
                }
            )
        }

        guard try !ConfirmedDailyTrainingPlanService.isSuperseded(schedule.id, in: context) else {
            throw HistoricalWorkoutServiceError.supersededSchedule
        }

        let frozenPlan = schedule.planSnapshot.isEmpty
            ? try ScheduleService.planSnapshot(templateID: schedule.templateID, in: context)
            : schedule.planSnapshot
        return ScheduledWorkoutBackfillPreparation(
            scheduleID: schedule.id,
            existingSessionID: nil,
            name: schedule.templateName,
            date: TrainingScheduleDate.displayDate(schedule),
            startedAt: nil,
            durationMinutes: nil,
            notes: "",
            exercises: frozenPlan.map { snapshot in
                let plans = snapshot.plannedSets.isEmpty
                    ? WorkoutSetPlan.preset(
                        snapshot.planPattern,
                        count: snapshot.targetSets,
                        baseWeight: snapshot.targetWeight,
                        baseReps: snapshot.minReps
                    )
                    : snapshot.plannedSets
                return ScheduledWorkoutBackfillExercisePreparation(
                    existingSnapshotID: nil,
                    exerciseID: snapshot.exerciseID,
                    sets: plans.map {
                        ScheduledWorkoutBackfillSetPreparation(
                            existingLogID: nil,
                            weight: $0.weight,
                            reps: $0.reps,
                            rir: nil,
                            weightSide: $0.weightSide,
                            repsSide: $0.repsSide
                        )
                    },
                    performanceNotes: "",
                    feeling: nil,
                    isWarmup: false,
                    plannedRestSeconds: snapshot.restSeconds,
                    planNotes: snapshot.exerciseNotes
                )
            }
        )
    }

    static func recordScheduledBackfill(
        _ input: ScheduledWorkoutBackfillInput,
        in context: ModelContext
    ) throws -> WorkoutSession {
        let normalizedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw HistoricalWorkoutServiceError.emptyName }
        guard !input.exercises.isEmpty else { throw HistoricalWorkoutServiceError.emptyExercises }
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        guard let schedule = schedules.first(where: { $0.id == input.scheduleID }) else {
            throw HistoricalWorkoutServiceError.missingSchedule
        }
        guard schedule.status != .inProgress else {
            throw HistoricalWorkoutServiceError.immutableSchedule
        }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let linkedSessions = sessions.filter { $0.scheduledWorkoutID == schedule.id }
        let emptyExercises = input.exercises.filter { $0.sets.isEmpty }
        if !emptyExercises.isEmpty {
            guard let sessionID = input.existingSessionID,
                  linkedSessions.contains(where: { $0.id == sessionID }) else {
                throw HistoricalWorkoutServiceError.emptySets
            }
            let snapshots = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.sessionID == sessionID }
            let logs = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionID == sessionID }
            for inputExercise in emptyExercises {
                guard let snapshotID = inputExercise.existingSnapshotID,
                      let snapshot = snapshots.first(where: { $0.id == snapshotID && $0.exerciseID == inputExercise.exerciseID }),
                      snapshot.hasManuallyReducedSets == true else { throw HistoricalWorkoutServiceError.emptySets }
                let rows = logs.filter { $0.sessionExerciseID == snapshotID }
                guard !rows.isEmpty, rows.allSatisfy({ $0.reductionOrder != nil && !$0.isCompleted }) else {
                    throw HistoricalWorkoutServiceError.emptySets
                }
            }
        }
        let session: WorkoutSession
        if let existingSessionID = input.existingSessionID {
            guard let existing = linkedSessions.first(where: { $0.id == existingSessionID }) else {
                throw HistoricalWorkoutServiceError.missingSession
            }
            session = existing
        } else if let existing = linkedSessions.first(where: {
            $0.status == .discarded || $0.status == .completed
        }) {
            session = existing
        } else {
            guard try !ConfirmedDailyTrainingPlanService.isSuperseded(schedule.id, in: context) else {
                throw HistoricalWorkoutServiceError.supersededSchedule
            }
            session = WorkoutSession(
                scheduledWorkoutID: schedule.id,
                templateID: schedule.templateID,
                templateName: normalizedName,
                plannedDate: input.date,
                startedAt: input.startedAt ?? input.date.startOfDay,
                isStartTimeKnown: input.startedAt != nil,
                completedAt: nil,
                status: .completed
            )
            context.insert(session)
        }

        if session.status == .discarded,
           try ConfirmedDailyTrainingPlanService.isSuperseded(schedule.id, in: context) {
            throw HistoricalWorkoutServiceError.supersededSchedule
        }

        session.scheduledWorkoutID = schedule.id
        session.templateID = schedule.templateID
        session.templateName = normalizedName
        session.plannedDate = input.date.startOfDay
        session.startedAt = input.startedAt ?? input.date.startOfDay
        TrainingHistoryDate.capture(session, date: input.date, schedule: schedule)
        session.isStartTimeKnown = input.startedAt != nil
        session.completedAt = input.durationMinutes.map {
            session.startedAt.addingTimeInterval(TimeInterval(max(1, $0) * 60))
        }
        session.status = .completed
        session.notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        session.restEndDate = nil

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        guard input.exercises.allSatisfy({ exerciseByID[$0.exerciseID] != nil }) else {
            throw HistoricalWorkoutServiceError.missingExercise
        }
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == session.id }
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionID == session.id }
        let retainedSnapshotIDs = Set(input.exercises.compactMap(\.existingSnapshotID))

        for snapshot in snapshots where !retainedSnapshotIDs.contains(snapshot.id) {
            logs.filter { $0.sessionExerciseID == snapshot.id && $0.reductionOrder == nil }.forEach {
                $0.isCompleted = false
                $0.completedAt = nil
                $0.rir = nil
            }
            snapshot.feeling = nil
            snapshot.exerciseCompletedAt = nil
        }

        for (order, item) in input.exercises.enumerated() {
            guard let exercise = exerciseByID[item.exerciseID] else { continue }
            let snapshot: SessionExercise
            if let existingSnapshotID = item.existingSnapshotID,
               let existing = snapshots.first(where: { $0.id == existingSnapshotID }) {
                snapshot = existing
            } else {
                let reps = item.sets.map(\.reps)
                let plannedSets = item.sets.map {
                    WorkoutSetPlan(
                        weight: max(0, $0.weight),
                        reps: max(1, $0.reps),
                        weightSide: $0.weightSide,
                        repsSide: $0.repsSide
                    )
                }
                let bodyWeight = exercise.volumeUnit == .bodyweight
                    ? BodyWeightSnapshotResolver.resolveSnapshot(
                        for: input.date,
                        measurements: measurements,
                        currentHealthWeightKg: nil
                    )
                    : nil
                snapshot = SessionExercise(
                    sessionID: session.id,
                    exerciseID: exercise.id,
                    exerciseName: exercise.name,
                    order: order,
                    targetSets: item.sets.count,
                    minReps: reps.min() ?? 1,
                    maxReps: reps.max() ?? 1,
                    targetWeight: item.sets.map(\.weight).max() ?? 0,
                    restSeconds: exercise.defaultRestSeconds,
                    muscleGroup: exercise.muscleGroup,
                    exerciseNotes: exercise.notes,
                    referenceURL: exercise.referenceURL,
                    volumeUnit: exercise.volumeUnit,
                    plannedSets: plannedSets,
                    bodyWeightKgSnapshot: bodyWeight?.weightKg,
                    bodyWeightSnapshotSourceDate: bodyWeight?.sourceDate
                )
                context.insert(snapshot)
            }

            snapshot.order = order
            snapshot.performanceNotes = item.performanceNotes
                .trimmingCharacters(in: .whitespacesAndNewlines)
            snapshot.feeling = item.feeling
            snapshot.exerciseStartedAt = nil
            snapshot.exerciseCompletedAt = nil

            let snapshotLogs = logs
                .filter { $0.sessionExerciseID == snapshot.id && $0.reductionOrder == nil }
                .sorted { $0.setNumber < $1.setNumber }
            let retainedLogIDs = Set(item.sets.compactMap(\.existingLogID))
            for log in snapshotLogs where !retainedLogIDs.contains(log.id) {
                log.isCompleted = false
                log.completedAt = nil
                log.rir = nil
            }

            var nextSetNumber = (logs.filter { $0.sessionExerciseID == snapshot.id }.map(\.setNumber).max() ?? 0) + 1
            let preservesReducedNumbers = snapshot.hasManuallyReducedSets == true
            for (setIndex, set) in item.sets.enumerated() {
                let log: SetLog
                if let existingLogID = set.existingLogID,
                   let existing = snapshotLogs.first(where: { $0.id == existingLogID }) {
                    log = existing
                } else if setIndex < snapshotLogs.count,
                          !retainedLogIDs.contains(snapshotLogs[setIndex].id) {
                    log = snapshotLogs[setIndex]
                } else {
                    log = SetLog(
                        sessionID: session.id,
                        sessionExerciseID: snapshot.id,
                        exerciseID: snapshot.exerciseID,
                        setNumber: preservesReducedNumbers ? nextSetNumber : setIndex + 1,
                        targetWeight: max(0, set.weight),
                        targetReps: max(1, set.reps),
                        actualWeight: max(0, set.weight),
                        actualReps: max(1, set.reps)
                    )
                    context.insert(log)
                    nextSetNumber += 1
                }
                let actualWeight = snapshot.volumeUnit == .bodyweight
                    ? (snapshot.bodyWeightKgSnapshot ?? 0)
                    : max(0, set.weight)
                if !preservesReducedNumbers { log.setNumber = setIndex + 1 }
                log.actualWeight = actualWeight
                log.actualReps = max(1, set.reps)
                log.rir = set.rir
                log.isWarmup = item.isWarmup
                log.isCompleted = true
                log.startedAt = nil
                log.completedAt = nil
                log.restStartedAt = nil
                log.restEndedAt = nil
                log.restDurationSeconds = nil
                log.actualWeightSide = set.weightSide
                log.actualRepsSide = set.repsSide
            }
        }

        schedule.status = .completed
        schedule.skipReason = ""
        schedule.reminderDate = nil
        schedule.updatedAt = .now
        try context.save()
        return session
    }

    static func record(
        _ input: HistoricalWorkoutInput,
        in context: ModelContext
    ) throws -> WorkoutSession {
        let trimmedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw HistoricalWorkoutServiceError.emptyName }
        guard !input.exercises.isEmpty else { throw HistoricalWorkoutServiceError.emptyExercises }
        guard input.exercises.allSatisfy({ !$0.sets.isEmpty }) else {
            throw HistoricalWorkoutServiceError.emptySets
        }
        guard input.exercises
            .flatMap(\.sets)
            .allSatisfy({ set in
                guard let rest = set.restDurationSeconds else { return true }
                return (0...RestDurationInput.maximumSeconds).contains(rest)
            }) else {
            throw HistoricalWorkoutServiceError.invalidRestDuration
        }

        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let isDuplicate = existingSessions.contains {
            if !input.importIdentifier.isEmpty {
                return $0.importIdentifier == input.importIdentifier
            }
            return $0.status == .completed
                && $0.templateName == trimmedName
                && abs($0.startedAt.timeIntervalSince(input.startedAt)) < 60
        }
        guard !isDuplicate else { throw HistoricalWorkoutServiceError.duplicateRecord }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        guard input.exercises.allSatisfy({ exerciseByID[$0.exerciseID] != nil }) else {
            throw HistoricalWorkoutServiceError.missingExercise
        }
        let linkedSchedule = input.scheduledWorkoutID.flatMap { scheduledID in
            schedules.first { $0.id == scheduledID }
        }
        if input.scheduledWorkoutID != nil, linkedSchedule == nil {
            throw HistoricalWorkoutServiceError.missingSchedule
        }
        if let linkedSchedule, try ConfirmedDailyTrainingPlanService.isSuperseded(linkedSchedule.id, in: context) {
            throw HistoricalWorkoutServiceError.supersededSchedule
        }

        let completedAt = input.durationMinutes.map {
            input.startedAt.addingTimeInterval(TimeInterval(max(1, $0) * 60))
        }
        let session = WorkoutSession(
            scheduledWorkoutID: linkedSchedule?.id,
            templateID: linkedSchedule?.templateID,
            templateName: trimmedName,
            plannedDate: input.startedAt,
            startedAt: input.startedAt,
            completedAt: completedAt,
            status: .completed,
            notes: input.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            importIdentifier: input.importIdentifier
        )
        session.isStartTimeKnown = input.isStartTimeKnown ?? true
        if let localDay = input.trainingLocalDay, !localDay.isEmpty {
            session.trainingLocalDay = localDay
        }
        if let timeZoneIdentifier = input.trainingTimeZoneIdentifier, !timeZoneIdentifier.isEmpty {
            session.trainingTimeZoneIdentifier = timeZoneIdentifier
        } else if input.importIdentifier.isEmpty {
            TrainingHistoryDate.capture(session, date: input.startedAt, schedule: linkedSchedule)
        }
        context.insert(session)

        for (index, item) in input.exercises.enumerated() {
            guard let exercise = exerciseByID[item.exerciseID] else { continue }
            let reps = item.sets.map(\.reps)
            let weight = item.sets.map(\.weight).max() ?? 0
            let bodyWeight = exercise.volumeUnit == .bodyweight
                ? BodyWeightSnapshotResolver.resolveSnapshot(
                    for: input.startedAt,
                    measurements: measurements,
                    currentHealthWeightKg: nil
                )
                : nil
            let snapshot = SessionExercise(
                sessionID: session.id,
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                order: index,
                targetSets: item.sets.count,
                minReps: reps.min() ?? 1,
                maxReps: reps.max() ?? 1,
                targetWeight: weight,
                restSeconds: exercise.defaultRestSeconds,
                muscleGroup: exercise.muscleGroup,
                exerciseNotes: exercise.notes,
                referenceURL: exercise.referenceURL,
                volumeUnit: exercise.volumeUnit,
                performanceNotes: item.performanceNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                bodyWeightKgSnapshot: bodyWeight?.weightKg,
                bodyWeightSnapshotSourceDate: bodyWeight?.sourceDate
            )
            context.insert(snapshot)

            for (setIndex, set) in item.sets.enumerated() {
                context.insert(
                    SetLog(
                        sessionID: session.id,
                        sessionExerciseID: snapshot.id,
                        exerciseID: exercise.id,
                        setNumber: setIndex + 1,
                        targetWeight: max(0, set.weight),
                        targetReps: max(1, set.reps),
                        actualWeight: exercise.volumeUnit == .bodyweight
                            ? (bodyWeight?.weightKg ?? 0)
                            : max(0, set.weight),
                        actualReps: max(1, set.reps),
                        rir: set.rir,
                        isCompleted: true,
                        startedAt: set.startedAt,
                        completedAt: set.startedAt ?? input.durationMinutes.map { _ in
                            input.startedAt.addingTimeInterval(TimeInterval((setIndex + 1) * 60))
                        },
                        targetWeightSide: set.weightSide,
                        targetRepsSide: set.repsSide,
                        actualWeightSide: set.weightSide,
                        actualRepsSide: set.repsSide
                    )
                )
            }
        }

        if let linkedSchedule {
            linkedSchedule.status = .completed
            linkedSchedule.updatedAt = .now
        }

        try context.save()
        return session
    }
}

struct ConfirmedHistoricalBackfillResult: Codable, Equatable {
    let workoutSessionID: UUID
    let workoutScheduleID: UUID
    let skippedJumpRopeScheduleID: UUID
    let createdExerciseCount: Int
}

enum ConfirmedHistoricalBackfillError: LocalizedError {
    case missingWorkout
    case ambiguousWorkout
    case missingJumpRope
    case immutableJumpRope

    var errorDescription: String? {
        switch self {
        case .missingWorkout: return "找不到 2026-09-14 待恢复训练。"
        case .ambiguousWorkout: return "2026-09-14 存在多条候选训练，未写入。"
        case .missingJumpRope: return "找不到 2026-09-19 跳绳日程。"
        case .immutableJumpRope: return "2026-09-19 跳绳日程已经完成或正在进行，未覆盖。"
        }
    }
}

@MainActor
enum ConfirmedHistoricalBackfillService {
    static let maintenanceArgument = "--apply-confirmed-20260914-backfill-v1"
    static let receiptFileName = "confirmed-20260914-backfill-v1.json"

    static func apply(in context: ModelContext) throws -> ConfirmedHistoricalBackfillResult {
        let calendar = Calendar.current
        guard let workoutDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)),
              let ropeDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19)) else {
            throw ConfirmedHistoricalBackfillError.missingWorkout
        }
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let allSnapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let allLogs = try context.fetch(FetchDescriptor<SetLog>())
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>())
        let ropeScheduleIDs = Set(links.filter {
            $0.templateCode.hasPrefix("ROPE_")
        }.map(\.scheduledWorkoutID))
        let ropeCandidates = schedules.filter {
            $0.plannedDate.isSameDay(as: ropeDate) && ropeScheduleIDs.contains($0.id)
        }
        guard ropeCandidates.count == 1, let ropeSchedule = ropeCandidates.first else {
            throw ConfirmedHistoricalBackfillError.missingJumpRope
        }
        guard ropeSchedule.status == .planned || ropeSchedule.status == .skipped else {
            throw ConfirmedHistoricalBackfillError.immutableJumpRope
        }

        let workoutCandidates = schedules.filter { schedule in
            guard schedule.plannedDate.isSameDay(as: workoutDate) else { return false }
            return sessions.contains { session in
                session.scheduledWorkoutID == schedule.id
                    && allSnapshots.contains {
                        $0.sessionID == session.id && $0.exerciseName == "前蹲"
                    }
            }
        }
        guard !workoutCandidates.isEmpty else {
            throw ConfirmedHistoricalBackfillError.missingWorkout
        }
        guard workoutCandidates.count == 1, let workoutSchedule = workoutCandidates.first else {
            throw ConfirmedHistoricalBackfillError.ambiguousWorkout
        }
        guard let workoutSession = sessions.first(where: {
            let candidateID = $0.id
            return $0.scheduledWorkoutID == workoutSchedule.id
                && allSnapshots.contains { $0.sessionID == candidateID }
        }) else {
            throw HistoricalWorkoutServiceError.missingSession
        }
        let snapshots = allSnapshots.filter { $0.sessionID == workoutSession.id }
        let logs = allLogs.filter { $0.sessionID == workoutSession.id }
        let snapshotByName = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.exerciseName, $0) })

        var exercises = try context.fetch(FetchDescriptor<Exercise>())
        var createdExerciseCount = 0
        func actualExercise(
            named name: String,
            muscleGroup: String,
            equipment: String,
            unit: ExerciseVolumeUnit,
            restSeconds: Int,
            notes: String
        ) -> Exercise {
            if let existing = exercises.first(where: {
                $0.name == name && $0.volumeUnit == unit && !$0.isArchived
            }) {
                return existing
            }
            let exercise = Exercise(
                name: name,
                muscleGroup: muscleGroup,
                equipment: equipment,
                defaultRestSeconds: restSeconds,
                isBuiltIn: false,
                notes: notes,
                volumeUnit: unit
            )
            context.insert(exercise)
            exercises.append(exercise)
            createdExerciseCount += 1
            return exercise
        }
        func existingExercise(named name: String) throws -> Exercise {
            guard let snapshot = snapshotByName[name],
                  let exercise = exercises.first(where: { $0.id == snapshot.exerciseID }) else {
                throw HistoricalWorkoutServiceError.missingExercise
            }
            return exercise
        }
        func completedSets(
            for snapshot: SessionExercise?,
            count: Int,
            weight: Double,
            reps: Int,
            rir: Int?,
            weightSide: MeasurementSide = .bilateral,
            repsSide: MeasurementSide = .bilateral
        ) -> [ScheduledWorkoutBackfillSetInput] {
            let existing = snapshot.map { selected in
                logs.filter { $0.sessionExerciseID == selected.id && $0.reductionOrder == nil }
                    .sorted { $0.setNumber < $1.setNumber }
            } ?? []
            return (0..<count).map { index in
                ScheduledWorkoutBackfillSetInput(
                    existingLogID: index < existing.count ? existing[index].id : nil,
                    weight: weight,
                    reps: reps,
                    rir: rir,
                    weightSide: weightSide,
                    repsSide: repsSide
                )
            }
        }
        func input(
            name: String,
            exercise: Exercise,
            count: Int,
            weight: Double,
            reps: Int,
            rir: Int?,
            notes: String,
            feeling: WorkoutFeeling? = nil,
            isWarmup: Bool = false,
            weightSide: MeasurementSide = .bilateral,
            repsSide: MeasurementSide = .bilateral
        ) -> ScheduledWorkoutBackfillExerciseInput {
            let snapshot = snapshotByName[name]
            return ScheduledWorkoutBackfillExerciseInput(
                existingSnapshotID: snapshot?.id,
                exerciseID: exercise.id,
                sets: completedSets(
                    for: snapshot,
                    count: count,
                    weight: weight,
                    reps: reps,
                    rir: rir,
                    weightSide: weightSide,
                    repsSide: repsSide
                ),
                performanceNotes: notes,
                feeling: feeling,
                isWarmup: isWarmup
            )
        }

        let wallAnkle = try existingExercise(named: "膝触墙踝背屈")
        let frontSquat = try existingExercise(named: "前蹲")
        let pendulum = try existingExercise(named: "钟摆深蹲")
        let bulgarian = try existingExercise(named: "保加利亚分腿蹲")
        let legExtension = try existingExercise(named: "腿屈伸")
        let soleus = try existingExercise(named: "坐姿比目鱼肌等长")
        let tibialis = try existingExercise(named: "胫骨前肌抬脚")
        let farmer = try existingExercise(named: "农夫走")
        let bodyweightSquat = actualExercise(
            named: "自重深蹲", muscleGroup: "腿部", equipment: "自重", unit: .count,
            restSeconds: 30, notes: "一般热身；动作稳定。"
        )
        let lungeShift = actualExercise(
            named: "前后向箭步重心转移", muscleGroup: "腿部", equipment: "自重", unit: .count,
            restSeconds: 30, notes: "一般热身；控制幅度。"
        )
        let ankleCAR = actualExercise(
            named: "脚踝主动环绕 CAR", muscleGroup: "小腿", equipment: "自重", unit: .count,
            restSeconds: 30, notes: "踝活动度；小腿尽量不跟着转。"
        )

        let workoutInput = ScheduledWorkoutBackfillInput(
            scheduleID: workoutSchedule.id,
            existingSessionID: workoutSession.id,
            name: workoutSchedule.templateName,
            date: workoutDate,
            startedAt: nil,
            durationMinutes: nil,
            notes: "一般热身：单车或椭圆机 5–6 分钟，RPE 4–5（具体器械与精确时长未记录）。",
            exercises: [
                input(name: "自重深蹲", exercise: bodyweightSquat, count: 2, weight: 0, reps: 8,
                      rir: nil, notes: "动作稳定。", isWarmup: true),
                input(name: "前后向箭步重心转移", exercise: lungeShift, count: 1, weight: 0, reps: 6,
                      rir: nil, notes: "每侧完成；控制幅度。", isWarmup: true, repsSide: .single),
                input(name: "膝触墙踝背屈", exercise: wallAnkle, count: 2, weight: 0, reps: 8,
                      rir: nil, notes: "每侧完成；脚跟不抬，膝盖沿第二脚趾方向。", isWarmup: true,
                      repsSide: .single),
                input(name: "脚踝主动环绕 CAR", exercise: ankleCAR, count: 1, weight: 0, reps: 5,
                      rir: nil, notes: "每侧、每方向完成；小腿尽量不跟着转。", isWarmup: true,
                      repsSide: .single),
                input(name: "前蹲", exercise: frontSquat, count: 4, weight: 25, reps: 8,
                      rir: 3, notes: "25 kg 为杠铃总重。"),
                input(name: "钟摆深蹲", exercise: pendulum, count: 3, weight: 55, reps: 8,
                      rir: 2, notes: "55 为器械显示值。"),
                input(name: "保加利亚分腿蹲", exercise: bulgarian, count: 3, weight: 25, reps: 8,
                      rir: 2, notes: "25 kg 为总负重；每侧完成。", repsSide: .single),
                input(name: "腿屈伸", exercise: legExtension, count: 3, weight: 40, reps: 12,
                      rir: 2, notes: "40 为器械显示值。"),
                input(name: "坐姿比目鱼肌等长", exercise: soleus, count: 3, weight: 0, reps: 35,
                      rir: nil, notes: "附加负重 20 kg；35 秒，轻松；脚掌稳定，不在疼痛位置硬顶。",
                      feeling: .strong),
                input(name: "胫骨前肌抬脚", exercise: tibialis, count: 2, weight: 0, reps: 12,
                      rir: nil, notes: "脚跟不离地。"),
                input(name: "农夫走", exercise: farmer, count: 6, weight: 35, reps: 1,
                      rir: nil,
                      notes: "每侧 34 kg；RPE 7–8；从第 2 组开始握力下降；原计划 6×30 米，共 180 米；实际 6×35 米，共 210 米。",
                      weightSide: .single)
            ]
        )
        ropeSchedule.status = .skipped
        ropeSchedule.skipReason = "拼家具"
        ropeSchedule.reminderDate = nil
        ropeSchedule.updatedAt = .now
        let restored = try HistoricalWorkoutService.recordScheduledBackfill(workoutInput, in: context)

        return ConfirmedHistoricalBackfillResult(
            workoutSessionID: restored.id,
            workoutScheduleID: workoutSchedule.id,
            skippedJumpRopeScheduleID: ropeSchedule.id,
            createdExerciseCount: createdExerciseCount
        )
    }
}

struct ConfirmedNotesImportPackage: Codable {
    var version: Int
    var packageID: String
    var timeZoneIdentifier: String
    var workouts: [ConfirmedNotesWorkout]
    var bodyMeasurements: [ConfirmedNotesBodyMeasurement]
    var meals: [ConfirmedNotesMeal]
    var jumpRopeEntries: [ConfirmedNotesJumpRope]?
    var voidMealIDs: [UUID]?
    var staleSession: ConfirmedNotesStaleSession?
}

struct ConfirmedNotesWorkout: Codable {
    var id: String
    var date: String
    var name: String
    var durationMinutes: Int?
    var notes: String
    var scheduleTemplateCode: String?
    var exercises: [ConfirmedNotesExercise]
    var startTimeKnown: Bool? = nil
}

struct ConfirmedNotesExercise: Codable {
    var name: String
    var muscleGroup: String
    var equipment: String
    var volumeUnit: ExerciseVolumeUnit
    var notes: String
    var sets: [ConfirmedNotesSet]
}

struct ConfirmedNotesSet: Codable {
    var weight: Double
    var reps: Int
    var weightSide: MeasurementSide
    var repsSide: MeasurementSide
}

struct ConfirmedNotesBodyMeasurement: Codable {
    var id: UUID
    var recordedAt: String
    var weightJin: Double
    var notes: String
}

struct ConfirmedNotesMeal: Codable {
    var id: UUID
    var date: String
    var mealType: MealType
    var name: String
    var calories: Int? = nil
    var estimationSource: String? = nil
}

struct ConfirmedNotesJumpRope: Codable {
    var id: UUID
    var date: String
    var count: Int
    var activeDurationSeconds: Int?
    var elapsedDurationSeconds: Int?
    var totalSetCount: Int? = nil
    var recordedTimeKnown: Bool? = nil
}

struct ConfirmedNotesStaleSession: Codable {
    var plannedDate: String
    var templateName: String
    var expectedSessionID: UUID? = nil
    var expectedScheduledWorkoutID: UUID? = nil
}

struct ConfirmedNotesImportSummary: Codable, Equatable {
    var importedSessions: Int = 0
    var skippedSessions: Int = 0
    var importedSessionExercises: Int = 0
    var importedSets: Int = 0
    var createdExercises: Int = 0
    var importedBodyMeasurements: Int = 0
    var skippedBodyMeasurements: Int = 0
    var importedMeals: Int = 0
    var skippedMeals: Int = 0
    var importedJumpRopeEntries: Int = 0
    var skippedJumpRopeEntries: Int = 0
    var voidedMeals: Int = 0
    var alreadyVoidedMeals: Int = 0
    var linkedSchedules: Int = 0
    var discardedStaleSessions: Int = 0
    var repairedSessionDateMetadata: Int = 0
}

struct ConfirmedNotesImportPreview: Codable, Equatable {
    var packageID: String
    var importedBodyMeasurements: Int
    var skippedBodyMeasurements: Int
    var importedMeals: Int
    var skippedMeals: Int
    var ownerEstimatedMeals: Int
    var skippedMeasurementIDs: [UUID]
    var skippedMealIDs: [UUID]
}

enum ConfirmedNotesImportError: LocalizedError {
    case unsupportedVersion
    case invalidPackage(String)
    case invalidDate(String)
    case exerciseConflict(String)
    case missingSchedule(String)
    case ambiguousSchedule(String)
    case ambiguousStaleSession

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Notes 同步包版本不受支持。"
        case let .invalidPackage(message): return "Notes 同步包无效：\(message)"
        case let .invalidDate(value): return "Notes 同步包日期无法识别：\(value)"
        case let .exerciseConflict(name): return "动作 \(name) 与动作库身份冲突。"
        case let .missingSchedule(code): return "找不到要关联的训练日程：\(code)"
        case let .ambiguousSchedule(code): return "训练日程匹配不唯一：\(code)"
        case .ambiguousStaleSession: return "待放弃的旧训练匹配不唯一，未执行同步。"
        }
    }
}

@MainActor
enum ConfirmedNotesImportService {
    /// Version 3 is the approved wellness-only increment. Validate the entire
    /// package before the first insert so an ambiguous existing meal cannot
    /// leave an unrelated weight partially imported.
    static func previewPackage(_ data: Data, in context: ModelContext) throws -> ConfirmedNotesImportPreview {
        let package = try JSONDecoder().decode(ConfirmedNotesImportPackage.self, from: data)
        guard package.version == 3 else { throw ConfirmedNotesImportError.unsupportedVersion }
        guard !package.packageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              package.workouts.isEmpty, (package.jumpRopeEntries ?? []).isEmpty,
              (package.voidMealIDs ?? []).isEmpty, package.staleSession == nil else {
            throw ConfirmedNotesImportError.invalidPackage("v3 仅补入已确认体重与餐食，不修改训练、跳绳或撤销记录")
        }
        guard Set(package.bodyMeasurements.map(\.id)).count == package.bodyMeasurements.count,
              Set(package.meals.map(\.id)).count == package.meals.count,
              let zone = TimeZone(identifier: package.timeZoneIdentifier) else {
            throw ConfirmedNotesImportError.invalidPackage("重复ID或时区无效")
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let days = DateFormatter()
        days.calendar = formatter.calendar
        days.locale = formatter.locale
        days.timeZone = zone
        days.isLenient = false
        days.dateFormat = "yyyy-MM-dd"
        var skippedMeasurements: [UUID] = [], skippedMeals: [UUID] = []
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        var packageTimes = Set<String>(), packageMealKeys = Set<String>()
        for item in package.bodyMeasurements {
            guard item.weightJin.isFinite, (40...800).contains(item.weightJin),
                  let timestamp = formatter.date(from: item.recordedAt), formatter.string(from: timestamp) == item.recordedAt,
                  packageTimes.insert(item.recordedAt).inserted else {
                throw ConfirmedNotesImportError.invalidPackage("体重或测量时间无效/重复")
            }
            func sameWeight(_ measurement: BodyMeasurement) -> Bool {
                measurement.weightKg.map { abs($0 - item.weightJin / 2) < 0.0001 } ?? false
            }
            let sameID = measurements.filter { $0.id == item.id }
            guard sameID.count <= 1 else { throw ConfirmedNotesImportError.invalidPackage("体重ID重复") }
            if let existing = sameID.first {
                guard formatter.string(from: existing.date) == item.recordedAt, sameWeight(existing) else {
                    throw ConfirmedNotesImportError.invalidPackage("同ID体重内容已变化，未覆盖")
                }
                skippedMeasurements.append(item.id)
                continue
            }
            let sameTime = measurements.filter { formatter.string(from: $0.date) == item.recordedAt && $0.weightKg != nil }
            guard sameTime.count <= 1, sameTime.allSatisfy(sameWeight) else {
                throw ConfirmedNotesImportError.invalidPackage("\(item.recordedAt) 已有不同或多条体重，需先核对")
            }
            if !sameTime.isEmpty { skippedMeasurements.append(item.id) }
        }
        for item in package.meals {
            let key = "\(item.date)|\(item.mealType.rawValue)"
            guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let date = days.date(from: item.date), days.string(from: date) == item.date,
                  packageMealKeys.insert(key).inserted,
                  item.calories.map({ (0...20_000).contains($0) }) ?? true,
                  (item.calories == nil && item.estimationSource == nil)
                    || (item.calories != nil && item.estimationSource == "本人估算（Notes）") else {
                throw ConfirmedNotesImportError.invalidPackage("餐食日期、原文或本人估算来源无效/重复")
            }
            func matches(_ meal: MealEntry) -> Bool {
                guard meal.isActiveMeal, (meal.recordedLocalDay ?? days.string(from: meal.date)) == item.date,
                      meal.mealType == item.mealType, meal.name == item.name else { return false }
                // Existing owner values are preserved. A supplied estimate must
                // agree; never silently enrich or overwrite an existing record.
                if let calories = item.calories {
                    return meal.isCalorieKnown && meal.calories == calories
                }
                return true
            }
            let sameID = meals.filter { $0.id == item.id }
            guard sameID.count <= 1 else { throw ConfirmedNotesImportError.invalidPackage("餐食ID重复") }
            if let existing = sameID.first {
                guard matches(existing) else { throw ConfirmedNotesImportError.invalidPackage("同ID餐食内容已变化，未覆盖") }
                skippedMeals.append(item.id)
                continue
            }
            let sameSlot = meals.filter { $0.isActiveMeal && ($0.recordedLocalDay ?? days.string(from: $0.date)) == item.date && $0.mealType == item.mealType }
            guard sameSlot.count <= 1, sameSlot.allSatisfy(matches) else {
                throw ConfirmedNotesImportError.invalidPackage("\(item.date) \(item.mealType.title) 已有不同或多条记录，需先核对")
            }
            if !sameSlot.isEmpty { skippedMeals.append(item.id) }
        }
        return ConfirmedNotesImportPreview(packageID: package.packageID,
            importedBodyMeasurements: package.bodyMeasurements.count - skippedMeasurements.count,
            skippedBodyMeasurements: skippedMeasurements.count,
            importedMeals: package.meals.count - skippedMeals.count,
            skippedMeals: skippedMeals.count,
            ownerEstimatedMeals: package.meals.filter { $0.calories != nil }.count,
            skippedMeasurementIDs: skippedMeasurements, skippedMealIDs: skippedMeals)
    }

    static func importPackage(
        _ data: Data,
        into context: ModelContext
    ) throws -> ConfirmedNotesImportSummary {
        let package = try JSONDecoder().decode(ConfirmedNotesImportPackage.self, from: data)
        guard (1...5).contains(package.version) else { throw ConfirmedNotesImportError.unsupportedVersion }
        let wellnessPreview = package.version == 3 ? try previewPackage(data, in: context) : nil
        if package.version == 4 {
            guard package.workouts.isEmpty, package.bodyMeasurements.isEmpty, package.meals.isEmpty,
                  (package.voidMealIDs ?? []).isEmpty, package.staleSession == nil,
                  !(package.jumpRopeEntries ?? []).isEmpty else {
                throw ConfirmedNotesImportError.invalidPackage("v4 仅导入跳绳实际记录")
            }
        } else if package.version == 5 {
            guard package.workouts.count == 1, package.bodyMeasurements.isEmpty, package.meals.isEmpty,
                  (package.jumpRopeEntries ?? []).isEmpty, (package.voidMealIDs ?? []).isEmpty,
                  package.staleSession?.expectedSessionID != nil,
                  package.staleSession?.expectedScheduledWorkoutID != nil else {
                throw ConfirmedNotesImportError.invalidPackage("v5 需要一场训练及已确认的草稿和计划")
            }
        } else if (package.jumpRopeEntries ?? []).contains(where: { $0.totalSetCount != nil || $0.recordedTimeKnown != nil }) {
            throw ConfirmedNotesImportError.invalidPackage("跳绳组数或时间状态需要 v4 同步包")
        }
        if package.version < 5,
           package.staleSession?.expectedSessionID != nil || package.staleSession?.expectedScheduledWorkoutID != nil {
            throw ConfirmedNotesImportError.invalidPackage("指定草稿和计划需要 v5 同步包")
        }
        if package.version < 3, package.meals.contains(where: { $0.calories != nil || $0.estimationSource != nil }) {
            throw ConfirmedNotesImportError.invalidPackage("结构化本人估算需要v3同步包")
        }
        let packageID = package.packageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !packageID.isEmpty else {
            throw ConfirmedNotesImportError.invalidPackage("packageID 为空")
        }
        guard Set(package.workouts.map(\.id)).count == package.workouts.count,
              Set(package.bodyMeasurements.map(\.id)).count == package.bodyMeasurements.count,
              Set(package.meals.map(\.id)).count == package.meals.count,
              Set((package.jumpRopeEntries ?? []).map(\.id)).count == (package.jumpRopeEntries ?? []).count,
              Set(package.voidMealIDs ?? []).count == (package.voidMealIDs ?? []).count else {
            throw ConfirmedNotesImportError.invalidPackage("存在重复 ID")
        }
        guard package.workouts.allSatisfy({ workout in
            !workout.id.isEmpty && !workout.name.isEmpty && !workout.exercises.isEmpty
                && workout.exercises.allSatisfy { exercise in
                    !exercise.name.isEmpty && !exercise.sets.isEmpty
                        && exercise.sets.allSatisfy { $0.weight >= 0 && $0.reps > 0 }
                }
        }) else {
            throw ConfirmedNotesImportError.invalidPackage("训练、动作或组记录不完整")
        }

        guard let timeZone = TimeZone(identifier: package.timeZoneIdentifier) else {
            throw ConfirmedNotesImportError.invalidPackage("时区无效")
        }

        if package.version == 4 {
            return try importRopeRecords(package, timeZone: timeZone, in: context)
        }

        guard (package.jumpRopeEntries ?? []).allSatisfy({
            $0.count > 0 && JumpRopeDurationValidation.isValid(active: $0.activeDurationSeconds, elapsed: $0.elapsedDurationSeconds)
        }) else {
            throw ConfirmedNotesImportError.invalidPackage("跳绳次数或时长无效")
        }
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.calendar = dayFormatter.calendar
        dateTimeFormatter.locale = dayFormatter.locale
        dateTimeFormatter.timeZone = timeZone
        dateTimeFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        func day(_ value: String) throws -> Date {
            guard let result = dayFormatter.date(from: value) else {
                throw ConfirmedNotesImportError.invalidDate(value)
            }
            return result
        }
        func dateTime(_ value: String) throws -> Date {
            guard let result = dateTimeFormatter.date(from: value) else {
                throw ConfirmedNotesImportError.invalidDate(value)
            }
            return result
        }

        let existingSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let existingImportIDs = Set(existingSessions.map(\.importIdentifier).filter { !$0.isEmpty })
        var exercises = try context.fetch(FetchDescriptor<Exercise>())
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())
        let existingMeals = try context.fetch(FetchDescriptor<MealEntry>())
        let existingMealIDs = Set(existingMeals.map(\.id))
        guard Set(package.voidMealIDs ?? []).isSubset(of: existingMealIDs) else {
            throw ConfirmedNotesImportError.invalidPackage("要作废的餐食不存在")
        }

        var resolvedSchedules: [String: ScheduledWorkout] = [:]
        for workout in package.workouts where !existingImportIDs.contains(importIdentifier(packageID, workout.id)) {
            guard let code = workout.scheduleTemplateCode else { continue }
            let workoutDay = try day(workout.date)
            let matchingScheduleIDs = links
                .filter {
                    $0.templateCode == code
                        && FatLossCalendar.sameDay($0.originalDate, workoutDay)
                }
                .map(\.scheduledWorkoutID)
            let matches = schedules.filter {
                matchingScheduleIDs.contains($0.id)
            }
            guard !matches.isEmpty else { throw ConfirmedNotesImportError.missingSchedule(code) }
            guard matches.count == 1, let match = matches.first else {
                throw ConfirmedNotesImportError.ambiguousSchedule(code)
            }
            resolvedSchedules[workout.id] = match
        }

        let packageExercises = package.workouts.flatMap(\.exercises)
        for item in packageExercises {
            if let existing = exercises.first(where: {
                $0.name.caseInsensitiveCompare(item.name) == .orderedSame
            }) {
                guard ExerciseCatalogService.semanticallyCompatible(
                    existing,
                    muscleGroup: item.muscleGroup,
                    equipment: item.equipment,
                    volumeUnit: item.volumeUnit
                ) else {
                    throw ConfirmedNotesImportError.exerciseConflict(item.name)
                }
            }
        }

        if let stale = package.staleSession {
            let staleDay = try day(stale.plannedDate)
            let candidates = existingSessions.filter { session in
                session.status == .inProgress
                    && session.templateName == stale.templateName
                    && session.plannedDate.isSameDay(as: staleDay)
                    && !logs.contains { $0.sessionID == session.id && $0.isCompleted }
            }
            if candidates.count > 1 { throw ConfirmedNotesImportError.ambiguousStaleSession }
            if package.version == 5 {
                let matchingSessions = existingSessions.filter { $0.id == stale.expectedSessionID }
                let matchingSchedules = schedules.filter { $0.id == stale.expectedScheduledWorkoutID }
                guard matchingSessions.count == 1, matchingSchedules.count == 1,
                      let original = matchingSessions.first, let schedule = matchingSchedules.first,
                      original.scheduledWorkoutID == schedule.id, original.templateName == stale.templateName,
                      original.plannedDate.isSameDay(as: staleDay),
                      !logs.contains(where: { $0.sessionID == original.id && $0.isCompleted }),
                      let workout = package.workouts.first, workout.date == stale.plannedDate,
                      TrainingScheduleDate.localDay(schedule) == stale.plannedDate else {
                    throw ConfirmedNotesImportError.invalidPackage("确认的空草稿或计划已变化，未导入")
                }
                let workoutDay = try day(workout.date)
                let completed = existingSessions.filter {
                    $0.status == .completed && ($0.trainingLocalDay == workout.date ||
                        (($0.trainingLocalDay == nil || $0.trainingLocalDay?.isEmpty == true)
                            && $0.plannedDate.isSameDay(as: workoutDay)))
                }
                let identifier = importIdentifier(packageID, workout.id)
                let imported = existingSessions.filter { $0.importIdentifier == identifier }
                if imported.isEmpty {
                    guard candidates.count == 1, candidates.first?.id == original.id,
                          schedule.status == .inProgress, completed.isEmpty else {
                        throw ConfirmedNotesImportError.invalidPackage("确认的草稿、计划或当天实际已变化，未导入")
                    }
                } else {
                    guard imported.count == 1, imported.first?.status == .completed,
                          completed.count == 1, completed.first?.id == imported.first?.id,
                          original.status == .discarded, schedule.status == .planned else {
                        throw ConfirmedNotesImportError.invalidPackage("已导入记录或草稿状态已变化，未修改")
                    }
                }
            }
        }

        var summary = ConfirmedNotesImportSummary()

        if let stale = package.staleSession {
            let staleDay = try day(stale.plannedDate)
            let candidates = existingSessions.filter { session in
                session.status == .inProgress
                    && session.templateName == stale.templateName
                    && session.plannedDate.isSameDay(as: staleDay)
                    && !logs.contains { $0.sessionID == session.id && $0.isCompleted }
            }
            if let session = candidates.first {
                session.status = .discarded
                session.completedAt = .now
                session.restEndDate = nil
                if let scheduledWorkoutID = session.scheduledWorkoutID,
                   let schedule = schedules.first(where: { $0.id == scheduledWorkoutID }),
                   schedule.status == .inProgress {
                    schedule.status = .planned
                    schedule.updatedAt = .now
                }
                summary.discardedStaleSessions = 1
            }
        }

        for workout in package.workouts {
            let stableID = importIdentifier(packageID, workout.id)
            if let existing = existingSessions.first(where: { $0.importIdentifier == stableID }) {
                summary.skippedSessions += 1
                let workoutDay = try day(workout.date)
                let hasMissingLocalDay = existing.trainingLocalDay?.isEmpty != false
                let hasMissingTimeZone = existing.trainingTimeZoneIdentifier?.isEmpty != false
                if hasMissingLocalDay || hasMissingTimeZone {
                    if hasMissingLocalDay { existing.trainingLocalDay = workout.date }
                    if hasMissingTimeZone { existing.trainingTimeZoneIdentifier = package.timeZoneIdentifier }
                    if existing.startedAt == workoutDay {
                        existing.isStartTimeKnown = workout.startTimeKnown ?? false
                    }
                    summary.repairedSessionDateMetadata += 1
                }
                continue
            }

            var inputs: [HistoricalExerciseInput] = []
            for item in workout.exercises {
                let exercise: Exercise
                if let existing = exercises.first(where: {
                    $0.name.caseInsensitiveCompare(item.name) == .orderedSame
                }) {
                    exercise = existing
                } else {
                    let created = Exercise(
                        name: item.name,
                        muscleGroup: item.muscleGroup,
                        equipment: item.equipment,
                        defaultRestSeconds: 90,
                        isBuiltIn: false,
                        notes: item.notes,
                        volumeUnit: item.volumeUnit
                    )
                    ExerciseTerminologyService.stageCandidate(for: created)
                    context.insert(created)
                    exercises.append(created)
                    exercise = created
                    summary.createdExercises += 1
                }
                inputs.append(
                    HistoricalExerciseInput(
                        exerciseID: exercise.id,
                        sets: item.sets.map {
                            HistoricalSetInput(
                                weight: $0.weight,
                                reps: $0.reps,
                                rir: nil,
                                weightSide: $0.weightSide,
                                repsSide: $0.repsSide
                            )
                        },
                        performanceNotes: item.notes
                    )
                )
            }

            let workoutDay = try day(workout.date)
            _ = try HistoricalWorkoutService.record(
                HistoricalWorkoutInput(
                    name: workout.name,
                    startedAt: workoutDay,
                    durationMinutes: workout.durationMinutes,
                    notes: workout.notes,
                    exercises: inputs,
                    importIdentifier: stableID,
                    scheduledWorkoutID: resolvedSchedules[workout.id]?.id,
                    trainingLocalDay: workout.date,
                    trainingTimeZoneIdentifier: package.timeZoneIdentifier,
                    isStartTimeKnown: workout.startTimeKnown ?? false
                ),
                in: context
            )
            summary.importedSessions += 1
            summary.importedSessionExercises += workout.exercises.count
            summary.importedSets += workout.exercises.reduce(0) { $0 + $1.sets.count }
            if resolvedSchedules[workout.id] != nil { summary.linkedSchedules += 1 }
        }

        var measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        var measurementIDs = Set(measurements.map(\.id))
        for item in package.bodyMeasurements {
            guard !measurementIDs.contains(item.id), wellnessPreview?.skippedMeasurementIDs.contains(item.id) != true else {
                summary.skippedBodyMeasurements += 1
                continue
            }
            let measuredAt = try dateTime(item.recordedAt)
            let measurement = BodyMeasurement(
                id: item.id,
                date: measuredAt,
                weightKg: item.weightJin / 2,
                notes: item.notes,
                source: .manual,
                createdAt: measuredAt
            )
            context.insert(measurement)
            measurements.append(measurement)
            measurementIDs.insert(item.id)
            summary.importedBodyMeasurements += 1
        }

        var mealIDs = existingMealIDs
        for item in package.meals {
            guard !mealIDs.contains(item.id), wellnessPreview?.skippedMealIDs.contains(item.id) != true else {
                summary.skippedMeals += 1
                continue
            }
            let mealDate = try day(item.date)
            let meal = MealEntry(
                id: item.id,
                date: mealDate,
                mealType: item.mealType,
                name: item.name,
                calories: item.calories ?? 0,
                proteinGrams: 0,
                carbsGrams: 0,
                fatGrams: 0,
                createdAt: mealDate
            )
            meal.nutritionKnown = false
            meal.knownNutritionFieldsRaw = item.calories == nil ? "" : "calories"
            meal.estimationMethod = item.estimationSource ?? "Notes 原始记录；营养未核算"
            meal.recordedLocalDay = item.date
            meal.captureTimeZoneIdentifier = package.timeZoneIdentifier
            meal.recordedTimeKnown = false
            context.insert(meal)
            mealIDs.insert(item.id)
            summary.importedMeals += 1
        }

        var jumpRopeIDs = Set(try context.fetch(FetchDescriptor<JumpRopeEntry>()).map(\.id))
        for item in package.jumpRopeEntries ?? [] {
            guard !jumpRopeIDs.contains(item.id) else {
                summary.skippedJumpRopeEntries += 1
                continue
            }
            let jumpDate = try day(item.date)
            context.insert(JumpRopeEntry(
                id: item.id,
                count: item.count,
                activeDurationSeconds: item.activeDurationSeconds,
                elapsedDurationSeconds: item.elapsedDurationSeconds,
                date: jumpDate,
                createdAt: jumpDate
            ))
            jumpRopeIDs.insert(item.id)
            summary.importedJumpRopeEntries += 1
        }

        for id in package.voidMealIDs ?? [] {
            guard let meal = existingMeals.first(where: { $0.id == id }) else { continue }
            if meal.isVoided == true {
                summary.alreadyVoidedMeals += 1
            } else {
                meal.isVoided = true
                meal.updatedAt = .now
                summary.voidedMeals += 1
            }
        }

        try context.save()
        return summary
    }

    private static func importRopeRecords(_ package: ConfirmedNotesImportPackage, timeZone: TimeZone,
                                          in context: ModelContext) throws -> ConfirmedNotesImportSummary {
        let existing = Dictionary(grouping: try context.fetch(FetchDescriptor<JumpRopeEntry>()), by: \.id)
        var additions: [(ConfirmedNotesJumpRope, Date)] = []
        var summary = ConfirmedNotesImportSummary()
        for item in package.jumpRopeEntries ?? [] {
            guard item.recordedTimeKnown != true,
                  let anchor = TrainingLocalDate.date(item.date, timeZone: timeZone),
                  JumpRopeDurationValidation.isValidRecord(count: item.count,
                    active: item.activeDurationSeconds, elapsed: item.elapsedDurationSeconds),
                  JumpRopeDurationValidation.isValidMetadata(totalSetCount: item.totalSetCount,
                    localDay: item.date, timeZoneIdentifier: package.timeZoneIdentifier,
                    recordedTimeKnown: false, date: anchor) else {
                throw ConfirmedNotesImportError.invalidPackage("跳绳日期、次数、组数或时长无效")
            }
            let matches = existing[item.id] ?? []
            guard matches.count <= 1 else { throw ConfirmedNotesImportError.invalidPackage("跳绳 ID 不唯一") }
            if let record = matches.first {
                guard record.count == item.count, record.totalSetCount == item.totalSetCount,
                      record.activeDurationSeconds == item.activeDurationSeconds,
                      record.elapsedDurationSeconds == item.elapsedDurationSeconds,
                      record.durationSeconds == nil, record.recordedTimeKnown == false,
                      record.trainingLocalDay == item.date,
                      record.trainingTimeZoneIdentifier == package.timeZoneIdentifier,
                      record.scheduledWorkoutID == nil,
                      JumpRopeDurationValidation.isValidMetadata(totalSetCount: record.totalSetCount,
                        localDay: record.trainingLocalDay, timeZoneIdentifier: record.trainingTimeZoneIdentifier,
                        recordedTimeKnown: record.recordedTimeKnown, date: record.date) else {
                    throw ConfirmedNotesImportError.invalidPackage("同 ID 跳绳内容已变化，未覆盖")
                }
                summary.skippedJumpRopeEntries += 1
            } else {
                additions.append((item, anchor))
            }
        }
        guard !additions.isEmpty else { return summary }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        var inserted: [JumpRopeEntry] = []
        var committed = false
        defer {
            if !committed { inserted.forEach { context.delete($0) } }
            context.autosaveEnabled = previousAutosave
        }
        for (item, anchor) in additions {
            let entry = JumpRopeEntry(id: item.id, count: item.count,
                activeDurationSeconds: item.activeDurationSeconds, elapsedDurationSeconds: item.elapsedDurationSeconds,
                date: anchor, createdAt: .now)
            entry.totalSetCount = item.totalSetCount
            entry.recordedTimeKnown = false
            entry.trainingLocalDay = item.date
            entry.trainingTimeZoneIdentifier = package.timeZoneIdentifier
            context.insert(entry)
            inserted.append(entry)
        }
        try context.save()
        committed = true
        summary.importedJumpRopeEntries = additions.count
        return summary
    }

    private static func importIdentifier(_ packageID: String, _ workoutID: String) -> String {
        "confirmed-notes:\(packageID):\(workoutID)"
    }
}
