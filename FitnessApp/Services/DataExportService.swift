import Foundation
import SwiftData

struct BackupPreview {
    let exercises: Int
    let templates: Int
    let sessions: Int
    let meals: Int
    let bodyCheckIns: Int
    let bodyMeasurements: Int
    let hydrationEntries: Int
    let jumpRopeEntries: Int
    let sedentarySessions: Int
    let fatLossRecords: Int

    var total: Int {
        exercises + templates + sessions + meals + bodyCheckIns + bodyMeasurements
            + hydrationEntries + jumpRopeEntries + sedentarySessions + fatLossRecords
    }
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
    /// Optional so backups created before daily body check-ins still decode.
    let bodyCheckIns: [DailyBodyCheckInRecord]?
    let bodyMeasurements: [BodyMeasurementRecord]
    /// Optional so backups created before the tools hub still decode.
    let hydrationEntries: [HydrationRecord]?
    let jumpRopeEntries: [JumpRopeRecord]?
    let sedentarySessions: [SedentaryRecord]?
    let fatLoss: FatLossBackup?
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
    let referenceURL: String?
    let volumeUnitRaw: String?
    let terminologyCanonicalID: String?
    let terminologyStandardNameZH: String?
    let terminologyStandardNameEN: String?
    let terminologyReviewStatusRaw: String?
    let terminologyDecisionRaw: String?
    let terminologyConfidenceRaw: String?
    let terminologyMergeGroup: String?
    let terminologyReviewNote: String?
    let terminologyCatalogVersion: String?
    let terminologyReviewedAt: Date?
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
    let defaultPlanPatternRaw: String?
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
    let plannedSetsJSON: String?
    let planPatternRaw: String?
    let patternSourceRaw: String?
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
    let restModeRaw: String?
    let importIdentifier: String?
    let defaultPlanPatternRaw: String?
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
    let referenceURL: String?
    let volumeUnitRaw: String?
    let performanceNotes: String?
    let feelingRaw: String?
    let plannedSetsJSON: String?
    let planPatternRaw: String?
    let patternSourceRaw: String?
    let exerciseStartedAt: Date?
    let exerciseCompletedAt: Date?
    let bodyWeightKgSnapshot: Double?
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
    let startedAt: Date?
    let completedAt: Date?
    let restStartedAt: Date?
    let restEndedAt: Date?
    let restDurationSeconds: Int?
    let targetWeightSideRaw: String?
    let targetRepsSideRaw: String?
    let actualWeightSideRaw: String?
    let actualRepsSideRaw: String?
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
    let programID: UUID?
    let plannedMealID: UUID?
    let recipeSnapshotJSON: String?
    let actualPortions: Double?
    let nutritionKnown: Bool?
    let knownNutritionFieldsRaw: String?
    let estimationMethod: String?
    let isVoided: Bool?
    let tasteRating: Int?
    let preparationDifficulty: Int?
    let bloatingScore: Int?
    let feedbackNotes: String?
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

private struct DailyBodyCheckInRecord: Codable {
    let id: UUID
    let date: Date
    let conditionScore: Int
    let discomfortNotes: String
    let bodyMarkersJSON: String?
    let createdAt: Date
    let updatedAt: Date
}

private struct HydrationRecord: Codable {
    let id: UUID
    let milliliters: Int
    let date: Date
    let createdAt: Date
}

private struct JumpRopeRecord: Codable {
    let id: UUID
    let count: Int
    let durationSeconds: Int?
    let activeDurationSeconds: Int?
    let elapsedDurationSeconds: Int?
    let date: Date
    let createdAt: Date
}

private struct SedentaryRecord: Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let createdAt: Date
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

