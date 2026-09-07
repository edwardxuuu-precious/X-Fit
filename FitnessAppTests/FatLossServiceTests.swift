import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class FatLossServiceTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let schema = Schema([Exercise.self, WorkoutTemplate.self, TemplateExercise.self, ScheduledWorkout.self,
                             WorkoutSession.self, SessionExercise.self, SetLog.self, NutritionTarget.self, MealEntry.self,
                             BodyMeasurement.self, DailyBodyCheckIn.self, HydrationEntry.self, JumpRopeEntry.self, SedentarySession.self,
                             FatLossProgram.self, ProgramTargetRevision.self, RecipeVersion.self, PlannedMeal.self,
                             ProgramDailyLog.self, ProgramHealthRecord.self, ProgramWeeklyReview.self, ProgramWorkoutLink.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    func testSetupDoesNotInventMeasurementMealsOrScheduleAndIsIdempotent() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        XCTAssertEqual(program.executionDays, 91)
        XCTAssertEqual(program.reportedStartWeightKg, 85)
        XCTAssertEqual(try FatLossService.createProgram(in: context).id, program.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BodyMeasurement>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PlannedMeal>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ScheduledWorkout>()).isEmpty)
        let target = try XCTUnwrap(FatLossService.target(program: program, on: program.startDate, in: context))
        XCTAssertNil(target.calories)
        XCTAssertNil(target.proteinGrams)
        XCTAssertFalse(target.isNutritionConfirmed)
        let urate = try XCTUnwrap(context.fetch(FetchDescriptor<ProgramHealthRecord>()).first { $0.metric == "尿酸" })
        XCTAssertNil(urate.measuredAt)
        XCTAssertNil(urate.unit)
    }

    func testFourteenDayImportOnlyCreatesPlansAndEndpointIsReviewOnly() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        XCTAssertEqual(try FatLossService.importMeals(program: program, from: program.startDate, days: 14, in: context), 42)
        XCTAssertEqual(try FatLossService.importMeals(program: program, from: program.startDate, days: 14, in: context), 0)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
        XCTAssertEqual(try FatLossService.importMeals(program: program, from: program.endDate, days: 14, in: context), 0)
        XCTAssertEqual(try FatLossService.timeline(program: program, in: context).count, 92)
    }

    func testUnknownMealIsNotZeroAndRepeatedActionIsIdempotent() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        try FatLossService.importMeals(program: program, from: program.startDate, days: 1, in: context)
        let plan = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedMeal>()).first)
        let actual = try FatLossService.recordMeal(plan, now: program.endDate, in: context)
        XCTAssertFalse(actual.isNutritionKnown)
        XCTAssertEqual(try FatLossService.recordMeal(plan, now: program.endDate, in: context).id, actual.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 1)
        let day = try XCTUnwrap(FatLossService.timeline(program: program, in: context).first)
        XCTAssertEqual(day.unknownNutritionMeals, 1)
        XCTAssertFalse(day.nutritionComplete)
        let csv = try FatLossService.exportCSV(program: program, in: context)
        defer { try? FileManager.default.removeItem(at: csv) }
        let csvText = try String(contentsOf: csv, encoding: .utf8)
        XCTAssertTrue(csvText.contains("待核算"))
    }

    func testReplacementKeepsSnapshotAndCannotChangeConsumedMeal() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        try FatLossService.importMeals(program: program, from: program.startDate, days: 1, in: context)
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedMeal>()).first)
        let snapshot = original.recipeSnapshotJSON
        let alternate = try XCTUnwrap(context.fetch(FetchDescriptor<RecipeVersion>()).first { $0.id != original.recipeID })
        let replacement = try FatLossService.replaceMeal(original, with: alternate, reason: "换个口味", in: context)
        XCTAssertFalse(original.isCurrent)
        XCTAssertEqual(original.recipeSnapshotJSON, snapshot)
        XCTAssertEqual(replacement.previousPlanID, original.id)
        let actual = try FatLossService.recordMeal(replacement, now: program.endDate, in: context)
        XCTAssertThrowsError(try FatLossService.replaceMeal(replacement, with: alternate, reason: "不覆盖已吃", in: context))
        try FatLossService.undoMeal(actual, in: context)
        XCTAssertFalse(actual.isActiveMeal)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 1)
        let rerecorded = try FatLossService.recordMeal(replacement, now: program.endDate, in: context)
        XCTAssertNotEqual(rerecorded.id, actual.id)
        XCTAssertEqual(rerecorded.recipeSnapshotJSON, replacement.recipeSnapshotJSON)
    }

    func testSkipIsExplicitAndMayBeCorrectedByActualMeal() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        try FatLossService.importMeals(program: program, from: program.startDate, days: 1, in: context)
        let plan = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedMeal>()).first)
        try FatLossService.skipMeal(plan, reason: "今天没吃", now: program.endDate, in: context)
        XCTAssertEqual(plan.statusRaw, "skipped")
        try FatLossService.recordMeal(plan, now: program.endDate, in: context)
        XCTAssertEqual(plan.statusRaw, "planned")
        XCTAssertThrowsError(try FatLossService.skipMeal(plan, reason: "", now: program.endDate, in: context))
    }

    func testTargetRevisionResolvesByEffectiveDayWithoutRewritingEarlierTarget() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let changeDate = FatLossCalendar.adding(14, to: program.startDate)
        let revision = ProgramTargetRevision(programID: program.id, effectiveDate: changeDate, reason: "医生复诊建议")
        revision.calories = 2_050; revision.proteinGrams = 80
        revision.isNutritionConfirmed = true
        XCTAssertThrowsError(try FatLossService.saveTarget(revision, in: context))
        revision.sourceNote = "测试中的医生建议记录"
        try FatLossService.saveTarget(revision, in: context)
        XCTAssertNil(try FatLossService.target(program: program, on: program.startDate, in: context)?.calories)
        XCTAssertEqual(try FatLossService.target(program: program, on: changeDate, in: context)?.calories, 2_050)
        XCTAssertThrowsError(try FatLossService.saveTarget(revision, in: context))
    }

    func testAverageRequiresThreeDistinctNaturalDaysAndDoesNotBridgeGaps() {
        let end = FatLossCalendar.date(2026, 9, 20)
        func value(_ offset: Int, _ weight: Double) -> BodyWeightDailyValue {
            BodyWeightDailyValue(date: FatLossCalendar.adding(offset, to: end), weightKg: weight, source: .manual, measurementID: UUID())
        }
        let sparse = [-20, -16, -12, -9, -7, -3, 0].map { value($0, 84) }
        XCTAssertEqual(FatLossService.average(endingOn: end, values: sparse).recordedDays, 2)
        XCTAssertNil(FatLossService.average(endingOn: end, values: sparse).value)
        let adequate = [value(-6, 85), value(-3, 84), value(0, 83)]
        XCTAssertEqual(FatLossService.average(endingOn: end, values: adequate).value, 84)
        XCTAssertEqual(FatLossService.average(endingOn: end, values: adequate + [value(0, 83)]).recordedDays, 3)
    }

    func testDailyLogUpsertValidatesBeforeChangingExistingAndPreservesUnknowns() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let log = ProgramDailyLog(programID: program.id, date: program.startDate)
        log.steps = 4_100
        try FatLossService.saveDailyLog(log, now: program.endDate, in: context)
        let edit = ProgramDailyLog(programID: program.id, date: program.startDate)
        edit.sleepHours = 7
        edit.bloatingScore = 0
        try FatLossService.saveDailyLog(edit, now: program.endDate, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgramDailyLog>()).count, 1)
        XCTAssertNil(log.steps)
        XCTAssertEqual(log.sleepHours, 7)
        let invalid = ProgramDailyLog(programID: program.id, date: program.startDate)
        invalid.sleepHours = 99
        XCTAssertThrowsError(try FatLossService.saveDailyLog(invalid, now: program.endDate, in: context))
        XCTAssertEqual(log.sleepHours, 7)
    }

    func testWeeklyReviewIsFrozenAndExplicitResaveCreatesVersion() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let end = FatLossCalendar.adding(6, to: program.startDate)
        let review = try FatLossService.saveReview(program: program, endingOn: end, notes: "首周", nextAction: "先完善记录", now: program.endDate, in: context)
        let snapshot = review.snapshotJSON
        context.insert(BodyMeasurement(date: program.startDate, weightKg: 84.5))
        try context.save()
        XCTAssertEqual(review.snapshotJSON, snapshot)
        let revised = try FatLossService.saveReview(program: program, endingOn: end, notes: "补记后重新复盘", nextAction: "继续", now: program.endDate, in: context)
        XCTAssertEqual(revised.previousReviewID, review.id)
        XCTAssertNotEqual(revised.snapshotJSON, snapshot)
    }

    func testWorkoutImportDetectsConflictBeforeWritesAndNeverOverwritesExisting() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let monday = FatLossCalendar.date(2026, 9, 7)
        let existing = ScheduledWorkout(templateID: UUID(), templateName: "真实已有计划", plannedDate: monday, isManuallyScheduled: true)
        context.insert(existing); try context.save()
        XCTAssertThrowsError(try FatLossService.importWorkouts(program: program, from: program.startDate, days: 7, in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: program.startDate, days: 7, conflictPolicy: .skipConflicts, in: context), 2)
        XCTAssertEqual(existing.templateName, "真实已有计划")
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: program.startDate, days: 7, conflictPolicy: .skipConflicts, in: context), 0)
    }

    func testImportedPlansSurviveRefreshAndRescheduleDoesNotRecreateOriginal() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: program.startDate, days: 7, in: context), 3)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        XCTAssertTrue(schedules.allSatisfy(\.isManuallyScheduled))
        let monday = try XCTUnwrap(schedules.first { FatLossCalendar.calendar.component(.weekday, from: $0.plannedDate) == 2 })
        monday.plannedDate = FatLossCalendar.adding(1, to: monday.plannedDate)
        try context.save()
        try ScheduleService.refreshUpcoming(in: context)
        try context.save()
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: program.startDate, days: 7, in: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 3)
        let items = try context.fetch(FetchDescriptor<TemplateExercise>())
        XCTAssertEqual(items.count, 16)
        XCTAssertTrue(items.allSatisfy { $0.targetSets == 2 })
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let carry = try XCTUnwrap(exercises.first { $0.volumeUnit == .meter })
        let carryItem = try XCTUnwrap(items.first { $0.exerciseID == carry.id })
        XCTAssertEqual(carryItem.targetWeight, 30)
        XCTAssertEqual(carryItem.plannedSets.first?.reps, 1)
    }

    func testLegacyJumpDurationIsNotMisrepresentedAsActive() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        context.insert(JumpRopeEntry(count: 1_500, durationSeconds: 1_800, date: program.startDate))
        try context.save()
        let day = try XCTUnwrap(FatLossService.timeline(program: program, in: context).first)
        XCTAssertEqual(day.jumpCount, 1_500)
        XCTAssertNil(day.jumpActiveSeconds)
        XCTAssertNil(day.jumpElapsedSeconds)
    }

    func testThreeSnacksDoNotCountAsThreeCompletedMeals() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        for _ in 0..<3 {
            context.insert(MealEntry(date: program.startDate, mealType: .snack, name: "水果", calories: 80, proteinGrams: 0, carbsGrams: 20, fatGrams: 0))
        }
        try context.save()
        let day = try XCTUnwrap(FatLossService.timeline(program: program, in: context).first)
        XCTAssertEqual(day.status(relativeTo: program.startDate), "部分记录")
    }

    func testShoppingQuantitiesScaleTwoPortionRecipeToOneMeal() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let recipe = try RecipeVersion(draft: RecipeDraft(key: "test", title: "两份菜", ingredients: [
            RecipeIngredient(name: "胡萝卜", amountText: "两份共200g", referenceGrams: 200),
            RecipeIngredient(name: "鸡肉", amountText: "待确认", isMedicalPortionPending: true)
        ], steps: ["分成两份"], equipment: ["蒸锅"], householdPortion: "两份", portions: 2, cookingMinutes: 15, storageNote: "及时冷藏"))
        let meal = PlannedMeal(programID: program.id, date: program.startDate, mealType: .lunch, recipe: recipe)
        let items = FatLossService.shoppingList(meals: [meal])
        XCTAssertEqual(items.first { $0.name == "胡萝卜" }?.referenceGrams, 100)
        XCTAssertNil(items.first { $0.name == "鸡肉" }?.referenceGrams)
        XCTAssertTrue(items.first { $0.name == "鸡肉" }?.isMedicalPortionPending ?? false)
    }
    func testFutureActualAndReviewCannotBeRecordedBeforeExecution() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let before = FatLossCalendar.adding(-1, to: program.startDate)
        try FatLossService.importMeals(program: program, from: program.startDate, days: 1, in: context)
        let meal = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedMeal>()).first)
        XCTAssertThrowsError(try FatLossService.recordMeal(meal, now: before, in: context))
        XCTAssertThrowsError(try FatLossService.skipMeal(meal, reason: "", now: before, in: context))
        XCTAssertThrowsError(try FatLossService.saveDailyLog(ProgramDailyLog(programID: program.id, date: program.startDate), now: before, in: context))
        XCTAssertThrowsError(try FatLossService.saveReview(program: program, endingOn: program.startDate, notes: "", nextAction: "", now: before, in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProgramDailyLog>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProgramWeeklyReview>()).isEmpty)
    }

    func testPartialKnownZeroCaloriesIsDifferentFromMissingAndExportPreservesVersions() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        try FatLossService.importMeals(program: program, from: program.startDate, days: 1, in: context)
        let plan = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedMeal>()).first)
        let meal = try FatLossService.recordMeal(plan, now: program.endDate, in: context)
        try FatLossService.updateMeal(meal, portions: 1, calories: 0, proteinGrams: nil, carbsGrams: nil, fatGrams: nil,
                                     tasteRating: 4, preparationDifficulty: 2, bloatingScore: 1, notes: "=SUM(1,2)", in: context)
        let day = try XCTUnwrap(FatLossService.timeline(program: program, in: context).first)
        XCTAssertEqual(day.knownCalorieMeals, 1)
        XCTAssertEqual(day.knownCalories, 0)
        XCTAssertFalse(meal.isProteinKnown)
        let url = try FatLossService.exportCSV(program: program, in: context)
        defer { try? FileManager.default.removeItem(at: url) }
        let csv = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(csv.contains("'=SUM(1,2)"))
        XCTAssertTrue(csv.contains("目标版本"))
        XCTAssertTrue(csv.contains("计划餐与换菜历史"))
        XCTAssertTrue(csv.contains("健康记录"))
        XCTAssertTrue(csv.contains("周复盘历史"))
    }

    func testDeletingImportedUnstartedScheduleAllowsReimportAndBackupRecovery() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        try FatLossService.importWorkouts(program: program, from: program.startDate, days: 7, in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        let removedID = schedule.id
        try ScheduleService.deleteManual(schedule, in: context)
        XCTAssertFalse(try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).contains { $0.scheduledWorkoutID == removedID })
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: program.startDate, days: 7, in: context), 1)
        let backup = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: backup), into: restored.mainContext)
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<ScheduledWorkout>()).count, 3)
    }

    func testInvalidNutritionScalingFailsBeforeWritingActualMeal() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        var draft = FatLossCatalog.recipes[0]
        draft.portions = Double.leastNormalMagnitude
        draft.calories = Int.max
        let recipe = try RecipeVersion(draft: draft)
        let plan = PlannedMeal(programID: program.id, date: program.startDate, mealType: .breakfast, recipe: recipe)
        context.insert(recipe); context.insert(plan); try context.save()
        XCTAssertThrowsError(try FatLossService.recordMeal(plan, now: program.endDate, in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<MealEntry>()).isEmpty)
    }

    func testManualMealConflictsWithPlannedRecordingWithoutChangingOriginal() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        try FatLossService.importMeals(program: program, from: program.startDate, days: 1, in: context)
        let plan = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedMeal>()).first { $0.mealType == .breakfast })
        let manual = MealEntry(date: plan.date.addingTimeInterval(8 * 3600), mealType: .breakfast,
                               name: "手填早餐", calories: 420, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        manual.knownNutritionFieldsRaw = "calories,fat"
        manual.feedbackNotes = "原备注"
        context.insert(manual); try context.save()

        XCTAssertThrowsError(try FatLossService.recordMeal(plan, now: program.endDate, in: context)) { error in
            XCTAssertTrue(error.localizedDescription.contains("已有实吃记录"))
        }
        let records = try context.fetch(FetchDescriptor<MealEntry>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, manual.id)
        XCTAssertEqual(manual.name, "手填早餐")
        XCTAssertEqual(manual.calories, 420)
        XCTAssertEqual(manual.knownNutritionFieldsRaw, "calories,fat")
        XCTAssertEqual(manual.feedbackNotes, "原备注")
        XCTAssertNil(manual.programID)
        XCTAssertNil(manual.plannedMealID)
        XCTAssertEqual(plan.statusRaw, "planned")
        XCTAssertFalse(context.hasChanges)

        try FatLossService.undoMeal(manual, in: context)
        let plannedActual = try FatLossService.recordMeal(plan, now: program.endDate, in: context)
        XCTAssertNotEqual(plannedActual.id, manual.id)
        XCTAssertEqual(try FatLossService.recordMeal(plan, now: program.endDate, in: context).id, plannedActual.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).filter(\.isActiveMeal).count, 1)
    }

    func testLinkedMealRemainsIdempotentWhenAnotherActualExistsInSameSlot() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        try FatLossService.importMeals(program: program, from: program.startDate, days: 1, in: context)
        let plan = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedMeal>()).first)
        let linked = try FatLossService.recordMeal(plan, now: program.endDate, in: context)
        linked.feedbackNotes = "已记录的反馈"
        let extra = MealEntry(date: plan.date, mealType: plan.mealType, name: "后来手填", calories: 30,
                              proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        context.insert(extra); try context.save()
        let reopened = try FatLossService.recordMeal(plan, now: program.endDate, in: context)
        XCTAssertEqual(reopened.id, linked.id)
        XCTAssertEqual(reopened.feedbackNotes, "已记录的反馈")
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 2)
        XCTAssertNil(extra.plannedMealID)
    }

    func testOtherDayAndOtherMealTypeDoNotBlockPlannedRecording() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        try FatLossService.importMeals(program: program, from: program.startDate, days: 1, in: context)
        let plan = try XCTUnwrap(context.fetch(FetchDescriptor<PlannedMeal>()).first { $0.mealType == .breakfast })
        context.insert(MealEntry(date: FatLossCalendar.adding(-1, to: plan.date), mealType: .breakfast,
                                 name: "前一天早餐", calories: 10, proteinGrams: 0, carbsGrams: 0, fatGrams: 0))
        context.insert(MealEntry(date: plan.date, mealType: .snack,
                                 name: "当天加餐", calories: 20, proteinGrams: 0, carbsGrams: 0, fatGrams: 0))
        try context.save()
        let actual = try FatLossService.recordMeal(plan, now: program.endDate, in: context)
        XCTAssertEqual(actual.plannedMealID, plan.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MealEntry>()).count, 3)
    }

    func testNutritionNavigationAndNewMealPreserveShanghaiDayAcrossDeviceTimeZones() throws {
        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        for identifier in ["Asia/Shanghai", "America/Los_Angeles", "Europe/London", "Pacific/Auckland"] {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: identifier))
            for date in [FatLossCalendar.date(2026, 9, 6), FatLossCalendar.date(2026, 3, 8), FatLossCalendar.date(2026, 11, 1)] {
                let history = NutritionView(initialDate: date)
                XCTAssertEqual(history.selectedDate, date, identifier)
                let editor = MealEditorView(meal: nil, date: history.selectedDate, initialMealType: .breakfast)
                XCTAssertEqual(editor.date, date, identifier)
                let entry = MealEntry(date: editor.date, mealType: .breakfast, name: "当日实际",
                                      calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
                XCTAssertTrue(FatLossCalendar.sameDay(entry.date, date), identifier)
                XCTAssertFalse(FatLossCalendar.sameDay(entry.date, FatLossCalendar.adding(-1, to: date)), identifier)
                let existing = MealEntry(date: date.addingTimeInterval(8 * 3600), mealType: .breakfast, name: "既有时间",
                                         calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
                XCTAssertEqual(MealEditorView(meal: existing, date: date).date, existing.date, identifier)
            }
        }
    }

}
