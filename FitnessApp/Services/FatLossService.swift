import Foundation
import SwiftData
import CryptoKit

enum FatLossError: LocalizedError {
    case invalidInput(String)
    case scheduleConflict
    case historicalMeal
    case unreadableRecipe
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        case .scheduleConflict: return "选定日期已有训练，请查看冲突并选择跳过这些日期。"
        case .historicalMeal: return "这份餐单已有实际记录。请修改实际吃下的内容，或先撤销实际记录。"
        case .unreadableRecipe: return "无法读取食谱，请保留原记录并重新选择可用食谱。"
        }
    }
}

struct ConfirmedTravelWeekPreview: Codable, Equatable {
    var programID: UUID
    var programCode: String
    var preferenceRevisionCode: String
    var pendingStrengthWorkouts: Int
    var pendingCardioWorkouts: Int
    var alreadyImportedCodes: [String]
    var conflictingDates: [String]
    var stateFingerprint: String
}

struct ConfirmedTravelWeekResult: Codable, Equatable {
    var programRevisionID: UUID
    var programCode: String
    var preferenceRevisionCode: String
    var importedSchedules: Int
}

@MainActor
enum ConfirmedTravelWeekService {
    static let startDate = FatLossCalendar.date(2026, 9, 21)
    static let programCode = "CUT-UPPER-TRAVEL-20260921-R1"

    /// Read-only approval payload. Missing or ambiguous authoritative state stops the import.
    static func preview(in context: ModelContext) throws -> ConfirmedTravelWeekPreview {
        let active = try context.fetch(FetchDescriptor<FatLossProgram>()).filter { $0.statusRaw == "active" }
        guard active.count == 1, let program = active.first,
              program.contains(startDate), program.contains(FatLossCalendar.adding(6, to: startDate)) else {
            throw FatLossError.invalidInput("需要唯一且覆盖旅行周的生效减脂周期；未创建或修改日程。")
        }
        let snapshot = FatLossCatalog.trainingProgram(preference: .upperBodyTravelWeek)
        let preferences = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>())
        let restoreDate = FatLossCalendar.adding(7, to: startDate)
        guard !preferences.contains(where: {
            $0.effectiveAt >= startDate && $0.effectiveAt <= restoreDate
                && ![TrainingPreferenceSnapshot.upperBodyTravelWeek.revisionCode,
                     TrainingPreferenceSnapshot.postTravelRestoration.revisionCode].contains($0.revisionCode)
        }) else { throw FatLossError.invalidInput("旅行周或恢复日已有其他偏好调整，需先确认冲突。") }
        for (expected, date) in [(TrainingPreferenceSnapshot.upperBodyTravelWeek, startDate),
                                 (.postTravelRestoration, FatLossCalendar.adding(7, to: startDate))] {
            let matching = preferences.filter { $0.revisionCode == expected.revisionCode }
            guard matching.count <= 1, matching.allSatisfy({ $0.snapshot == expected && FatLossCalendar.sameDay($0.effectiveAt, date) }) else {
                throw FatLossError.invalidInput("旅行周或恢复偏好版本存在冲突，请保留原数据并核对。")
            }
        }
        let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>()).filter { $0.programID == program.id }
        let matching = revisions.filter { $0.snapshot?.code == programCode }
        guard matching.count <= 1, matching.allSatisfy({
            $0.snapshot == snapshot && FatLossCalendar.sameDay($0.effectiveDate, startDate)
        }) else { throw FatLossError.invalidInput("旅行周编排已有不同内容或日期。") }
        if let existing = matching.first,
           !preferences.contains(where: { $0.id == existing.preferenceRevisionID && $0.revisionCode == snapshot.preferenceRevisionCode }) {
            throw FatLossError.invalidInput("旅行周编排关联的偏好无法核对。")
        }
        let end = FatLossCalendar.adding(7, to: startDate)
        let firstLocalDay = FatLossCalendar.label(startDate)
        let endLocalDay = FatLossCalendar.label(end)
        let allSchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        func sessionLocalDay(_ session: WorkoutSession) -> String {
            if let linked = allSchedules.first(where: { $0.id == session.scheduledWorkoutID }) {
                return TrainingScheduleDate.localDay(linked)
            }
            // A legacy/free session has no source-timezone metadata. Keep its
            // existing current-day display interpretation; never rewrite it.
            return TrainingLocalDate.key(session.plannedDate)
        }
        let schedules = allSchedules.filter {
            let day = TrainingScheduleDate.localDay($0)
            return day >= firstLocalDay && day < endLocalDay
        }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).filter {
            let day = sessionLocalDay($0)
            return day >= firstLocalDay && day < endLocalDay
        }
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).filter { $0.programID == program.id && $0.originalDate >= startDate && $0.originalDate < end }
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        for draft in snapshot.strengthWorkouts.flatMap(\.exercises) {
            let candidates = exercises.filter { !$0.isArchived && $0.name == draft.name && $0.equipment == draft.equipment && $0.volumeUnit.rawValue == draft.volumeUnitRaw }
            guard candidates.count <= 1 else { throw FatLossError.invalidInput("动作“\(draft.name)”身份不唯一，请先核对。") }
        }
        guard exercises.filter({ !$0.isArchived && $0.name == "轻松单车／椭圆机"
            && $0.equipment == "单车或椭圆机" && $0.volumeUnit == .second }).count <= 1 else {
            throw FatLossError.invalidInput("恢复有氧动作身份不唯一，请先核对。")
        }
        var imported: [String] = [], conflicts: [String] = []
        let days = snapshot.strengthWorkouts.map { ($0.weekday, $0.code) } + snapshot.cardioWorkouts.map { ($0.weekday, $0.code) }
        for (weekday, code) in days {
            let day = FatLossCalendar.adding(weekday - 2, to: startDate)
            let ownLinks = links.filter { $0.templateCode == code && FatLossCalendar.sameDay($0.originalDate, day) }
            guard ownLinks.count <= 1 else { throw FatLossError.invalidInput("旅行日程关联重复，请先核对。") }
            if let link = ownLinks.first {
                guard schedules.contains(where: { $0.id == link.scheduledWorkoutID }),
                      link.trainingProgramRevisionID == matching.first?.id else {
                    throw FatLossError.invalidInput("旅行日程关联缺失或已变化，请先核对。")
                }
                imported.append(code)
            } else if schedules.contains(where: { TrainingScheduleDate.localDay($0) == FatLossCalendar.label(day) })
                        || sessions.contains(where: { $0.status != .discarded && sessionLocalDay($0) == FatLossCalendar.label(day) }) {
                conflicts.append(FatLossCalendar.label(day))
            }
        }
        if revisions.contains(where: { $0.effectiveDate >= startDate && $0.effectiveDate < end && $0.snapshot?.code != programCode }) {
            conflicts.append("旅行周已有其他编排版本")
        }
        var state = ["\(program.id)|\(program.startDate.timeIntervalSince1970)|\(program.endDate.timeIntervalSince1970)"]
        state += preferences.map { "pref|\($0.id)|\($0.effectiveAt.timeIntervalSince1970)|\($0.snapshotJSON)" }
        state += revisions.map { "revision|\($0.id)|\($0.effectiveDate.timeIntervalSince1970)|\($0.preferenceRevisionID)|\($0.snapshotJSON)" }
        state += schedules.map { "schedule|\($0.id)|\($0.plannedDate.timeIntervalSince1970)|\($0.plannedLocalDay ?? "<unknown>")|\($0.plannedTimeZoneIdentifier ?? "<unknown>")|\($0.statusRaw)|\($0.planSnapshotJSON ?? "")" }
        state += sessions.map { "session|\($0.id)|\($0.plannedDate.timeIntervalSince1970)|\(sessionLocalDay($0))|\($0.statusRaw)" }
        state += links.map { "link|\($0.id)|\($0.scheduledWorkoutID)|\($0.templateCode)" }
        state += exercises.map { "exercise|\($0.id)|\($0.name)|\($0.equipment)|\($0.volumeUnit.rawValue)|\($0.isArchived)" }
        let fingerprint = SHA256.hash(data: try JSONEncoder().encode(state.sorted())).map { String(format: "%02x", $0) }.joined()
        return ConfirmedTravelWeekPreview(programID: program.id, programCode: programCode,
            preferenceRevisionCode: snapshot.preferenceRevisionCode,
            pendingStrengthWorkouts: snapshot.strengthWorkouts.filter { !imported.contains($0.code) }.count,
            pendingCardioWorkouts: snapshot.cardioWorkouts.filter { !imported.contains($0.code) }.count,
            alreadyImportedCodes: imported.sorted(), conflictingDates: conflicts.sorted(), stateFingerprint: fingerprint)
    }

    static func apply(expectedPreview: ConfirmedTravelWeekPreview, in context: ModelContext) throws -> ConfirmedTravelWeekResult {
        let fresh = try preview(in: context)
        guard fresh == expectedPreview else { throw FatLossError.invalidInput("旅行周数据已变化，请重新预览确认。") }
        guard fresh.conflictingDates.isEmpty else { throw FatLossError.scheduleConflict }
        guard let program = try context.fetch(FetchDescriptor<FatLossProgram>()).first(where: { $0.id == fresh.programID }) else {
            throw FatLossError.invalidInput("减脂周期已变化，请重新预览。")
        }
        let revision = try TrainingPreferenceService.activateUpperBodyTravelWeek(programID: program.id, effectiveDate: startDate, in: context)
        let count = try FatLossService.importWorkouts(program: program, from: startDate, days: 7, in: context)
        return ConfirmedTravelWeekResult(programRevisionID: revision.id, programCode: programCode,
            preferenceRevisionCode: revision.preferenceRevisionCode, importedSchedules: count)
    }
}

