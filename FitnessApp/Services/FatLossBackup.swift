import Foundation
import SwiftData

/// Schema 14 extension. Missing collections decode as empty for older backups.
struct FatLossBackup: Codable {
    var programs: [FatLossProgramRecord]?
    var targetRevisions: [ProgramTargetRevisionRecord]?
    var recipes: [RecipeVersionRecord]?
    var plannedMeals: [PlannedMealRecord]?
    var dailyLogs: [ProgramDailyLogRecord]?
    var healthRecords: [ProgramHealthRecordRecord]?
    var weeklyReviews: [ProgramWeeklyReviewRecord]?
    var workoutLinks: [ProgramWorkoutLinkRecord]?
    var trainingPreferences: [TrainingPreferenceRevisionRecord]?
    var trainingPrograms: [TrainingProgramRevisionRecord]?
    var total: Int {
        (programs?.count ?? 0) + (targetRevisions?.count ?? 0) + (recipes?.count ?? 0) + (plannedMeals?.count ?? 0) + (dailyLogs?.count ?? 0) + (healthRecords?.count ?? 0) + (weeklyReviews?.count ?? 0) + (workoutLinks?.count ?? 0) + (trainingPreferences?.count ?? 0) + (trainingPrograms?.count ?? 0)
    }
}

struct TrainingPreferenceRevisionRecord: Codable {
    let id: UUID
    let revisionCode: String
    let revision: Int
    let effectiveAt: Date
    let createdAt: Date
    let reason: String
    let snapshotJSON: String

    init(_ model: TrainingPreferenceRevision) {
        id = model.id
        revisionCode = model.revisionCode
        revision = model.revision
        effectiveAt = model.effectiveAt
        createdAt = model.createdAt
        reason = model.reason
        snapshotJSON = model.snapshotJSON
    }

    @MainActor func makeModel() -> TrainingPreferenceRevision {
        TrainingPreferenceRevision(
            id: id,
            revisionCode: revisionCode,
            revision: revision,
            effectiveAt: effectiveAt,
            createdAt: createdAt,
            reason: reason,
            snapshotJSON: snapshotJSON
        )
    }
}

struct TrainingProgramRevisionRecord: Codable {
    let id: UUID
    let programID: UUID?
    let preferenceRevisionID: UUID
    let preferenceRevisionCode: String
    let revision: Int
    let effectiveDate: Date
    let createdAt: Date
    let reason: String
    let snapshotJSON: String

    init(_ model: TrainingProgramRevision) {
        id = model.id
        programID = model.programID
        preferenceRevisionID = model.preferenceRevisionID
        preferenceRevisionCode = model.preferenceRevisionCode
        revision = model.revision
        effectiveDate = model.effectiveDate
        createdAt = model.createdAt
        reason = model.reason
        snapshotJSON = model.snapshotJSON
    }

    @MainActor func makeModel() -> TrainingProgramRevision {
        TrainingProgramRevision(
            id: id,
            programID: programID,
            preferenceRevisionID: preferenceRevisionID,
            preferenceRevisionCode: preferenceRevisionCode,
            revision: revision,
            effectiveDate: effectiveDate,
            createdAt: createdAt,
            reason: reason,
            snapshotJSON: snapshotJSON
        )
    }
}

struct FatLossProgramRecord: Codable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let timeZoneIdentifier: String
    let reportedStartWeightKg: Double
    let targetWeightKg: Double
    let statusRaw: String
    let createdAt: Date
    init(_ model: FatLossProgram) {
        id = model.id
        title = model.title
        startDate = model.startDate
        endDate = model.endDate
        timeZoneIdentifier = model.timeZoneIdentifier
        reportedStartWeightKg = model.reportedStartWeightKg
        targetWeightKg = model.targetWeightKg
        statusRaw = model.statusRaw
        createdAt = model.createdAt
    }
    @MainActor func makeModel() throws -> FatLossProgram {
        let model = FatLossProgram(id: id, startDate: startDate, endDate: endDate, reportedStartWeightKg: reportedStartWeightKg, targetWeightKg: targetWeightKg)
        model.id = id
        model.title = title
        model.startDate = startDate
        model.endDate = endDate
        model.timeZoneIdentifier = timeZoneIdentifier
        model.reportedStartWeightKg = reportedStartWeightKg
        model.targetWeightKg = targetWeightKg
        model.statusRaw = statusRaw
        model.createdAt = createdAt
        return model
    }
}