        var rows = ["session_id,date,workout,exercise,muscle_group,set,weight_kg,volume_unit,reps,rir,set_started_at,set_completed_at,rest_seconds,rest_started_at,rest_ended_at,rest_mode,exercise_reference_url,exercise_notes,workout_notes,completed"]
        for log in logs.sorted(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }) {
            guard let session = sessionByID[log.sessionID], let exercise = exerciseByID[log.sessionExerciseID] else { continue }
            let startedAt = log.startedAt.map { formatter.string(from: $0) } ?? ""
            let completedAt = log.completedAt.map { formatter.string(from: $0) } ?? ""
            let restDuration = log.restDurationSeconds.map(String.init) ?? ""
            let restStartedAt = log.restStartedAt.map { formatter.string(from: $0) } ?? ""
            let restEndedAt = log.restEndedAt.map { formatter.string(from: $0) } ?? ""
            let row: [String] = [
                log.sessionID.uuidString,
                formatter.string(from: session.startedAt),
                csv(session.templateName),
                csv(exercise.exerciseName),
                csv(exercise.muscleGroup),
                String(log.setNumber),
                String(log.actualWeight),
                exercise.volumeUnit.rawValue,
                String(log.actualReps),
                log.rir.map(String.init) ?? "",
                startedAt,
                completedAt,
                restDuration,
                restStartedAt,
                restEndedAt,
                session.restMode.rawValue,
                csv(exercise.referenceURL),
                csv(exercise.performanceNotes),
                csv(session.notes),
                log.isCompleted ? "true" : "false"
            ]
            rows.append(row.joined(separator: ","))
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
            bodyCheckIns: backup.bodyCheckIns?.count ?? 0,
            bodyMeasurements: backup.bodyMeasurements.count,
            hydrationEntries: backup.hydrationEntries?.count ?? 0,
            jumpRopeEntries: backup.jumpRopeEntries?.count ?? 0,
            sedentarySessions: backup.sedentarySessions?.count ?? 0,
            fatLossRecords: backup.fatLoss?.total ?? 0
        )
    }

    static func importBackup(_ data: Data, into context: ModelContext) throws -> BackupImportSummary {
        let backup = try decode(data)
        guard backup.schemaVersion <= 13 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "这个备份来自更高版本的 X-Fit，当前版本无法安全导入。"
            ])
        }
        try validateUniqueIdentifiers(in: backup)
        try validateRestIntervals(in: backup)
        try validateWellnessRecords(in: backup)
        try FatLossBackupService.validate(backup.fatLoss, in: context)
        try validateProgramReferences(in: backup, context: context)

        var imported = 0
        var skipped = 0

        var exerciseIDs = Set(try context.fetch(FetchDescriptor<Exercise>()).map(\.id))
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
                notes: record.notes,
                referenceURL: record.referenceURL ?? "",
                volumeUnit: record.volumeUnitRaw.flatMap(ExerciseVolumeUnit.init(rawValue:)) ?? .kilogram,
                terminologyCanonicalID: record.terminologyCanonicalID,
                terminologyStandardNameZH: record.terminologyStandardNameZH,
                terminologyStandardNameEN: record.terminologyStandardNameEN,
                terminologyReviewStatus: record.terminologyReviewStatusRaw.flatMap(ExerciseTerminologyReviewStatus.init(rawValue:)),
                terminologyDecision: record.terminologyDecisionRaw.flatMap(ExerciseTerminologyDecision.init(rawValue:)) ?? .pending,
                terminologyConfidence: record.terminologyConfidenceRaw.flatMap(ExerciseTerminologyConfidence.init(rawValue:)),
                terminologyMergeGroup: record.terminologyMergeGroup,
                terminologyReviewNote: record.terminologyReviewNote,
                terminologyCatalogVersion: record.terminologyCatalogVersion,
                terminologyReviewedAt: record.terminologyReviewedAt
            )
            model.updatedAt = record.updatedAt
            context.insert(model)
            exerciseIDs.insert(record.id)
            imported += 1
        }

        var templateIDs = Set(try context.fetch(FetchDescriptor<WorkoutTemplate>()).map(\.id))
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
                    .map(String.init),
                defaultPlanPattern: record.defaultPlanPatternRaw.flatMap(SetPlanPattern.init(rawValue:))
            ))
            templateIDs.insert(record.id)
            imported += 1
        }

        var templateExerciseIDs = Set(try context.fetch(FetchDescriptor<TemplateExercise>()).map(\.id))
        for record in backup.templateExercises {
            guard !templateExerciseIDs.contains(record.id) else { skipped += 1; continue }
            let model = TemplateExercise(
                id: record.id,
                templateID: record.templateID,
                exerciseID: record.exerciseID,
                order: record.order,
                targetSets: record.targetSets,
                minReps: record.minReps,
                maxReps: record.maxReps,
                targetWeight: record.targetWeight,
                restSeconds: record.restSeconds
            )
            if let plannedSetsJSON = record.plannedSetsJSON {
                model.plannedSetsJSON = plannedSetsJSON
            }
            if let planPatternRaw = record.planPatternRaw {
                model.planPatternRaw = planPatternRaw
            }
            model.patternSourceRaw = record.patternSourceRaw
            context.insert(model)
            templateExerciseIDs.insert(record.id)
            imported += 1
        }

        var scheduleIDs = Set(try context.fetch(FetchDescriptor<ScheduledWorkout>()).map(\.id))
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
            scheduleIDs.insert(record.id)
            imported += 1
        }

        var sessionIDs = Set(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id))
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
                restMode: record.restModeRaw.flatMap(WorkoutRestMode.init(rawValue:)) ?? .countdown,
                importIdentifier: record.importIdentifier ?? "",
                defaultPlanPattern: record.defaultPlanPatternRaw.flatMap(SetPlanPattern.init(rawValue:))
            ))
            sessionIDs.insert(record.id)
            imported += 1
        }

        var sessionExerciseIDs = Set(try context.fetch(FetchDescriptor<SessionExercise>()).map(\.id))
        for record in backup.sessionExercises {
            guard !sessionExerciseIDs.contains(record.id) else { skipped += 1; continue }
            let model = SessionExercise(
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
                referenceURL: record.referenceURL ?? "",
                volumeUnit: record.volumeUnitRaw.flatMap(ExerciseVolumeUnit.init(rawValue:)) ?? .kilogram,
                performanceNotes: record.performanceNotes ?? "",
                feeling: record.feelingRaw.flatMap(WorkoutFeeling.init(rawValue:)),
                exerciseStartedAt: record.exerciseStartedAt,
                exerciseCompletedAt: record.exerciseCompletedAt,
                bodyWeightKgSnapshot: record.bodyWeightKgSnapshot
            )
            if let plannedSetsJSON = record.plannedSetsJSON {
                model.plannedSetsJSON = plannedSetsJSON
            }
            if let planPatternRaw = record.planPatternRaw {
                model.planPatternRaw = planPatternRaw
            }
            model.patternSourceRaw = record.patternSourceRaw
            context.insert(model)
            sessionExerciseIDs.insert(record.id)
            imported += 1
        }

        var setLogIDs = Set(try context.fetch(FetchDescriptor<SetLog>()).map(\.id))
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
                startedAt: record.startedAt,
                completedAt: record.completedAt,
                restStartedAt: record.restStartedAt,
                restEndedAt: record.restEndedAt,
                restDurationSeconds: record.restDurationSeconds,
                targetWeightSide: record.targetWeightSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? .bilateral,
                targetRepsSide: record.targetRepsSideRaw.flatMap(MeasurementSide.init(rawValue:)) ?? .bilateral,
                actualWeightSide: record.actualWeightSideRaw.flatMap(MeasurementSide.init(rawValue:)),
                actualRepsSide: record.actualRepsSideRaw.flatMap(MeasurementSide.init(rawValue:))
            ))
            setLogIDs.insert(record.id)
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

        var mealIDs = Set(try context.fetch(FetchDescriptor<MealEntry>()).map(\.id))
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
            model.programID = record.programID
            model.plannedMealID = record.plannedMealID
            model.recipeSnapshotJSON = record.recipeSnapshotJSON
            model.actualPortions = record.actualPortions
            model.nutritionKnown = record.nutritionKnown
            model.knownNutritionFieldsRaw = record.knownNutritionFieldsRaw
            model.estimationMethod = record.estimationMethod
            model.isVoided = record.isVoided
            model.tasteRating = record.tasteRating
            model.preparationDifficulty = record.preparationDifficulty
            model.bloatingScore = record.bloatingScore
            model.feedbackNotes = record.feedbackNotes
            context.insert(model)
            mealIDs.insert(record.id)
            imported += 1
        }

        let existingBodyCheckIns = try context.fetch(FetchDescriptor<DailyBodyCheckIn>())
        var bodyCheckInIDs = Set(existingBodyCheckIns.map(\.id))
        var bodyCheckInDates = Set(existingBodyCheckIns.map { $0.date.startOfDay })
        for record in backup.bodyCheckIns ?? [] {
            guard !bodyCheckInIDs.contains(record.id) else { skipped += 1; continue }
            let normalizedDate = record.date.startOfDay
            guard !bodyCheckInDates.contains(normalizedDate) else { skipped += 1; continue }
            let model = DailyBodyCheckIn(
                id: record.id,
                date: normalizedDate,
                conditionScore: record.conditionScore,
                discomfortNotes: record.discomfortNotes,
                createdAt: record.createdAt
            )
            model.bodyMarkersJSON = record.bodyMarkersJSON
            model.updatedAt = record.updatedAt
            context.insert(model)
            bodyCheckInIDs.insert(record.id)
            bodyCheckInDates.insert(normalizedDate)
            imported += 1
        }

        var bodyIDs = Set(try context.fetch(FetchDescriptor<BodyMeasurement>()).map(\.id))
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
            bodyIDs.insert(record.id)
            imported += 1
        }

        var hydrationIDs = Set(try context.fetch(FetchDescriptor<HydrationEntry>()).map(\.id))
        for record in backup.hydrationEntries ?? [] {
            guard !hydrationIDs.contains(record.id) else { skipped += 1; continue }
            guard (1...5_000).contains(record.milliliters) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [
                    NSLocalizedDescriptionKey: "备份包含无效的饮水记录，已停止导入。"
                ])
            }
            context.insert(HydrationEntry(
                id: record.id,
                milliliters: record.milliliters,
                date: record.date,
                createdAt: record.createdAt
            ))
            hydrationIDs.insert(record.id)
            imported += 1
        }

        var jumpRopeIDs = Set(try context.fetch(FetchDescriptor<JumpRopeEntry>()).map(\.id))
        for record in backup.jumpRopeEntries ?? [] {
            guard !jumpRopeIDs.contains(record.id) else { skipped += 1; continue }
            guard (1...100_000).contains(record.count),
                  record.durationSeconds.map({ (1...86_400).contains($0) }) ?? true else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [
                    NSLocalizedDescriptionKey: "备份包含无效的跳绳记录，已停止导入。"
                ])
            }
            context.insert(JumpRopeEntry(
                id: record.id,
                count: record.count,
                durationSeconds: record.durationSeconds,
                activeDurationSeconds: record.activeDurationSeconds,
                elapsedDurationSeconds: record.elapsedDurationSeconds,
                date: record.date,
                createdAt: record.createdAt
            ))
            jumpRopeIDs.insert(record.id)
            imported += 1
        }

        var sedentaryIDs = Set(try context.fetch(FetchDescriptor<SedentarySession>()).map(\.id))
        for record in backup.sedentarySessions ?? [] {
            guard !sedentaryIDs.contains(record.id) else { skipped += 1; continue }
            guard record.endedAt.map({ $0 > record.startedAt }) ?? true else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [
                    NSLocalizedDescriptionKey: "备份包含结束时间早于开始时间的久坐记录，已停止导入。"
                ])
            }
            context.insert(SedentarySession(
                id: record.id,
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                createdAt: record.createdAt
            ))
            sedentaryIDs.insert(record.id)
            imported += 1
        }

        let fatLossResult = try FatLossBackupService.restore(backup.fatLoss, in: context)
        imported += fatLossResult.imported
        skipped += fatLossResult.skipped
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
            schemaVersion: 13,
            exportedAt: .now,
            exercises: try context.fetch(FetchDescriptor<Exercise>()).map {
                ExerciseRecord(
                    id: $0.id,
                    name: $0.name,
                    muscleGroup: $0.muscleGroup,
                    equipment: $0.equipment,
                    defaultRestSeconds: $0.defaultRestSeconds,
                    createdAt: $0.createdAt,
                    isBuiltIn: $0.isBuiltIn,
                    isArchived: $0.isArchived,
                    notes: $0.notes,
                    referenceURL: $0.referenceURL,
                    volumeUnitRaw: $0.volumeUnitRaw,
                    terminologyCanonicalID: $0.terminologyCanonicalID,
                    terminologyStandardNameZH: $0.terminologyStandardNameZH,
                    terminologyStandardNameEN: $0.terminologyStandardNameEN,
                    terminologyReviewStatusRaw: $0.terminologyReviewStatusRaw,
                    terminologyDecisionRaw: $0.terminologyDecisionRaw,
                    terminologyConfidenceRaw: $0.terminologyConfidenceRaw,
                    terminologyMergeGroup: $0.terminologyMergeGroup,
                    terminologyReviewNote: $0.terminologyReviewNote,
                    terminologyCatalogVersion: $0.terminologyCatalogVersion,
                    terminologyReviewedAt: $0.terminologyReviewedAt,
                    updatedAt: $0.updatedAt
                )
            },
            templates: try context.fetch(FetchDescriptor<WorkoutTemplate>()).map {
                TemplateRecord(id: $0.id, name: $0.name, weekday: $0.weekday, isActive: $0.isActive, createdAt: $0.createdAt, isOneOff: $0.isOneOff, plannedForDate: $0.plannedForDate, focusMuscleGroupsRaw: $0.focusMuscleGroupsRaw, defaultPlanPatternRaw: $0.defaultPlanPatternRaw)
            },
            templateExercises: try context.fetch(FetchDescriptor<TemplateExercise>()).map {
                TemplateExerciseRecord(id: $0.id, templateID: $0.templateID, exerciseID: $0.exerciseID, order: $0.order, targetSets: $0.targetSets, minReps: $0.minReps, maxReps: $0.maxReps, targetWeight: $0.targetWeight, restSeconds: $0.restSeconds, plannedSetsJSON: $0.plannedSetsJSON, planPatternRaw: $0.planPatternRaw, patternSourceRaw: $0.patternSourceRaw)
            },
            schedules: try context.fetch(FetchDescriptor<ScheduledWorkout>()).map {
                ScheduleRecord(id: $0.id, templateID: $0.templateID, templateName: $0.templateName, plannedDate: $0.plannedDate, statusRaw: $0.statusRaw, createdAt: $0.createdAt, originalPlannedDate: $0.originalPlannedDate, isManuallyScheduled: $0.isManuallyScheduled, skipReason: $0.skipReason, reminderDate: $0.reminderDate, updatedAt: $0.updatedAt)
            },
            sessions: try context.fetch(FetchDescriptor<WorkoutSession>()).map {
                SessionRecord(id: $0.id, scheduledWorkoutID: $0.scheduledWorkoutID, templateID: $0.templateID, templateName: $0.templateName, plannedDate: $0.plannedDate, startedAt: $0.startedAt, completedAt: $0.completedAt, statusRaw: $0.statusRaw, notes: $0.notes, restEndDate: $0.restEndDate, restModeRaw: $0.restModeRaw, importIdentifier: $0.importIdentifier, defaultPlanPatternRaw: $0.defaultPlanPatternRaw)
            },
            sessionExercises: try context.fetch(FetchDescriptor<SessionExercise>()).map {
                SessionExerciseRecord(id: $0.id, sessionID: $0.sessionID, exerciseID: $0.exerciseID, exerciseName: $0.exerciseName, order: $0.order, targetSets: $0.targetSets, minReps: $0.minReps, maxReps: $0.maxReps, targetWeight: $0.targetWeight, restSeconds: $0.restSeconds, muscleGroup: $0.muscleGroup, exerciseNotes: $0.exerciseNotes, referenceURL: $0.referenceURL, volumeUnitRaw: $0.volumeUnitRaw, performanceNotes: $0.performanceNotes, feelingRaw: $0.feelingRaw, plannedSetsJSON: $0.plannedSetsJSON, planPatternRaw: $0.planPatternRaw, patternSourceRaw: $0.patternSourceRaw, exerciseStartedAt: $0.exerciseStartedAt, exerciseCompletedAt: $0.exerciseCompletedAt, bodyWeightKgSnapshot: $0.bodyWeightKgSnapshot)
            },
            setLogs: try context.fetch(FetchDescriptor<SetLog>()).map {
                SetLogRecord(id: $0.id, sessionID: $0.sessionID, sessionExerciseID: $0.sessionExerciseID, exerciseID: $0.exerciseID, setNumber: $0.setNumber, targetWeight: $0.targetWeight, targetReps: $0.targetReps, actualWeight: $0.actualWeight, actualReps: $0.actualReps, rir: $0.rir, isWarmup: $0.isWarmup, isCompleted: $0.isCompleted, startedAt: $0.startedAt, completedAt: $0.completedAt, restStartedAt: $0.restStartedAt, restEndedAt: $0.restEndedAt, restDurationSeconds: $0.restDurationSeconds, targetWeightSideRaw: $0.targetWeightSideRaw, targetRepsSideRaw: $0.targetRepsSideRaw, actualWeightSideRaw: $0.actualWeightSideRaw, actualRepsSideRaw: $0.actualRepsSideRaw)
            },
            nutritionTargets: try context.fetch(FetchDescriptor<NutritionTarget>()).map {
                NutritionTargetRecord(id: $0.id, calories: $0.calories, proteinGrams: $0.proteinGrams, carbsGrams: $0.carbsGrams, fatGrams: $0.fatGrams, updatedAt: $0.updatedAt)
            },
            meals: try context.fetch(FetchDescriptor<MealEntry>()).map {
                MealRecord(id: $0.id, date: $0.date, mealTypeRaw: $0.mealTypeRaw, name: $0.name, calories: $0.calories, proteinGrams: $0.proteinGrams, carbsGrams: $0.carbsGrams, fatGrams: $0.fatGrams, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                           programID: $0.programID, plannedMealID: $0.plannedMealID,
                           recipeSnapshotJSON: $0.recipeSnapshotJSON, actualPortions: $0.actualPortions,
                           nutritionKnown: $0.nutritionKnown, knownNutritionFieldsRaw: $0.knownNutritionFieldsRaw, estimationMethod: $0.estimationMethod,
                           isVoided: $0.isVoided, tasteRating: $0.tasteRating,
                           preparationDifficulty: $0.preparationDifficulty, bloatingScore: $0.bloatingScore,
                           feedbackNotes: $0.feedbackNotes)
            },
            bodyCheckIns: try context.fetch(FetchDescriptor<DailyBodyCheckIn>()).map {
                DailyBodyCheckInRecord(id: $0.id, date: $0.date, conditionScore: $0.conditionScore, discomfortNotes: $0.discomfortNotes, bodyMarkersJSON: $0.bodyMarkersJSON, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            bodyMeasurements: try context.fetch(FetchDescriptor<BodyMeasurement>()).map {
                BodyMeasurementRecord(id: $0.id, date: $0.date, weightKg: $0.weightKg, bodyFatPercent: $0.bodyFatPercent, waistCm: $0.waistCm, chestCm: $0.chestCm, armCm: $0.armCm, notes: $0.notes, sourceRaw: $0.sourceRaw, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            hydrationEntries: try context.fetch(FetchDescriptor<HydrationEntry>()).map {
                HydrationRecord(id: $0.id, milliliters: $0.milliliters, date: $0.date, createdAt: $0.createdAt)
            },
            jumpRopeEntries: try context.fetch(FetchDescriptor<JumpRopeEntry>()).map {
                JumpRopeRecord(id: $0.id, count: $0.count, durationSeconds: $0.durationSeconds, activeDurationSeconds: $0.activeDurationSeconds, elapsedDurationSeconds: $0.elapsedDurationSeconds, date: $0.date, createdAt: $0.createdAt)
            },
            sedentarySessions: try context.fetch(FetchDescriptor<SedentarySession>()).map {
                SedentaryRecord(id: $0.id, startedAt: $0.startedAt, endedAt: $0.endedAt, createdAt: $0.createdAt)
            },
            fatLoss: try FatLossBackupService.export(in: context)
        )
    }

    private static func decode(_ data: Data) throws -> XFitBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(XFitBackup.self, from: data)
    }

    private static func validateUniqueIdentifiers(in backup: XFitBackup) throws {
        let groups: [(String, [UUID])] = [
            ("Exercise", backup.exercises.map(\.id)),
            ("WorkoutTemplate", backup.templates.map(\.id)),
            ("TemplateExercise", backup.templateExercises.map(\.id)),
            ("ScheduledWorkout", backup.schedules.map(\.id)),
            ("WorkoutSession", backup.sessions.map(\.id)),
            ("SessionExercise", backup.sessionExercises.map(\.id)),
            ("SetLog", backup.setLogs.map(\.id)),
            ("NutritionTarget", backup.nutritionTargets.map(\.id)),
            ("MealEntry", backup.meals.map(\.id)),
            ("DailyBodyCheckIn", (backup.bodyCheckIns ?? []).map(\.id)),
            ("BodyMeasurement", backup.bodyMeasurements.map(\.id)),
            ("HydrationEntry", (backup.hydrationEntries ?? []).map(\.id)),
            ("JumpRopeEntry", (backup.jumpRopeEntries ?? []).map(\.id)),
            ("SedentarySession", (backup.sedentarySessions ?? []).map(\.id))
        ]
        guard let duplicateGroup = groups.first(where: { Set($0.1).count != $0.1.count })?.0 else {
            return
        }
        throw CocoaError(.fileReadCorruptFile, userInfo: [
            NSLocalizedDescriptionKey: "备份包含重复的 \(duplicateGroup) 标识，已停止导入。"
        ])
    }

    private static func validateWellnessRecords(in backup: XFitBackup) throws {
        for meal in backup.meals {
            if let raw = meal.knownNutritionFieldsRaw {
                let fields = raw.isEmpty ? [] : raw.components(separatedBy: ",")
                guard Set(fields).count == fields.count,
                      fields.allSatisfy({ ["calories", "protein", "carbs", "fat"].contains($0) }) else {
                    throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "备份包含无效的已知营养字段。"])
                }
            }
            guard meal.actualPortions.map({ $0.isFinite && $0 > 0 }) ?? true,
                  [meal.tasteRating, meal.preparationDifficulty]
                    .allSatisfy({ $0.map { (1...5).contains($0) } ?? true }),
                  meal.bloatingScore.map({ (0...3).contains($0) }) ?? true else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "备份包含无效的餐食份数或反馈评分。"])
            }
            if let snapshot = meal.recipeSnapshotJSON {
                try FatLossBackupService.validateRecipeJSON(snapshot)
            }
        }
        for rope in backup.jumpRopeEntries ?? [] {
            guard JumpRopeDurationValidation.isValid(active: rope.activeDurationSeconds, elapsed: rope.elapsedDurationSeconds) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "备份跳绳有效时长不能超过含休息总时长。"])
            }
        }
    }

    private static func validateProgramReferences(in backup: XFitBackup, context: ModelContext) throws {
        let referencedMeals = backup.meals.filter { $0.plannedMealID != nil || $0.programID != nil }
        let links = backup.fatLoss?.workoutLinks ?? []
        guard !referencedMeals.isEmpty || !links.isEmpty else { return }
        guard FatLossBackupService.isRegistered(FatLossProgram.self, in: context),
              FatLossBackupService.isRegistered(PlannedMeal.self, in: context) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "当前数据库不支持此备份的减脂记录。"])
        }
        let programIDs = Set((backup.fatLoss?.programs ?? []).map(\.id))
            .union(try context.fetch(FetchDescriptor<FatLossProgram>()).map(\.id))
        let planPairs = (backup.fatLoss?.plannedMeals ?? []).map { ($0.id, $0.programID) }
            + (try context.fetch(FetchDescriptor<PlannedMeal>())).map { ($0.id, $0.programID) }
        let plans = Dictionary(planPairs, uniquingKeysWith: { first, _ in first })
        let existingMeals = try context.fetch(FetchDescriptor<MealEntry>())
        var activePlanIDs = Set<UUID>()
        for meal in referencedMeals {
            if let programID = meal.programID, !programIDs.contains(programID) {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "实际餐食引用的减脂周期不存在。"])
            }
            if let plannedMealID = meal.plannedMealID {
                guard let owningProgram = plans[plannedMealID], meal.programID == owningProgram else {
                    throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "实际餐食引用的餐单不存在或属于其他周期。"])
                }
                if meal.isVoided != true {
                    guard activePlanIDs.insert(plannedMealID).inserted else {
                        throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "同一餐单存在重复的有效实际餐食。"])
                    }
                    if !existingMeals.contains(where: { $0.id == meal.id }),
                       existingMeals.contains(where: { $0.isActiveMeal && $0.plannedMealID == plannedMealID }) {
                        throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "备份实际餐食与现有记录冲突。"])
                    }
                }
            }
        }
        let scheduleIDs = Set(backup.schedules.map(\.id))
            .union(try context.fetch(FetchDescriptor<ScheduledWorkout>()).map(\.id))
        guard links.allSatisfy({ scheduleIDs.contains($0.scheduledWorkoutID) }) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "减脂训练引用的日程不存在。"])
        }
    }

    private static func validateRestIntervals(in backup: XFitBackup) throws {
        for record in backup.setLogs {
            if let duration = record.restDurationSeconds,
               !(0...RestDurationInput.maximumSeconds).contains(duration) {
                throw CocoaError(.fileReadCorruptFile, userInfo: [
                    NSLocalizedDescriptionKey: "备份包含无效的组后休息秒数，已停止导入。"
                ])
            }
            if let startedAt = record.restStartedAt,
               let endedAt = record.restEndedAt,
               endedAt < startedAt {
                throw CocoaError(.fileReadCorruptFile, userInfo: [
                    NSLocalizedDescriptionKey: "备份包含结束时间早于开始时间的组间休息，已停止导入。"
                ])
            }
        }
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
