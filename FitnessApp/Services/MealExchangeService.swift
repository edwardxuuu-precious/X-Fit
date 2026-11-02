import Foundation
import SwiftData

enum MealExchangeOperation: String, Codable {
    case exportWeek, applyReview, importNotes, previewTravelWeek, applyTravelWeek
    case previewTrainingPlan, applyTrainingPlan, readTrainingPlan
    case previewDailyTrainingPlan, applyDailyTrainingPlan, readDailyTrainingPlan
    case correctHistoricalExercise
}

struct ConfirmedDailyTrainingPlanReadRequest: Codable {
    let id: UUID
    let packetSHA256: String
}

struct ConfirmedTrainingPlanReadRequest: Codable {
    let code: String
    let packetSHA256: String
}

struct MealExchangeRequest: Codable {
    let version: Int
    let id: UUID
    let operation: MealExchangeOperation
    let startLocalDay: String?
    let endLocalDay: String?
    let payloadFileName: String?
    let approvedSHA256: String?

    func validate() throws {
        guard version == 1 else { throw MealExchangeError.invalidRequest }
        switch operation {
        case .exportWeek:
            let utc = TimeZone(secondsFromGMT: 0)!
            guard let startLocalDay, let endLocalDay,
                  let start = MealLocalDay.date(startLocalDay, timeZone: utc),
                  let end = MealLocalDay.date(endLocalDay, timeZone: utc),
                  end.timeIntervalSince(start) == 6 * 86_400 else { throw MealExchangeError.invalidRequest }
        case .previewTravelWeek: break
        case .applyReview, .importNotes, .applyTravelWeek, .previewTrainingPlan, .applyTrainingPlan, .readTrainingPlan,
             .previewDailyTrainingPlan, .applyDailyTrainingPlan, .readDailyTrainingPlan, .correctHistoricalExercise:
            guard let payloadFileName, Self.isSafeFileName(payloadFileName),
                  let approvedSHA256, approvedSHA256.count == 64,
                  approvedSHA256.allSatisfy({ $0.isHexDigit }) else { throw MealExchangeError.invalidRequest }
        }
    }

    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 180 && name.hasSuffix(".json") &&
        name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } &&
        !name.contains("..") && !name.hasPrefix(".")
    }
}

enum MealExchangeError: LocalizedError {
    case invalidRequest, changedPayload, unsafePath
    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "同步请求不完整或尚未确认，未写入。"
        case .changedPayload: return "待写入文件与已确认版本不同，未写入。"
        case .unsafePath: return "同步文件路径不安全，未读取或写入。"
        }
    }
}

struct MealExchangeReceipt: Codable {
    let requestID: UUID
    let completedAt: Date
    let status: String
    let message: String
}

