import Foundation
import SwiftData

enum WorkoutServiceError: LocalizedError {
    case emptyTemplate

    var errorDescription: String? {
        switch self {
        case .emptyTemplate:
            return "这个训练计划还没有动作，请先在计划页添加动作。"
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