struct ProgramTargetRevisionRecord: Codable {
    let id: UUID
    let programID: UUID
    let effectiveDate: Date
    let createdAt: Date
    let reason: String
    let sourceNote: String
    let isNutritionConfirmed: Bool
    let targetWeightKg: Double?
    let calories: Int?
    let proteinGrams: Int?
    let carbsGrams: Int?
    let fatGrams: Int?
    let steps: Int?
    init(_ model: ProgramTargetRevision) {
        id = model.id
        programID = model.programID
        effectiveDate = model.effectiveDate
        createdAt = model.createdAt
        reason = model.reason
        sourceNote = model.sourceNote
        isNutritionConfirmed = model.isNutritionConfirmed
        targetWeightKg = model.targetWeightKg
        calories = model.calories
        proteinGrams = model.proteinGrams
        carbsGrams = model.carbsGrams
        fatGrams = model.fatGrams
        steps = model.steps
    }
    @MainActor func makeModel() throws -> ProgramTargetRevision {
        let model = ProgramTargetRevision(programID: programID, effectiveDate: effectiveDate, reason: reason)
        model.id = id
        model.programID = programID
        model.effectiveDate = effectiveDate
        model.createdAt = createdAt
        model.reason = reason
        model.sourceNote = sourceNote
        model.isNutritionConfirmed = isNutritionConfirmed
        model.targetWeightKg = targetWeightKg
        model.calories = calories
        model.proteinGrams = proteinGrams
        model.carbsGrams = carbsGrams
        model.fatGrams = fatGrams
        model.steps = steps
        return model
    }
}

struct RecipeVersionRecord: Codable {
    let id: UUID
    let catalogKey: String
    let version: Int
    let draftJSON: String
    let createdAt: Date
    init(_ model: RecipeVersion) {
        id = model.id
        catalogKey = model.catalogKey
        version = model.version
        draftJSON = model.draftJSON
        createdAt = model.createdAt
    }
    @MainActor func makeModel() throws -> RecipeVersion {
        let model = try RecipeVersion(draft: JSONDecoder().decode(RecipeDraft.self, from: Data(draftJSON.utf8)), version: version)
        model.id = id
        model.catalogKey = catalogKey
        model.version = version
        model.draftJSON = draftJSON
        model.createdAt = createdAt
        return model
    }
}

struct PlannedMealRecord: Codable {
    let id: UUID
    let programID: UUID
    let date: Date
    let mealTypeRaw: String
    let recipeID: UUID
    let recipeSnapshotJSON: String
    let isCurrent: Bool
    let previousPlanID: UUID?
    let statusRaw: String
    let changeReason: String
    let createdAt: Date
    init(_ model: PlannedMeal) {
        id = model.id
        programID = model.programID
        date = model.date
        mealTypeRaw = model.mealTypeRaw
        recipeID = model.recipeID
        recipeSnapshotJSON = model.recipeSnapshotJSON
        isCurrent = model.isCurrent
        previousPlanID = model.previousPlanID
        statusRaw = model.statusRaw
        changeReason = model.changeReason
        createdAt = model.createdAt
    }
    @MainActor func makeModel() throws -> PlannedMeal {
        let model = PlannedMeal(programID: programID, date: date, mealType: MealType(rawValue: mealTypeRaw) ?? .snack, recipe: try RecipeVersion(draft: JSONDecoder().decode(RecipeDraft.self, from: Data(recipeSnapshotJSON.utf8))))
        model.id = id
        model.programID = programID
        model.date = date
        model.mealTypeRaw = mealTypeRaw
        model.recipeID = recipeID
        model.recipeSnapshotJSON = recipeSnapshotJSON
        model.isCurrent = isCurrent
        model.previousPlanID = previousPlanID
        model.statusRaw = statusRaw
        model.changeReason = changeReason
        model.createdAt = createdAt
        return model
    }
}