/// Invoked only by an explicit paired-Mac launch request. No polling, server or network upload.
@MainActor
enum MealExchangeService {
    static func processLaunchRequest(arguments: [String], in context: ModelContext) throws -> String? {
        let prefix = "--meal-exchange-request="
        guard let argument = arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let name = String(argument.dropFirst(prefix.count))
        guard MealExchangeRequest.isSafeFileName(name) else { throw MealExchangeError.unsafePath }
        let documents = URL.documentsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let request = try decoder.decode(MealExchangeRequest.self, from: Data(contentsOf: safeFile(name, in: documents)))
        let output = documents.appendingPathComponent("MealExchange", isDirectory: true)
            .appendingPathComponent(request.id.uuidString.lowercased(), isDirectory: true)
        guard output.resolvingSymlinksInPath().path == output.standardizedFileURL.path else { throw MealExchangeError.unsafePath }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        do {
            try request.validate()
            let message: String
            switch request.operation {
            case .exportWeek:
                let package = try MealReviewService().exportWeek(meals: context.fetch(FetchDescriptor<MealEntry>()),
                    startLocalDay: request.startLocalDay!, endLocalDay: request.endLocalDay!)
                try write(package, to: output.appendingPathComponent("week.json"))
                message = "已导出指定周的 \(package.meals.count) 条餐食；未修改手机记录。"
            case .applyReview:
                let batch = try decoder.decode(MealReviewBatch.self, from: payload(request, documents: documents))
                let result = try MealReviewService().apply(batch, confirmed: true, context: context)
                try write(result, to: output.appendingPathComponent("review-result.json"))
                message = "评估已写入 \(result.appliedCount) 餐，重复跳过 \(result.duplicateCount) 餐。"
            case .importNotes:
                let data = try payload(request, documents: documents)
                let result = try ConfirmedNotesImportService.importPackage(data, into: context)
                try write(result, to: output.appendingPathComponent("notes-result.json"))
                message = "训练 \(result.importedSessions) 场（\(result.importedSessionExercises) 个动作、\(result.importedSets) 组），日期元数据修复 \(result.repairedSessionDateMetadata) 条；跳过重复训练 \(result.skippedSessions) 场。跳绳 \(result.importedJumpRopeEntries) 条，跳过重复跳绳 \(result.skippedJumpRopeEntries) 条。体重 \(result.importedBodyMeasurements) 条，餐食 \(result.importedMeals) 条。"
            case .correctHistoricalExercise:
                let data = try payload(request, documents: documents)
                let result = try HistoricalExerciseCorrectionService.apply(data, in: context)
                try write(result, to: output.appendingPathComponent("historical-exercise-result.json"))
                let version = try decoder.decode(HistoricalCorrectionVersion.self, from: data).version
                message = result.applied
                    ? (version == 2 ? "已更正 1 个历史动作并补入 4 组实际，原组 ID 保留。" : "已纠正 1 个历史动作，原组记录保持。")
                    : "该历史动作已按同一确认内容纠正，无新增修改。"
            case .previewTravelWeek:
                let preview = try ConfirmedTravelWeekService.preview(in: context)
                try write(preview, to: output.appendingPathComponent("travel-preview.json"))
                message = "已生成旅行周写入预览；未修改训练。"
            case .applyTravelWeek:
                let preview = try decoder.decode(ConfirmedTravelWeekPreview.self, from: payload(request, documents: documents))
                let result = try ConfirmedTravelWeekService.apply(expectedPreview: preview, in: context)
                try write(result, to: output.appendingPathComponent("travel-result.json"))
                message = "已写入已确认旅行周训练；保留历史完成记录。"
            case .previewTrainingPlan:
                let packet = try decoder.decode(ConfirmedTrainingPlanPacket.self, from: payload(request, documents: documents))
                let preview = try ConfirmedTrainingPlanService.preview(packet, in: context)
                try write(preview, to: output.appendingPathComponent("training-preview.json"))
                message = preview.conflicts.isEmpty
                    ? "已预览完整确认计划，共\(preview.newScheduleCount)项新日程；未写入训练。"
                    : "计划尚未写入；需处理\(preview.conflicts.count)项身份或日程冲突。"
            case .applyTrainingPlan:
                let preview = try decoder.decode(ConfirmedTrainingPlanPreview.self, from: payload(request, documents: documents))
                let result = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
                try write(result, to: output.appendingPathComponent("training-result.json"))
                message = "完整确认计划已核验，新增\(result.newScheduleCount)项日程；原实际记录保持不变。"
            case .readTrainingPlan:
                let query = try decoder.decode(ConfirmedTrainingPlanReadRequest.self, from: payload(request, documents: documents))
                guard !query.code.isEmpty, query.packetSHA256.count == 64,
                      let readback = try ConfirmedTrainingPlanService.readback(code: query.code, in: context),
                      readback.snapshot.confirmedImport?.packetSHA256 == query.packetSHA256 else {
                    throw ConfirmedTrainingPlanError.conflict("未找到来源一致的完整计划")
                }
                try write(readback, to: output.appendingPathComponent("training-readback.json"))
                message = "已完整回读\(readback.snapshot.code)及\(readback.schedules.count)项日程；未修改实际记录。"
            case .previewDailyTrainingPlan:
                let packet = try decoder.decode(ConfirmedDailyTrainingPlanPacket.self, from: payload(request, documents: documents))
                let preview = try ConfirmedDailyTrainingPlanService.preview(packet, in: context)
                try write(preview, to: output.appendingPathComponent("daily-training-preview.json"))
                message = preview.conflicts.isEmpty
                    ? "已预览\(packet.localDay)单日确认计划，新增\(preview.newScheduleCount)项；未写入训练。"
                    : "单日计划尚未写入，存在\(preview.conflicts.count)项冲突。"
            case .applyDailyTrainingPlan:
                let preview = try decoder.decode(ConfirmedDailyTrainingPlanPreview.self, from: payload(request, documents: documents))
                let result = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
                try write(result, to: output.appendingPathComponent("daily-training-result.json"))
                message = "单日确认计划已核验，新增\(result.newScheduleCount)项日程；实际训练记录保持不变。"
            case .readDailyTrainingPlan:
                let query = try decoder.decode(ConfirmedDailyTrainingPlanReadRequest.self, from: payload(request, documents: documents))
                guard let readback = try ConfirmedDailyTrainingPlanService.readback(id: query.id, in: context),
                      readback.packetSHA256 == query.packetSHA256 else {
                    throw ConfirmedTrainingPlanError.conflict("未找到来源一致的单日计划")
                }
                try write(readback, to: output.appendingPathComponent("daily-training-readback.json"))
                message = "已完整回读\(readback.packet.localDay)单日确认计划；未修改实际记录。"
            }
            try write(MealExchangeReceipt(requestID: request.id, completedAt: .now, status: "completed", message: message),
                to: output.appendingPathComponent("receipt.json"))
            return message
        } catch {
            try? write(MealExchangeReceipt(requestID: request.id, completedAt: .now, status: "failed", message: error.localizedDescription),
                to: output.appendingPathComponent("receipt.json"))
            throw error
        }
    }

    private static func payload(_ request: MealExchangeRequest, documents: URL) throws -> Data {
        guard let name = request.payloadFileName, let digest = request.approvedSHA256 else { throw MealExchangeError.invalidRequest }
        let file = try safeFile(name, in: documents)
        switch request.operation {
        case .previewTrainingPlan, .applyTrainingPlan, .readTrainingPlan,
             .previewDailyTrainingPlan, .applyDailyTrainingPlan, .readDailyTrainingPlan, .correctHistoricalExercise:
            guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 2_097_152 else {
                throw ConfirmedTrainingPlanError.invalidPacket("文件过大")
            }
        default: break
        }
        let data = try Data(contentsOf: file)
        guard MealPhotoService.digest(data) == digest.lowercased() else { throw MealExchangeError.changedPayload }
        return data
    }

