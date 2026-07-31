import Foundation
import SwiftData

struct BackupPreview {
    let exercises: Int
    let templates: Int
    let sessions: Int
    let meals: Int
    let bodyMeasurements: Int

    var total: Int { exercises + templates + sessions + meals + bodyMeasurements }
}

struct BackupImportSummary {
    let imported: Int
    let skipped: Int
}

private struct XFitBackup: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let exercises: [ExerciseRecord]
    let templates: [TemplateRecord]
    let templateExercises: [TemplateExerciseRecord]
    let schedules: [ScheduleRecord]
    let sessions: [SessionRecord]
    let sessionExercises: [SessionExerciseRecord]
    let setLogs: [SetLogRecord]
    let nutritionTargets: [NutritionTargetRecord]
    let meals: [MealRecord]
    let bodyMeasurements: [BodyMeasurementRecord]
}

private struct ExerciseRecord: Codable {
    let id: UUID
    let name: String
    let muscleGroup: String
    let equipment: String
    let defaultRestSeconds: Int
    let createdAt: Date
    let isBuiltIn: Bool
    let isArchived: Bool
    let notes: String
    let updatedAt: Date
}

private struct TemplateRecord: Codable {
    let id: UUID
    let name: String
    let weekday: Int
    let isActive: Bool
    let createdAt: Date
    let isOneOff: Bool?
    let plannedForDate: Date?
    let focusMuscleGroupsRaw: String?
}

private struct TemplateExerciseRecord: Codable {
    let id: UUID
    let templateID: UUID
    let exerciseID: UUID
    let order: Int
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let targetWeight: Double
    let restSeconds: Int
}

private struct ScheduleRecord: Codable {
    let id: UUID
    let templateID: UUID
    let templateName: String
    let plannedDate: Date
    let statusRaw: String
    let createdAt: Date
    let originalPlannedDate: Date?
    let isManuallyScheduled: Bool
    let skipReason: String
    let reminderDate: Date?
    let updatedAt: Date
}

private struct SessionRecord: Codable {
    let id: UUID
    let scheduledWorkoutID: UUID?
    let templateID: UUID?
    let templateName: String
    let plannedDate: Date
    let startedAt: Date
    let completedAt: Date?
    let statusRaw: String
    let notes: String
    let restEndDate: Date?
    let importIdentifier: String?
}

private struct SessionExerciseRecord: Codable {
    let id: UUID
    let sessionID: UUID
    let exerciseID: UUID
    let exerciseName: String
    let order: Int
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let targetWeight: Double
    let restSeconds: Int
    let muscleGroup: String?
    let exerciseNotes: String?
    let performanceNotes: String?
}

private struct SetLogRecord: Codable {
    let id: UUID
    let sessionID: UUID
    let sessionExerciseID: UUID
    let exerciseID: UUID
    let setNumber: Int
    let targetWeight: Double
    let targetReps: Int
    let actualWeight: Double
    let actualReps: Int
    let rir: Int?
    let isWarmup: Bool
    let isCompleted: Bool
    let completedAt: Date?
}

private struct NutritionTargetRecord: Codable {
    let id: UUID
    let calories: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int
    let updatedAt: Date
}

private struct MealRecord: Codable {
    let id: UUID
    let date: Date
    let mealTypeRaw: String
    let name: String
    let calories: Int
    let proteinGrams: Int
    let carbsGrams: Int
    let fatGrams: Int
    let createdAt: Date
    let updatedAt: Date
}

private struct BodyMeasurementRecord: Codable {
    let id: UUID
    let date: Date
    let weightKg: Double?
    let bodyFatPercent: Double?
    let waistCm: Double?
    let chestCm: Double?
    let armCm: Double?
    let notes: String
    let sourceRaw: String
    let createdAt: Date
    let updatedAt: Date
}

@MainActor
enum DataExportService {
    static func createBackup(in context: ModelContext) throws -> URL {
        let backup = try makeBackup(in: context)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try write(
            encoder.encode(backup),
            filename: "X-Fit-Backup-\(timestamp()).json"
        )
    }

