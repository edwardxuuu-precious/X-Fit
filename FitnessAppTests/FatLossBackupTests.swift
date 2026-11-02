import SwiftData
import SQLite3
import XCTest
@testable import FitnessApp

@MainActor
final class FatLossBackupTests: XCTestCase {
    private let start = FatLossCalendar.date(2026, 9, 7)

    func testNotesRopeV4PreservesAggregateUnknownTimeAndCivilDay() throws {
        let source = try makeContainer(), context = source.mainContext
        let ropeID = UUID()
        func packet(_ rows: [[String: Any]], version: Int = 4) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["version": version, "packageID": "rope-source",
                "timeZoneIdentifier": "Asia/Shanghai", "workouts": [], "bodyMeasurements": [],
                "meals": [], "jumpRopeEntries": rows])
        }
        let item: [String: Any] = ["id": ropeID.uuidString, "date": "2026-10-27",
                                   "count": 1550, "totalSetCount": 8]
        let data = try packet([item])
        let before = Date()
        let first = try ConfirmedNotesImportService.importPackage(data, into: context)
        let again = try ConfirmedNotesImportService.importPackage(data, into: context)
        XCTAssertEqual(first.importedJumpRopeEntries, 1)
        XCTAssertEqual(again.importedJumpRopeEntries, 0)
        XCTAssertEqual(again.skippedJumpRopeEntries, 1)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertEqual(entry.id, ropeID)
        XCTAssertEqual(entry.count, 1550)
        XCTAssertEqual(entry.totalSetCount, 8)
        XCTAssertEqual(entry.recordedTimeKnown, false)
        XCTAssertEqual(entry.trainingLocalDay, "2026-10-27")
        XCTAssertEqual(entry.trainingTimeZoneIdentifier, "Asia/Shanghai")
        XCTAssertNil(entry.activeDurationSeconds)
        XCTAssertNil(entry.elapsedDurationSeconds)
        XCTAssertGreaterThanOrEqual(entry.createdAt, before)
        XCTAssertEqual(entry.displaySummary, "1550 个 · 8 组")

        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let localDay = try XCTUnwrap(TrainingLocalDate.date("2026-10-27", timeZone: zone))
        XCTAssertEqual(TrainingJumpRopeDate.localDay(entry, schedules: [], timeZone: zone), "2026-10-27")
        XCTAssertEqual(TrainingDaySummary(localDay: "2026-10-27", schedules: [], sessions: [],
            jumpRopeEntries: [entry], timeZone: zone).jumpRopeEntries.map(\.id), [ropeID])
        XCTAssertEqual(WellnessToolService.todaySummary(on: localDay, hydrationEntries: [],
            jumpRopeEntries: [entry], sedentarySessions: [], calendar: calendar).jumpRopeCount, 1550)
        let previousDay = try XCTUnwrap(TrainingLocalDate.date("2026-10-26", timeZone: zone))
        XCTAssertEqual(WellnessToolService.todaySummary(on: previousDay, hydrationEntries: [],
            jumpRopeEntries: [entry], sedentarySessions: [], calendar: calendar).jumpRopeCount, 0)
        let program = FatLossProgram(startDate: FatLossCalendar.date(2026, 10, 26),
                                     endDate: FatLossCalendar.date(2026, 10, 28))
        let timeline = try FatLossService.timeline(program: program, in: context)
        XCTAssertEqual(timeline.first { FatLossCalendar.label($0.date) == "2026-10-27" }?.jumpCount, 1550)

        var conflict = item
        conflict["count"] = 1549
        let newItem: [String: Any] = ["id": UUID().uuidString, "date": "2026-10-26", "count": 500]
        XCTAssertThrowsError(try ConfirmedNotesImportService.importPackage(packet([newItem, conflict]), into: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JumpRopeEntry>()), 1)
        XCTAssertThrowsError(try ConfirmedNotesImportService.importPackage(packet([item], version: 2), into: context))
        var invalid = item
        invalid["date"] = "2026-02-30"
        XCTAssertThrowsError(try ConfirmedNotesImportService.importPackage(packet([invalid]), into: context))
        invalid = item; invalid["totalSetCount"] = 0
        XCTAssertThrowsError(try ConfirmedNotesImportService.importPackage(packet([invalid]), into: context))
        invalid = item; invalid["recordedTimeKnown"] = true
        XCTAssertThrowsError(try ConfirmedNotesImportService.importPackage(packet([invalid]), into: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JumpRopeEntry>()), 1)
    }

    func testNotesV5DiscardsOnlyConfirmedDraftAndRetryIsIdempotent() throws {
        let (container, schedule, draft, packet) = try guardedNotesFixture()
        let context = container.mainContext
        let data = try JSONSerialization.data(withJSONObject: packet)
        let first = try ConfirmedNotesImportService.importPackage(data, into: context)
        XCTAssertEqual(first.discardedStaleSessions, 1)
        XCTAssertEqual(first.importedSessions, 1)
        XCTAssertEqual(first.importedSets, 1)
        XCTAssertEqual(draft.status, .discarded)
        XCTAssertEqual(schedule.status, .planned)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let ids = Set(sessions.map(\.id))
        let second = try ConfirmedNotesImportService.importPackage(data, into: context)
        XCTAssertEqual(second.importedSessions, 0)
        XCTAssertEqual(second.skippedSessions, 1)
        XCTAssertEqual(second.discardedStaleSessions, 0)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id)), ids)
    }

    func testNotesV5RejectsChangedDraftScheduleOrCompletedWorkout() throws {
        for caseIndex in 0..<6 {
            let (container, schedule, draft, original) = try guardedNotesFixture()
            let context = container.mainContext
            var packet = original
            switch caseIndex {
            case 0:
                var stale = try XCTUnwrap(packet["staleSession"] as? [String: Any])
                stale["expectedSessionID"] = UUID().uuidString
                packet["staleSession"] = stale
            case 1: schedule.status = .planned
            case 2:
                context.insert(SetLog(sessionID: draft.id, sessionExerciseID: UUID(), exerciseID: UUID(),
                    setNumber: 1, targetWeight: 10, targetReps: 5, actualWeight: 10,
                    actualReps: 5, isCompleted: true))
            case 3:
                let completed = WorkoutSession(templateName: "另一个实际训练", plannedDate: draft.plannedDate,
                    status: .completed)
                completed.trainingLocalDay = "2026-10-28"
                context.insert(completed)
            case 4: schedule.plannedLocalDay = "2026-10-29"
            default: packet["version"] = 2
            }
            try context.save()
            let oldSessionCount = try context.fetchCount(FetchDescriptor<WorkoutSession>())
            let oldSetCount = try context.fetchCount(FetchDescriptor<SetLog>())
            XCTAssertThrowsError(try ConfirmedNotesImportService.importPackage(
                JSONSerialization.data(withJSONObject: packet), into: context), "case \(caseIndex)")
            XCTAssertEqual(draft.status, .inProgress)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), oldSessionCount)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), oldSetCount)
            XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
        }
    }

    func testRopeV18BackupRestoresMetadataAndV17KeepsLegacySemantics() throws {
        let source = try makeContainer(includeProgram: false), context = source.mainContext
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let date = try XCTUnwrap(TrainingLocalDate.date("2026-10-27", timeZone: zone))
        let entry = JumpRopeEntry(count: 1550, date: date)
        entry.totalSetCount = 8
        entry.recordedTimeKnown = false
        entry.trainingLocalDay = "2026-10-27"
        entry.trainingTimeZoneIdentifier = zone.identifier
        context.insert(entry); try context.save()
        let data = try backupData(context)
        var json = try object(data)
        XCTAssertEqual(json["schemaVersion"] as? Int, 19)
        let destination = try makeContainer(includeProgram: false)
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertEqual(restored.id, entry.id)
        XCTAssertEqual(restored.count, 1550)
        XCTAssertEqual(restored.totalSetCount, 8)
        XCTAssertEqual(restored.recordedTimeKnown, false)
        XCTAssertEqual(restored.trainingLocalDay, "2026-10-27")
        XCTAssertEqual(restored.trainingTimeZoneIdentifier, "Asia/Shanghai")
        XCTAssertNil(restored.activeDurationSeconds)
        XCTAssertEqual(try DataExportService.importBackup(data, into: destination.mainContext).imported, 0)

        var rows = try XCTUnwrap(json["jumpRopeEntries"] as? [[String: Any]])
        rows[0]["totalSetCount"] = 0
        json["jumpRopeEntries"] = rows
        let invalidDestination = try makeContainer(includeProgram: false)
        XCTAssertThrowsError(try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: invalidDestination.mainContext))
        XCTAssertEqual(try invalidDestination.mainContext.fetchCount(FetchDescriptor<JumpRopeEntry>()), 0)

        json = try object(data)
        rows = try XCTUnwrap(json["jumpRopeEntries"] as? [[String: Any]])
        for key in ["totalSetCount", "recordedTimeKnown", "trainingLocalDay", "trainingTimeZoneIdentifier"] {
            rows[0].removeValue(forKey: key)
        }
        json["jumpRopeEntries"] = rows
        json["schemaVersion"] = 17
        let legacyDestination = try makeContainer(includeProgram: false)
        _ = try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: legacyDestination.mainContext)
        let legacy = try XCTUnwrap(legacyDestination.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertNil(legacy.totalSetCount)
        XCTAssertNil(legacy.recordedTimeKnown)
        XCTAssertNil(legacy.trainingLocalDay)
        XCTAssertEqual(legacy.count, 1550)
    }

    func testRopeInputRejectsInvalidGroupsBeforeSaving() throws {
        let store = try makeContainer(includeProgram: false), context = store.mainContext
        XCTAssertThrowsError(try WellnessToolService.recordJumpRope(count: 1550,
            activeDurationSeconds: nil, elapsedDurationSeconds: nil, at: start,
            totalSetCount: 0, recordedTimeKnown: false, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JumpRopeEntry>()), 0)
        _ = try WellnessToolService.recordJumpRope(count: 1550, activeDurationSeconds: nil,
            elapsedDurationSeconds: nil, at: start, totalSetCount: 8, recordedTimeKnown: false, in: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertEqual(entry.totalSetCount, 8)
        XCTAssertEqual(entry.recordedTimeKnown, false)
        XCTAssertEqual(entry.trainingLocalDay, TrainingLocalDate.key(start))
        XCTAssertEqual(entry.trainingTimeZoneIdentifier, TimeZone.current.identifier)
        XCTAssertNil(entry.activeDurationSeconds)
    }

    func testDateMenuBackupPreservesTypedTargetsExplicitLinksAndUnlinkedLegacyRecords() throws {
        let source = try makeContainer(includeProgram: true)
        let day = TrainingLocalDate.key(Date.now.addingDays(-1))
        let plan = JumpRopeMenuPlan(targetCount: nil, activeSeconds: 600, elapsedSeconds: 900, notes: "本人间歇目标")
        let schedule = try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: day, in: source.mainContext)
        let recordID = try TrainingDateMenuService.recordJumpRope(schedule: schedule, count: nil,
            active: 480, elapsed: 800, at: TrainingLocalDate.date(day)!, in: source.mainContext)
        let legacy = JumpRopeEntry(count: nil, durationSeconds: 420, date: start)
        source.mainContext.insert(legacy); try source.mainContext.save()
        let data = try backupData(source.mainContext)
        let destination = try makeContainer(includeProgram: true)
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        let entries = try destination.mainContext.fetch(FetchDescriptor<JumpRopeEntry>())
        XCTAssertEqual(restored.id, schedule.id)
        XCTAssertEqual(restored.jumpRopePlan, plan)
        XCTAssertEqual(entries.first { $0.id == recordID }?.scheduledWorkoutID, schedule.id)
        XCTAssertNil(entries.first { $0.id == recordID }?.count)
        XCTAssertNil(entries.first { $0.id == legacy.id }?.scheduledWorkoutID)
        XCTAssertEqual(entries.first { $0.id == legacy.id }?.durationSeconds, 420)
        XCTAssertNil(entries.first { $0.id == legacy.id }?.activeDurationSeconds)
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<JumpRopeEntry>()), 2)
    }

    func testSessionBackupPreservesCivilOwnershipAndLegacyRawPlannedDate() throws {
        let source = try makeContainer(includeProgram: false)
        let rawPlan = ISO8601DateFormatter().date(from: "2026-09-26T16:00:00Z")!
        let actualStart = rawPlan.addingTimeInterval(30 * 60)
        let session = WorkoutSession(templateName: "跨时区历史", plannedDate: rawPlan,
            startedAt: actualStart, status: .completed)
        session.plannedDate = rawPlan
        session.trainingLocalDay = "2026-09-27"
        session.trainingTimeZoneIdentifier = "Asia/Shanghai"
        source.mainContext.insert(session)
        try source.mainContext.save()
        let data = try backupData(source.mainContext)
        let destination = try makeContainer(includeProgram: false)
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(restored.trainingLocalDay, "2026-09-27")
        XCTAssertEqual(restored.trainingTimeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(restored.plannedDate, rawPlan)
        XCTAssertEqual(restored.startedAt, actualStart)

        var legacyJSON = try object(data)
        var rows = try XCTUnwrap(legacyJSON["sessions"] as? [[String: Any]])
        rows[0].removeValue(forKey: "trainingLocalDay")
        rows[0].removeValue(forKey: "trainingTimeZoneIdentifier")
        legacyJSON["sessions"] = rows
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        let legacyDestination = try makeContainer(includeProgram: false)
        _ = try DataExportService.importBackup(legacyData, into: legacyDestination.mainContext)
        let legacy = try XCTUnwrap(legacyDestination.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertNil(legacy.trainingLocalDay)
        XCTAssertNil(legacy.trainingTimeZoneIdentifier)
        XCTAssertEqual(legacy.plannedDate, rawPlan)
        XCTAssertEqual(legacy.startedAt, actualStart)
    }

    func testSchema14RoundTripPreservesEveryProgramEntityAndMealFacts() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let program = FatLossProgram(startDate: start, endDate: FatLossCalendar.adding(91, to: start))
        context.insert(program)
        let preference = try TrainingPreferenceRevision(
            snapshot: .confirmed,
            revision: 1,
            effectiveAt: start,
            reason: "用户确认四日部位分化"
        )
        context.insert(preference)
        let trainingProgram = try TrainingProgramRevision(
            programID: program.id,
            preferenceRevision: preference,
            snapshot: FatLossCatalog.trainingProgram(preference: .confirmed),
            revision: 1,
            effectiveDate: start,
            reason: "保存编排快照"
        )
        context.insert(trainingProgram)
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
        link.trainingProgramRevisionID = trainingProgram.id
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
        XCTAssertEqual(preview.fatLossRecords, 10)
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
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<TrainingPreferenceRevision>()).first?.revisionCode, preference.revisionCode)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<TrainingProgramRevision>()).first?.preferenceRevisionID, preference.id)
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

    func testSchema13WithoutTrainingPreferenceCollectionsStillImportsWithoutInventingVersions() throws {
        let source = try makeContainer()
        source.mainContext.insert(FatLossProgram(startDate: start, endDate: FatLossCalendar.adding(91, to: start)))
        try source.mainContext.save()
        var json = try object(backupData(source.mainContext))
        json["schemaVersion"] = 13
        var fatLoss = try XCTUnwrap(json["fatLoss"] as? [String: Any])
        fatLoss.removeValue(forKey: "trainingPreferences")
        fatLoss.removeValue(forKey: "trainingPrograms")
        json["fatLoss"] = fatLoss

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: destination.mainContext)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<FatLossProgram>()).count, 1)
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<TrainingPreferenceRevision>()).isEmpty)
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<TrainingProgramRevision>()).isEmpty)
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

    func testDurationOnlyRopeBackupKeepsCountUnknownAndRestoresIdempotently() throws {
        let source = try makeContainer(includeProgram: false)
        source.mainContext.insert(JumpRopeEntry(count: 1200, activeDurationSeconds: 600,
                                               elapsedDurationSeconds: 900, date: start))
        try source.mainContext.save()
        var json = try object(backupData(source.mainContext))
        var rows = try XCTUnwrap(json["jumpRopeEntries"] as? [[String: Any]])
        rows[0].removeValue(forKey: "count") // Observed duration, never an observed count.
        json["jumpRopeEntries"] = rows
        let data = try JSONSerialization.data(withJSONObject: json)
        let destination = try makeContainer(includeProgram: false)
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertNil(restored.count as Int?)
        XCTAssertEqual(restored.activeDurationSeconds, 600)
        XCTAssertEqual(restored.elapsedDurationSeconds, 900)
        let exported = try object(backupData(destination.mainContext))
        let exportedRows = try XCTUnwrap(exported["jumpRopeEntries"] as? [[String: Any]])
        XCTAssertNil(exportedRows[0]["count"])
        XCTAssertEqual(try DataExportService.importBackup(data, into: destination.mainContext).imported, 0)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).count, 1)
    }

    func testDurationOnlyRopeCompletesOnlySelectedScheduleAndUnknownTotalStaysUnknown() throws {
        let store = try makeContainer(includeProgram: false), context = store.mainContext
        let linked = ScheduledWorkout(templateID: UUID(), templateName: "轻松跳绳", plannedDate: start)
        let unrelated = ScheduledWorkout(templateID: UUID(), templateName: "单车", plannedDate: start)
        context.insert(linked); context.insert(unrelated)
        try context.save()
        XCTAssertThrowsError(try WellnessToolService.recordJumpRope(count: nil, activeDurationSeconds: nil,
            elapsedDurationSeconds: nil, at: start, in: context))
        XCTAssertThrowsError(try WellnessToolService.recordJumpRope(count: 0, activeDurationSeconds: 600,
            elapsedDurationSeconds: 900, at: start, in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<JumpRopeEntry>()).isEmpty)
        let result = try WellnessToolService.recordJumpRope(count: nil, activeDurationSeconds: 600,
            elapsedDurationSeconds: 900, at: start, scheduledWorkoutID: linked.id, in: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertNil(entry.count)
        XCTAssertEqual(entry.activeDurationSeconds, 600)
        XCTAssertEqual(entry.elapsedDurationSeconds, 900)
        XCTAssertEqual(linked.status, .completed)
        XCTAssertEqual(unrelated.status, .planned)
        XCTAssertTrue(result.message.contains("次数未知"))
        XCTAssertNil(WellnessToolService.todaySummary(on: start, hydrationEntries: [],
            jumpRopeEntries: [entry, JumpRopeEntry(count: 1000, date: start)], sedentarySessions: []).jumpRopeCount)
        XCTAssertThrowsError(try WellnessToolService.recordJumpRope(count: nil, activeDurationSeconds: 600,
            elapsedDurationSeconds: 900, at: start, scheduledWorkoutID: linked.id, in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<JumpRopeEntry>()).count, 1)
    }

    func testJumpRopeEntryCompletesOnlyItsLinkedSchedule() throws {
        let container = try makeContainer(includeProgram: false)
        let linked = ScheduledWorkout(
            templateID: UUID(),
            templateName: "跳绳间歇 · 技术与燃脂",
            plannedDate: start
        )
        let unrelated = ScheduledWorkout(
            templateID: UUID(),
            templateName: "下肢后链＋足踝 · 高消耗",
            plannedDate: start
        )
        container.mainContext.insert(linked)
        container.mainContext.insert(unrelated)
        try container.mainContext.save()

        _ = try WellnessToolService.recordJumpRope(
            count: 1_200,
            activeDurationSeconds: 600,
            elapsedDurationSeconds: 900,
            at: start,
            scheduledWorkoutID: linked.id,
            in: container.mainContext
        )

        XCTAssertEqual(linked.status, .completed)
        XCTAssertEqual(unrelated.status, .planned)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).count, 1)
    }

    func testJumpRopeCompletionUsesScheduledCivilDayRatherThanRawInstant() throws {
        let schema = Schema([ScheduledWorkout.self, JumpRopeEntry.self])
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = store.mainContext
        let enteredDate = try XCTUnwrap(TrainingLocalDate.date("2026-09-24"))
        let raw = FatLossCalendar.date(2026, 9, 23)
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "跳绳", plannedDate: raw, status: .skipped)
        schedule.plannedDate = raw
        schedule.plannedLocalDay = "2026-09-24"
        schedule.plannedTimeZoneIdentifier = "Australia/Sydney"
        context.insert(schedule)
        try context.save()

        XCTAssertThrowsError(try WellnessToolService.recordJumpRope(count: 100, activeDurationSeconds: 60,
            elapsedDurationSeconds: 90, at: TrainingLocalDate.date("2026-09-23")!,
            scheduledWorkoutID: schedule.id, in: context))
        XCTAssertEqual(schedule.status, .skipped)
        let result = try WellnessToolService.recordJumpRope(count: 100, activeDurationSeconds: 60,
            elapsedDurationSeconds: 90, at: enteredDate, scheduledWorkoutID: schedule.id, in: context)
        XCTAssertNotNil(result.recordID)
        XCTAssertEqual(schedule.status, .completed)
        XCTAssertEqual(schedule.plannedDate, raw)
        XCTAssertEqual(schedule.plannedLocalDay, "2026-09-24")
        XCTAssertThrowsError(try WellnessToolService.recordJumpRope(count: 100, activeDurationSeconds: 60,
            elapsedDurationSeconds: 90, at: enteredDate, scheduledWorkoutID: schedule.id, in: context))
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
            XCTAssertTrue(try context.fetch(FetchDescriptor<SetLog>()).allSatisfy { $0.reductionOrder == nil })
            XCTAssertTrue(try context.fetch(FetchDescriptor<SessionExercise>()).allSatisfy { $0.hasManuallyReducedSets == nil })
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
        func readFailure(_ code: Int32, stage: String) -> NSError {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "no SQLite connection"
            return NSError(domain: "XFitSQLiteRead", code: Int(code), userInfo: [
                NSLocalizedDescriptionKey: "\(stage): SQLite \(code): \(message)"
            ])
        }
        let openStatus = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil)
        guard openStatus == SQLITE_OK else {
            let failure = readFailure(openStatus, stage: "open temporary migration copy")
            if let connection { sqlite3_close(connection) }
            throw failure
        }
        defer { sqlite3_close(connection) }
        let tables = ["ZEXERCISE", "ZWORKOUTTEMPLATE", "ZTEMPLATEEXERCISE", "ZSCHEDULEDWORKOUT",
                      "ZWORKOUTSESSION", "ZSESSIONEXERCISE", "ZSETLOG", "ZNUTRITIONTARGET", "ZMEALENTRY",
                      "ZDAILYBODYCHECKIN", "ZBODYMEASUREMENT", "ZHYDRATIONENTRY", "ZJUMPROPEENTRY", "ZSEDENTARYSESSION"]
        var result: [String: [String]] = [:]
        for table in tables {
            var statement: OpaquePointer?
            let prepared = sqlite3_prepare_v2(connection, "SELECT hex(ZID) FROM \(table) ORDER BY hex(ZID)", -1, &statement, nil)
            guard prepared == SQLITE_OK else {
                throw readFailure(prepared, stage: "prepare \(table)")
            }
            var ids: [String] = []
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) { ids.append(String(cString: text)) }
                status = sqlite3_step(statement)
            }
            let failure = status == SQLITE_DONE ? nil : readFailure(status, stage: "step \(table)")
            sqlite3_finalize(statement)
            if let failure { throw failure }
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


    func testMalformedTrainingVersionsRejectBeforeAnyInsertion() throws {
        let source = try makeContainer()
        _ = try FatLossService.createProgram(in: source.mainContext)
        let original = try object(backupData(source.mainContext))
        for mutation in ["negative-sets", "invalid-weekday", "bad-cardio-time", "missing-preference"] {
            var json = original
            var payload = try XCTUnwrap(json["fatLoss"] as? [String: Any])
            var records = try XCTUnwrap(payload["trainingPrograms"] as? [[String: Any]])
            var snapshot = try JSONDecoder().decode(TrainingProgramSnapshot.self, from: Data((records[0]["snapshotJSON"] as! String).utf8))
            switch mutation {
            case "negative-sets": snapshot.strengthWorkouts[0].exercises[0].sets = -1
            case "invalid-weekday": snapshot.strengthWorkouts[0].weekday = 9
            case "bad-cardio-time": snapshot.cardioWorkouts[0].activeSeconds = 1300
            default: records[0]["preferenceRevisionID"] = UUID().uuidString
            }
            records[0]["snapshotJSON"] = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
            payload["trainingPrograms"] = records; json["fatLoss"] = payload
            let destination = try makeContainer()
            XCTAssertThrowsError(try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: destination.mainContext), mutation)
            XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<FatLossProgram>()).isEmpty)
            XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<TrainingPreferenceRevision>()).isEmpty)
        }
    }

    func testBackupCannotChangeImmutableTrainingVersionWithSameUUID() throws {
        let store = try makeContainer(), context = store.mainContext
        _ = try FatLossService.createProgram(in: context)
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingProgramRevision>()).first)
        let originalJSON = original.snapshotJSON
        var json = try object(backupData(context))
        var payload = try XCTUnwrap(json["fatLoss"] as? [String: Any])
        var records = try XCTUnwrap(payload["trainingPrograms"] as? [[String: Any]])
        var snapshot = try XCTUnwrap(original.snapshot)
        snapshot.strengthWorkouts[0].exercises[0].sets = 2
        records[0]["snapshotJSON"] = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        payload["trainingPrograms"] = records; json["fatLoss"] = payload
        XCTAssertThrowsError(try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: context))
        XCTAssertEqual(original.snapshotJSON, originalJSON)
    }

    func testDuplicatePreferenceCodeInsideBackupRejectsBeforeAnyInsertion() throws {
        let source = try makeContainer()
        _ = try FatLossService.createProgram(in: source.mainContext)
        source.mainContext.insert(Exercise(name: "不应导入的动作", muscleGroup: "胸部", equipment: "杠铃"))
        try source.mainContext.save()
        let data = try backupWithConflictingPreferenceCode(in: source.mainContext, includesOriginal: true)
        let destination = try makeContainer(), context = destination.mainContext

        XCTAssertThrowsError(try DataExportService.importBackup(data, into: context)) { error in
            XCTAssertTrue(error.localizedDescription.contains("同一训练偏好版本号对应不同标识"))
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FatLossProgram>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingProgramRevision>()).isEmpty)
    }

    func testPreferenceCodeConflictingWithDatabaseRejectsBeforeAnyInsertion() throws {
        let source = try makeContainer()
        _ = try FatLossService.createProgram(in: source.mainContext)
        source.mainContext.insert(Exercise(name: "不应导入的动作", muscleGroup: "胸部", equipment: "杠铃"))
        try source.mainContext.save()
        let data = try backupWithConflictingPreferenceCode(in: source.mainContext, includesOriginal: false)
        let destination = try makeContainer(), context = destination.mainContext
        let existing = try XCTUnwrap(TrainingPreferenceService.ensureConfirmedProfile(in: context))
        let existingJSON = existing.snapshotJSON

        XCTAssertThrowsError(try DataExportService.importBackup(data, into: context)) { error in
            XCTAssertTrue(error.localizedDescription.contains("同一训练偏好版本号对应不同标识"))
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FatLossProgram>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingProgramRevision>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).map(\.id), [existing.id])
        XCTAssertEqual(existing.snapshotJSON, existingJSON)
    }

    func testTrainingVersionSelectionSupportsFutureAndExplicitHistory() throws {
        let preference = try TrainingPreferenceRevision(snapshot: .confirmed, revision: 1,
            effectiveAt: start, reason: "测试偏好")
        let snapshot = FatLossCatalog.trainingProgram(preference: .confirmed)
        let previous = try TrainingProgramRevision(programID: nil, preferenceRevision: preference,
            snapshot: snapshot, revision: 1, effectiveDate: start, reason: "历史编排")
        let next = try TrainingProgramRevision(programID: nil, preferenceRevision: preference,
            snapshot: snapshot, revision: 2, effectiveDate: FatLossCalendar.adding(7, to: start), reason: "未来编排")
        let today = FatLossCalendar.adding(2, to: start)

        XCTAssertEqual(TrainingPlanPresentation.selectedRevision(in: [next], selectedID: nil, now: today)?.id, next.id)
        XCTAssertEqual(TrainingPlanPresentation.selectedRevision(in: [next, previous], selectedID: nil, now: today)?.id, previous.id)
        XCTAssertEqual(TrainingPlanPresentation.selectedRevision(in: [previous, next], selectedID: next.id, now: today)?.id, next.id)
        next.snapshotJSON = "damaged"
        XCTAssertEqual(TrainingPlanPresentation.selectedRevision(in: [next, previous], selectedID: previous.id,
            now: FatLossCalendar.adding(9, to: start))?.id, previous.id)
    }

    func testJumpRopeInitialDateKeepsHistoryAndClampsFuture() {
        let now = FatLossCalendar.adding(3, to: start).addingTimeInterval(12 * 3600)
        XCTAssertEqual(TrainingPlanPresentation.initialActualDate(selectedDate: start, now: now), start)
        XCTAssertEqual(TrainingPlanPresentation.initialActualDate(selectedDate: now, now: now), now)
        XCTAssertEqual(TrainingPlanPresentation.initialActualDate(selectedDate: FatLossCalendar.adding(7, to: start), now: now), now)
    }

    private func backupWithConflictingPreferenceCode(in context: ModelContext, includesOriginal: Bool) throws -> Data {
        var json = try object(backupData(context))
        var payload = try XCTUnwrap(json["fatLoss"] as? [String: Any])
        var preferences = try XCTUnwrap(payload["trainingPreferences"] as? [[String: Any]])
        var duplicate = try XCTUnwrap(preferences.first)
        let newID = UUID().uuidString
        duplicate["id"] = newID
        let snapshotJSON = try XCTUnwrap(duplicate["snapshotJSON"] as? String)
        var snapshot = try JSONDecoder().decode(TrainingPreferenceSnapshot.self, from: Data(snapshotJSON.utf8))
        snapshot.zone2Minutes = 35
        duplicate["snapshotJSON"] = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        if includesOriginal {
            preferences.append(duplicate)
        } else {
            preferences = [duplicate]
            var programs = try XCTUnwrap(payload["trainingPrograms"] as? [[String: Any]])
            for index in programs.indices { programs[index]["preferenceRevisionID"] = newID }
            payload["trainingPrograms"] = programs
        }
        payload["trainingPreferences"] = preferences
        json["fatLoss"] = payload
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func backupData(_ context: ModelContext) throws -> Data {
        let url = try DataExportService.createBackup(in: context)
        return try Data(contentsOf: url)
    }

    private func guardedNotesFixture() throws -> (ModelContainer, ScheduledWorkout, WorkoutSession, [String: Any]) {
        let container = try makeContainer()
        let context = container.mainContext
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let day = try XCTUnwrap(TrainingLocalDate.date("2026-10-28", timeZone: zone))
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "原计划", plannedDate: day, status: .inProgress)
        schedule.plannedLocalDay = "2026-10-28"
        schedule.plannedTimeZoneIdentifier = zone.identifier
        let draft = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: "原计划",
            plannedDate: day, status: .inProgress)
        context.insert(schedule); context.insert(draft); try context.save()
        let packet: [String: Any] = [
            "version": 5, "packageID": "guarded-draft-test", "timeZoneIdentifier": zone.identifier,
            "workouts": [["id": "actual", "date": "2026-10-28", "name": "实际训练", "notes": "",
                "exercises": [["name": "新动作", "muscleGroup": "腿部", "equipment": "器械",
                    "volumeUnit": "kilogram", "notes": "", "sets": [["weight": 30, "reps": 10,
                        "weightSide": "bilateral", "repsSide": "bilateral"]]]]]],
            "bodyMeasurements": [], "meals": [], "jumpRopeEntries": [],
            "staleSession": ["plannedDate": "2026-10-28", "templateName": "原计划",
                "expectedSessionID": draft.id.uuidString, "expectedScheduledWorkoutID": schedule.id.uuidString]
        ]
        return (container, schedule, draft, packet)
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
                ProgramDailyLog.self, ProgramHealthRecord.self, ProgramWeeklyReview.self, ProgramWorkoutLink.self,
                TrainingPreferenceRevision.self, TrainingProgramRevision.self]
        }
        return Schema(models)
    }

    private func makeContainer(includeProgram: Bool = true) throws -> ModelContainer {
        let schema = makeSchema(includeProgram: includeProgram)
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
}