    private static func safeFile(_ name: String, in root: URL) throws -> URL {
        guard MealExchangeRequest.isSafeFileName(name) else { throw MealExchangeError.unsafePath }
        let file = root.appendingPathComponent(name)
        guard file.resolvingSymlinksInPath().deletingLastPathComponent().path == root.resolvingSymlinksInPath().path else {
            throw MealExchangeError.unsafePath
        }
        return file
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

struct HistoricalCorrectionSnapshotState: Codable, Equatable {
    var id: UUID
    var sessionID: UUID
    var exerciseID: UUID
    var exerciseName: String
    var order: Int
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var targetWeight: Double
    var restSeconds: Int
    var muscleGroup: String
    var exerciseNotes: String
    var referenceURL: String
    var volumeUnitRaw: String?
    var performanceNotes: String
    var plannedSetsJSON: String?
    var planPatternRaw: String?
    var patternSourceRaw: String?
    var feelingRaw: String?
    var exerciseStartedAtReferenceSeconds: Double?
    var exerciseCompletedAtReferenceSeconds: Double?
    var bodyWeightKgSnapshot: Double?
    var bodyWeightSnapshotSourceDateReferenceSeconds: Double?
    var equipmentSnapshot: String?

    init(_ snapshot: SessionExercise) {
        id = snapshot.id
        sessionID = snapshot.sessionID
        exerciseID = snapshot.exerciseID
        exerciseName = snapshot.exerciseName
        order = snapshot.order
        targetSets = snapshot.targetSets
        minReps = snapshot.minReps
        maxReps = snapshot.maxReps
        targetWeight = snapshot.targetWeight
        restSeconds = snapshot.restSeconds
        muscleGroup = snapshot.muscleGroup
        exerciseNotes = snapshot.exerciseNotes
        referenceURL = snapshot.referenceURL
        volumeUnitRaw = snapshot.volumeUnitRaw
        performanceNotes = snapshot.performanceNotes
        plannedSetsJSON = snapshot.plannedSetsJSON
        planPatternRaw = snapshot.planPatternRaw
        patternSourceRaw = snapshot.patternSourceRaw
        feelingRaw = snapshot.feelingRaw
        exerciseStartedAtReferenceSeconds = snapshot.exerciseStartedAt?.timeIntervalSinceReferenceDate
        exerciseCompletedAtReferenceSeconds = snapshot.exerciseCompletedAt?.timeIntervalSinceReferenceDate
        bodyWeightKgSnapshot = snapshot.bodyWeightKgSnapshot
        bodyWeightSnapshotSourceDateReferenceSeconds = snapshot.bodyWeightSnapshotSourceDate?.timeIntervalSinceReferenceDate
        equipmentSnapshot = snapshot.equipmentSnapshot
    }
}

struct HistoricalCorrectionSetState: Codable, Equatable {
    var id: UUID
    var sessionID: UUID
    var sessionExerciseID: UUID
    var exerciseID: UUID
    var setNumber: Int
    var targetWeight: Double
    var targetReps: Int
    var actualWeight: Double
    var actualReps: Int
    var rir: Int?
    var isWarmup: Bool
    var isCompleted: Bool
    var startedAtReferenceSeconds: Double?
    var completedAtReferenceSeconds: Double?
    var restStartedAtReferenceSeconds: Double?
    var restEndedAtReferenceSeconds: Double?
    var restDurationSeconds: Int?
    var targetWeightSideRaw: String?
    var targetRepsSideRaw: String?
    var actualWeightSideRaw: String?
    var actualRepsSideRaw: String?
    var actualEntrySourceRaw: String?
    var sourceHistorySetID: UUID?
    var actualWeightIsBlank: Bool?

    init(_ log: SetLog) {
        id = log.id
        sessionID = log.sessionID
        sessionExerciseID = log.sessionExerciseID
        exerciseID = log.exerciseID
        setNumber = log.setNumber
        targetWeight = log.targetWeight
        targetReps = log.targetReps
        actualWeight = log.actualWeight
        actualReps = log.actualReps
        rir = log.rir
        isWarmup = log.isWarmup
        isCompleted = log.isCompleted
        startedAtReferenceSeconds = log.startedAt?.timeIntervalSinceReferenceDate
        completedAtReferenceSeconds = log.completedAt?.timeIntervalSinceReferenceDate
        restStartedAtReferenceSeconds = log.restStartedAt?.timeIntervalSinceReferenceDate
        restEndedAtReferenceSeconds = log.restEndedAt?.timeIntervalSinceReferenceDate
        restDurationSeconds = log.restDurationSeconds
        targetWeightSideRaw = log.targetWeightSideRaw
        targetRepsSideRaw = log.targetRepsSideRaw
        actualWeightSideRaw = log.actualWeightSideRaw
        actualRepsSideRaw = log.actualRepsSideRaw
        actualEntrySourceRaw = log.actualEntrySourceRaw
        sourceHistorySetID = log.sourceHistorySetID
        actualWeightIsBlank = log.actualWeightIsBlank
    }
}

struct HistoricalCorrectionTarget: Codable, Equatable {
    var id: UUID
    var name: String
    var muscleGroup: String
    var equipment: String
    var volumeUnit: ExerciseVolumeUnit
    var notes: String
}

struct HistoricalExerciseCorrectionPacket: Codable {
    var version: Int
    var sessionID: UUID
    var expectedLocalDay: String?
    var expectedImportIdentifier: String
    var expectedSnapshot: HistoricalCorrectionSnapshotState
    var expectedSets: [HistoricalCorrectionSetState]
    var target: HistoricalCorrectionTarget
    var confirmationReference: String
    var correctionNote: String
}

struct HistoricalExerciseCorrectionResult: Codable, Equatable {
    let applied: Bool
    let sessionID: UUID
    let snapshotID: UUID
    let targetExerciseID: UUID
    let preservedSetCount: Int
}

enum HistoricalExerciseCorrectionError: LocalizedError, Equatable {
    case invalidPacket, changedRecord, conflictingTarget, pendingChanges

    var errorDescription: String? {
        switch self {
        case .invalidPacket: return "历史动作纠正信息不完整，未修改记录。"
        case .changedRecord: return "历史动作或组记录与确认时不同，未修改记录。"
        case .conflictingTarget: return "目标动作身份冲突，未修改记录。"
        case .pendingChanges: return "存在其他尚未保存的修改，请先处理后再纠正。"
        }
    }
}

@MainActor
enum HistoricalExerciseCorrectionService {
    static func apply(_ packet: HistoricalExerciseCorrectionPacket, in context: ModelContext,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> HistoricalExerciseCorrectionResult {
        let expected = packet.expectedSnapshot
        let target = packet.target
        guard packet.version == 1,
              !packet.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !packet.correctionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !target.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !target.muscleGroup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !target.equipment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expected.sessionID == packet.sessionID, target.id != expected.exerciseID,
              target.name.caseInsensitiveCompare(expected.exerciseName) != .orderedSame,
              target.volumeUnit.rawValue == (expected.volumeUnitRaw ?? ExerciseVolumeUnit.kilogram.rawValue),
              packet.expectedSets.count == 4,
              Set(packet.expectedSets.map(\.id)).count == packet.expectedSets.count,
              packet.expectedSets.allSatisfy({
                  $0.sessionID == packet.sessionID && $0.sessionExerciseID == expected.id
                      && $0.exerciseID == expected.exerciseID && $0.isCompleted
                      && $0.actualWeight.isFinite && $0.targetWeight.isFinite
              }) else { throw HistoricalExerciseCorrectionError.invalidPacket }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.id == packet.sessionID }
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.id == expected.id }
        guard sessions.count == 1, snapshots.count == 1,
              let session = sessions.first, let snapshot = snapshots.first,
              session.statusRaw == WorkoutSessionStatus.completed.rawValue,
              session.trainingLocalDay == packet.expectedLocalDay,
              session.importIdentifier == packet.expectedImportIdentifier else {
            throw HistoricalExerciseCorrectionError.changedRecord
        }
        let logs = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionExerciseID == expected.id }
        guard logs.count == packet.expectedSets.count else { throw HistoricalExerciseCorrectionError.changedRecord }
        let orderedExpected = packet.expectedSets.sorted { $0.id.uuidString < $1.id.uuidString }
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let byID = exercises.filter { $0.id == target.id }
        let targetName = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let byName = exercises.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(targetName) == .orderedSame
        }
        guard byID.count <= 1, byName.count <= 1,
              byName.allSatisfy({ $0.id == target.id }),
              byID.allSatisfy({ $0.name == target.name && $0.muscleGroup == target.muscleGroup
                  && $0.equipment == target.equipment && $0.volumeUnit == target.volumeUnit
                  && $0.notes == target.notes && !$0.isArchived && !$0.isBuiltIn
                  && $0.defaultRestSeconds == 90 && $0.referenceURL.isEmpty
                  && $0.terminologyCanonicalID == nil && $0.terminologyStandardNameZH == nil
                  && $0.terminologyStandardNameEN == nil && $0.terminologyReviewStatusRaw == nil
                  && $0.terminologyDecision == .pending && $0.terminologyConfidenceRaw == nil
                  && $0.terminologyMergeGroup == nil && $0.terminologyReviewNote == nil
                  && $0.terminologyCatalogVersion == nil && $0.terminologyReviewedAt == nil }) else {
            throw HistoricalExerciseCorrectionError.conflictingTarget
        }
        let annotation = "本人确认动作更正为「\(target.name)」；原名称「\(expected.exerciseName)」。确认依据：\(packet.confirmationReference)。\(packet.correctionNote)"
        let correctedNotes = expected.performanceNotes.isEmpty
            ? annotation : expected.performanceNotes + "\n" + annotation
        var currentSnapshot = HistoricalCorrectionSnapshotState(snapshot)
        var currentSets = logs.map(HistoricalCorrectionSetState.init).sorted { $0.id.uuidString < $1.id.uuidString }
        let alreadyApplied = snapshot.exerciseID == target.id && snapshot.exerciseName == target.name
            && snapshot.performanceNotes == correctedNotes
            && logs.allSatisfy { $0.exerciseID == target.id }
        if alreadyApplied {
            guard byID.count == 1 else { throw HistoricalExerciseCorrectionError.conflictingTarget }
            currentSnapshot.exerciseID = expected.exerciseID
            currentSnapshot.exerciseName = expected.exerciseName
            currentSnapshot.performanceNotes = expected.performanceNotes
            for index in currentSets.indices { currentSets[index].exerciseID = expected.exerciseID }
        }
        guard currentSnapshot == expected, currentSets == orderedExpected else {
            throw HistoricalExerciseCorrectionError.changedRecord
        }
        let result = HistoricalExerciseCorrectionResult(applied: !alreadyApplied, sessionID: session.id,
            snapshotID: snapshot.id, targetExerciseID: target.id, preservedSetCount: logs.count)
        guard !alreadyApplied else { return result }
        guard !context.hasChanges else { throw HistoricalExerciseCorrectionError.pendingChanges }
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        var createdExercise: Exercise?
        var saved = false
        defer {
            if !saved {
                snapshot.exerciseID = expected.exerciseID
                snapshot.exerciseName = expected.exerciseName
                snapshot.performanceNotes = expected.performanceNotes
                for log in logs { log.exerciseID = expected.exerciseID }
                if let createdExercise { context.delete(createdExercise) }
            }
            context.autosaveEnabled = previousAutosave
        }
        if byID.isEmpty {
            let exercise = Exercise(id: target.id, name: target.name, muscleGroup: target.muscleGroup,
                equipment: target.equipment, isBuiltIn: false, notes: target.notes, volumeUnit: target.volumeUnit)
            context.insert(exercise)
            createdExercise = exercise
        }
        snapshot.exerciseID = target.id
        snapshot.exerciseName = target.name
        snapshot.performanceNotes = correctedNotes
        for log in logs { log.exerciseID = target.id }
        try save(context)
        saved = true
        return result
    }
}


