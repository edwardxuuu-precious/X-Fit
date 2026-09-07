import SwiftData
import SQLite3
import XCTest
@testable import FitnessApp

@MainActor
final class FatLossBackupTests: XCTestCase {
    private let start = FatLossCalendar.date(2026, 9, 7)

    func testSchema13RoundTripPreservesEveryProgramEntityAndMealFacts() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let program = FatLossProgram(startDate: start, endDate: FatLossCalendar.adding(91, to: start))
        context.insert(program)
        let revision = ProgramTargetRevision(programID: program.id, effectiveDate: start, reason: "等待医学确认")
        revision.sourceNote = "不得按默认值补齐"
        context.insert(revision)
        let recipe = try RecipeVersion(draft: sampleRecipe())
        context.insert(recipe)
        let plan = PlannedMeal(programID: program.id, date: start, mealType: .lunch, recipe: recipe)
        plan.statusRaw = "logged"
        context.insert(plan)
        let daily = ProgramDailyLog(programID: program.id, date: start)
        daily.steps = 6543
        daily.sleepHours = 7.25
        daily.bloatingScore = 0
        daily.explicitlyNoWorkout = true
        context.insert(daily)
        let health = ProgramHealthRecord(programID: program.id, metric: "尿酸")
        health.value = 480
        health.unit = "µmol/L"
        health.measuredAt = start
        context.insert(health)
        let review = ProgramWeeklyReview(programID: program.id, weekStart: start, weekEnd: FatLossCalendar.adding(6, to: start))
        review.snapshotJSON = "{\"recordedDays\":3}"
        review.notes = "按实际记录复盘"
        review.nextAction = "补全记录"
        context.insert(review)
        let template = WorkoutTemplate(name: "手动训练", weekday: 2)
        context.insert(template)
        let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name, plannedDate: start, isManuallyScheduled: true)
        context.insert(schedule)
        let link = ProgramWorkoutLink(programID: program.id, scheduledWorkoutID: schedule.id, templateCode: "A", originalDate: start)
        context.insert(link)
        let meal = MealEntry(date: start, mealType: .lunch, name: "已吃餐食", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        meal.programID = program.id
        meal.plannedMealID = plan.id
        meal.recipeSnapshotJSON = recipe.draftJSON
        meal.actualPortions = 1.5
        meal.nutritionKnown = false
        meal.estimationMethod = "未核算"
        meal.isVoided = true
        meal.tasteRating = 5
        meal.preparationDifficulty = 2
        meal.bloatingScore = 0
        meal.feedbackNotes = "保留作废事实"
        context.insert(meal)
        context.insert(JumpRopeEntry(count: 1000, durationSeconds: 900, activeDurationSeconds: 600, elapsedDurationSeconds: 1000, date: start))
        try context.save()

        let data = try backupData(context)
        let preview = try DataExportService.preview(data)
        XCTAssertEqual(preview.fatLossRecords, 8)
        let destination = try makeContainer()
        let first = try DataExportService.importBackup(data, into: destination.mainContext)
        XCTAssertGreaterThan(first.imported, 0)
        let second = try DataExportService.importBackup(data, into: destination.mainContext)
        XCTAssertEqual(second.imported, 0)
        XCTAssertGreaterThan(second.skipped, 0)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertEqual(restored.programID, program.id)
        XCTAssertEqual(restored.plannedMealID, plan.id)
        XCTAssertEqual(restored.recipeSnapshotJSON, recipe.draftJSON)
        XCTAssertEqual(restored.actualPortions, 1.5)
        XCTAssertFalse(restored.isNutritionKnown)
        XCTAssertFalse(restored.isActiveMeal)
        XCTAssertEqual(restored.tasteRating, 5)
        XCTAssertEqual(restored.bloatingScore, 0)
        XCTAssertEqual(restored.feedbackNotes, "保留作废事实")
        let rope = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertEqual(rope.durationSeconds, 900)
        XCTAssertEqual(rope.activeDurationSeconds, 600)
        XCTAssertEqual(rope.elapsedDurationSeconds, 1000)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<ProgramTargetRevision>()).first?.sourceNote, revision.sourceNote)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<ProgramDailyLog>()).first?.steps, 6543)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<ProgramHealthRecord>()).first?.value, 480)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<ProgramWeeklyReview>()).first?.snapshotJSON, review.snapshotJSON)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<ProgramWorkoutLink>()).first?.scheduledWorkoutID, schedule.id)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<PlannedMeal>()).first?.recipeID, recipe.id)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<RecipeVersion>()).first?.draftJSON, recipe.draftJSON)
    }

    func testSchema12WithoutOptionalFieldsImportsWithoutInventingNutritionOrJumpDurations() throws {
        let source = try makeContainer(includeProgram: false)
        source.mainContext.insert(MealEntry(date: start, mealType: .dinner, name: "旧记录", calories: 450, proteinGrams: 20, carbsGrams: 50, fatGrams: 10))
        source.mainContext.insert(JumpRopeEntry(count: 900, durationSeconds: 720, date: start))
        try source.mainContext.save()
        var json = try object(backupData(source.mainContext))
        json["schemaVersion"] = 12
        json.removeValue(forKey: "fatLoss")
        var ropes = try XCTUnwrap(json["jumpRopeEntries"] as? [[String: Any]])
        ropes[0].removeValue(forKey: "activeDurationSeconds")
        ropes[0].removeValue(forKey: "elapsedDurationSeconds")
        json["jumpRopeEntries"] = ropes
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: destination.mainContext)
        let meal = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertTrue(meal.isNutritionKnown)
        XCTAssertTrue(meal.isActiveMeal)
        XCTAssertNil(meal.programID)
        let rope = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertEqual(rope.durationSeconds, 720)
        XCTAssertNil(rope.activeDurationSeconds)
        XCTAssertNil(rope.elapsedDurationSeconds)
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<FatLossProgram>()).isEmpty)
    }

    func testInvalidNewJumpDurationsAreRejectedBeforeAnyBackupInsertion() throws {
        let source = try makeContainer()
        source.mainContext.insert(MealEntry(date: start, mealType: .lunch, name: "不应导入", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0))
        source.mainContext.insert(JumpRopeEntry(count: 1000, activeDurationSeconds: 1200, elapsedDurationSeconds: 600, date: start))
        try source.mainContext.save()
        let destination = try makeContainer()
        XCTAssertThrowsError(try DataExportService.importBackup(backupData(source.mainContext), into: destination.mainContext))
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<MealEntry>()).isEmpty)
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).isEmpty)
    }

    func testDuplicateProgramIdentifiersAreRejectedBeforeInsertion() throws {
        let source = try makeContainer()
        source.mainContext.insert(FatLossProgram(startDate: start, endDate: FatLossCalendar.adding(91, to: start)))
        try source.mainContext.save()
        var json = try object(backupData(source.mainContext))
        var payload = try XCTUnwrap(json["fatLoss"] as? [String: Any])
        let programs = try XCTUnwrap(payload["programs"] as? [[String: Any]])
        payload["programs"] = programs + programs
        json["fatLoss"] = payload
        let destination = try makeContainer()
        XCTAssertThrowsError(try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: destination.mainContext))
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<FatLossProgram>()).isEmpty)
    }

    func testPendingProgramTargetNeverFallsBackToLegacyAndHistoricalRevisionRemainsStable() throws {
        let container = try makeContainer()
        let program = FatLossProgram(startDate: start, endDate: FatLossCalendar.adding(91, to: start))
        container.mainContext.insert(program)
        let pending = ProgramTargetRevision(programID: program.id, effectiveDate: start, reason: "待确认")
        container.mainContext.insert(pending)
        let legacy = NutritionTarget()
        container.mainContext.insert(legacy)
        try container.mainContext.save()
        XCTAssertNil(NutritionDisplayTarget.resolve(on: start, legacy: legacy, in: container.mainContext).calories)
        let confirmed = ProgramTargetRevision(programID: program.id, effectiveDate: FatLossCalendar.adding(7, to: start), reason: "已确认")
        confirmed.isNutritionConfirmed = true
        confirmed.calories = 2000
        confirmed.proteinGrams = 100
        container.mainContext.insert(confirmed)
        try container.mainContext.save()
        XCTAssertNil(NutritionDisplayTarget.resolve(on: start, legacy: legacy, in: container.mainContext).protein)
        XCTAssertEqual(NutritionDisplayTarget.resolve(on: FatLossCalendar.adding(7, to: start), legacy: legacy, in: container.mainContext).calories, 2000)
        let oldStore = try makeContainer(includeProgram: false)
        XCTAssertEqual(NutritionDisplayTarget.resolve(on: start, legacy: nil, in: oldStore.mainContext).calories, 2400)
    }

    func testJumpRopeEntrySeparatesActiveAndElapsedAndValidatesBeforeSaving() throws {
        let container = try makeContainer(includeProgram: false)
        XCTAssertThrowsError(try WellnessToolService.recordJumpRope(count: 1000, activeDurationSeconds: 700, elapsedDurationSeconds: 600, at: start, in: container.mainContext))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).isEmpty)
        _ = try WellnessToolService.recordJumpRope(count: 1000, activeDurationSeconds: 600, elapsedDurationSeconds: 900, at: start, in: container.mainContext)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertNil(entry.durationSeconds)
        XCTAssertEqual(entry.activeDurationSeconds, 600)
        XCTAssertEqual(entry.elapsedDurationSeconds, 900)
    }

    func testMissingRecipeReferenceAndMalformedSnapshotRejectBeforeInsertion() throws {
        let source = try makeContainer()
        let program = FatLossProgram(startDate: start, endDate: FatLossCalendar.adding(91, to: start))
        source.mainContext.insert(program)
        let recipe = try RecipeVersion(draft: sampleRecipe())
        source.mainContext.insert(recipe)
        let plan = PlannedMeal(programID: program.id, date: start, mealType: .dinner, recipe: recipe)
        source.mainContext.insert(plan)
        try source.mainContext.save()
        let original = try object(backupData(source.mainContext))
        for mutation in ["missing-reference", "malformed-snapshot", "invalid-portions"] {
            var json = original
            var payload = try XCTUnwrap(json["fatLoss"] as? [String: Any])
            var plans = try XCTUnwrap(payload["plannedMeals"] as? [[String: Any]])
            if mutation == "missing-reference" {
                plans[0]["recipeID"] = UUID().uuidString
            } else if mutation == "malformed-snapshot" {
                plans[0]["recipeSnapshotJSON"] = "not-json"
            } else {
                var draft = sampleRecipe()
                draft.portions = 0
                plans[0]["recipeSnapshotJSON"] = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self)
            }
            payload["plannedMeals"] = plans
            json["fatLoss"] = payload
            let destination = try makeContainer()
            XCTAssertThrowsError(try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: destination.mainContext), mutation)
            XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<FatLossProgram>()).isEmpty, mutation)
        }
    }

    func testMissingActualMealAndWorkoutReferencesRejectBeforeInsertion() throws {
        let source = try makeContainer()
        let program = FatLossProgram(startDate: start, endDate: FatLossCalendar.adding(91, to: start))
        source.mainContext.insert(program)
        let meal = MealEntry(date: start, mealType: .lunch, name: "孤立餐食", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        meal.programID = program.id
        meal.plannedMealID = UUID()
        source.mainContext.insert(meal)
        try source.mainContext.save()
        let destination = try makeContainer()
        XCTAssertThrowsError(try DataExportService.importBackup(backupData(source.mainContext), into: destination.mainContext))
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<FatLossProgram>()).isEmpty)
        source.mainContext.delete(meal)
        source.mainContext.insert(ProgramWorkoutLink(programID: program.id, scheduledWorkoutID: UUID(), templateCode: "A", originalDate: start))
        try source.mainContext.save()
        XCTAssertThrowsError(try DataExportService.importBackup(backupData(source.mainContext), into: destination.mainContext))
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<FatLossProgram>()).isEmpty)
    }

    func testPartialKnownCaloriesAndExplicitZeroRemainDistinctAfterSaveReopenAndBackup() throws {
        let source = try makeContainer()
        let meal = MealEntry(date: start, mealType: .dinner, name: "只知热量", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        try MealNutritionInput(calories: "420", protein: "", carbs: "", fat: "0").apply(to: meal)
        source.mainContext.insert(meal)
        try source.mainContext.save()
        XCTAssertTrue(meal.isCalorieKnown)
        XCTAssertFalse(meal.isProteinKnown)
        XCTAssertFalse(meal.isCarbsKnown)
        XCTAssertTrue(meal.isFatKnown)
        XCTAssertFalse(meal.isNutritionKnown)
        XCTAssertEqual(meal.knownNutritionFieldsRaw, "calories,fat")
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(backupData(source.mainContext), into: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertEqual(restored.calories, 420)
        XCTAssertTrue(restored.isCalorieKnown)
        XCTAssertEqual(restored.fatGrams, 0)
        XCTAssertTrue(restored.isFatKnown)
        XCTAssertFalse(restored.isProteinKnown)
        XCTAssertFalse(restored.isCarbsKnown)
        XCTAssertFalse(restored.isNutritionKnown)
        XCTAssertEqual(restored.knownNutritionFieldsRaw, "calories,fat")
        // Reopening the editor must not convert unknown backing zeros into known values.
        try MealNutritionInput(calories: restored.isCalorieKnown ? String(restored.calories) : "",
                               protein: restored.isProteinKnown ? String(restored.proteinGrams) : "",
                               carbs: restored.isCarbsKnown ? String(restored.carbsGrams) : "",
                               fat: restored.isFatKnown ? String(restored.fatGrams) : "").apply(to: restored)
        XCTAssertEqual(restored.knownNutritionFieldsRaw, "calories,fat")
        try MealNutritionInput(calories: "420", protein: "", carbs: "", fat: "").apply(to: restored)
        XCTAssertEqual(restored.knownNutritionFieldsRaw, "calories")
        XCTAssertFalse(restored.isFatKnown)
        try destination.mainContext.save()
        let caloriesOnlyStore = try makeContainer()
        _ = try DataExportService.importBackup(backupData(destination.mainContext), into: caloriesOnlyStore.mainContext)
        let caloriesOnly = try XCTUnwrap(caloriesOnlyStore.mainContext.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertEqual(caloriesOnly.calories, 420)
        XCTAssertEqual(caloriesOnly.knownNutritionFieldsRaw, "calories")
        XCTAssertTrue(caloriesOnly.isCalorieKnown)
        XCTAssertFalse(caloriesOnly.isNutritionKnown)
        XCTAssertFalse(caloriesOnly.isFatKnown)
    }

    func testUnknownFieldNamesAreRejectedAndLegacyKnownFlagsRemainCompatible() throws {
        let source = try makeContainer()
        let meal = MealEntry(date: start, mealType: .lunch, name: "旧餐食", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        XCTAssertTrue(meal.isCalorieKnown)
        XCTAssertTrue(meal.isFatKnown)
        meal.nutritionKnown = false
        XCTAssertFalse(meal.isCalorieKnown)
        XCTAssertFalse(meal.isProteinKnown)
        meal.knownNutritionFieldsRaw = "calories,fiber"
        source.mainContext.insert(meal)
        try source.mainContext.save()
        let destination = try makeContainer()
        XCTAssertThrowsError(try DataExportService.importBackup(backupData(source.mainContext), into: destination.mainContext))
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<MealEntry>()).isEmpty)
        XCTAssertThrowsError(try MealNutritionInput(calories: "-1", protein: "", carbs: "", fat: ""))
        XCTAssertThrowsError(try MealNutritionInput(calories: "abc", protein: "", carbs: "", fat: ""))
    }

    func testHistoricalStoreCopyMigratesOnDiskWithoutChangingSourceOrLegacyIdentifiers() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let original = root.appending(path: "outputs/stage-validation/20260902-template-bilingual-volume-device/agent-acceptance/device-data/pre-test/default.store")
        guard FileManager.default.fileExists(atPath: original.path) else {
            throw XCTSkip("既有历史证据库不可访问；尚未验证磁盘迁移。")
        }
        let originalBytes = try Data(contentsOf: original)
        let folder = FileManager.default.temporaryDirectory.appending(path: "xfit-legacy-migration-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appending(path: "default.store")
        try FileManager.default.copyItem(at: original, to: copy)
        let wal = URL(fileURLWithPath: original.path + "-wal")
        if FileManager.default.fileExists(atPath: wal.path) {
            try FileManager.default.copyItem(at: wal, to: URL(fileURLWithPath: copy.path + "-wal"))
        }
        // Read SQLite only from the temporary copy, including before migration.
        let baseline = try identifiers(in: copy)
        XCTAssertGreaterThan(baseline["ZWORKOUTSESSION"]?.count ?? 0, 0)
        XCTAssertGreaterThan(baseline["ZSETLOG"]?.count ?? 0, 0)
        let schema = makeSchema(includeProgram: true)
        var container: ModelContainer? = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: copy, cloudKitDatabase: .none)])
        var migratedMealID: UUID?
        try autoreleasepool {
            let context = try XCTUnwrap(container).mainContext
            XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, baseline["ZWORKOUTSESSION"]?.count)
            XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).count, baseline["ZSETLOG"]?.count)
            XCTAssertTrue(try context.fetch(FetchDescriptor<FatLossProgram>()).isEmpty)
            let meal = MealEntry(date: start, mealType: .snack, name: "迁移后部分营养", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
            try MealNutritionInput(calories: "120", protein: "", carbs: "", fat: "0").apply(to: meal)
            context.insert(meal)
            migratedMealID = meal.id
            try context.save()
        }
        container = nil
        var reopened: ModelContainer? = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: copy, cloudKitDatabase: .none)])
        try autoreleasepool {
            let context = try XCTUnwrap(reopened).mainContext
            let meal = try XCTUnwrap(context.fetch(FetchDescriptor<MealEntry>()).first { $0.id == migratedMealID })
            XCTAssertEqual(meal.calories, 120)
            XCTAssertTrue(meal.isCalorieKnown)
            XCTAssertTrue(meal.isFatKnown)
            XCTAssertFalse(meal.isProteinKnown)
            context.delete(meal)
            try context.save()
        }
        reopened = nil
        XCTAssertEqual(try identifiers(in: copy), baseline)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }

    func testImportedTargetCannotBypassMedicalSourceReasonOrProgramDateGate() throws {
        let source = try makeContainer()
        let program = FatLossProgram(startDate: start, endDate: FatLossCalendar.adding(91, to: start))
        source.mainContext.insert(program)
        let target = ProgramTargetRevision(programID: program.id, effectiveDate: start, reason: "已确认调整")
        target.isNutritionConfirmed = true
        target.sourceNote = "医生建议与日期"
        target.calories = 2000
        source.mainContext.insert(target)
        try source.mainContext.save()
        let baseline = try object(backupData(source.mainContext))
        for mutation in ["missing-source", "missing-reason", "outside-period", "invalid-calories"] {
            var json = baseline
            var payload = try XCTUnwrap(json["fatLoss"] as? [String: Any])
            var targets = try XCTUnwrap(payload["targetRevisions"] as? [[String: Any]])
            switch mutation {
            case "missing-source": targets[0]["sourceNote"] = "  "
            case "missing-reason": targets[0]["reason"] = ""
            case "outside-period": targets[0]["effectiveDate"] = "2025-01-01T00:00:00Z"
            default: targets[0]["calories"] = 0
            }
            payload["targetRevisions"] = targets
            json["fatLoss"] = payload
            let destination = try makeContainer()
            XCTAssertThrowsError(try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: destination.mainContext), mutation)
            XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<FatLossProgram>()).isEmpty, mutation)
            XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<ProgramTargetRevision>()).isEmpty, mutation)
        }
    }

    func testExtremeRecipeBackupFailsBeforeAnyInsertion() throws {
        for mutation in ["tiny-portions", "large-portions", "calories", "grams", "cooking-time"] {
            let source = try makeContainer()
            let program = FatLossProgram(startDate: start, endDate: FatLossCalendar.adding(91, to: start))
            source.mainContext.insert(program)
            var draft = sampleRecipe()
            switch mutation {
            case "tiny-portions": draft.portions = 1e-300
            case "large-portions": draft.portions = 1001
            case "calories": draft.calories = 100001
            case "grams": draft.ingredients[0].referenceGrams = 100001
            default: draft.cookingMinutes = 1441
            }
            source.mainContext.insert(try RecipeVersion(draft: draft))
            try source.mainContext.save()
            let destination = try makeContainer()
            XCTAssertThrowsError(try DataExportService.importBackup(backupData(source.mainContext), into: destination.mainContext), mutation)
            XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<FatLossProgram>()).isEmpty, mutation)
            XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<RecipeVersion>()).isEmpty, mutation)
        }
    }

    private func identifiers(in url: URL) throws -> [String: [String]] {
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_close(connection) }
        let tables = ["ZEXERCISE", "ZWORKOUTTEMPLATE", "ZTEMPLATEEXERCISE", "ZSCHEDULEDWORKOUT",
                      "ZWORKOUTSESSION", "ZSESSIONEXERCISE", "ZSETLOG", "ZNUTRITIONTARGET", "ZMEALENTRY",
                      "ZDAILYBODYCHECKIN", "ZBODYMEASUREMENT", "ZHYDRATIONENTRY", "ZJUMPROPEENTRY", "ZSEDENTARYSESSION"]
        var result: [String: [String]] = [:]
        for table in tables {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, "SELECT hex(ZID) FROM \(table) ORDER BY hex(ZID)", -1, &statement, nil) == SQLITE_OK else {
                throw CocoaError(.fileReadCorruptFile)
            }
            var ids: [String] = []
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) { ids.append(String(cString: text)) }
                status = sqlite3_step(statement)
            }
            sqlite3_finalize(statement)
            guard status == SQLITE_DONE else { throw CocoaError(.fileReadCorruptFile) }
            result[table] = ids
        }
        return result
    }

    func testActiveProgramMedicalGateContinuesAfterEndpointWithoutRewritingEarlierHistory() throws {
        let store = try makeContainer(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let after = FatLossCalendar.adding(1, to: program.endDate)
        var display = NutritionDisplayTarget.resolve(on: after, legacy: nil, in: context)
        XCTAssertTrue(display.isProgram)
        XCTAssertNil(display.calories)
        XCTAssertNil(display.protein)
        let confirmed = ProgramTargetRevision(programID: program.id, effectiveDate: program.startDate, reason: "测试医嘱")
        confirmed.sourceNote = "测试来源"; confirmed.isNutritionConfirmed = true
        confirmed.calories = 2050; confirmed.proteinGrams = 80
        try FatLossService.saveTarget(confirmed, in: context)
        display = NutritionDisplayTarget.resolve(on: after, legacy: nil, in: context)
        XCTAssertEqual(display.calories, 2050)
        let pending = ProgramTargetRevision(programID: program.id, effectiveDate: program.endDate, reason: "等待复查配量")
        try FatLossService.saveTarget(pending, in: context)
        XCTAssertNil(NutritionDisplayTarget.resolve(on: after, legacy: nil, in: context).calories)
        let before = FatLossCalendar.adding(-30, to: program.startDate)
        XCTAssertFalse(NutritionDisplayTarget.resolve(on: before, legacy: nil, in: context).isProgram)
    }

    private func sampleRecipe() -> RecipeDraft {
        RecipeDraft(key: "test-rice", title: "测试饭", ingredients: [RecipeIngredient(name: "米饭", amountText: "一份")],
                    steps: ["加热"], equipment: ["微波炉"], householdPortion: "一份", cookingMinutes: 5, storageNote: "当餐食用")
    }

    private func backupData(_ context: ModelContext) throws -> Data {
        let url = try DataExportService.createBackup(in: context)
        return try Data(contentsOf: url)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeSchema(includeProgram: Bool) -> Schema {
        var models: [any PersistentModel.Type] = [Exercise.self, WorkoutTemplate.self, TemplateExercise.self,
            ScheduledWorkout.self, WorkoutSession.self, SessionExercise.self, SetLog.self, NutritionTarget.self,
            MealEntry.self, DailyBodyCheckIn.self, BodyMeasurement.self, HydrationEntry.self, JumpRopeEntry.self, SedentarySession.self]
        if includeProgram {
            models += [FatLossProgram.self, ProgramTargetRevision.self, RecipeVersion.self, PlannedMeal.self,
                ProgramDailyLog.self, ProgramHealthRecord.self, ProgramWeeklyReview.self, ProgramWorkoutLink.self]
        }
        return Schema(models)
    }

    private func makeContainer(includeProgram: Bool = true) throws -> ModelContainer {
        let schema = makeSchema(includeProgram: includeProgram)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
}
