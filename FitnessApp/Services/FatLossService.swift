import Foundation
import SwiftData

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
        if let existing = try activeProgram(in: context) { return existing }
        var startDate = FatLossCalendar.date(2026, 9, 6)
        var endDate = FatLossCalendar.date(2026, 12, 6)
        #if DEBUG
        if CloudSyncRuntime.isTesting && !CloudSyncRuntime.usesPersistentUITestStore
            && ProcessInfo.processInfo.arguments.contains("--ui-redesign-preview") {
            // Keep the isolated UI fixture on day one as the real date advances.
            startDate = FatLossCalendar.day(.now)
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
            $0.mealType == meal.mealType && FatLossCalendar.sameDay($0.date, meal.date)
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

    static func importPreview(program: FatLossProgram, from date: Date, days: Int = 14, in context: ModelContext) throws -> [ProgramImportPreview] {
        guard (1...91).contains(days) else { throw FatLossError.invalidInput("请选择 1–91 天。") }
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).filter { $0.programID == program.id }
        return (0..<days).compactMap { offset in
            let day = FatLossCalendar.adding(offset, to: date)
            guard program.contains(day, includeReviewDay: false), let workout = FatLossCatalog.workout(on: day) else { return nil }
            let alreadyImported = links.contains { FatLossCalendar.sameDay($0.originalDate, day) && $0.templateCode == workout.code }
            let names = schedules.filter { FatLossCalendar.sameDay($0.plannedDate, day) }.map(\.templateName)
            let freeSessions = sessions.filter { $0.scheduledWorkoutID == nil && FatLossCalendar.sameDay($0.plannedDate, day) && $0.status != .discarded }.map(\.templateName)
            return ProgramImportPreview(date: day, workout: workout, alreadyImported: alreadyImported,
                                        conflictingNames: alreadyImported ? [] : names + freeSessions)
        }
    }

    @discardableResult
    static func importWorkouts(program: FatLossProgram, from date: Date, days: Int = 14,
                               conflictPolicy: ProgramImportConflictPolicy = .reject, in context: ModelContext) throws -> Int {
        let preview = try importPreview(program: program, from: date, days: days, in: context)
        if case .reject = conflictPolicy, preview.contains(where: { !$0.conflictingNames.isEmpty }) { throw FatLossError.scheduleConflict }
        var exercises = try context.fetch(FetchDescriptor<Exercise>())
        let candidates = preview.filter { !$0.alreadyImported && $0.conflictingNames.isEmpty }
        for candidate in candidates {
            // Each imported day gets its own template: future edits cannot alter another day.
            let template = WorkoutTemplate(name: candidate.workout.title, weekday: candidate.workout.weekday,
                                           isActive: false, isOneOff: true, plannedForDate: candidate.date,
                                           focusMuscleGroups: Array(Set(candidate.workout.exercises.map(\.muscleGroup))).sorted())
            context.insert(template)
            for (index, draft) in candidate.workout.exercises.enumerated() {
                let unit = ExerciseVolumeUnit(rawValue: draft.volumeUnitRaw) ?? .kilogram
                let exercise: Exercise
                if let existing = exercises.first(where: { !$0.isArchived && $0.name == draft.name && $0.volumeUnit == unit }) {
                    exercise = existing
                } else {
                    exercise = Exercise(name: draft.name, muscleGroup: draft.muscleGroup, equipment: draft.equipment,
                                        defaultRestSeconds: draft.restSeconds, isBuiltIn: false, notes: draft.note)
                    exercise.volumeUnit = unit
                    context.insert(exercise)
                    exercises.append(exercise)
                }
                let isDistance = unit == .meter
                let plans = (0..<draft.sets).map { _ in
                    WorkoutSetPlan(weight: isDistance ? Double(draft.repsLower) : 0,
                                   reps: isDistance ? 1 : draft.repsLower,
                                   repsSide: draft.unilateral ? .single : .bilateral)
                }
                context.insert(TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: index,
                                                targetSets: draft.sets, minReps: isDistance ? 1 : draft.repsLower,
                                                maxReps: isDistance ? 1 : draft.repsUpper, targetWeight: isDistance ? Double(draft.repsLower) : 0,
                                                restSeconds: draft.restSeconds, plannedSets: plans))
            }
            let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name,
                                            plannedDate: candidate.date, isManuallyScheduled: true)
            // Preserve the program's natural-day timezone even if the device timezone differs.
            schedule.plannedDate = candidate.date
            context.insert(schedule)
            context.insert(ProgramWorkoutLink(programID: program.id, scheduledWorkoutID: schedule.id,
                                              templateCode: candidate.workout.code, originalDate: candidate.date))
        }
        try context.save()
        return candidates.count
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
            let entries = meals.filter { matches($0.date) && ($0.programID == nil || $0.programID == program.id) }
            let dayPlans = plans.filter { matches($0.date) }
            let feeling = feelings.filter { matches($0.date) }.max { $0.updatedAt < $1.updatedAt }
            let dayJumps = jumps.filter { matches($0.date) }
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
                                     jumpCount: dayJumps.reduce(0) { $0 + $1.count },
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
            row += [String(day.completedWorkouts), String(day.jumpCount), text(day.jumpActiveSeconds), text(day.jumpElapsedSeconds),
                          day.waterMilliliters > 0 ? String(day.waterMilliliters) : "", text(day.steps), text(day.sleepHours), text(day.bloatingScore), day.bodyFeeling ?? "", day.workoutNotes?.joined(separator: "；") ?? ""]
            lines.append(row.map(csvCell).joined(separator: ","))
        }
        lines += ["", "餐食明细", "日期,餐次,菜名,实际份数,热量kcal,蛋白质g,碳水g,脂肪g,营养状态,喜欢1至5,难度1至5,腹胀0至3,备注"]
        let meals = try context.fetch(FetchDescriptor<MealEntry>()).filter { $0.isActiveMeal && program.contains($0.date) && ($0.programID == nil || $0.programID == program.id) }.sorted { $0.date < $1.date }
        for meal in meals {
            var row: [String] = [FatLossCalendar.label(meal.date), meal.mealType.title, meal.name, meal.actualPortions.map { String($0) } ?? ""]
            row += [meal.isCalorieKnown ? String(meal.calories) : "",
                          meal.isProteinKnown ? String(meal.proteinGrams) : "", meal.isCarbsKnown ? String(meal.carbsGrams) : "", meal.isFatKnown ? String(meal.fatGrams) : ""]
            row += [meal.isNutritionKnown ? "估算 / 手动记录" : "部分或全部待核算", text(meal.tasteRating), text(meal.preparationDifficulty), text(meal.bloatingScore), meal.feedbackNotes ?? ""]
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