private struct HistoricalCorrectionVersion: Decodable {
    let version: Int
}

@propertyWrapper
struct HistoricalRequiredNullable<Value: Codable & Equatable>: Codable, Equatable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        wrappedValue = try value.decodeNil() ? nil : value.decode(Value.self)
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        if let wrappedValue { try value.encode(wrappedValue) }
        else { try value.encodeNil() }
    }
}

struct HistoricalCorrectionSessionState: Codable, Equatable {
    var id: UUID
    @HistoricalRequiredNullable var scheduledWorkoutID: UUID?
    @HistoricalRequiredNullable var templateID: UUID?
    var templateName: String
    var plannedDateReferenceSeconds: Double
    @HistoricalRequiredNullable var trainingLocalDay: String?
    @HistoricalRequiredNullable var trainingTimeZoneIdentifier: String?
    var startedAtReferenceSeconds: Double
    @HistoricalRequiredNullable var startTimeKnownRaw: Bool?
    @HistoricalRequiredNullable var completedAtReferenceSeconds: Double?
    var statusRaw: String
    var notes: String
    @HistoricalRequiredNullable var restEndDateReferenceSeconds: Double?
    @HistoricalRequiredNullable var restModeRaw: String?
    var importIdentifier: String
    @HistoricalRequiredNullable var defaultPlanPatternRaw: String?
    @HistoricalRequiredNullable var cardioResistanceLevel: Double?

