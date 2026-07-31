import Foundation
import SwiftData

enum WorkoutServiceError: LocalizedError {
    case emptyTemplate
    case exerciseAlreadyAdded
    case noIncompleteSet
    case cannotRemoveStartedExercise
    case cannotRemoveLastExercise

    var errorDescription: String? {
        switch self {
        case .emptyTemplate:
            return "这个训练计划还没有动作，请先在计划页添加动作。"
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

@MainActor
enum WorkoutService {
    static func start(
        schedule: ScheduledWorkout,
        in context: ModelContext
    ) throws -> UUID {
        if let active = try activeSession(in: context) {
            return active.id
        }

        let templateID = schedule.templateID
        let descriptor = FetchDescriptor<TemplateExercise>(
            predicate: #Predicate { $0.templateID == templateID },
            sortBy: [SortDescriptor(\.order)]
        )
        let plannedExercises = try context.fetch(descriptor)
        guard !plannedExercises.isEmpty else { throw WorkoutServiceError.emptyTemplate }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let previousLogs = try context.fetch(FetchDescriptor<SetLog>())
            .filter(\.isCompleted)

        let session = WorkoutSession(
            scheduledWorkoutID: schedule.id,
            templateID: templateID,
            templateName: schedule.templateName,
            plannedDate: schedule.plannedDate
        )
        context.insert(session)

        for planned in plannedExercises {
            guard let exercise = exerciseByID[planned.exerciseID] else { continue }

            let previous = previousLogs
                .filter { $0.exerciseID == exercise.id }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                .first
            let startingWeight = previous?.actualWeight ?? planned.targetWeight
            let startingReps = previous?.actualReps ?? planned.minReps

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
                exerciseNotes: exercise.notes
            )
            context.insert(snapshot)

            for setNumber in 1...planned.targetSets {
                context.insert(
                    SetLog(
                        sessionID: session.id,
                        sessionExerciseID: snapshot.id,
                        exerciseID: exercise.id,
                        setNumber: setNumber,
                        targetWeight: planned.targetWeight,
                        targetReps: planned.minReps,
                        actualWeight: startingWeight,
                        actualReps: startingReps
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
        in context: ModelContext
    ) throws -> SessionExercise {
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
        let order = (snapshots.map(\.order).max() ?? -1) + 1

        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: order,
            targetSets: 3,
            minReps: 8,
            maxReps: 12,
            targetWeight: startingWeight,
            restSeconds: exercise.defaultRestSeconds,
            muscleGroup: exercise.muscleGroup,
            exerciseNotes: exercise.notes
        )
        context.insert(snapshot)

        for setNumber in 1...3 {
            context.insert(
                SetLog(
                    sessionID: session.id,
                    sessionExerciseID: snapshot.id,
                    exerciseID: exercise.id,
                    setNumber: setNumber,
                    targetWeight: startingWeight,
                    targetReps: startingReps,
                    actualWeight: startingWeight,
                    actualReps: startingReps
                )
            )
        }
        try context.save()
        return snapshot
    }

    @discardableResult
    static func addSet(
        to exercise: SessionExercise,
        in context: ModelContext
    ) throws -> SetLog {
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
            actualReps: previous?.actualReps ?? exercise.minReps
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
        session.status = .completed
        session.completedAt = .now
        session.restEndDate = nil

        if let scheduledID = session.scheduledWorkoutID,
           let schedule = schedules.first(where: { $0.id == scheduledID }) {
            schedule.status = .completed
        }
        try context.save()
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
