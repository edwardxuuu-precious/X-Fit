import Foundation
import SwiftData

struct HistoricalSetInput {
    let weight: Double
    let reps: Int
    let rir: Int?
    var startedAt: Date? = nil
    var restDurationSeconds: Int? = nil
}

struct HistoricalExerciseInput {
    let exerciseID: UUID
    let sets: [HistoricalSetInput]
    let performanceNotes: String
}

struct HistoricalWorkoutInput {
    let name: String
    let startedAt: Date
    let durationMinutes: Int
    let notes: String
    let exercises: [HistoricalExerciseInput]
    var importIdentifier: String = ""
}

enum HistoricalWorkoutServiceError: LocalizedError {
    case emptyName
    case emptyExercises
    case emptySets
    case missingExercise
    case duplicateRecord
    case invalidRestDuration

    var errorDescription: String? {
        switch self {
        case .emptyName: return "请填写训练名称。"
        case .emptyExercises: return "请至少添加一个动作。"
        case .emptySets: return "每个动作至少需要一组完成记录。"
        case .missingExercise: return "补录动作已不存在，请重新选择。"
        case .duplicateRecord: return "相同时间和名称的训练已经存在，请勿重复补录。"
        case .invalidRestDuration:
            return "组后休息必须在 0–\(RestDurationInput.maximumSeconds) 秒之间。"
        }
    }
}

@MainActor
enum HistoricalWorkoutService {
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
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        guard input.exercises.allSatisfy({ exerciseByID[$0.exerciseID] != nil }) else {
            throw HistoricalWorkoutServiceError.missingExercise
        }

        let completedAt = input.startedAt.addingTimeInterval(TimeInterval(max(1, input.durationMinutes) * 60))
        let session = WorkoutSession(
            templateName: trimmedName,
            plannedDate: input.startedAt,
            startedAt: input.startedAt,
            completedAt: completedAt,
            status: .completed,
            notes: input.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            importIdentifier: input.importIdentifier
        )
        context.insert(session)

        for (index, item) in input.exercises.enumerated() {
            guard let exercise = exerciseByID[item.exerciseID] else { continue }
            let reps = item.sets.map(\.reps)
            let weight = item.sets.map(\.weight).max() ?? 0
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
                performanceNotes: item.performanceNotes.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        actualWeight: max(0, set.weight),
                        actualReps: max(1, set.reps),
                        rir: set.rir,
                        isCompleted: true,
                        startedAt: set.startedAt,
                        completedAt: input.startedAt.addingTimeInterval(TimeInterval((setIndex + 1) * 60)),
                        restDurationSeconds: set.restDurationSeconds
                    )
                )
            }
        }

        try context.save()
        return session
    }
}
