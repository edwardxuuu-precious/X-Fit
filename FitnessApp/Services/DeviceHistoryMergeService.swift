import Foundation
import SwiftData

struct DeviceHistoryMergePackage: Codable {
    let schemaVersion: Int
    let source: String
    let sessions: [DeviceHistoryMergeSession]
}

struct DeviceHistoryMergeSession: Codable {
    let id: UUID
    let templateName: String
    let plannedDate: Date
    let startedAt: Date
    let completedAt: Date?
    var startedAtTimeIntervalSince1970: Double? = nil
    var completedAtTimeIntervalSince1970: Double? = nil
    let statusRaw: String
    let notes: String
    let restEndDate: Date?
    var restModeRaw: String? = nil
    let importIdentifier: String
    let exercises: [DeviceHistoryMergeExercise]
}

struct DeviceHistoryMergeExercise: Codable {
    let id: UUID
    let sourceExerciseID: UUID
    let exerciseName: String
    let order: Int
    let targetSets: Int
    let minReps: Int
    let maxReps: Int
    let targetWeight: Double
    let restSeconds: Int
    let muscleGroup: String
    let equipment: String
    let exerciseNotes: String
    var referenceURL: String? = nil
    var volumeUnitRaw: String? = nil
    let performanceNotes: String
    var feelingRaw: String? = nil
    var exerciseStartedAt: Date? = nil
    var exerciseCompletedAt: Date? = nil
    var bodyWeightKgSnapshot: Double? = nil
    var bodyWeightSnapshotSourceDate: Date? = nil
    let sets: [DeviceHistoryMergeSet]
}

struct DeviceHistoryMergeSet: Codable {
    let id: UUID
    let setNumber: Int
    let targetWeight: Double
    let targetReps: Int
    let actualWeight: Double
    let actualReps: Int
    let rir: Int?
    let isWarmup: Bool
    let isCompleted: Bool
    var startedAt: Date? = nil
    let completedAt: Date?
    var restStartedAt: Date? = nil
    var restEndedAt: Date? = nil
    var restDurationSeconds: Int? = nil
    var completedAtTimeIntervalSince1970: Double? = nil
}

struct DeviceHistoryMergeSummary: Codable, Equatable {
    let importedSessions: Int
    let skippedSessions: Int
    let importedSessionExercises: Int
    let importedSetLogs: Int
    let importedCompletedSetLogs: Int
    let updatedSchedules: Int
}

enum DeviceHistoryMergeError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case emptyPackage
    case duplicateIdentifier(String)
    case ambiguousExistingSession(String)
    case missingExercise(String)
    case ambiguousExercise(String)
    case incompatibleExercise(String)
    case ambiguousTemplate(String)
    case ambiguousSchedule(String)
    case existingIdentifierConflict(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            return "合并文件版本 \(version) 不受支持。"
        case .emptyPackage:
            return "合并文件没有训练记录。"
        case let .duplicateIdentifier(value):
            return "合并文件包含重复标识：\(value)。"
        case let .ambiguousExistingSession(value):
            return "已有多场训练与 \(value) 同时匹配，已停止合并。"
        case let .missingExercise(value):
            return "手机动作库缺少 \(value)，已停止合并。"
        case let .ambiguousExercise(value):
            return "手机动作库存在多个同名动作 \(value)，已停止合并。"
        case let .incompatibleExercise(value):
            return "手机动作库中的同名动作 \(value) 与来源肌群、器械或计量单位不一致，已停止合并。"
        case let .ambiguousTemplate(value):
            return "手机存在多个同名计划 \(value)，已停止合并。"
        case let .ambiguousSchedule(value):
            return "手机存在多个同日安排 \(value)，已停止合并。"
        case let .existingIdentifierConflict(value):
            return "手机已有记录占用了标识 \(value)，已停止合并。"
        }
    }
}