    init(_ value: WorkoutSession) {
        id = value.id
        _scheduledWorkoutID = HistoricalRequiredNullable(wrappedValue: value.scheduledWorkoutID)
        _templateID = HistoricalRequiredNullable(wrappedValue: value.templateID)
        templateName = value.templateName
        plannedDateReferenceSeconds = value.plannedDate.timeIntervalSinceReferenceDate
        _trainingLocalDay = HistoricalRequiredNullable(wrappedValue: value.trainingLocalDay)
        _trainingTimeZoneIdentifier = HistoricalRequiredNullable(wrappedValue: value.trainingTimeZoneIdentifier)
        startedAtReferenceSeconds = value.startedAt.timeIntervalSinceReferenceDate
        _startTimeKnownRaw = HistoricalRequiredNullable(wrappedValue: value.startTimeKnownRaw)
        _completedAtReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.completedAt?.timeIntervalSinceReferenceDate)
        statusRaw = value.statusRaw
        notes = value.notes
        _restEndDateReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.restEndDate?.timeIntervalSinceReferenceDate)
        _restModeRaw = HistoricalRequiredNullable(wrappedValue: value.restModeRaw)
        importIdentifier = value.importIdentifier
        _defaultPlanPatternRaw = HistoricalRequiredNullable(wrappedValue: value.defaultPlanPatternRaw)
        _cardioResistanceLevel = HistoricalRequiredNullable(wrappedValue: value.cardioResistanceLevel)
    }
}

struct HistoricalBlankSnapshotState: Codable, Equatable {
    var id: UUID
    var sessionID: UUID
    var exerciseID: UUID
    var exerciseName: String
    var order: Int
    var targetSets: Int
    var minReps: Int
    var maxReps: Int
    var targetWeight: Double
    var restSeconds: Int
    var muscleGroup: String
    var exerciseNotes: String
    var referenceURL: String
    @HistoricalRequiredNullable var volumeUnitRaw: String?
    var performanceNotes: String
    @HistoricalRequiredNullable var plannedSetsJSON: String?
    @HistoricalRequiredNullable var hasManuallyReducedSets: Bool?
    @HistoricalRequiredNullable var planPatternRaw: String?
    @HistoricalRequiredNullable var patternSourceRaw: String?
    @HistoricalRequiredNullable var feelingRaw: String?
    @HistoricalRequiredNullable var exerciseStartedAtReferenceSeconds: Double?
    @HistoricalRequiredNullable var exerciseCompletedAtReferenceSeconds: Double?
    @HistoricalRequiredNullable var bodyWeightKgSnapshot: Double?
    @HistoricalRequiredNullable var bodyWeightSnapshotSourceDateReferenceSeconds: Double?
    @HistoricalRequiredNullable var equipmentSnapshot: String?