@MainActor
enum FatLossService {
    static func activeProgram(in context: ModelContext) throws -> FatLossProgram? {
        try context.fetch(FetchDescriptor<FatLossProgram>())
            .filter { $0.statusRaw == "active" }
            .sorted { $0.createdAt > $1.createdAt }.first
    }

    /// Called only by the explicit setup confirmation. Opening the app never calls this.
    @discardableResult
    static func createProgram(in context: ModelContext) throws -> FatLossProgram {
        if let existing = try activeProgram(in: context) {
            _ = try TrainingPreferenceService.ensureProgramRevision(
                programID: existing.id,
                effectiveDate: existing.startDate,
                in: context
            )
            return existing
        }
        var startDate = FatLossCalendar.date(2026, 9, 6)
        var endDate = FatLossCalendar.date(2026, 12, 6)
        #if DEBUG
        if CloudSyncRuntime.isTesting && !CloudSyncRuntime.usesPersistentUITestStore
            && ProcessInfo.processInfo.arguments.contains("--ui-redesign-preview") {
            // Keep the isolated UI fixture on day one as the real date advances.
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-lower-body-week") {
                startDate = FatLossCalendar.date(2026, 9, 14)
            } else {
                startDate = FatLossCalendar.day(.now)
            }
            endDate = FatLossCalendar.adding(91, to: startDate)
        } else if CloudSyncRuntime.isTesting && ProcessInfo.processInfo.arguments.contains("--ui-testing-fat-loss-started") {
            startDate = FatLossCalendar.adding(-7, to: .now)
            endDate = FatLossCalendar.adding(91, to: startDate)
        }
        #endif
        let program = FatLossProgram(startDate: startDate, endDate: endDate)
        let recipes = try FatLossCatalog.recipes.map { try RecipeVersion(draft: $0) }
        let existingKeys = Set(try context.fetch(FetchDescriptor<RecipeVersion>()).map(\.catalogKey))
        context.insert(program)
        recipes.filter { !existingKeys.contains($0.catalogKey) }.forEach(context.insert)
        let target = ProgramTargetRevision(programID: program.id, effectiveDate: program.startDate,
                                          reason: "已确认的 13 周计划；营养目标待医生确认")
        target.targetWeightKg = 77.5
        target.steps = 4_000
        context.insert(target)
        let urate = ProgramHealthRecord(programID: program.id, metric: "尿酸")
        urate.value = 300
        urate.notes = "本人回忆约 300；检测日期和单位待核对，服药期间读数。"
        context.insert(urate)
        let kidney = ProgramHealthRecord(programID: program.id, metric: "肾功能与饮食限制")
        kidney.notes = "本人报告肌酐偏高，具体数值、eGFR 和尿蛋白未知；医生建议控制肉量，具体总蛋白及份量待确认。"
        context.insert(kidney)
        let medication = ProgramHealthRecord(programID: program.id, metric: "本人报告的用药")
        medication.notes = "综合维生素、非布司他、非那雄胺；剂量与频率未知。本记录不提供调整用药建议。"
        context.insert(medication)
        try context.save()
        _ = try TrainingPreferenceService.ensureProgramRevision(
            programID: program.id,
            effectiveDate: program.startDate,
            in: context
        )
        return program
    }

    static func target(program: FatLossProgram, on date: Date, in context: ModelContext) throws -> ProgramTargetRevision? {
        try context.fetch(FetchDescriptor<ProgramTargetRevision>())
            .filter { $0.programID == program.id && $0.effectiveDate <= FatLossCalendar.day(date) }
            .sorted {
                if $0.effectiveDate != $1.effectiveDate { return $0.effectiveDate > $1.effectiveDate }
                return $0.createdAt > $1.createdAt
            }.first
    }

    static func saveTarget(_ revision: ProgramTargetRevision, in context: ModelContext) throws {
        guard !revision.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FatLossError.invalidInput("请写明调整原因。")
        }
        if let weight = revision.targetWeightKg, !weight.isFinite || !(20...400).contains(weight) {
            throw FatLossError.invalidInput("目标体重需为 20–400 kg。")
        }
        for value in [revision.calories, revision.proteinGrams, revision.carbsGrams, revision.fatGrams] {
            if let value, !(1...20_000).contains(value) { throw FatLossError.invalidInput("营养目标需为正数；未知请留空。") }
        }
        if let steps = revision.steps, !(0...100_000).contains(steps) {
            throw FatLossError.invalidInput("步数需在 0–100,000 之间。")
        }
        if revision.isNutritionConfirmed && revision.sourceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FatLossError.invalidInput("确认营养目标前，请记录医生或营养师建议的来源。")
        }
        // User-facing edits always create a new model, never mutate a saved revision.
        if try context.fetch(FetchDescriptor<ProgramTargetRevision>()).contains(where: { $0.id == revision.id }) {
            throw FatLossError.invalidInput("已保存目标不可覆盖，请新增调整版本。")
        }
        let programs = try context.fetch(FetchDescriptor<FatLossProgram>())
        guard let program = programs.first(where: { $0.id == revision.programID }), program.contains(revision.effectiveDate) else {
            throw FatLossError.invalidInput("目标生效日期需在减脂周期内。")
        }
        revision.effectiveDate = FatLossCalendar.day(revision.effectiveDate)
        context.insert(revision)
        try context.save()
    }

    @discardableResult
    static func importMeals(program: FatLossProgram, from date: Date, days: Int = 14, in context: ModelContext) throws -> Int {
        guard (1...91).contains(days) else { throw FatLossError.invalidInput("请选择 1–91 天。") }
        let recipes = try context.fetch(FetchDescriptor<RecipeVersion>())
        let existing = try context.fetch(FetchDescriptor<PlannedMeal>()).filter { $0.programID == program.id && $0.isCurrent }
        var newMeals: [PlannedMeal] = []
        for offset in 0..<days {
            let day = FatLossCalendar.adding(offset, to: date)
            guard program.contains(day, includeReviewDay: false) else { continue }
            for mealType in [MealType.breakfast, .lunch, .dinner] {
                guard !existing.contains(where: { FatLossCalendar.sameDay($0.date, day) && $0.mealType == mealType }) else { continue }
                guard let draft = FatLossCatalog.recipe(dayIndex: FatLossCalendar.distance(program.startDate, day), mealType: mealType),
                      let recipe = recipes.filter({ $0.catalogKey == draft.key }).max(by: { $0.version < $1.version }) else {
                    throw FatLossError.unreadableRecipe
                }
                newMeals.append(PlannedMeal(programID: program.id, date: day, mealType: mealType, recipe: recipe))
            }
        }
        newMeals.forEach(context.insert)
        try context.save()
        return newMeals.count
    }

    @discardableResult
    static func replaceMeal(_ meal: PlannedMeal, with recipe: RecipeVersion, reason: String, in context: ModelContext) throws -> PlannedMeal {
        guard meal.isCurrent, recipe.draft != nil else { throw FatLossError.unreadableRecipe }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FatLossError.invalidInput("请记录换菜原因。") }
        guard try !context.fetch(FetchDescriptor<MealEntry>()).contains(where: { $0.plannedMealID == meal.id && $0.isActiveMeal }) else {
            throw FatLossError.historicalMeal
        }
        let replacement = PlannedMeal(programID: meal.programID, date: meal.date, mealType: meal.mealType, recipe: recipe)
        replacement.previousPlanID = meal.id
        replacement.changeReason = reason
        meal.isCurrent = false
        context.insert(replacement)
        try context.save()
        return replacement
    }

    @discardableResult
    static func recordMeal(_ meal: PlannedMeal, portions: Double = 1, now: Date = .now, in context: ModelContext) throws -> MealEntry {
        guard meal.date <= FatLossCalendar.day(now) else { throw FatLossError.invalidInput("未来餐次可以安排，吃完后再记录实际。") }
        guard portions.isFinite, portions > 0, portions <= 20 else { throw FatLossError.invalidInput("实际份量需大于 0，不超过 20 份。") }
        guard meal.isCurrent else { throw FatLossError.historicalMeal }
        let actuals = try context.fetch(FetchDescriptor<MealEntry>()).filter(\.isActiveMeal)
        if let existing = actuals.first(where: { $0.plannedMealID == meal.id }) { return existing }
        guard !actuals.contains(where: {
            $0.mealType == meal.mealType && $0.stableLocalDay == FatLossCalendar.label(meal.date)
                && ($0.programID == nil || $0.programID == meal.programID)
        }) else {
            throw FatLossError.invalidInput("这一天的\(meal.mealType.title)已有实吃记录，请到饮食记录中修改；原记录会保留。")
        }
        guard let recipe = meal.recipe, recipe.portions.isFinite, recipe.portions > 0 else { throw FatLossError.unreadableRecipe }
        let factor = portions / recipe.portions
        func scaled(_ value: Int?) throws -> Int {
            let amount = (Double(value ?? 0) * factor).rounded()
            guard amount.isFinite, (0...100_000).contains(amount) else {
                throw FatLossError.invalidInput("食谱营养或份数无效，请核对后再记录。")
            }
            return Int(amount)
        }
        let entry = MealEntry(date: meal.date, mealType: meal.mealType, name: recipe.title,
                              calories: try scaled(recipe.calories), proteinGrams: try scaled(recipe.proteinGrams),
                              carbsGrams: try scaled(recipe.carbsGrams), fatGrams: try scaled(recipe.fatGrams))
        entry.programID = meal.programID
        entry.plannedMealID = meal.id
        entry.recipeSnapshotJSON = meal.recipeSnapshotJSON
        entry.actualPortions = portions
        entry.nutritionKnown = recipe.hasCompleteNutrition
        entry.knownNutritionFieldsRaw = zip(["calories", "protein", "carbs", "fat"], [recipe.calories, recipe.proteinGrams, recipe.carbsGrams, recipe.fatGrams])
            .compactMap { $0.1 != nil ? $0.0 : nil }.joined(separator: ",")
        entry.estimationMethod = "家庭份量估算"
        meal.statusRaw = "planned"
        context.insert(entry)
        try context.save()
        return entry
    }

    static func updateMeal(_ entry: MealEntry, portions: Double, calories: Int?, proteinGrams: Int?, carbsGrams: Int?, fatGrams: Int?,
                           tasteRating: Int?, preparationDifficulty: Int?, bloatingScore: Int?, notes: String,
                           in context: ModelContext) throws {
        guard entry.isActiveMeal, portions.isFinite, (0.01...20).contains(portions) else { throw FatLossError.invalidInput("实际份量无效。") }
        for value in [calories, proteinGrams, carbsGrams, fatGrams] {
            if let value, !(0...100_000).contains(value) { throw FatLossError.invalidInput("营养值需为非负数；未知留空。") }
        }
        guard tasteRating.map({ (1...5).contains($0) }) ?? true,
              preparationDifficulty.map({ (1...5).contains($0) }) ?? true,
              bloatingScore.map({ (0...3).contains($0) }) ?? true else { throw FatLossError.invalidInput("反馈评分超出范围。") }
        entry.actualPortions = portions
        entry.calories = calories ?? 0
        entry.proteinGrams = proteinGrams ?? 0
        entry.carbsGrams = carbsGrams ?? 0
        entry.fatGrams = fatGrams ?? 0
        entry.nutritionKnown = [calories, proteinGrams, carbsGrams, fatGrams].allSatisfy { $0 != nil }
        entry.knownNutritionFieldsRaw = zip(["calories", "protein", "carbs", "fat"], [calories, proteinGrams, carbsGrams, fatGrams])
            .compactMap { $0.1 != nil ? $0.0 : nil }.joined(separator: ",")
        entry.estimationMethod = "手动填写 / 家庭份量估算"
        entry.tasteRating = tasteRating
        entry.preparationDifficulty = preparationDifficulty
        entry.bloatingScore = bloatingScore
        entry.feedbackNotes = notes
        entry.updatedAt = .now
        try context.save()
    }

    static func undoMeal(_ entry: MealEntry, in context: ModelContext) throws {
        entry.isVoided = true
        entry.updatedAt = .now
        try context.save()
    }

    static func skipMeal(_ meal: PlannedMeal, reason: String, now: Date = .now, in context: ModelContext) throws {
        guard meal.date <= FatLossCalendar.day(now) else { throw FatLossError.invalidInput("未来餐次暂不能记录实际未吃。") }
        guard meal.isCurrent else { throw FatLossError.historicalMeal }
        guard try !context.fetch(FetchDescriptor<MealEntry>()).contains(where: { $0.plannedMealID == meal.id && $0.isActiveMeal }) else { throw FatLossError.historicalMeal }
        meal.statusRaw = "skipped"
        meal.changeReason = reason.isEmpty ? "本人明确记录未吃此餐" : reason
        try context.save()
    }

    static func saveDailyLog(_ log: ProgramDailyLog, now: Date = .now, in context: ModelContext) throws {
        guard FatLossCalendar.day(log.date) <= FatLossCalendar.day(now) else { throw FatLossError.invalidInput("未来日期暂不能记录实际执行。") }
        guard log.steps.map({ (0...100_000).contains($0) }) ?? true,
              log.sleepHours.map({ $0.isFinite && (0...24).contains($0) }) ?? true,
              log.bloatingScore.map({ (0...3).contains($0) }) ?? true else { throw FatLossError.invalidInput("请检查步数、睡眠小时与腹胀评分。") }
        try validateDay(log.date, programID: log.programID, in: context)
        let existing = try context.fetch(FetchDescriptor<ProgramDailyLog>()).first {
            $0.programID == log.programID && FatLossCalendar.sameDay($0.date, log.date)
        }
        if let existing, existing.id != log.id {
            existing.steps = log.steps; existing.sleepHours = log.sleepHours
            existing.bloatingScore = log.bloatingScore; existing.notes = log.notes
            existing.explicitlyNoWorkout = log.explicitlyNoWorkout
            existing.updatedAt = .now
        } else {
            log.date = FatLossCalendar.day(log.date)
            log.updatedAt = .now
            context.insert(log)
        }
        try context.save()
    }

    static func saveHealthRecord(_ record: ProgramHealthRecord, in context: ModelContext) throws {
        guard !record.metric.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.value.map({ $0.isFinite && $0 >= 0 }) ?? true else { throw FatLossError.invalidInput("请输入记录名称和有效数值；未知可留空。") }
        guard try context.fetch(FetchDescriptor<FatLossProgram>()).contains(where: { $0.id == record.programID }) else {
            throw FatLossError.invalidInput("找不到对应减脂周期。")
        }
        context.insert(record)
        try context.save()
    }

    private static func matchingExercises(for draft: ProgramExerciseDraft, in exercises: [Exercise]) -> [Exercise] {
        exercises.filter {
            !$0.isArchived && $0.name == draft.name && $0.equipment == draft.equipment
                && $0.volumeUnit.rawValue == draft.volumeUnitRaw
        }
    }

    /// The confirmed 2026-09-14 lower-body specialty week treats its two rope
    /// sessions as first-class schedule items. Other program revisions retain
    /// their existing strength-only import behavior.
    static func cardioImportPreview(
        program: FatLossProgram,
        from date: Date,
        days: Int,
        in context: ModelContext
    ) throws -> [ProgramCardioImportPreview] {
        guard (1...7).contains(days) else {
            throw FatLossError.invalidInput("先安排 1–7 天，复盘后再确认下一周。")
        }
        let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>())
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).filter { $0.programID == program.id }

        return (0..<days).compactMap { offset in
            let day = FatLossCalendar.adding(offset, to: date)
            guard program.contains(day, includeReviewDay: false),
                  let revision = TrainingPreferenceService.effectiveProgram(revisions, programID: program.id, on: day),
                  let snapshot = revision.snapshot,
                  ["CUT-LB3-20260914-R1", ConfirmedTravelWeekService.programCode].contains(snapshot.code),
                  let cardio = snapshot.cardioWorkouts.first(where: {
                      $0.weekday == FatLossCalendar.calendar.component(.weekday, from: day)
                  }) else { return nil }

            let alreadyImported = links.contains {
                FatLossCalendar.sameDay($0.originalDate, day) && $0.templateCode == cardio.code
            }
            let localDay = FatLossCalendar.label(day)
            let scheduledNames = schedules.filter {
                TrainingScheduleDate.localDay($0) == localDay && $0.status != .skipped
            }.map(\.templateName)
            let freeSessionNames = sessions.filter {
                $0.scheduledWorkoutID == nil && TrainingLocalDate.key($0.plannedDate) == localDay && $0.status != .discarded
            }.map(\.templateName)
            return ProgramCardioImportPreview(
                trainingProgramRevisionID: revision.id,
                date: day,
                cardio: cardio,
                alreadyImported: alreadyImported,
                conflictingNames: alreadyImported ? [] : scheduledNames + freeSessionNames
            )
        }
    }

    static func importPreview(program: FatLossProgram, from date: Date, days: Int = 7, lowEnergyMorning: Bool = false, in context: ModelContext) throws -> [ProgramImportPreview] {
        guard (1...7).contains(days) else { throw FatLossError.invalidInput("先安排 1–7 天，复盘后再确认下一周。") }
        let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>())
        let exerciseCatalog = try context.fetch(FetchDescriptor<Exercise>())
        let history = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).filter { $0.programID == program.id }
        return try (0..<days).compactMap { offset in
            let day = FatLossCalendar.adding(offset, to: date)
            guard program.contains(day, includeReviewDay: false),
                  let revision = TrainingPreferenceService.effectiveProgram(revisions, programID: program.id, on: day) else { return nil }
            guard let snapshot = revision.snapshot, snapshot.isValid else {
                throw FatLossError.invalidInput("该日期的编排无法读取，请保留原版本并检查备份。")
            }
            guard let workout = snapshot.strengthWorkouts.first(where: {
                $0.weekday == FatLossCalendar.calendar.component(.weekday, from: day)
            }) else { return nil }
            let alreadyImported = links.contains { FatLossCalendar.sameDay($0.originalDate, day) && $0.templateCode == workout.code }
            let localDay = FatLossCalendar.label(day)
            let names = schedules.filter { TrainingScheduleDate.localDay($0) == localDay }.map(\.templateName)
            let freeSessions = sessions.filter { $0.scheduledWorkoutID == nil && TrainingLocalDate.key($0.plannedDate) == localDay && $0.status != .discarded }.map(\.templateName)
            let firstLoadedExercise = workout.exercises.first { $0.volumeUnitRaw == ExerciseVolumeUnit.kilogram.rawValue }?.name
            var loads: [String: WorkoutSetPlan] = [:]
            for draft in workout.exercises {
                let matches = matchingExercises(for: draft, in: exerciseCatalog)
                guard matches.count <= 1 else {
                    throw FatLossError.invalidInput("动作“\(draft.name)”有多个同器械记录，请先在动作库核对，避免混入错误历史。")
                }
                // Left-elbow symptoms and travel fatigue make this confirmed
                // one-week plan a warmup-selected load, not a history preload.
                if snapshot.code == ConfirmedTravelWeekService.programCode { continue }
                guard draft.volumeUnitRaw == ExerciseVolumeUnit.kilogram.rawValue, let exercise = matches.first else { continue }
                let validSnapshots = Set(history.filter { $0.exerciseID == exercise.id && $0.volumeUnit == .kilogram }.map(\.id))
                let completedSessions = Set(sessions.filter { $0.status == .completed && $0.startedAt < day }.map(\.id))
                let sets = logs.filter {
                    $0.exerciseID == exercise.id && validSnapshots.contains($0.sessionExerciseID)
                        && completedSessions.contains($0.sessionID) && $0.isCompleted && !$0.isWarmup
                        && ($0.completedAt.map { $0 < day && $0 >= FatLossCalendar.adding(-42, to: day) } ?? false)
                        && $0.actualWeight.isFinite && $0.actualWeight > 0 && $0.actualReps >= draft.repsLower
                        && $0.actualRepsSide == (draft.unilateral ? .single : .bilateral)
                        && ($0.rir.map { $0 >= 2 } ?? false)
                }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
                guard let last = sets.first else { continue }
                let factor = lowEnergyMorning && draft.name == firstLoadedExercise ? 0.9 : 1.0
                loads[draft.name] = WorkoutSetPlan(id: last.id, weight: (last.actualWeight * factor * 10).rounded(.down) / 10,
                    reps: draft.repsLower, weightSide: last.actualWeightSide,
                    repsSide: draft.unilateral ? .single : .bilateral)
            }
            return ProgramImportPreview(trainingProgramRevisionID: revision.id, loadPlans: loads, date: day, workout: workout, alreadyImported: alreadyImported,
                                        conflictingNames: alreadyImported ? [] : names + freeSessions)
        }
    }

    @discardableResult
    static func importWorkouts(program: FatLossProgram, from date: Date, days: Int = 7,
                               conflictPolicy: ProgramImportConflictPolicy = .reject, lowEnergyMorning: Bool = false,
                               expectedPreview: [ProgramImportPreview]? = nil,
                               expectedCardioPreview: [ProgramCardioImportPreview]? = nil,
                               in context: ModelContext) throws -> Int {
        let preview = try importPreview(program: program, from: date, days: days, lowEnergyMorning: lowEnergyMorning, in: context)
        if let expectedPreview, expectedPreview != preview {
            throw FatLossError.invalidInput("编排或已有日程已变化，请重新预览后导入。")
        }
        if case .reject = conflictPolicy, preview.contains(where: { !$0.conflictingNames.isEmpty }) { throw FatLossError.scheduleConflict }
        var exercises = try context.fetch(FetchDescriptor<Exercise>())
        let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>())
        let preferences = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>())
        let candidates = preview.filter { !$0.alreadyImported && $0.conflictingNames.isEmpty }
        let cardioPreview = try cardioImportPreview(
            program: program,
            from: date,
            days: days,
            in: context
        )
        if let expectedCardioPreview, expectedCardioPreview != cardioPreview {
            throw FatLossError.invalidInput("有氧编排或已有日程已变化，请重新预览后导入。")
        }
        if case .reject = conflictPolicy, cardioPreview.contains(where: { !$0.conflictingNames.isEmpty }) {
            throw FatLossError.scheduleConflict
        }
        let cardioCandidates = cardioPreview.filter { !$0.alreadyImported && $0.conflictingNames.isEmpty }
        for candidate in candidates {
            // Each imported day gets its own template: future edits cannot alter another day.
            let template = WorkoutTemplate(name: candidate.workout.title, weekday: candidate.workout.weekday,
                                           isActive: false, isOneOff: true, plannedForDate: candidate.date,
                                           focusMuscleGroups: Array(Set(candidate.workout.exercises.map(\.muscleGroup))).sorted())
            if let revision = revisions.first(where: { $0.id == candidate.trainingProgramRevisionID }) {
                template.trainingPreferenceSnapshotJSON = preferences.first { $0.id == revision.preferenceRevisionID }?.snapshotJSON
            }
            context.insert(template)
            for (index, draft) in candidate.workout.exercises.enumerated() {
                let unit = ExerciseVolumeUnit(rawValue: draft.volumeUnitRaw) ?? .kilogram
                let exercise: Exercise
                if let existing = matchingExercises(for: draft, in: exercises).first {
                    exercise = existing
                } else {
                    exercise = Exercise(name: draft.name, muscleGroup: draft.muscleGroup, equipment: draft.equipment,
                                        defaultRestSeconds: draft.restSeconds, isBuiltIn: false, notes: draft.note)
                    exercise.volumeUnit = unit
                    context.insert(exercise)
                    exercises.append(exercise)
                }
                let isDistance = unit == .meter
                let basePlan = candidate.loadPlans[draft.name] ?? WorkoutSetPlan(
                    weight: isDistance ? Double(draft.repsLower) : 0,
                    reps: isDistance ? 1 : draft.repsLower,
                    weightSide: candidate.workout.code.hasPrefix("TRAVEL_") ? .unknown : .bilateral,
                    repsSide: draft.unilateral ? .single : .bilateral)
                // Preview references use the source log ID for stable comparison. Saved plan rows own independent IDs.
                let plans = (0..<draft.sets).map { _ in
                    var plan = basePlan
                    plan.id = UUID()
                    return plan
                }
                context.insert(TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: index,
                                                targetSets: draft.sets, minReps: isDistance ? 1 : draft.repsLower,
                                                maxReps: isDistance ? 1 : draft.repsUpper, targetWeight: basePlan.weight,
                                                restSeconds: draft.restSeconds, plannedSets: plans))
            }
            let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name,
                                            plannedDate: candidate.date, isManuallyScheduled: true)
            // Preserve the program's natural-day timezone even if the device timezone differs.
            schedule.plannedDate = candidate.date
            schedule.plannedLocalDay = FatLossCalendar.label(candidate.date)
            schedule.plannedTimeZoneIdentifier = FatLossCalendar.calendar.timeZone.identifier
            context.insert(schedule)
            try ScheduleService.freezePlanSnapshot(for: schedule, in: context)
            if candidate.workout.code.hasPrefix("TRAVEL_") {
                // A shared catalog exercise can retain old cues. Freeze this week's
                // approved safety instructions into the new schedule only.
                schedule.planSnapshot = schedule.planSnapshot.map { item in
                    var updated = item
                    if let draft = candidate.workout.exercises.first(where: { $0.name == item.exerciseName }) {
                        updated.exerciseNotes = draft.note + "\n" + candidate.workout.guidance
                    }
                    return updated
                }
            }
            let link = ProgramWorkoutLink(programID: program.id, scheduledWorkoutID: schedule.id,
                                          templateCode: candidate.workout.code, originalDate: candidate.date)
            link.trainingProgramRevisionID = candidate.trainingProgramRevisionID
            context.insert(link)
        }

        for candidate in cardioCandidates {
            let isRecovery = candidate.cardio.code.hasPrefix("RECOVERY_")
            let template = WorkoutTemplate(
                name: candidate.cardio.title,
                weekday: candidate.cardio.weekday,
                isActive: false,
                isOneOff: true,
                plannedForDate: candidate.date,
                focusMuscleGroups: isRecovery ? ["心肺", "恢复"] : ["心肺", "足踝"]
            )
            if let revision = revisions.first(where: { $0.id == candidate.trainingProgramRevisionID }) {
                template.trainingPreferenceSnapshotJSON = preferences.first {
                    $0.id == revision.preferenceRevisionID
                }?.snapshotJSON
            }
            context.insert(template)

            let cardioName = isRecovery ? "轻松单车／椭圆机" : "跳绳"
            let cardioEquipment = isRecovery ? "单车或椭圆机" : "跳绳"
            let matchingRopeExercises = exercises.filter {
                !$0.isArchived && $0.name == cardioName && $0.equipment == cardioEquipment && $0.volumeUnit == .second
            }
            guard matchingRopeExercises.count <= 1 else {
                throw FatLossError.invalidInput("动作“\(cardioName)”有多个同器械记录，请先在动作库核对。")
            }
            let ropeExercise: Exercise
            if let existing = matchingRopeExercises.first {
                ropeExercise = existing
            } else {
                ropeExercise = Exercise(
                    name: cardioName,
                    muscleGroup: "心肺",
                    equipment: cardioEquipment,
                    defaultRestSeconds: 0,
                    isBuiltIn: false,
                    notes: isRecovery ? candidate.cardio.guidance : "按当日日程完成间歇；实际次数、有效时长和含休息总时长从今日页记录。",
                    volumeUnit: .second
                )
                context.insert(ropeExercise)
                exercises.append(ropeExercise)
            }

            let activeSeconds = candidate.cardio.activeSeconds ?? 1
            context.insert(TemplateExercise(
                templateID: template.id,
                exerciseID: ropeExercise.id,
                order: 0,
                targetSets: 1,
                minReps: activeSeconds,
                maxReps: isRecovery ? 1800 : activeSeconds,
                targetWeight: 0,
                restSeconds: 0,
                plannedSets: [WorkoutSetPlan(weight: 0, reps: activeSeconds)]
            ))

            let schedule = ScheduledWorkout(
                templateID: template.id,
                templateName: template.name,
                plannedDate: candidate.date,
                isManuallyScheduled: true
            )
            schedule.plannedDate = candidate.date
            schedule.plannedLocalDay = FatLossCalendar.label(candidate.date)
            schedule.plannedTimeZoneIdentifier = FatLossCalendar.calendar.timeZone.identifier
            context.insert(schedule)
            try ScheduleService.freezePlanSnapshot(for: schedule, in: context)
            if isRecovery {
                schedule.planSnapshot = schedule.planSnapshot.map { item in
                    var updated = item
                    updated.exerciseNotes = candidate.cardio.intervals + "；" + candidate.cardio.guidance
                    return updated
                }
            }
            let link = ProgramWorkoutLink(
                programID: program.id,
                scheduledWorkoutID: schedule.id,
                templateCode: candidate.cardio.code,
                originalDate: candidate.date
            )
            link.trainingProgramRevisionID = candidate.trainingProgramRevisionID
            context.insert(link)
        }
        try context.save()
        return candidates.count + cardioCandidates.count
    }

    static func average(endingOn date: Date, values: [BodyWeightDailyValue]) -> FatLossWeightAverage {
        let start = FatLossCalendar.adding(-6, to: date)
        let end = FatLossCalendar.day(date)
        var unique: [Date: Double] = [:]
        for value in values.sorted(by: { $0.date < $1.date }) where value.weightKg.isFinite && value.weightKg > 0 {
            let day = FatLossCalendar.day(value.date)
            if day >= start && day <= end { unique[day] = value.weightKg }
        }
        return FatLossWeightAverage(value: unique.count >= 3 ? unique.values.reduce(0, +) / Double(unique.count) : nil,
                                    recordedDays: unique.count)
    }

    static func timeline(program: FatLossProgram, in context: ModelContext) throws -> [FatLossDaySummary] {
        guard (1...366).contains(program.executionDays) else { throw FatLossError.invalidInput("周期日期无效。") }
        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
        let meals = try context.fetch(FetchDescriptor<MealEntry>()).filter { $0.isActiveMeal }
        let plans = try context.fetch(FetchDescriptor<PlannedMeal>()).filter { $0.programID == program.id && $0.isCurrent }
        let workouts = try context.fetch(FetchDescriptor<WorkoutSession>())
        let feelings = try context.fetch(FetchDescriptor<DailyBodyCheckIn>())
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let jumps = try context.fetch(FetchDescriptor<JumpRopeEntry>())
        let water = try context.fetch(FetchDescriptor<HydrationEntry>())
        let logs = try context.fetch(FetchDescriptor<ProgramDailyLog>()).filter { $0.programID == program.id }
        return (0...program.executionDays).map { offset in
            let day = FatLossCalendar.adding(offset, to: program.startDate)
            func matches(_ date: Date) -> Bool { FatLossCalendar.sameDay(date, day) }
            let body = measurements.filter { matches($0.date) }.sorted {
                if $0.source != $1.source { return $0.source == .manual }
                return $0.date > $1.date
            }
            let entries = meals.filter { $0.stableLocalDay == FatLossCalendar.label(day) && ($0.programID == nil || $0.programID == program.id) }
            let dayPlans = plans.filter { matches($0.date) }
            let feeling = feelings.filter { matches($0.date) }.max { $0.updatedAt < $1.updatedAt }
            let dayJumps = jumps.filter { entry in
                entry.trainingLocalDay.map { $0 == FatLossCalendar.label(day) } ?? matches(entry.date)
            }
            let log = logs.filter { matches($0.date) }.max { $0.updatedAt < $1.updatedAt }
            func durationSum(_ key: KeyPath<JumpRopeEntry, Int?>) -> Int? {
                guard !dayJumps.isEmpty, dayJumps.allSatisfy({ $0[keyPath: key] != nil }) else { return nil }
                return dayJumps.compactMap { $0[keyPath: key] }.reduce(0, +)
            }
            return FatLossDaySummary(date: day, weightKg: body.compactMap(\.weightKg).first,
                                     waistCm: body.compactMap(\.waistCm).first,
                                     loggedMeals: entries.count, plannedMeals: dayPlans.count,
                                     skippedMeals: dayPlans.filter { $0.statusRaw == "skipped" }.count,
                                     knownCalories: entries.filter(\.isCalorieKnown).reduce(0) { $0 + $1.calories },
                                     unknownNutritionMeals: entries.filter { !$0.isNutritionKnown }.count,
                                     completedWorkouts: workouts.filter { matches($0.completedAt ?? $0.plannedDate) && $0.status == .completed }.count,
                                     plannedWorkouts: schedules.filter { matches($0.plannedDate) && $0.status != .skipped }.count,
                                     jumpCount: JumpRopeEntry.totalKnownCount(dayJumps),
                                     jumpActiveSeconds: durationSum(\.activeDurationSeconds), jumpElapsedSeconds: durationSum(\.elapsedDurationSeconds),
                                     waterMilliliters: water.filter { matches($0.date) }.reduce(0) { $0 + $1.milliliters },
                                     steps: log?.steps, sleepHours: log?.sleepHours,
                                     bloatingScore: log?.bloatingScore ?? entries.compactMap(\.bloatingScore).max(),
                                     explicitlyNoWorkout: log?.explicitlyNoWorkout ?? false, hasDailyLog: log != nil,
                                     resolvedMealTypes: Array(Set(entries.map(\.mealTypeRaw) + dayPlans.filter { $0.statusRaw == "skipped" }.map(\.mealTypeRaw))),
                                     knownCalorieMeals: entries.filter(\.isCalorieKnown).count,
                                     bodyFeeling: feeling.map { "体感 \($0.conditionScore)/5" + ($0.discomfortNotes.isEmpty ? "" : " · \($0.discomfortNotes)") },
                                     workoutNotes: workouts.filter { matches($0.completedAt ?? $0.plannedDate) && $0.status == .completed }.map { $0.templateName + ($0.notes.isEmpty ? "" : " · " + $0.notes) })
        }
    }

    @discardableResult
    static func saveReview(program: FatLossProgram, endingOn date: Date, notes: String, nextAction: String,
                           now: Date = .now, in context: ModelContext) throws -> ProgramWeeklyReview {
        guard FatLossCalendar.day(date) <= FatLossCalendar.day(now) else { throw FatLossError.invalidInput("未来日期不能保存实际复盘。") }
        let end = min(FatLossCalendar.day(date), program.endDate)
        guard end >= program.startDate else { throw FatLossError.invalidInput("复盘日期需在周期开始之后。") }
        let start = max(program.startDate, FatLossCalendar.adding(-6, to: end))
        let days = try timeline(program: program, in: context).filter { $0.date >= start && $0.date <= end }
        let data = try JSONEncoder().encode(days)
        let previous = try context.fetch(FetchDescriptor<ProgramWeeklyReview>())
            .filter { $0.programID == program.id && $0.weekEnd == end }.max { $0.createdAt < $1.createdAt }
        let review = ProgramWeeklyReview(programID: program.id, weekStart: start, weekEnd: end)
        review.snapshotJSON = String(decoding: data, as: UTF8.self)
        review.notes = notes
        review.nextAction = nextAction
        review.previousReviewID = previous?.id
        context.insert(review)
        try context.save()
        return review
    }

    static func shoppingList(meals: [PlannedMeal]) -> [ShoppingItem] {
        var result: [String: ShoppingItem] = [:]
        for meal in meals where meal.isCurrent && meal.statusRaw != "skipped" {
            guard let recipe = meal.recipe else { continue }
            for ingredient in recipe.ingredients {
                var item = result[ingredient.name] ?? ShoppingItem(name: ingredient.name, portions: 0, amounts: [], isMedicalPortionPending: false)
                if item.portions == 0 {
                    item.referenceGrams = ingredient.referenceGrams.map { $0 / recipe.portions }
                } else if let existing = item.referenceGrams, let grams = ingredient.referenceGrams {
                    item.referenceGrams = existing + grams / recipe.portions
                } else {
                    item.referenceGrams = nil
                }
                item.portions += 1
                let amount = "\(ingredient.amountText)（原配方 \(recipe.portions.formatted()) 份，每餐取 1 份）"
                if !item.amounts.contains(amount) { item.amounts.append(amount) }
                item.isMedicalPortionPending = item.isMedicalPortionPending || ingredient.isMedicalPortionPending
                result[ingredient.name] = item
            }
        }
        return result.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func prepText(program: FatLossProgram, date: Date, meals: [PlannedMeal]) -> String {
        PrepPresentation.shareText(program: program, date: date, meals: meals)
    }

    static func exportCSV(program: FatLossProgram, in context: ModelContext) throws -> URL {
        func text<T>(_ value: T?) -> String { value.map { String(describing: $0) } ?? "" }
        var lines = ["日期,状态,体重kg,腰围cm,餐食记录数,已知热量kcal,未知营养餐数,完成训练数,跳绳次数,实际跳跃秒,含休息总秒,饮水ml,步数,睡眠小时,腹胀0至3,体感,训练与感受"]
        for day in try timeline(program: program, in: context) {
            var row: [String] = [FatLossCalendar.label(day.date), day.status(relativeTo: .now), text(day.weightKg), text(day.waistCm),
                          String(day.loggedMeals), day.knownCalorieMeals == 0 ? "" : String(day.knownCalories), String(day.unknownNutritionMeals)]
            row += [String(day.completedWorkouts), text(day.jumpCount), text(day.jumpActiveSeconds), text(day.jumpElapsedSeconds),
                          day.waterMilliliters > 0 ? String(day.waterMilliliters) : "", text(day.steps), text(day.sleepHours), text(day.bloatingScore), day.bodyFeeling ?? "", day.workoutNotes?.joined(separator: "；") ?? ""]
            lines.append(row.map(csvCell).joined(separator: ","))
        }
        lines += ["", "餐食明细", "日期,餐次,菜名,实际份数,热量kcal,蛋白质g,碳水g,脂肪g,营养状态,喜欢1至5,难度1至5,腹胀0至3,备注,估算来源"]
        let startLocalDay = FatLossCalendar.label(program.startDate)
        let endLocalDay = FatLossCalendar.label(program.endDate)
        let meals = try context.fetch(FetchDescriptor<MealEntry>()).filter {
            $0.isActiveMeal && $0.stableLocalDay >= startLocalDay && $0.stableLocalDay <= endLocalDay
                && ($0.programID == nil || $0.programID == program.id)
        }.sorted {
            $0.stableLocalDay == $1.stableLocalDay ? $0.date < $1.date : $0.stableLocalDay < $1.stableLocalDay
        }
        for meal in meals {
            var row: [String] = [meal.stableLocalDay, meal.mealType.title, meal.name, meal.actualPortions.map { String($0) } ?? ""]
            row += [meal.isCalorieKnown ? String(meal.calories) : "",
                          meal.isProteinKnown ? String(meal.proteinGrams) : "", meal.isCarbsKnown ? String(meal.carbsGrams) : "", meal.isFatKnown ? String(meal.fatGrams) : ""]
            row += [meal.isNutritionKnown ? "估算 / 手动记录" : "部分或全部待核算", text(meal.tasteRating), text(meal.preparationDifficulty), text(meal.bloatingScore), meal.feedbackNotes ?? "", meal.estimationMethod ?? ""]
            lines.append(row.map(csvCell).joined(separator: ","))
        }
        lines += ["", "目标版本", "生效日期,记录时间,目标体重kg,热量kcal,蛋白质g,步数,营养已确认,原因,依据"]
        for revision in try context.fetch(FetchDescriptor<ProgramTargetRevision>()).filter({ $0.programID == program.id }).sorted(by: { $0.effectiveDate < $1.effectiveDate }) {
            lines.append([FatLossCalendar.label(revision.effectiveDate), revision.createdAt.ISO8601Format(), text(revision.targetWeightKg), text(revision.calories), text(revision.proteinGrams), text(revision.steps), revision.isNutritionConfirmed ? "是" : "否", revision.reason, revision.sourceNote].map(csvCell).joined(separator: ","))
        }
        lines += ["", "计划餐与换菜历史", "日期,餐次,菜名,当前版本,状态,计划ID,前版ID,调整原因"]
        for plan in try context.fetch(FetchDescriptor<PlannedMeal>()).filter({ $0.programID == program.id }).sorted(by: { $0.date < $1.date }) {
            lines.append([FatLossCalendar.label(plan.date), plan.mealType.title, plan.title, plan.isCurrent ? "是" : "否", plan.statusRaw, plan.id.uuidString, plan.previousPlanID?.uuidString ?? "", plan.changeReason].map(csvCell).joined(separator: ","))
        }
        lines += ["", "健康记录", "项目,值,单位,化验日期,来源,备注"]
        for record in try context.fetch(FetchDescriptor<ProgramHealthRecord>()).filter({ $0.programID == program.id }) {
            lines.append([record.metric, text(record.value), record.unit ?? "", record.measuredAt.map(FatLossCalendar.label) ?? "", record.source, record.notes].map(csvCell).joined(separator: ","))
        }
        lines += ["", "周复盘历史", "开始日期,结束日期,保存时间,复盘ID,前版ID,备注,下一步,当时记录快照"]
        for review in try context.fetch(FetchDescriptor<ProgramWeeklyReview>()).filter({ $0.programID == program.id }).sorted(by: { $0.createdAt < $1.createdAt }) {
            lines.append([FatLossCalendar.label(review.weekStart), FatLossCalendar.label(review.weekEnd), review.createdAt.ISO8601Format(), review.id.uuidString, review.previousReviewID?.uuidString ?? "", review.notes, review.nextAction, review.snapshotJSON].map(csvCell).joined(separator: ","))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("XFit-fat-loss-\(UUID().uuidString).csv")
        try ("\u{feff}" + lines.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func csvCell(_ value: String) -> String {
        var text = value
        if let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first, "=+-@".contains(first) { text = "'" + text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func validateDay(_ date: Date, programID: UUID, in context: ModelContext) throws {
        guard let program = try context.fetch(FetchDescriptor<FatLossProgram>()).first(where: { $0.id == programID }), program.contains(date) else {
            throw FatLossError.invalidInput("记录日期需在减脂周期内。")
        }
    }
}