    static func createCSV(in context: ModelContext) throws -> URL {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let exercises = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let exerciseByID = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0) })
        let formatter = ISO8601DateFormatter()

        var rows = ["session_id,date,workout,exercise,muscle_group,set,weight_kg,reps,rir,exercise_notes,workout_notes,completed"]
        for log in logs.sorted(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }) {
            guard let session = sessionByID[log.sessionID], let exercise = exerciseByID[log.sessionExerciseID] else { continue }
            rows.append([
                log.sessionID.uuidString,
                formatter.string(from: session.startedAt),
                csv(session.templateName),
                csv(exercise.exerciseName),
                csv(exercise.muscleGroup),
                String(log.setNumber),
                String(log.actualWeight),
                String(log.actualReps),
                log.rir.map(String.init) ?? "",
                csv(exercise.performanceNotes),
                csv(session.notes),
                log.isCompleted ? "true" : "false"
            ].joined(separator: ","))
        }

        return try write(
            Data(rows.joined(separator: "\n").utf8),
            filename: "X-Fit-Sets-\(timestamp()).csv"
        )
    }

    static func loadBackupData(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    static func preview(_ data: Data) throws -> BackupPreview {
        let backup = try decode(data)
        return BackupPreview(
            exercises: backup.exercises.count,
            templates: backup.templates.count,
            sessions: backup.sessions.count,
            meals: backup.meals.count,
            bodyMeasurements: backup.bodyMeasurements.count
        )
    }

    static func importBackup(_ data: Data, into context: ModelContext) throws -> BackupImportSummary {
        let backup = try decode(data)
        guard backup.schemaVersion <= 3 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "这个备份来自更高版本的 X-Fit，当前版本无法安全导入。"
            ])
        }

        var imported = 0
        var skipped = 0

        let exerciseIDs = Set(try context.fetch(FetchDescriptor<Exercise>()).map(\.id))
        for record in backup.exercises {
            guard !exerciseIDs.contains(record.id) else { skipped += 1; continue }
            let model = Exercise(
                id: record.id,
                name: record.name,
                muscleGroup: record.muscleGroup,
                equipment: record.equipment,
                defaultRestSeconds: record.defaultRestSeconds,
                createdAt: record.createdAt,
                isBuiltIn: record.isBuiltIn,
                isArchived: record.isArchived,
                notes: record.notes
            )
            model.updatedAt = record.updatedAt
            context.insert(model)
            imported += 1
        }

        let templateIDs = Set(try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.id))
        for record in backup.templates {
            guard !templateIDs.contains(record.id) else { skipped += 1; continue }
            context.insert(WorkoutTemplate(
                id: record.id,
                name: record.name,
                weekday: record.weekday,
                isActive: record.isActive,
                createdAt: record.createdAt,
                isOneOff: record.isOneOff ?? false,
                plannedForDate: record.plannedForDate,
                focusMuscleGroups: (record.focusMuscleGroupsRaw ?? "")
                    .split(separator: ",")
                    .map(String.init)
            ))
            imported += 1
        }

        let templateExerciseIDs = Set(try context.fetch(FetchDescriptor<TemplateExercise>()).map(\.id))
        for record in backup.templateExercises {
            guard !templateExerciseIDs.contains(record.id) else { skipped += 1; continue }
            context.insert(TemplateExercise(
                id: record.id,
                templateID: record.templateID,
                exerciseID: record.exerciseID,
                order: record.order,
                targetSets: record.targetSets,
                minReps: record.minReps,
                maxReps: record.maxReps,
                targetWeight: record.targetWeight,
                restSeconds: record.restSeconds
            ))
            imported += 1
        }

        let scheduleIDs = Set(try context.fetch(FetchDescriptor<ScheduledWorkout>()).map(\.id))
        for record in backup.schedules {
            guard !scheduleIDs.contains(record.id) else { skipped += 1; continue }
            let model = ScheduledWorkout(
                id: record.id,
                templateID: record.templateID,
                templateName: record.templateName,
                plannedDate: record.plannedDate,
                status: ScheduleStatus(rawValue: record.statusRaw) ?? .planned,
                createdAt: record.createdAt,
                originalPlannedDate: record.originalPlannedDate,
                isManuallyScheduled: record.isManuallyScheduled,
                skipReason: record.skipReason,
                reminderDate: record.reminderDate
            )
            model.updatedAt = record.updatedAt
            context.insert(model)
            imported += 1
        }

        let sessionIDs = Set(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id))
        for record in backup.sessions {
            guard !sessionIDs.contains(record.id) else { skipped += 1; continue }
            context.insert(WorkoutSession(
                id: record.id,
                scheduledWorkoutID: record.scheduledWorkoutID,
                templateID: record.templateID,
                templateName: record.templateName,
                plannedDate: record.plannedDate,
                startedAt: record.startedAt,
                completedAt: record.completedAt,
                status: WorkoutSessionStatus(rawValue: record.statusRaw) ?? .completed,
                notes: record.notes,
                restEndDate: record.restEndDate,
                importIdentifier: record.importIdentifier ?? ""
            ))
            imported += 1
        }

        let sessionExerciseIDs = Set(try context.fetch(FetchDescriptor<SessionExercise>()).map(\.id))
        for record in backup.sessionExercises {
            guard !sessionExerciseIDs.contains(record.id) else { skipped += 1; continue }
            context.insert(SessionExercise(
                id: record.id,
                sessionID: record.sessionID,
                exerciseID: record.exerciseID,
                exerciseName: record.exerciseName,
                order: record.order,
                targetSets: record.targetSets,
                minReps: record.minReps,
                maxReps: record.maxReps,
                targetWeight: record.targetWeight,
                restSeconds: record.restSeconds,
                muscleGroup: record.muscleGroup ?? "",
                exerciseNotes: record.exerciseNotes ?? "",
                performanceNotes: record.performanceNotes ?? ""
            ))
            imported += 1
        }

        let setLogIDs = Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id))
        for record in backup.setLogs {
            guard !setLogIDs.contains(record.id) else { skipped += 1; continue }
            context.insert(SetLog(
                id: record.id,
                sessionID: record.sessionID,
                sessionExerciseID: record.sessionExerciseID,
                exerciseID: record.exerciseID,
                setNumber: record.setNumber,
                targetWeight: record.targetWeight,
                targetReps: record.targetReps,
                actualWeight: record.actualWeight,
                actualReps: record.actualReps,
                rir: record.rir,
                isWarmup: record.isWarmup,
                isCompleted: record.isCompleted,
                completedAt: record.completedAt
            ))
            imported += 1
        }

        let existingTargets = try context.fetch(FetchDescriptor<NutritionTarget>())
        if existingTargets.isEmpty, let record = backup.nutritionTargets.first {
            context.insert(NutritionTarget(
                id: record.id,
                calories: record.calories,
                proteinGrams: record.proteinGrams,
                carbsGrams: record.carbsGrams,
                fatGrams: record.fatGrams,
                updatedAt: record.updatedAt
            ))
            imported += 1
            skipped += max(0, backup.nutritionTargets.count - 1)
        } else {
            skipped += backup.nutritionTargets.count
        }

        let mealIDs = Set(try context.fetch(FetchDescriptor<MealEntry>()).map(\.id))
        for record in backup.meals {
            guard !mealIDs.contains(record.id) else { skipped += 1; continue }
            let model = MealEntry(
                id: record.id,
                date: record.date,
                mealType: MealType(rawValue: record.mealTypeRaw) ?? .snack,
                name: record.name,
                calories: record.calories,
                proteinGrams: record.proteinGrams,
                carbsGrams: record.carbsGrams,
                fatGrams: record.fatGrams,
                createdAt: record.createdAt
            )
            model.updatedAt = record.updatedAt
            context.insert(model)
            imported += 1
        }

        let bodyIDs = Set(try context.fetch(FetchDescriptor<BodyMeasurement>()).map(\.id))
        for record in backup.bodyMeasurements {
            guard !bodyIDs.contains(record.id) else { skipped += 1; continue }
            let model = BodyMeasurement(
                id: record.id,
                date: record.date,
                weightKg: record.weightKg,
                bodyFatPercent: record.bodyFatPercent,
                waistCm: record.waistCm,
                chestCm: record.chestCm,
                armCm: record.armCm,
                notes: record.notes,
                source: BodyMeasurementSource(rawValue: record.sourceRaw) ?? .manual,
                createdAt: record.createdAt
            )
            model.updatedAt = record.updatedAt
            context.insert(model)
            imported += 1
        }

        try context.save()
        try ScheduleService.refreshUpcoming(in: context)
        try context.save()
        let refreshedSchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        Task {
            await NotificationService.syncWorkoutReminders(refreshedSchedules)
        }
        return BackupImportSummary(imported: imported, skipped: skipped)
    }

    private static func makeBackup(in context: ModelContext) throws -> XFitBackup {
        XFitBackup(
            schemaVersion: 3,
            exportedAt: .now,
            exercises: try context.fetch(FetchDescriptor<Exercise>()).map {
                ExerciseRecord(id: $0.id, name: $0.name, muscleGroup: $0.muscleGroup, equipment: $0.equipment, defaultRestSeconds: $0.defaultRestSeconds, createdAt: $0.createdAt, isBuiltIn: $0.isBuiltIn, isArchived: $0.isArchived, notes: $0.notes, updatedAt: $0.updatedAt)
            },
            templates: try context.fetch(FetchDescriptor<WorkoutTemplate>()).map {
                TemplateRecord(id: $0.id, name: $0.name, weekday: $0.weekday, isActive: $0.isActive, createdAt: $0.createdAt, isOneOff: $0.isOneOff, plannedForDate: $0.plannedForDate, focusMuscleGroupsRaw: $0.focusMuscleGroupsRaw)
            },
            templateExercises: try context.fetch(FetchDescriptor<TemplateExercise>()).map {
                TemplateExerciseRecord(id: $0.id, templateID: $0.templateID, exerciseID: $0.exerciseID, order: $0.order, targetSets: $0.targetSets, minReps: $0.minReps, maxReps: $0.maxReps, targetWeight: $0.targetWeight, restSeconds: $0.restSeconds)
            },
            schedules: try context.fetch(FetchDescriptor<ScheduledWorkout>()).map {
                ScheduleRecord(id: $0.id, templateID: $0.templateID, templateName: $0.templateName, plannedDate: $0.plannedDate, statusRaw: $0.statusRaw, createdAt: $0.createdAt, originalPlannedDate: $0.originalPlannedDate, isManuallyScheduled: $0.isManuallyScheduled, skipReason: $0.skipReason, reminderDate: $0.reminderDate, updatedAt: $0.updatedAt)
            },
            sessions: try context.fetch(FetchDescriptor<WorkoutSession>()).map {
                SessionRecord(id: $0.id, scheduledWorkoutID: $0.scheduledWorkoutID, templateID: $0.templateID, templateName: $0.templateName, plannedDate: $0.plannedDate, startedAt: $0.startedAt, completedAt: $0.completedAt, statusRaw: $0.statusRaw, notes: $0.notes, restEndDate: $0.restEndDate, importIdentifier: $0.importIdentifier)
            },
            sessionExercises: try context.fetch(FetchDescriptor<SessionExercise>()).map {
                SessionExerciseRecord(id: $0.id, sessionID: $0.sessionID, exerciseID: $0.exerciseID, exerciseName: $0.exerciseName, order: $0.order, targetSets: $0.targetSets, minReps: $0.minReps, maxReps: $0.maxReps, targetWeight: $0.targetWeight, restSeconds: $0.restSeconds, muscleGroup: $0.muscleGroup, exerciseNotes: $0.exerciseNotes, performanceNotes: $0.performanceNotes)
            },
            setLogs: try context.fetch(FetchDescriptor<SetLog>()).map {
                SetLogRecord(id: $0.id, sessionID: $0.sessionID, sessionExerciseID: $0.sessionExerciseID, exerciseID: $0.exerciseID, setNumber: $0.setNumber, targetWeight: $0.targetWeight, targetReps: $0.targetReps, actualWeight: $0.actualWeight, actualReps: $0.actualReps, rir: $0.rir, isWarmup: $0.isWarmup, isCompleted: $0.isCompleted, completedAt: $0.completedAt)
            },
            nutritionTargets: try context.fetch(FetchDescriptor<NutritionTarget>()).map {
                NutritionTargetRecord(id: $0.id, calories: $0.calories, proteinGrams: $0.proteinGrams, carbsGrams: $0.carbsGrams, fatGrams: $0.fatGrams, updatedAt: $0.updatedAt)
            },
            meals: try context.fetch(FetchDescriptor<MealEntry>()).map {
                MealRecord(id: $0.id, date: $0.date, mealTypeRaw: $0.mealTypeRaw, name: $0.name, calories: $0.calories, proteinGrams: $0.proteinGrams, carbsGrams: $0.carbsGrams, fatGrams: $0.fatGrams, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            bodyMeasurements: try context.fetch(FetchDescriptor<BodyMeasurement>()).map {
                BodyMeasurementRecord(id: $0.id, date: $0.date, weightKg: $0.weightKg, bodyFatPercent: $0.bodyFatPercent, waistCm: $0.waistCm, chestCm: $0.chestCm, armCm: $0.armCm, notes: $0.notes, sourceRaw: $0.sourceRaw, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            }
        )
    }

    private static func decode(_ data: Data) throws -> XFitBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(XFitBackup.self, from: data)
    }

    private static func write(_ data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("X-Fit Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }

    private static func csv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