    init(_ value: SessionExercise) {
        id = value.id
        sessionID = value.sessionID
        exerciseID = value.exerciseID
        exerciseName = value.exerciseName
        order = value.order
        targetSets = value.targetSets
        minReps = value.minReps
        maxReps = value.maxReps
        targetWeight = value.targetWeight
        restSeconds = value.restSeconds
        muscleGroup = value.muscleGroup
        exerciseNotes = value.exerciseNotes
        referenceURL = value.referenceURL
        _volumeUnitRaw = HistoricalRequiredNullable(wrappedValue: value.volumeUnitRaw)
        performanceNotes = value.performanceNotes
        _plannedSetsJSON = HistoricalRequiredNullable(wrappedValue: value.plannedSetsJSON)
        _hasManuallyReducedSets = HistoricalRequiredNullable(wrappedValue: value.hasManuallyReducedSets)
        _planPatternRaw = HistoricalRequiredNullable(wrappedValue: value.planPatternRaw)
        _patternSourceRaw = HistoricalRequiredNullable(wrappedValue: value.patternSourceRaw)
        _feelingRaw = HistoricalRequiredNullable(wrappedValue: value.feelingRaw)
        _exerciseStartedAtReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.exerciseStartedAt?.timeIntervalSinceReferenceDate)
        _exerciseCompletedAtReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.exerciseCompletedAt?.timeIntervalSinceReferenceDate)
        _bodyWeightKgSnapshot = HistoricalRequiredNullable(wrappedValue: value.bodyWeightKgSnapshot)
        _bodyWeightSnapshotSourceDateReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.bodyWeightSnapshotSourceDate?.timeIntervalSinceReferenceDate)
        _equipmentSnapshot = HistoricalRequiredNullable(wrappedValue: value.equipmentSnapshot)
    }
}

struct HistoricalBlankSetState: Codable, Equatable {
    var id: UUID
    var sessionID: UUID
    var sessionExerciseID: UUID
    var exerciseID: UUID
    var setNumber: Int
    @HistoricalRequiredNullable var reductionOrder: Int?
    var targetWeight: Double
    var targetReps: Int
    var actualWeight: Double
    var actualReps: Int
    @HistoricalRequiredNullable var rir: Int?
    var isWarmup: Bool
    var isCompleted: Bool
    @HistoricalRequiredNullable var startedAtReferenceSeconds: Double?
    @HistoricalRequiredNullable var completedAtReferenceSeconds: Double?
    @HistoricalRequiredNullable var restStartedAtReferenceSeconds: Double?
    @HistoricalRequiredNullable var restEndedAtReferenceSeconds: Double?
    @HistoricalRequiredNullable var restDurationSeconds: Int?
    @HistoricalRequiredNullable var targetWeightSideRaw: String?
    @HistoricalRequiredNullable var targetRepsSideRaw: String?
    @HistoricalRequiredNullable var actualWeightSideRaw: String?
    @HistoricalRequiredNullable var actualRepsSideRaw: String?
    @HistoricalRequiredNullable var actualEntrySourceRaw: String?
    @HistoricalRequiredNullable var sourceHistorySetID: UUID?
    @HistoricalRequiredNullable var actualWeightIsBlank: Bool?

    init(_ value: SetLog) {
        id = value.id
        sessionID = value.sessionID
        sessionExerciseID = value.sessionExerciseID
        exerciseID = value.exerciseID
        setNumber = value.setNumber
        _reductionOrder = HistoricalRequiredNullable(wrappedValue: value.reductionOrder)
        targetWeight = value.targetWeight
        targetReps = value.targetReps
        actualWeight = value.actualWeight
        actualReps = value.actualReps
        _rir = HistoricalRequiredNullable(wrappedValue: value.rir)
        isWarmup = value.isWarmup
        isCompleted = value.isCompleted
        _startedAtReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.startedAt?.timeIntervalSinceReferenceDate)
        _completedAtReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.completedAt?.timeIntervalSinceReferenceDate)
        _restStartedAtReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.restStartedAt?.timeIntervalSinceReferenceDate)
        _restEndedAtReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.restEndedAt?.timeIntervalSinceReferenceDate)
        _restDurationSeconds = HistoricalRequiredNullable(wrappedValue: value.restDurationSeconds)
        _targetWeightSideRaw = HistoricalRequiredNullable(wrappedValue: value.targetWeightSideRaw)
        _targetRepsSideRaw = HistoricalRequiredNullable(wrappedValue: value.targetRepsSideRaw)
        _actualWeightSideRaw = HistoricalRequiredNullable(wrappedValue: value.actualWeightSideRaw)
        _actualRepsSideRaw = HistoricalRequiredNullable(wrappedValue: value.actualRepsSideRaw)
        _actualEntrySourceRaw = HistoricalRequiredNullable(wrappedValue: value.actualEntrySourceRaw)
        _sourceHistorySetID = HistoricalRequiredNullable(wrappedValue: value.sourceHistorySetID)
        _actualWeightIsBlank = HistoricalRequiredNullable(wrappedValue: value.actualWeightIsBlank)
    }
}

struct HistoricalCorrectionCatalogState: Codable, Equatable {
    var id: UUID
    var name: String
    var muscleGroup: String
    var equipment: String
    var defaultRestSeconds: Int
    var createdAtReferenceSeconds: Double
    var isBuiltIn: Bool
    var isArchived: Bool
    var notes: String
    var referenceURL: String
    @HistoricalRequiredNullable var volumeUnitRaw: String?
    @HistoricalRequiredNullable var terminologyCanonicalID: String?
    @HistoricalRequiredNullable var terminologyStandardNameZH: String?
    @HistoricalRequiredNullable var terminologyStandardNameEN: String?
    @HistoricalRequiredNullable var terminologyReviewStatusRaw: String?
    @HistoricalRequiredNullable var terminologyDecisionRaw: String?
    @HistoricalRequiredNullable var terminologyConfidenceRaw: String?
    @HistoricalRequiredNullable var terminologyMergeGroup: String?
    @HistoricalRequiredNullable var terminologyReviewNote: String?
    @HistoricalRequiredNullable var terminologyCatalogVersion: String?
    @HistoricalRequiredNullable var terminologyReviewedAtReferenceSeconds: Double?
    var updatedAtReferenceSeconds: Double