struct ProgramDailyLogRecord: Codable {
    let id: UUID
    let programID: UUID
    let date: Date
    let steps: Int?
    let sleepHours: Double?
    let bloatingScore: Int?
    let explicitlyNoWorkout: Bool
    let notes: String
    let updatedAt: Date
    init(_ model: ProgramDailyLog) {
        id = model.id
        programID = model.programID
        date = model.date
        steps = model.steps
        sleepHours = model.sleepHours
        bloatingScore = model.bloatingScore
        explicitlyNoWorkout = model.explicitlyNoWorkout
        notes = model.notes
        updatedAt = model.updatedAt
    }
    @MainActor func makeModel() throws -> ProgramDailyLog {
        let model = ProgramDailyLog(programID: programID, date: date)
        model.id = id
        model.programID = programID
        model.date = date
        model.steps = steps
        model.sleepHours = sleepHours
        model.bloatingScore = bloatingScore
        model.explicitlyNoWorkout = explicitlyNoWorkout
        model.notes = notes
        model.updatedAt = updatedAt
        return model
    }
}

struct ProgramHealthRecordRecord: Codable {
    let id: UUID
    let programID: UUID
    let metric: String
    let value: Double?
    let unit: String?
    let measuredAt: Date?
    let notes: String
    let source: String
    let createdAt: Date
    init(_ model: ProgramHealthRecord) {
        id = model.id
        programID = model.programID
        metric = model.metric
        value = model.value
        unit = model.unit
        measuredAt = model.measuredAt
        notes = model.notes
        source = model.source
        createdAt = model.createdAt
    }
    @MainActor func makeModel() throws -> ProgramHealthRecord {
        let model = ProgramHealthRecord(programID: programID, metric: metric)
        model.id = id
        model.programID = programID
        model.metric = metric
        model.value = value
        model.unit = unit
        model.measuredAt = measuredAt
        model.notes = notes
        model.source = source
        model.createdAt = createdAt
        return model
    }
}

struct ProgramWeeklyReviewRecord: Codable {
    let id: UUID
    let programID: UUID
    let weekStart: Date
    let weekEnd: Date
    let snapshotJSON: String
    let notes: String
    let nextAction: String
    let previousReviewID: UUID?
    let createdAt: Date
    init(_ model: ProgramWeeklyReview) {
        id = model.id
        programID = model.programID
        weekStart = model.weekStart
        weekEnd = model.weekEnd
        snapshotJSON = model.snapshotJSON
        notes = model.notes
        nextAction = model.nextAction
        previousReviewID = model.previousReviewID
        createdAt = model.createdAt
    }
    @MainActor func makeModel() throws -> ProgramWeeklyReview {
        let model = ProgramWeeklyReview(programID: programID, weekStart: weekStart, weekEnd: weekEnd)
        model.id = id
        model.programID = programID
        model.weekStart = weekStart
        model.weekEnd = weekEnd
        model.snapshotJSON = snapshotJSON
        model.notes = notes
        model.nextAction = nextAction
        model.previousReviewID = previousReviewID
        model.createdAt = createdAt
        return model
    }
}

struct ProgramWorkoutLinkRecord: Codable {
    let id: UUID
    let programID: UUID
    let scheduledWorkoutID: UUID
    let trainingProgramRevisionID: UUID?
    let templateCode: String
    let originalDate: Date
    let createdAt: Date
    init(_ model: ProgramWorkoutLink) {
        id = model.id
        programID = model.programID
        scheduledWorkoutID = model.scheduledWorkoutID
        trainingProgramRevisionID = model.trainingProgramRevisionID
        templateCode = model.templateCode
        originalDate = model.originalDate
        createdAt = model.createdAt
    }
    @MainActor func makeModel() throws -> ProgramWorkoutLink {
        let model = ProgramWorkoutLink(programID: programID, scheduledWorkoutID: scheduledWorkoutID, templateCode: templateCode, originalDate: originalDate)
        model.id = id
        model.programID = programID
        model.scheduledWorkoutID = scheduledWorkoutID
        model.trainingProgramRevisionID = trainingProgramRevisionID
        model.templateCode = templateCode
        model.originalDate = originalDate
        model.createdAt = createdAt
        return model
    }
}