@MainActor
enum DeviceHistoryMergeService {
    static func decode(_ data: Data) throws -> DeviceHistoryMergePackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(DeviceHistoryMergePackage.self, from: data)
        guard package.schemaVersion == 1 else {
            throw DeviceHistoryMergeError.unsupportedSchema(package.schemaVersion)
        }
        guard !package.sessions.isEmpty else {
            throw DeviceHistoryMergeError.emptyPackage
        }
        try validatePackageIdentifiers(package)
        return package
    }

    static func importPackage(
        _ data: Data,
        into context: ModelContext
    ) throws -> DeviceHistoryMergeSummary {
        let package = try decode(data)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())

        try validateExistingIdentifiers(exercises, label: "Exercise")
        try validateExistingIdentifiers(templates, label: "WorkoutTemplate")
        try validateExistingIdentifiers(schedules, label: "ScheduledWorkout")
        try validateExistingIdentifiers(sessions, label: "WorkoutSession")
        try validateExistingIdentifiers(snapshots, label: "SessionExercise")
        try validateExistingIdentifiers(logs, label: "SetLog")

        let existingSessionIDs = Set(sessions.map(\.id))
        let existingSnapshotIDs = Set(snapshots.map(\.id))
        let existingLogIDs = Set(logs.map(\.id))

        var importedSessions = 0
        var skippedSessions = 0
        var importedSnapshots = 0
        var importedLogs = 0
        var importedCompletedLogs = 0
        var updatedSchedules = 0

        do {
            for record in package.sessions {
                let mergeIdentifier = stableMergeIdentifier(source: package.source, sessionID: record.id)
                let semanticMatches = sessions.filter {
                    $0.templateName == record.templateName
                        && abs($0.startedAt.timeIntervalSince(record.resolvedStartedAt)) < 60
                }
                guard semanticMatches.count <= 1 else {
                    throw DeviceHistoryMergeError.ambiguousExistingSession(record.templateName)
                }

                let identityMatches = sessions.filter {
                    $0.id == record.id
                        || $0.importIdentifier == mergeIdentifier
                        || (!record.importIdentifier.isEmpty && $0.importIdentifier == record.importIdentifier)
                }
                guard identityMatches.count <= 1 else {
                    throw DeviceHistoryMergeError.ambiguousExistingSession(record.templateName)
                }
                if let existingSession = identityMatches.first {
                    try reconcilePreciseTimestamps(
                        for: existingSession,
                        from: record,
                        snapshots: snapshots,
                        logs: logs
                    )
                    skippedSessions += 1
                    continue
                }
                if existingSessionIDs.contains(record.id) || semanticMatches.count == 1 {
                    skippedSessions += 1
                    continue
                }

                let matchingTemplates = templates.filter { $0.name == record.templateName }
                guard matchingTemplates.count <= 1 else {
                    throw DeviceHistoryMergeError.ambiguousTemplate(record.templateName)
                }
                let matchingSchedules = schedules.filter {
                    $0.templateName == record.templateName
                        && $0.plannedDate.isSameDay(as: record.plannedDate)
                }
                guard matchingSchedules.count <= 1 else {
                    throw DeviceHistoryMergeError.ambiguousSchedule(record.templateName)
                }

                let mappedExercises = try Dictionary(uniqueKeysWithValues: record.exercises.map { item in
                    (item.id, try matchingExercise(for: item, in: exercises))
                })
                for item in record.exercises where existingSnapshotIDs.contains(item.id) {
                    throw DeviceHistoryMergeError.existingIdentifierConflict(item.id.uuidString)
                }
                for item in record.exercises {
                    for set in item.sets where existingLogIDs.contains(set.id) {
                        throw DeviceHistoryMergeError.existingIdentifierConflict(set.id.uuidString)
                    }
                }

                let matchingSchedule = matchingSchedules.first
                let session = WorkoutSession(
                    id: record.id,
                    scheduledWorkoutID: matchingSchedule?.id,
                    templateID: matchingTemplates.first?.id,
                    templateName: record.templateName,
                    plannedDate: record.plannedDate,
                    startedAt: record.resolvedStartedAt,
                    completedAt: record.resolvedCompletedAt,
                    status: WorkoutSessionStatus(rawValue: record.statusRaw) ?? .completed,
                    notes: record.notes,
                    restEndDate: record.restEndDate,
                    restMode: record.restModeRaw.flatMap(WorkoutRestMode.init(rawValue:)) ?? .countdown,
                    importIdentifier: mergeIdentifier
                )
                context.insert(session)
                importedSessions += 1

                for item in record.exercises.sorted(by: { $0.order < $1.order }) {
                    guard let exercise = mappedExercises[item.id] else {
                        throw DeviceHistoryMergeError.missingExercise(item.exerciseName)
                    }
                    let snapshot = SessionExercise(
                        id: item.id,
                        sessionID: session.id,
                        exerciseID: exercise.id,
                        exerciseName: item.exerciseName,
                        order: item.order,
                        targetSets: item.targetSets,
                        minReps: item.minReps,
                        maxReps: item.maxReps,
                        targetWeight: item.targetWeight,
                        restSeconds: item.restSeconds,
                        muscleGroup: item.muscleGroup,
                        exerciseNotes: item.exerciseNotes,
                        referenceURL: item.referenceURL ?? "",
                        volumeUnit: item.volumeUnitRaw.flatMap(ExerciseVolumeUnit.init(rawValue:)) ?? .kilogram,
                        performanceNotes: item.performanceNotes,
                        feeling: item.feelingRaw.flatMap(WorkoutFeeling.init(rawValue:)),
                        exerciseStartedAt: item.exerciseStartedAt,
                        exerciseCompletedAt: item.exerciseCompletedAt,
                        bodyWeightKgSnapshot: item.bodyWeightKgSnapshot,
                        bodyWeightSnapshotSourceDate: item.bodyWeightSnapshotSourceDate
                    )
                    context.insert(snapshot)
                    importedSnapshots += 1

                    for set in item.sets.sorted(by: { $0.setNumber < $1.setNumber }) {
                        context.insert(SetLog(
                            id: set.id,
                            sessionID: session.id,
                            sessionExerciseID: snapshot.id,
                            exerciseID: exercise.id,
                            setNumber: set.setNumber,
                            targetWeight: set.targetWeight,
                            targetReps: set.targetReps,
                            actualWeight: set.actualWeight,
                            actualReps: set.actualReps,
                            rir: set.rir,
                            isWarmup: set.isWarmup,
                            isCompleted: set.isCompleted,
                            startedAt: set.startedAt,
                            completedAt: set.resolvedCompletedAt,
                            restStartedAt: set.restStartedAt,
                            restEndedAt: set.restEndedAt,
                            restDurationSeconds: set.restDurationSeconds
                        ))
                        importedLogs += 1
                        if set.isCompleted { importedCompletedLogs += 1 }
                    }
                }

                if let matchingSchedule, matchingSchedule.status != .completed {
                    matchingSchedule.status = .completed
                    matchingSchedule.updatedAt = max(
                        matchingSchedule.updatedAt,
                        record.resolvedCompletedAt ?? record.resolvedStartedAt
                    )
                    updatedSchedules += 1
                }
            }

            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return DeviceHistoryMergeSummary(
            importedSessions: importedSessions,
            skippedSessions: skippedSessions,
            importedSessionExercises: importedSnapshots,
            importedSetLogs: importedLogs,
            importedCompletedSetLogs: importedCompletedLogs,
            updatedSchedules: updatedSchedules
        )
    }

    private static func matchingExercise(
        for item: DeviceHistoryMergeExercise,
        in exercises: [Exercise]
    ) throws -> Exercise {
        if let exact = exercises.first(where: { $0.id == item.sourceExerciseID }) {
            guard ExerciseCatalogService.semanticallyCompatible(
                exact,
                muscleGroup: item.muscleGroup,
                equipment: item.equipment,
                volumeUnit: item.volumeUnitRaw.flatMap(ExerciseVolumeUnit.init(rawValue:)) ?? .kilogram
            ) else {
                throw DeviceHistoryMergeError.incompatibleExercise(item.exerciseName)
            }
            return exact
        }
        let nameMatches = exercises.filter {
            $0.name.caseInsensitiveCompare(item.exerciseName) == .orderedSame
        }
        let identityMatches = nameMatches.filter {
            ExerciseCatalogService.semanticallyCompatible(
                $0,
                muscleGroup: item.muscleGroup,
                equipment: item.equipment,
                volumeUnit: item.volumeUnitRaw.flatMap(ExerciseVolumeUnit.init(rawValue:)) ?? .kilogram
            )
        }
        if identityMatches.count == 1, let match = identityMatches.first {
            return match
        }
        if identityMatches.count > 1 {
            throw DeviceHistoryMergeError.ambiguousExercise(item.exerciseName)
        }
        if nameMatches.isEmpty {
            throw DeviceHistoryMergeError.missingExercise(item.exerciseName)
        }
        throw DeviceHistoryMergeError.incompatibleExercise(item.exerciseName)
    }

    private static func reconcilePreciseTimestamps(
        for session: WorkoutSession,
        from record: DeviceHistoryMergeSession,
        snapshots: [SessionExercise],
        logs: [SetLog]
    ) throws {
        session.plannedDate = record.plannedDate
        session.startedAt = record.resolvedStartedAt
        session.completedAt = record.resolvedCompletedAt
        session.restEndDate = record.restEndDate
        if let restModeRaw = record.restModeRaw {
            session.restModeRaw = restModeRaw
        }

        let existingSnapshots = snapshots.filter { $0.sessionID == session.id }
        let existingLogs = logs.filter { $0.sessionID == session.id }
        for item in record.exercises {
            guard let existingSnapshot = existingSnapshots.first(where: { $0.id == item.id }) else {
                throw DeviceHistoryMergeError.existingIdentifierConflict(item.id.uuidString)
            }
            if let feelingRaw = item.feelingRaw {
                existingSnapshot.feelingRaw = feelingRaw
            }
            if let exerciseStartedAt = item.exerciseStartedAt {
                existingSnapshot.exerciseStartedAt = exerciseStartedAt
            }
            if let exerciseCompletedAt = item.exerciseCompletedAt {
                existingSnapshot.exerciseCompletedAt = exerciseCompletedAt
            }
            if let bodyWeightKgSnapshot = item.bodyWeightKgSnapshot {
                existingSnapshot.bodyWeightKgSnapshot = bodyWeightKgSnapshot
            }
            if let bodyWeightSnapshotSourceDate = item.bodyWeightSnapshotSourceDate {
                existingSnapshot.bodyWeightSnapshotSourceDate = bodyWeightSnapshotSourceDate
            }
            for set in item.sets {
                guard let existingLog = existingLogs.first(where: { $0.id == set.id }) else {
                    throw DeviceHistoryMergeError.existingIdentifierConflict(set.id.uuidString)
                }
                if let startedAt = set.startedAt {
                    existingLog.startedAt = startedAt
                }
                existingLog.completedAt = set.resolvedCompletedAt
                if let restStartedAt = set.restStartedAt {
                    existingLog.restStartedAt = restStartedAt
                }
                if let restEndedAt = set.restEndedAt {
                    existingLog.restEndedAt = restEndedAt
                }
                if let restDurationSeconds = set.restDurationSeconds {
                    existingLog.restDurationSeconds = restDurationSeconds
                }
            }
        }
    }

    private static func stableMergeIdentifier(source: String, sessionID: UUID) -> String {
        "device-history-merge:\(source):\(sessionID.uuidString.lowercased())"
    }

    private static func validatePackageIdentifiers(_ package: DeviceHistoryMergePackage) throws {
        try requireUnique(package.sessions.map(\.id), label: "WorkoutSession")
        let snapshots = package.sessions.flatMap(\.exercises)
        try requireUnique(snapshots.map(\.id), label: "SessionExercise")
        try requireUnique(snapshots.flatMap(\.sets).map(\.id), label: "SetLog")
    }

    private static func requireUnique(_ values: [UUID], label: String) throws {
        guard Set(values).count == values.count else {
            throw DeviceHistoryMergeError.duplicateIdentifier(label)
        }
    }

    private static func validateExistingIdentifiers<T>(
        _ models: [T],
        label: String
    ) throws where T: IdentifiedModel {
        try requireUnique(models.map(\.id), label: label)
    }
}

protocol IdentifiedModel {
    var id: UUID { get }
}

extension Exercise: IdentifiedModel {}
extension WorkoutTemplate: IdentifiedModel {}
extension TemplateExercise: IdentifiedModel {}
extension ScheduledWorkout: IdentifiedModel {}
extension WorkoutSession: IdentifiedModel {}
extension SessionExercise: IdentifiedModel {}
extension SetLog: IdentifiedModel {}
extension NutritionTarget: IdentifiedModel {}
extension MealEntry: IdentifiedModel {}
extension BodyMeasurement: IdentifiedModel {}

private extension DeviceHistoryMergeSession {
    var resolvedStartedAt: Date {
        startedAtTimeIntervalSince1970.map(Date.init(timeIntervalSince1970:)) ?? startedAt
    }

    var resolvedCompletedAt: Date? {
        completedAtTimeIntervalSince1970.map(Date.init(timeIntervalSince1970:)) ?? completedAt
    }
}

private extension DeviceHistoryMergeSet {
    var resolvedCompletedAt: Date? {
        completedAtTimeIntervalSince1970.map(Date.init(timeIntervalSince1970:)) ?? completedAt
    }
}