    init(_ value: Exercise) {
        id = value.id
        name = value.name
        muscleGroup = value.muscleGroup
        equipment = value.equipment
        defaultRestSeconds = value.defaultRestSeconds
        createdAtReferenceSeconds = value.createdAt.timeIntervalSinceReferenceDate
        isBuiltIn = value.isBuiltIn
        isArchived = value.isArchived
        notes = value.notes
        referenceURL = value.referenceURL
        _volumeUnitRaw = HistoricalRequiredNullable(wrappedValue: value.volumeUnitRaw)
        _terminologyCanonicalID = HistoricalRequiredNullable(wrappedValue: value.terminologyCanonicalID)
        _terminologyStandardNameZH = HistoricalRequiredNullable(wrappedValue: value.terminologyStandardNameZH)
        _terminologyStandardNameEN = HistoricalRequiredNullable(wrappedValue: value.terminologyStandardNameEN)
        _terminologyReviewStatusRaw = HistoricalRequiredNullable(wrappedValue: value.terminologyReviewStatusRaw)
        _terminologyDecisionRaw = HistoricalRequiredNullable(wrappedValue: value.terminologyDecisionRaw)
        _terminologyConfidenceRaw = HistoricalRequiredNullable(wrappedValue: value.terminologyConfidenceRaw)
        _terminologyMergeGroup = HistoricalRequiredNullable(wrappedValue: value.terminologyMergeGroup)
        _terminologyReviewNote = HistoricalRequiredNullable(wrappedValue: value.terminologyReviewNote)
        _terminologyCatalogVersion = HistoricalRequiredNullable(wrappedValue: value.terminologyCatalogVersion)
        _terminologyReviewedAtReferenceSeconds = HistoricalRequiredNullable(wrappedValue: value.terminologyReviewedAt?.timeIntervalSinceReferenceDate)
        updatedAtReferenceSeconds = value.updatedAt.timeIntervalSinceReferenceDate
    }
}

enum HistoricalPlateWeightConvention: String, Codable {
    case platesPerSideExcludingMachine
}

struct HistoricalConfirmedPlateActual: Codable, Equatable {
    var setID: UUID
    var kilogramsPerSide: Double
    var reps: Int
}

struct HistoricalBlankActualCorrectionPacket: Codable {
    var version: Int
    var weightConvention: HistoricalPlateWeightConvention
    var expectedSession: HistoricalCorrectionSessionState
    var expectedSnapshot: HistoricalBlankSnapshotState
    var expectedSets: [HistoricalBlankSetState]
    var existingTarget: HistoricalCorrectionCatalogState
    var confirmedActuals: [HistoricalConfirmedPlateActual]
    var confirmationReference: String
    var correctionNote: String
}