@MainActor
enum FatLossBackupService {
    static func isRegistered<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> Bool {
        context.container.schema.entities.contains { $0.name == String(describing: type) }
    }

    static func export(in context: ModelContext) throws -> FatLossBackup? {
        guard isRegistered(FatLossProgram.self, in: context) else { return nil }
        return FatLossBackup(
            programs: try context.fetch(FetchDescriptor<FatLossProgram>()).map(FatLossProgramRecord.init),
            targetRevisions: try context.fetch(FetchDescriptor<ProgramTargetRevision>()).map(ProgramTargetRevisionRecord.init),
            recipes: try context.fetch(FetchDescriptor<RecipeVersion>()).map(RecipeVersionRecord.init),
            plannedMeals: try context.fetch(FetchDescriptor<PlannedMeal>()).map(PlannedMealRecord.init),
            dailyLogs: try context.fetch(FetchDescriptor<ProgramDailyLog>()).map(ProgramDailyLogRecord.init),
            healthRecords: try context.fetch(FetchDescriptor<ProgramHealthRecord>()).map(ProgramHealthRecordRecord.init),
            weeklyReviews: try context.fetch(FetchDescriptor<ProgramWeeklyReview>()).map(ProgramWeeklyReviewRecord.init),
            workoutLinks: try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).map(ProgramWorkoutLinkRecord.init),
            trainingPreferences: isRegistered(TrainingPreferenceRevision.self, in: context) ? try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).map(TrainingPreferenceRevisionRecord.init) : nil,
            trainingPrograms: isRegistered(TrainingProgramRevision.self, in: context) ? try context.fetch(FetchDescriptor<TrainingProgramRevision>()).map(TrainingProgramRevisionRecord.init) : nil
        )
    }

    static func validate(_ backup: FatLossBackup?, in context: ModelContext) throws {
        guard let backup, backup.total > 0 else { return }
        guard isRegistered(FatLossProgram.self, in: context) else { throw invalid("当前数据库未注册减脂记录类型。") }
        guard isRegistered(ProgramTargetRevision.self, in: context) else { throw invalid("当前数据库未注册减脂记录类型。") }
        guard isRegistered(RecipeVersion.self, in: context) else { throw invalid("当前数据库未注册减脂记录类型。") }
        guard isRegistered(PlannedMeal.self, in: context) else { throw invalid("当前数据库未注册减脂记录类型。") }
        guard isRegistered(ProgramDailyLog.self, in: context) else { throw invalid("当前数据库未注册减脂记录类型。") }
        guard isRegistered(ProgramHealthRecord.self, in: context) else { throw invalid("当前数据库未注册减脂记录类型。") }
        guard isRegistered(ProgramWeeklyReview.self, in: context) else { throw invalid("当前数据库未注册减脂记录类型。") }
        guard isRegistered(ProgramWorkoutLink.self, in: context) else { throw invalid("当前数据库未注册减脂记录类型。") }
        if !(backup.trainingPreferences ?? []).isEmpty || !(backup.trainingPrograms ?? []).isEmpty {
            guard isRegistered(TrainingPreferenceRevision.self, in: context),
                  isRegistered(TrainingProgramRevision.self, in: context) else {
                throw invalid("当前数据库未注册训练偏好或编排版本类型。")
            }
        }
        let idGroups: [[UUID]] = [
            (backup.programs ?? []).map(\.id),
            (backup.targetRevisions ?? []).map(\.id),
            (backup.recipes ?? []).map(\.id),
            (backup.plannedMeals ?? []).map(\.id),
            (backup.dailyLogs ?? []).map(\.id),
            (backup.healthRecords ?? []).map(\.id),
            (backup.weeklyReviews ?? []).map(\.id),
            (backup.workoutLinks ?? []).map(\.id),
            (backup.trainingPreferences ?? []).map(\.id),
            (backup.trainingPrograms ?? []).map(\.id)
        ]
        guard idGroups.allSatisfy({ Set($0).count == $0.count }) else { throw invalid("减脂备份包含重复标识。") }
        for p in backup.programs ?? [] {
            guard p.endDate > p.startDate, p.reportedStartWeightKg.isFinite, p.reportedStartWeightKg > 0,
                  p.targetWeightKg.isFinite, p.targetWeightKg > 0,
                  TimeZone(identifier: p.timeZoneIdentifier) != nil else { throw invalid("减脂周期或体重无效。") }
        }
        let existingPrograms = try context.fetch(FetchDescriptor<FatLossProgram>())
        let bounds = Dictionary(existingPrograms.map { ($0.id, ($0.startDate, $0.endDate)) }
            + (backup.programs ?? []).map { ($0.id, ($0.startDate, $0.endDate)) }, uniquingKeysWith: { first, _ in first })
        for t in backup.targetRevisions ?? [] {
            guard [t.calories, t.proteinGrams, t.carbsGrams, t.fatGrams].allSatisfy({ $0.map { (1...20_000).contains($0) } ?? true }),
                  t.steps.map({ (0...100_000).contains($0) }) ?? true,
                  t.targetWeightKg.map({ $0.isFinite && (20...400).contains($0) }) ?? true else { throw invalid("减脂目标包含无效数值。") }
            guard !t.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !t.isNutritionConfirmed || !t.sourceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw invalid("确认营养目标必须记录医生或营养师建议来源，目标调整必须记录原因。")
            }
            guard let period = bounds[t.programID],
                  FatLossCalendar.day(t.effectiveDate) >= FatLossCalendar.day(period.0),
                  FatLossCalendar.day(t.effectiveDate) <= FatLossCalendar.day(period.1) else {
                throw invalid("目标生效日期需在对应减脂周期内。")
            }
        }
        for recipe in backup.recipes ?? [] {
            guard recipe.version > 0 else { throw invalid("食谱版本无效。") }
            try validateRecipeJSON(recipe.draftJSON)
        }
        var currentSlots = Set<String>()
        let existingPlans = try context.fetch(FetchDescriptor<PlannedMeal>())
        for meal in backup.plannedMeals ?? [] {
            guard MealType(rawValue: meal.mealTypeRaw) != nil,
                  ["planned", "logged", "skipped", "replaced"].contains(meal.statusRaw) else { throw invalid("餐单状态或餐次无效。") }
            try validateRecipeJSON(meal.recipeSnapshotJSON)
            if meal.isCurrent {
                let slot = "\(meal.programID)-\(FatLossCalendar.label(meal.date))-\(meal.mealTypeRaw)"
                guard currentSlots.insert(slot).inserted else { throw invalid("同一餐次存在多个当前餐单。") }
                if existingPlans.contains(where: { $0.id == meal.id }) { continue }
                guard !existingPlans.contains(where: {
                    $0.isCurrent && $0.programID == meal.programID && $0.mealTypeRaw == meal.mealTypeRaw
                        && FatLossCalendar.sameDay($0.date, meal.date)
                }) else { throw invalid("备份餐单与现有当前餐单冲突，已停止导入。") }
            }
        }
        for log in backup.dailyLogs ?? [] {
            guard log.steps.map({ $0 >= 0 }) ?? true,
                  log.sleepHours.map({ $0.isFinite && (0...24).contains($0) }) ?? true,
                  log.bloatingScore.map({ (0...3).contains($0) }) ?? true else { throw invalid("每日记录数值无效。") }
        }
        for record in backup.healthRecords ?? [] {
            guard record.value.map({ $0.isFinite }) ?? true else { throw invalid("健康记录数值无效。") }
        }
        for review in backup.weeklyReviews ?? [] {
            guard review.weekEnd >= review.weekStart else { throw invalid("周复盘日期无效。") }
        }
        let existingPreferences = isRegistered(TrainingPreferenceRevision.self, in: context)
            ? try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()) : []
        let existingTraining = isRegistered(TrainingProgramRevision.self, in: context)
            ? try context.fetch(FetchDescriptor<TrainingProgramRevision>()) : []
        var preferenceIDsByCode: [String: Set<UUID>] = [:]
        for preference in existingPreferences {
            preferenceIDsByCode[preference.revisionCode, default: []].insert(preference.id)
        }
        for preference in backup.trainingPreferences ?? [] {
            guard preference.revision > 0, !preference.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let snapshot = try? JSONDecoder().decode(TrainingPreferenceSnapshot.self, from: Data(preference.snapshotJSON.utf8)),
                  snapshot.revisionCode == preference.revisionCode, snapshot.isValid else {
                throw invalid("训练偏好版本无效。")
            }
            let matchingIDs = preferenceIDsByCode[preference.revisionCode, default: []]
            guard matchingIDs.isEmpty || matchingIDs == Set([preference.id]) else {
                throw invalid("同一训练偏好版本号对应不同标识；请核对备份，不能合并导入。")
            }
            preferenceIDsByCode[preference.revisionCode, default: []].insert(preference.id)
            if let same = existingPreferences.first(where: { $0.id == preference.id }),
               same.snapshot != snapshot || same.revisionCode != preference.revisionCode
                || same.effectiveAt != preference.effectiveAt || same.revision != preference.revision || same.reason != preference.reason {
                throw invalid("同一偏好版本有不同内容；请保留两个备份并核对，不能覆盖。")
            }
        }
        let preferenceCodes = Dictionary(existingPreferences.map { ($0.id, $0.revisionCode) }
            + (backup.trainingPreferences ?? []).map { ($0.id, $0.revisionCode) }, uniquingKeysWith: { first, _ in first })
        let preferenceDates = Dictionary(existingPreferences.map { ($0.id, $0.effectiveAt) }
            + (backup.trainingPreferences ?? []).map { ($0.id, $0.effectiveAt) }, uniquingKeysWith: { first, _ in first })
        for revision in backup.trainingPrograms ?? [] {
            guard revision.revision > 0,
                  preferenceCodes[revision.preferenceRevisionID] == revision.preferenceRevisionCode,
                  (preferenceDates[revision.preferenceRevisionID].map { $0 <= revision.effectiveDate } ?? false),
                  !revision.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let snapshot = try? JSONDecoder().decode(TrainingProgramSnapshot.self, from: Data(revision.snapshotJSON.utf8)),
                  snapshot.preferenceRevisionCode == revision.preferenceRevisionCode, snapshot.isValid else {
                throw invalid("训练编排版本或偏好引用无效。")
            }
            if let same = existingTraining.first(where: { $0.id == revision.id }),
               same.snapshot != snapshot || same.preferenceRevisionID != revision.preferenceRevisionID
                || same.programID != revision.programID || same.effectiveDate != revision.effectiveDate
                || same.revision != revision.revision || same.reason != revision.reason {
                throw invalid("同一编排版本有不同内容；请保留两个备份并核对，不能覆盖。")
            }
        }
        let revisionPrograms = Dictionary(existingTraining.map { ($0.id, $0.programID) }
            + (backup.trainingPrograms ?? []).map { ($0.id, $0.programID) }, uniquingKeysWith: { first, _ in first })
        for link in backup.workoutLinks ?? [] {
            if let revisionID = link.trainingProgramRevisionID {
                guard revisionPrograms[revisionID] == .some(link.programID) else {
                    throw invalid("训练日程引用的编排版本不存在或不属于该周期。")
                }
            }
        }
        let programIDs = Set((backup.programs ?? []).map(\.id))
            .union(try context.fetch(FetchDescriptor<FatLossProgram>()).map(\.id))
        let referencedPrograms = (backup.targetRevisions ?? []).map(\.programID)
            + (backup.plannedMeals ?? []).map(\.programID) + (backup.dailyLogs ?? []).map(\.programID)
            + (backup.healthRecords ?? []).map(\.programID) + (backup.weeklyReviews ?? []).map(\.programID)
            + (backup.workoutLinks ?? []).map(\.programID)
            + (backup.trainingPrograms ?? []).compactMap(\.programID)
        guard referencedPrograms.allSatisfy(programIDs.contains) else { throw invalid("减脂备份包含不存在的周期引用。") }
        let recipeIDs = Set((backup.recipes ?? []).map(\.id))
            .union(try context.fetch(FetchDescriptor<RecipeVersion>()).map(\.id))
        guard (backup.plannedMeals ?? []).allSatisfy({ recipeIDs.contains($0.recipeID) }) else {
            throw invalid("餐单引用的食谱版本不存在。")
        }
    }

    static func validateRecipeJSON(_ json: String) throws {
        let recipe = try JSONDecoder().decode(RecipeDraft.self, from: Data(json.utf8))
        guard recipe.portions.isFinite, (0.01...1000).contains(recipe.portions),
              (0...1440).contains(recipe.cookingMinutes),
              recipe.ingredients.allSatisfy({ $0.referenceGrams.map { $0.isFinite && (0...100_000).contains($0) } ?? true }),
              [recipe.calories, recipe.proteinGrams, recipe.carbsGrams, recipe.fatGrams]
                .allSatisfy({ $0.map { (0...100_000).contains($0) } ?? true }) else {
            throw invalid("食谱份数、食材克重或营养值无效。")
        }
    }

    static func restore(_ backup: FatLossBackup?, in context: ModelContext) throws -> BackupImportSummary {
        guard let backup, backup.total > 0 else { return BackupImportSummary(imported: 0, skipped: 0) }
        var imported = 0
        var skipped = 0
        var preferenceIDs = Set(isRegistered(TrainingPreferenceRevision.self, in: context) ? try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).map(\.id) : [])
        for record in backup.trainingPreferences ?? [] {
            guard preferenceIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(record.makeModel())
            imported += 1
        }
        var trainingProgramIDs = Set(isRegistered(TrainingProgramRevision.self, in: context) ? try context.fetch(FetchDescriptor<TrainingProgramRevision>()).map(\.id) : [])
        for record in backup.trainingPrograms ?? [] {
            guard trainingProgramIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(record.makeModel())
            imported += 1
        }
        var programsIDs = Set(try context.fetch(FetchDescriptor<FatLossProgram>()).map(\.id))
        for record in backup.programs ?? [] {
            guard programsIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(try record.makeModel())
            imported += 1
        }
        var targetRevisionsIDs = Set(try context.fetch(FetchDescriptor<ProgramTargetRevision>()).map(\.id))
        for record in backup.targetRevisions ?? [] {
            guard targetRevisionsIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(try record.makeModel())
            imported += 1
        }
        var recipesIDs = Set(try context.fetch(FetchDescriptor<RecipeVersion>()).map(\.id))
        for record in backup.recipes ?? [] {
            guard recipesIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(try record.makeModel())
            imported += 1
        }
        var plannedMealsIDs = Set(try context.fetch(FetchDescriptor<PlannedMeal>()).map(\.id))
        for record in backup.plannedMeals ?? [] {
            guard plannedMealsIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(try record.makeModel())
            imported += 1
        }
        var dailyLogsIDs = Set(try context.fetch(FetchDescriptor<ProgramDailyLog>()).map(\.id))
        for record in backup.dailyLogs ?? [] {
            guard dailyLogsIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(try record.makeModel())
            imported += 1
        }
        var healthRecordsIDs = Set(try context.fetch(FetchDescriptor<ProgramHealthRecord>()).map(\.id))
        for record in backup.healthRecords ?? [] {
            guard healthRecordsIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(try record.makeModel())
            imported += 1
        }
        var weeklyReviewsIDs = Set(try context.fetch(FetchDescriptor<ProgramWeeklyReview>()).map(\.id))
        for record in backup.weeklyReviews ?? [] {
            guard weeklyReviewsIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(try record.makeModel())
            imported += 1
        }
        var workoutLinksIDs = Set(try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).map(\.id))
        for record in backup.workoutLinks ?? [] {
            guard workoutLinksIDs.insert(record.id).inserted else { skipped += 1; continue }
            context.insert(try record.makeModel())
            imported += 1
        }
        return BackupImportSummary(imported: imported, skipped: skipped)
    }

    private static func invalid(_ message: String) -> CocoaError {
        CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