extension HistoricalExerciseCorrectionService {
    static func apply(_ data: Data, in context: ModelContext,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> HistoricalExerciseCorrectionResult {
        let decoder = JSONDecoder()
        switch try decoder.decode(HistoricalCorrectionVersion.self, from: data).version {
        case 1:
            return try apply(decoder.decode(HistoricalExerciseCorrectionPacket.self, from: data), in: context, save: save)
        case 2:
            return try apply(decoder.decode(HistoricalBlankActualCorrectionPacket.self, from: data), in: context, save: save)
        default:
            throw HistoricalExerciseCorrectionError.invalidPacket
        }
    }

    static func apply(_ packet: HistoricalBlankActualCorrectionPacket, in context: ModelContext,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> HistoricalExerciseCorrectionResult {
        let before = packet.expectedSnapshot
        let sessionState = packet.expectedSession
        let target = packet.existingTarget
        let oldSets = packet.expectedSets.sorted { $0.id.uuidString < $1.id.uuidString }
        let actualIDs = Set(packet.confirmedActuals.map(\.setID))
        guard packet.version == 2,
              packet.weightConvention == .platesPerSideExcludingMachine,
              !packet.confirmationReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !packet.correctionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              sessionState.statusRaw == WorkoutSessionStatus.completed.rawValue,
              let localDay = sessionState.trainingLocalDay,
              let zoneName = sessionState.trainingTimeZoneIdentifier,
              let zone = TimeZone(identifier: zoneName), MealLocalDay.date(localDay, timeZone: zone) != nil,
              before.sessionID == sessionState.id, before.targetSets == 4,
              before.exerciseID != target.id,
              before.exerciseName.caseInsensitiveCompare(target.name) != .orderedSame,
              before.muscleGroup == target.muscleGroup,
              before.volumeUnitRaw == nil || before.volumeUnitRaw == ExerciseVolumeUnit.kilogram.rawValue,
              target.volumeUnitRaw == nil || target.volumeUnitRaw == ExerciseVolumeUnit.kilogram.rawValue,
              !target.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              before.hasManuallyReducedSets != true, before.exerciseCompletedAtReferenceSeconds == nil,
              oldSets.count == 4, Set(oldSets.map(\.id)).count == 4,
              Set(oldSets.map(\.setNumber)) == Set(1...4),
              packet.confirmedActuals.count == 4, actualIDs == Set(oldSets.map(\.id)), actualIDs.count == 4,
              packet.confirmedActuals.allSatisfy({ $0.kilogramsPerSide.isFinite && $0.kilogramsPerSide > 0 && $0.reps > 0 }),
              oldSets.allSatisfy({
                  $0.sessionID == sessionState.id && $0.sessionExerciseID == before.id
                      && $0.exerciseID == before.exerciseID && $0.targetWeight.isFinite
                      && $0.actualEntrySourceRaw == WorkoutActualEntrySource.blank.rawValue
                      && $0.actualWeightIsBlank == true && $0.actualWeight == 0 && $0.actualReps == 0
                      && !$0.isCompleted && !$0.isWarmup && $0.rir == nil && $0.reductionOrder == nil
                      && $0.sourceHistorySetID == nil && $0.startedAtReferenceSeconds == nil
                      && $0.completedAtReferenceSeconds == nil && $0.restStartedAtReferenceSeconds == nil
                      && $0.restEndedAtReferenceSeconds == nil && $0.restDurationSeconds == nil
              }) else { throw HistoricalExerciseCorrectionError.invalidPacket }
        guard !context.hasChanges else { throw HistoricalExerciseCorrectionError.pendingChanges }

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).filter { $0.id == sessionState.id }
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.id == before.id }
        guard sessions.count == 1, let session = sessions.first,
              HistoricalCorrectionSessionState(session) == sessionState,
              snapshots.count == 1, let snapshot = snapshots.first else {
            throw HistoricalExerciseCorrectionError.changedRecord
        }
        let allLogs = try context.fetch(FetchDescriptor<SetLog>())
        let logs = allLogs.filter { $0.sessionExerciseID == before.id }
        guard logs.count == 4, allLogs.filter({ actualIDs.contains($0.id) }).count == 4 else {
            throw HistoricalExerciseCorrectionError.changedRecord
        }
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        let targets = catalog.filter { $0.id == target.id }
        let targetName = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sameNames = catalog.filter {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(targetName) == .orderedSame
        }
        guard targets.count == 1, let existing = targets.first, !existing.isArchived,
              HistoricalCorrectionCatalogState(existing) == target,
              sameNames.count == 1, sameNames.first?.id == target.id else {
            throw HistoricalExerciseCorrectionError.conflictingTarget
        }

        let actuals = Dictionary(uniqueKeysWithValues: packet.confirmedActuals.map { ($0.setID, $0) })
        let values = oldSets.sorted { $0.setNumber < $1.setNumber }.map {
            let actual = actuals[$0.id]!
            return "\(actual.kilogramsPerSide)×\(actual.reps)"
        }.joined(separator: "、")
        let annotation = "本人确认动作更正为「\(target.name)」；原计划动作「\(before.exerciseName)」。实际每侧挂片 kg、不含机器空载：\(values)。RIR、组起止与休息未知；原计划处方保留。确认依据：\(packet.confirmationReference)。\(packet.correctionNote)"
        var desired = before
        desired.exerciseID = target.id
        desired.exerciseName = target.name
        desired.performanceNotes = before.performanceNotes.isEmpty ? annotation : before.performanceNotes + "\n" + annotation
        let desiredSets = oldSets.map { old -> HistoricalBlankSetState in
            let actual = actuals[old.id]!
            var value = old
            value.exerciseID = target.id
            value.actualWeight = actual.kilogramsPerSide
            value.actualReps = actual.reps
            value.actualWeightSideRaw = MeasurementSide.single.rawValue
            value.actualEntrySourceRaw = WorkoutActualEntrySource.manual.rawValue
            value.actualWeightIsBlank = false
            value.isCompleted = true
            return value
        }
        let current = HistoricalBlankSnapshotState(snapshot)
        let currentSets = logs.map(HistoricalBlankSetState.init).sorted { $0.id.uuidString < $1.id.uuidString }
        let result = HistoricalExerciseCorrectionResult(applied: current != desired || currentSets != desiredSets,
            sessionID: session.id, snapshotID: snapshot.id, targetExerciseID: target.id, preservedSetCount: 4)
        if !result.applied { return result }
        guard current == before, currentSets == oldSets else { throw HistoricalExerciseCorrectionError.changedRecord }

        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        snapshot.exerciseID = desired.exerciseID
        snapshot.exerciseName = desired.exerciseName
        snapshot.performanceNotes = desired.performanceNotes
        let desiredByID = Dictionary(uniqueKeysWithValues: desiredSets.map { ($0.id, $0) })
        for log in logs {
            let value = desiredByID[log.id]!
            log.exerciseID = value.exerciseID
            log.actualWeight = value.actualWeight
            log.actualReps = value.actualReps
            log.actualWeightSideRaw = value.actualWeightSideRaw
            log.actualEntrySourceRaw = value.actualEntrySourceRaw
            log.actualWeightIsBlank = value.actualWeightIsBlank
            log.isCompleted = value.isCompleted
        }
        do { try save(context) }
        catch {
            snapshot.exerciseID = current.exerciseID
            snapshot.exerciseName = current.exerciseName
            snapshot.performanceNotes = current.performanceNotes
            let originalByID = Dictionary(uniqueKeysWithValues: currentSets.map { ($0.id, $0) })
            for log in logs {
                let value = originalByID[log.id]!
                log.exerciseID = value.exerciseID
                log.actualWeight = value.actualWeight
                log.actualReps = value.actualReps
                log.actualWeightSideRaw = value.actualWeightSideRaw
                log.actualEntrySourceRaw = value.actualEntrySourceRaw
                log.actualWeightIsBlank = value.actualWeightIsBlank
                log.isCompleted = value.isCompleted
            }
            context.rollback()
            throw error
        }
        return result
    }
}
