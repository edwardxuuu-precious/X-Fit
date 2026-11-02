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
                             ProgramDailyLog.self, ProgramHealthRecord.self, ProgramWeeklyReview.self, ProgramWorkoutLink.self,
                             TrainingPreferenceRevision.self, TrainingProgramRevision.self])
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
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingProgramRevision>()).count, 1)
        XCTAssertEqual(try TrainingPreferenceService.current(in: context)?.revisionCode, "TP-20260908-02")
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingProgramRevision>()).first?.snapshot?.code, "CUT-4D-20260908-R2")
        let target = try XCTUnwrap(FatLossService.target(program: program, on: program.startDate, in: context))
        XCTAssertNil(target.calories)
        XCTAssertNil(target.proteinGrams)
        XCTAssertFalse(target.isNutritionConfirmed)
        let urate = try XCTUnwrap(context.fetch(FetchDescriptor<ProgramHealthRecord>()).first { $0.metric == "尿酸" })
        XCTAssertNil(urate.measuredAt)
        XCTAssertNil(urate.unit)
    }

    func testPreferenceChangeAppendsVersionAndCreatesNewProgramSnapshotWithoutScheduling() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let original = try XCTUnwrap(TrainingPreferenceService.current(in: context))
        var changed = try XCTUnwrap(original.snapshot)
        changed.revisionCode = "TP-TEST-02"
        changed.zone2Minutes = 35
        let appended = try TrainingPreferenceService.append(
            snapshot: changed,
            effectiveAt: .now.addingTimeInterval(-1),
            reason: "测试追加版本",
            in: context
        )
        XCTAssertNotEqual(appended.id, original.id)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).count, 2)
        XCTAssertEqual(try TrainingPreferenceService.current(in: context)?.id, appended.id)
        _ = try TrainingPreferenceService.ensureProgramRevision(programID: program.id, effectiveDate: .now, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingProgramRevision>()).count, 1, "读取不应自动重新编排")
        _ = try TrainingPreferenceService.appendProgram(
            snapshot: FatLossCatalog.trainingProgram(preference: changed), preference: appended,
            programID: program.id, effectiveDate: .now, reason: "用户确认延长单车", in: context)
        let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>())
        XCTAssertEqual(revisions.count, 2)
        XCTAssertEqual(revisions.first { $0.preferenceRevisionID == appended.id }?.snapshot?.preferenceRevisionCode, "TP-TEST-02")
        XCTAssertEqual(revisions.first { $0.preferenceRevisionID == appended.id }?.snapshot?.cardioWorkouts.first { $0.code == "ZONE2_FRI" }?.activeSeconds, 2100)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ScheduledWorkout>()).isEmpty)
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
        let tuesday = FatLossCalendar.date(2026, 9, 8)
        let existing = ScheduledWorkout(templateID: UUID(), templateName: "真实已有计划", plannedDate: tuesday, isManuallyScheduled: true)
        context.insert(existing); try context.save()
        XCTAssertThrowsError(try FatLossService.importWorkouts(program: program, from: FatLossCalendar.date(2026, 9, 8), days: 7, in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: FatLossCalendar.date(2026, 9, 8), days: 7, conflictPolicy: .skipConflicts, in: context), 3)
        XCTAssertEqual(existing.templateName, "真实已有计划")
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: FatLossCalendar.date(2026, 9, 8), days: 7, conflictPolicy: .skipConflicts, in: context), 0)
    }

    func testManualTuesdayWorkoutIsKeptWhileRemainingThreeDaysCanImport() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let tuesday = FatLossCalendar.date(2026, 9, 8)
        let manual = WorkoutSession(templateName: "推 · 胸肩三头", plannedDate: tuesday,
            startedAt: tuesday.addingTimeInterval(8 * 3600), status: .completed,
            notes: "本人当天实际训练")
        context.insert(manual)
        try context.save()

        let preview = try FatLossService.importPreview(program: program, from: tuesday, days: 7, in: context)
        let summary = ProgramImportSummary(preview: preview)
        XCTAssertEqual(summary.importableCount, 3)
        XCTAssertEqual(summary.conflictCount, 1)
        XCTAssertEqual(summary.alreadyImportedCount, 0)
        XCTAssertEqual(summary.actionTitle, "导入其余 3 天")
        XCTAssertTrue(summary.canImport)
        XCTAssertTrue(preview.first { FatLossCalendar.sameDay($0.date, tuesday) }?.conflictingNames.contains(manual.templateName) == true)

        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: tuesday, days: 7,
            conflictPolicy: .skipConflicts, expectedPreview: preview, in: context), 3)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id), [manual.id])
        XCTAssertFalse(try context.fetch(FetchDescriptor<ScheduledWorkout>()).contains { FatLossCalendar.sameDay($0.plannedDate, tuesday) })
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: tuesday, days: 7,
            conflictPolicy: .skipConflicts, in: context), 0)
    }

    func testStrengthAndCardioPreviewUseCivilDatesWithoutRewritingStoredInstants() throws {
        let (store, program) = try civilPreviewFixture()
        let context = store.mainContext
        let strengthRaw = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-21T00:00:00+14:00"))
        let cardioRaw = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-24T00:00:00+14:00"))
        let strength = ScheduledWorkout(templateID: UUID(), templateName: "当地胸肩", plannedDate: strengthRaw)
        strength.plannedDate = strengthRaw
        strength.plannedLocalDay = "2026-09-21"
        strength.plannedTimeZoneIdentifier = "Pacific/Kiritimati"
        let cardio = ScheduledWorkout(templateID: UUID(), templateName: "当地恢复单车", plannedDate: cardioRaw)
        cardio.plannedDate = cardioRaw
        cardio.plannedLocalDay = "2026-09-24"
        cardio.plannedTimeZoneIdentifier = "Pacific/Kiritimati"
        let free = WorkoutSession(templateName: "自行训练", plannedDate: TrainingLocalDate.date("2026-09-22")!, status: .completed)
        context.insert(strength); context.insert(cardio); context.insert(free)
        try context.save()

        let start = FatLossCalendar.date(2026, 9, 21)
        let strengthPreview = try FatLossService.importPreview(program: program, from: start, in: context)
        XCTAssertEqual(strengthPreview.first { FatLossCalendar.label($0.date) == "2026-09-21" }?.conflictingNames, ["当地胸肩"])
        XCTAssertEqual(strengthPreview.first { FatLossCalendar.label($0.date) == "2026-09-22" }?.conflictingNames, ["自行训练"])
        XCTAssertEqual(strengthPreview.first { FatLossCalendar.label($0.date) == "2026-09-23" }?.conflictingNames, [])
        let cardioPreview = try FatLossService.cardioImportPreview(program: program, from: start, days: 7, in: context)
        XCTAssertEqual(cardioPreview.first { FatLossCalendar.label($0.date) == "2026-09-24" }?.conflictingNames, ["当地恢复单车"])
        XCTAssertEqual(strength.plannedDate, strengthRaw)
        XCTAssertEqual(cardio.plannedDate, cardioRaw)
    }

    func testTravelPreviewFiltersByCivilWeekAndKeepsFreeSessionsOnDisplayedDay() throws {
        let (store, _) = try civilPreviewFixture()
        let context = store.mainContext
        let raw = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-21T00:00:00+14:00"))
        let monday = ScheduledWorkout(templateID: UUID(), templateName: "已有当地周一训练", plannedDate: raw)
        monday.plannedDate = raw
        monday.plannedLocalDay = "2026-09-21"
        monday.plannedTimeZoneIdentifier = "Pacific/Kiritimati"
        let free = WorkoutSession(templateName: "自行周三训练", plannedDate: TrainingLocalDate.date("2026-09-23")!, status: .completed)
        context.insert(monday); context.insert(free)
        try context.save()
        let before = try ConfirmedTravelWeekService.preview(in: context)
        XCTAssertEqual(before.conflictingDates, ["2026-09-21", "2026-09-23"])

        // Its absolute instant is still in the Shanghai week, but its recorded
        // civil date is next week and must not enter this approval payload.
        let nextRaw = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-28T00:00:00+14:00"))
        let next = ScheduledWorkout(templateID: UUID(), templateName: "下一周", plannedDate: nextRaw)
        next.plannedDate = nextRaw
        next.plannedLocalDay = "2026-09-28"
        next.plannedTimeZoneIdentifier = "Pacific/Kiritimati"
        context.insert(next)
        try context.save()
        XCTAssertEqual(try ConfirmedTravelWeekService.preview(in: context), before)
        XCTAssertEqual(monday.plannedDate, raw)
        XCTAssertEqual(next.plannedDate, nextRaw)
    }

    func testTravelApprovalRejectsCivilMetadataOnlyDriftBeforeWrites() throws {
        for mutation in ["day", "timezone"] {
            let (store, _) = try civilPreviewFixture()
            let context = store.mainContext
            let initial = try ConfirmedTravelWeekService.preview(in: context)
            XCTAssertEqual(try ConfirmedTravelWeekService.apply(expectedPreview: initial, in: context).importedSchedules, 6)
            let approved = try ConfirmedTravelWeekService.preview(in: context)
            let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
            let monday = try XCTUnwrap(schedules.first { $0.plannedLocalDay == "2026-09-21" })
            let raw = monday.plannedDate
            let preferenceCount = try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).count
            if mutation == "day" {
                monday.plannedLocalDay = "2026-09-22"
            } else {
                monday.plannedTimeZoneIdentifier = "Australia/Sydney"
            }
            try context.save()

            let fresh = try ConfirmedTravelWeekService.preview(in: context)
            XCTAssertNotEqual(fresh.stateFingerprint, approved.stateFingerprint, mutation)
            XCTAssertThrowsError(try ConfirmedTravelWeekService.apply(expectedPreview: approved, in: context), mutation)
            XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).map(\.id).sorted { $0.uuidString < $1.uuidString },
                schedules.map(\.id).sorted { $0.uuidString < $1.uuidString })
            XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).count, preferenceCount)
            XCTAssertEqual(monday.plannedDate, raw)
        }
    }

    private func civilPreviewFixture() throws -> (ModelContainer, FatLossProgram) {
        let schema = Schema([Exercise.self, WorkoutTemplate.self, TemplateExercise.self, ScheduledWorkout.self,
            WorkoutSession.self, SessionExercise.self, SetLog.self, FatLossProgram.self,
            TrainingPreferenceRevision.self, TrainingProgramRevision.self, ProgramWorkoutLink.self])
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let program = FatLossProgram(startDate: FatLossCalendar.date(2026, 9, 6), endDate: FatLossCalendar.date(2026, 12, 6))
        let preference = try TrainingPreferenceRevision(snapshot: .upperBodyTravelWeek, revision: 1,
            effectiveAt: FatLossCalendar.date(2026, 9, 21), reason: "已确认旅行周测试夹具")
        let revision = try TrainingProgramRevision(programID: program.id, preferenceRevision: preference,
            snapshot: FatLossCatalog.trainingProgram(preference: .upperBodyTravelWeek), revision: 1,
            effectiveDate: FatLossCalendar.date(2026, 9, 21), reason: "已确认旅行周测试夹具")
        store.mainContext.insert(program); store.mainContext.insert(preference); store.mainContext.insert(revision)
        try store.mainContext.save()
        return (store, program)
    }

    func testImportedPlansSurviveRefreshAndRescheduleDoesNotRecreateOriginal() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: FatLossCalendar.date(2026, 9, 8), days: 7, in: context), 4)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        XCTAssertTrue(schedules.allSatisfy(\.isManuallyScheduled))
        let tuesday = try XCTUnwrap(schedules.first { FatLossCalendar.calendar.component(.weekday, from: $0.plannedDate) == 3 })
        tuesday.plannedDate = FatLossCalendar.adding(1, to: tuesday.plannedDate)
        try context.save()
        try ScheduleService.refreshUpcoming(in: context)
        try context.save()
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: FatLossCalendar.date(2026, 9, 8), days: 7, in: context), 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 4)
        let items = try context.fetch(FetchDescriptor<TemplateExercise>())
        XCTAssertEqual(items.count, 33)
        XCTAssertEqual(items.reduce(0) { $0 + $1.targetSets }, 110)
        XCTAssertTrue(items.contains { $0.targetSets == 5 })
        let allPlans = items.flatMap(\.plannedSets)
        XCTAssertEqual(Set(allPlans.map(\.id)).count, allPlans.count)
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

    func testUnknownRopeCountWithLegacyDurationStillCountsAsARecordedDay() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        context.insert(JumpRopeEntry(count: nil, durationSeconds: 1_800, date: program.startDate))
        try context.save()
        let timeline = try FatLossService.timeline(program: program, in: context)
        let recorded = try XCTUnwrap(timeline.first)
        XCTAssertNil(recorded.jumpCount)
        XCTAssertNil(recorded.jumpActiveSeconds, "旧总时长不能冒充有效跳跃时长")
        XCTAssertNil(recorded.jumpElapsedSeconds, "旧总时长口径不明，不能改成含休息时长")
        XCTAssertTrue(recorded.hasRecords)
        XCTAssertEqual(recorded.status(relativeTo: program.startDate), "部分记录")
        XCTAssertEqual(timeline[1].jumpCount, 0)
        XCTAssertFalse(timeline[1].hasRecords, "没有条目的下一天不应被标成已记录")
        let url = try FatLossService.exportCSV(program: program, in: context)
        defer { try? FileManager.default.removeItem(at: url) }
        let firstRow = try XCTUnwrap(String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n").dropFirst().first)
        XCTAssertEqual(firstRow.components(separatedBy: ",")[8], "\"\"", "CSV空单元格按原格式带引号，不写0")
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
        try FatLossService.importWorkouts(program: program, from: FatLossCalendar.date(2026, 9, 8), days: 7, in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        let removedID = schedule.id
        try ScheduleService.deleteManual(schedule, in: context)
        XCTAssertFalse(try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).contains { $0.scheduledWorkoutID == removedID })
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: FatLossCalendar.date(2026, 9, 8), days: 7, in: context), 1)
        let backup = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: backup), into: restored.mainContext)
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<ScheduledWorkout>()).count, 4)
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

    func testFuturePreferenceDoesNotTakeEffectEarlyOrSeedDuplicates() throws {
        let store = try container(), context = store.mainContext
        let today = FatLossCalendar.date(2026, 9, 8)
        let original = try XCTUnwrap(TrainingPreferenceService.ensureConfirmedProfile(in: context))
        var changed = TrainingPreferenceSnapshot.confirmed
        changed.revisionCode = "FUTURE"
        changed.zone2Minutes = 40
        let future = try TrainingPreferenceService.append(snapshot: changed, effectiveAt: FatLossCalendar.adding(7, to: today), reason: "下周生效", in: context)
        XCTAssertEqual(try TrainingPreferenceService.current(in: context, on: today)?.id, original.id)
        XCTAssertEqual(try TrainingPreferenceService.current(in: context, on: FatLossCalendar.adding(7, to: today))?.id, future.id)
        context.delete(original); try context.save()
        XCTAssertNil(try TrainingPreferenceService.current(in: context, on: today))
        _ = try TrainingPreferenceService.ensureConfirmedProfile(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).count, 1)
    }

    func testFrozenWeekIsNotBackdatedOrRepeatedAndPreviewDoesNotWrite() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let week = FatLossCalendar.date(2026, 9, 8)
        let revisions = try context.fetch(FetchDescriptor<TrainingProgramRevision>())
        XCTAssertEqual(revisions.first?.effectiveDate, week)
        XCTAssertTrue(try FatLossService.importPreview(program: program, from: program.startDate, days: 2, in: context).isEmpty)
        XCTAssertTrue(try FatLossService.importPreview(program: program, from: FatLossCalendar.adding(7, to: week), in: context).isEmpty)
        let preview = try FatLossService.importPreview(program: program, from: week, in: context)
        XCTAssertEqual(preview.count, 4)
        XCTAssertTrue(preview.allSatisfy { $0.trainingProgramRevisionID == revisions.first?.id })
        XCTAssertTrue(try context.fetch(FetchDescriptor<ScheduledWorkout>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingProgramRevision>()).count, 1)
    }

    func testConfirmedLowerBodyWeekImportsThreeStrengthAndTwoJumpRopeSchedulesAndExpiresAfterSevenDays() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let start = FatLossCalendar.date(2026, 9, 14)
        let revision = try TrainingPreferenceService.activateLowerBodySpecialtyWeek(
            programID: program.id,
            effectiveDate: start,
            in: context
        )
        XCTAssertEqual(try TrainingPreferenceService.activateLowerBodySpecialtyWeek(
            programID: program.id,
            effectiveDate: start,
            in: context
        ).id, revision.id)

        let preview = try FatLossService.importPreview(program: program, from: start, days: 7, in: context)
        XCTAssertEqual(preview.map(\.date), [start, FatLossCalendar.adding(2, to: start), FatLossCalendar.adding(4, to: start)])
        XCTAssertEqual(preview.map(\.workout.code), ["LOWER_FRONT_LB3", "LOWER_POSTERIOR_LB3", "LOWER_INTEGRATED_LB3"])
        XCTAssertEqual(Set(preview.map(\.trainingProgramRevisionID)), [revision.id])
        XCTAssertTrue(try FatLossService.importPreview(program: program, from: FatLossCalendar.adding(7, to: start), days: 7, in: context).isEmpty)
        let cardioPreview = try FatLossService.cardioImportPreview(program: program, from: start, days: 7, in: context)
        XCTAssertEqual(cardioPreview.map(\.date), [FatLossCalendar.adding(1, to: start), FatLossCalendar.adding(5, to: start)])
        XCTAssertEqual(cardioPreview.map(\.cardio.code), ["ROPE_TUE_LB3", "ROPE_SAT_LB3"])

        XCTAssertEqual(try FatLossService.importWorkouts(
            program: program,
            from: start,
            days: 7,
            expectedPreview: preview,
            expectedCardioPreview: cardioPreview,
            in: context
        ), 5)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        XCTAssertEqual(schedules.count, 5)
        XCTAssertEqual(schedules.map { FatLossCalendar.distance(start, $0.plannedDate) }.sorted(), [0, 1, 2, 4, 5])
        XCTAssertEqual(Set(schedules.map(\.templateName)), [
            "下肢前链＋足踝 · 高消耗",
            "跳绳间歇 · 技术与燃脂",
            "下肢后链＋足踝 · 高消耗",
            "下肢前后链整合＋足踝",
            "跳绳混合间歇 · 燃脂"
        ])
        let links = try context.fetch(FetchDescriptor<ProgramWorkoutLink>())
        XCTAssertEqual(Set(links.map(\.templateCode)), [
            "LOWER_FRONT_LB3",
            "ROPE_TUE_LB3",
            "LOWER_POSTERIOR_LB3",
            "LOWER_INTEGRATED_LB3",
            "ROPE_SAT_LB3"
        ])
        let ropeTemplateIDs = Set(links.filter { $0.templateCode.hasPrefix("ROPE_") }.compactMap { link in
            schedules.first { $0.id == link.scheduledWorkoutID }?.templateID
        })
        let templateExercises = try context.fetch(FetchDescriptor<TemplateExercise>())
        XCTAssertEqual(templateExercises.filter { ropeTemplateIDs.contains($0.templateID) }.count, 2)
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: start, days: 7, conflictPolicy: .skipConflicts, in: context), 0)
    }

    func testTravelWeekImportsSixDaysOnceAndRestoresBaselineWithoutNextWeekSchedule() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let lowerStart = FatLossCalendar.date(2026, 9, 14)
        _ = try TrainingPreferenceService.activateLowerBodySpecialtyWeek(programID: program.id, effectiveDate: lowerStart, in: context)
        let historicalPreview = try FatLossService.importPreview(program: program, from: lowerStart, in: context)
        let start = FatLossCalendar.date(2026, 9, 21)
        _ = try TrainingPreferenceService.activateUpperBodyTravelWeek(programID: program.id, effectiveDate: start, in: context)
        let preview = try FatLossService.importPreview(program: program, from: start, in: context)
        XCTAssertEqual(preview.map { $0.workout.exercises.reduce(0) { $0 + $1.sets } }, [15, 16, 12, 16])
        XCTAssertEqual(try FatLossService.cardioImportPreview(program: program, from: start, days: 7, in: context).count, 2)
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: start, in: context), 6)
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: start, in: context), 0)
        XCTAssertTrue(try FatLossService.importPreview(program: program, from: FatLossCalendar.date(2026, 9, 28), in: context).isEmpty)
        let restored = try XCTUnwrap(TrainingPreferenceService.current(in: context, on: FatLossCalendar.date(2026, 9, 28))?.snapshot)
        XCTAssertEqual(restored.constraints, TrainingPreferenceSnapshot.weekdayFocused.constraints)
        XCTAssertEqual(try FatLossService.importPreview(program: program, from: lowerStart, in: context), historicalPreview)
    }

    func testConfirmedTravelExchangePreviewIsReadOnlyCodableAndRejectsStaleApproval() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let preview = try ConfirmedTravelWeekService.preview(in: context)
        let decoded = try JSONDecoder().decode(ConfirmedTravelWeekPreview.self, from: JSONEncoder().encode(preview))
        XCTAssertEqual(decoded, preview)
        XCTAssertEqual(preview.pendingStrengthWorkouts, 4)
        XCTAssertEqual(preview.pendingCardioWorkouts, 2)
        XCTAssertTrue(try FatLossService.importPreview(program: program, from: FatLossCalendar.date(2026, 9, 21), in: context).isEmpty)
        let result = try ConfirmedTravelWeekService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(result.importedSchedules, 6)
        XCTAssertThrowsError(try ConfirmedTravelWeekService.apply(expectedPreview: preview, in: context))
        let repeated = try ConfirmedTravelWeekService.apply(expectedPreview: ConfirmedTravelWeekService.preview(in: context), in: context)
        XCTAssertEqual(repeated.importedSchedules, 0)
        XCTAssertEqual(repeated.programRevisionID, result.programRevisionID)
    }

    func testTravelWeekLeavesHistoricalWeightsUnfilledForElbowSafety() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let exercise = Exercise(name: "上斜哑铃卧推", muscleGroup: "胸部", equipment: "哑铃")
        context.insert(exercise)
        try context.save()
        _ = try HistoricalWorkoutService.record(.init(name: "上次胸部", startedAt: FatLossCalendar.date(2026, 9, 18),
            durationMinutes: 30, notes: "既有历史",
            exercises: [.init(exerciseID: exercise.id, sets: [.init(weight: 30, reps: 12, rir: 3)], performanceNotes: "")]), in: context)
        _ = try TrainingPreferenceService.activateUpperBodyTravelWeek(programID: program.id,
            effectiveDate: FatLossCalendar.date(2026, 9, 21), in: context)
        let preview = try FatLossService.importPreview(program: program, from: FatLossCalendar.date(2026, 9, 21), in: context)
        XCTAssertTrue(preview.allSatisfy { $0.loadPlans.isEmpty })
    }

    func testTravelScheduleCivilDatesStayStableInShanghaiSydneyAndPerth() throws {
        let originalZone = NSTimeZone.default
        defer { NSTimeZone.default = originalZone }
        for identifier in ["Asia/Shanghai", "Australia/Sydney", "Australia/Perth"] {
            NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: identifier))
            let store = try container(), context = store.mainContext
            let program = try FatLossService.createProgram(in: context)
            let preview = try ConfirmedTravelWeekService.preview(in: context)
            _ = try ConfirmedTravelWeekService.apply(expectedPreview: preview, in: context)
            let week = try FatLossService.timeline(program: program, in: context).filter {
                $0.date >= FatLossCalendar.date(2026, 9, 21) && $0.date <= FatLossCalendar.date(2026, 9, 27)
            }
            XCTAssertEqual(week.map(\.plannedWorkouts), [1, 1, 1, 1, 1, 1, 0], identifier)
            let importedSchedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
            XCTAssertEqual(importedSchedules.count, 6)
            for schedule in importedSchedules {
                XCTAssertEqual(schedule.plannedLocalDay, FatLossCalendar.label(schedule.plannedDate))
                XCTAssertEqual(schedule.plannedTimeZoneIdentifier, "Asia/Shanghai")
            }
            for destination in ["Australia/Perth", "Australia/Sydney", "Asia/Shanghai"] {
                NSTimeZone.default = try XCTUnwrap(TimeZone(identifier: destination))
                let after = try FatLossService.importPreview(program: program, from: FatLossCalendar.date(2026, 9, 21), in: context)
                XCTAssertEqual(after.map { FatLossCalendar.label($0.date) }, ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-26"])
                XCTAssertTrue(after.allSatisfy(\.alreadyImported))
            }
        }
    }

    func testTravelMealLocalDayDrivesTimelineCSVAndSameMealProtection() throws {
        let store = try container(), context = store.mainContext
        let captured = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-24T00:30:00+10:00"))
        let actual = MealEntry(date: captured, mealType: .breakfast, name: "悉尼凌晨餐",
            calories: 400, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        actual.recordedLocalDay = "2026-09-24"
        actual.captureTimeZoneIdentifier = "Australia/Sydney"
        actual.recordedTimeKnown = true
        actual.knownNutritionFieldsRaw = "calories"
        context.insert(actual)
        try context.save()
        let program = FatLossProgram(startDate: FatLossCalendar.date(2026, 9, 23), endDate: FatLossCalendar.date(2026, 9, 25))
        let timeline = try FatLossService.timeline(program: program, in: context)
        XCTAssertEqual(timeline.map(\.loggedMeals), [0, 1, 0])
        XCTAssertEqual(timeline.map(\.knownCalories), [0, 400, 0])
        // The row belongs inside this narrower civil-date range even though its
        // absolute timestamp is still the previous Shanghai day.
        let exportProgram = FatLossProgram(startDate: FatLossCalendar.date(2026, 9, 24), endDate: FatLossCalendar.date(2026, 9, 25))
        let csvURL = try FatLossService.exportCSV(program: exportProgram, in: context)
        defer { try? FileManager.default.removeItem(at: csvURL) }
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("\"2026-09-24\",\"早餐\",\"悉尼凌晨餐\""))
        XCTAssertFalse(csv.contains("\"2026-09-23\",\"早餐\",\"悉尼凌晨餐\""))
        let recipe = try RecipeVersion(draft: FatLossCatalog.recipes[0])
        let planned = PlannedMeal(programID: program.id, date: FatLossCalendar.date(2026, 9, 24),
            mealType: .breakfast, recipe: recipe)
        XCTAssertThrowsError(try FatLossService.recordMeal(planned, now: FatLossCalendar.date(2026, 9, 25), in: context))
    }

    func testStartingImportedTravelWorkoutPreservesFrozenSafetyNotesWithoutRewritingHistory() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let exercise = Exercise(name: "器械推胸", muscleGroup: "胸部", equipment: "器械", notes: "既有动作库提示，不含本周规则")
        context.insert(exercise)
        try context.save()
        let oldSession = try HistoricalWorkoutService.record(.init(name: "之前完成的胸部训练",
            startedAt: FatLossCalendar.date(2026, 9, 18), durationMinutes: 30, notes: "保留历史",
            exercises: [.init(exerciseID: exercise.id, sets: [.init(weight: 30, reps: 12, rir: 3)], performanceNotes: "")]), in: context)
        let start = FatLossCalendar.date(2026, 9, 21)
        _ = try TrainingPreferenceService.activateUpperBodyTravelWeek(programID: program.id, effectiveDate: start, in: context)
        _ = try FatLossService.importWorkouts(program: program, from: start, in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first {
            FatLossCalendar.sameDay($0.plannedDate, start)
        })
        let frozenNote = try XCTUnwrap(schedule.planSnapshot.first { $0.exerciseID == exercise.id }?.exerciseNotes)
        let sessionID = try WorkoutService.start(schedule: schedule, in: context)
        XCTAssertEqual(try WorkoutService.start(schedule: schedule, in: context), sessionID, "恢复进行中的训练不重建快照")

        // Read the persisted user-facing export, rather than inspecting private
        // storage internals of the start implementation.
        let backupURL = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backupURL) }
        let data = try DataExportService.loadBackupData(from: backupURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try XCTUnwrap(json["sessionExercises"] as? [[String: Any]])
        func exportedNote(for id: UUID) throws -> String {
            let row = try XCTUnwrap(rows.first {
                UUID(uuidString: $0["sessionID"] as? String ?? "") == id
                    && UUID(uuidString: $0["exerciseID"] as? String ?? "") == exercise.id
            })
            return try XCTUnwrap(row["exerciseNotes"] as? String)
        }
        let activeNote = try exportedNote(for: sessionID)
        XCTAssertEqual(activeNote, frozenNote)
        XCTAssertTrue(activeNote.contains("RIR 2–3"))
        XCTAssertTrue(activeNote.contains("次晨"))
        XCTAssertTrue(activeNote.contains("疼痛"))
        XCTAssertEqual(try exportedNote(for: oldSession.id), "既有动作库提示，不含本周规则")
        XCTAssertEqual(exercise.notes, "既有动作库提示，不含本周规则")
    }

    func testCustomRevisionDrivesImportAndRejectsStalePreviewBeforeWriting() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let week = FatLossCalendar.date(2026, 9, 8)
        let preference = try XCTUnwrap(TrainingPreferenceService.current(in: context, on: week))
        let before = try FatLossService.importPreview(program: program, from: week, in: context)
        var changed = FatLossCatalog.trainingProgram(preference: try XCTUnwrap(preference.snapshot))
        changed.strengthWorkouts[0].exercises[0].sets = 3
        let revision = try TrainingPreferenceService.appendProgram(snapshot: changed, preference: preference,
            programID: program.id, effectiveDate: week, reason: "按训练反馈调整", in: context)
        XCTAssertThrowsError(try FatLossService.importWorkouts(program: program, from: week, expectedPreview: before, in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        let after = try FatLossService.importPreview(program: program, from: week, in: context)
        XCTAssertEqual(after.first?.workout.exercises.first?.sets, 3)
        XCTAssertEqual(try FatLossService.importWorkouts(program: program, from: week, expectedPreview: after, in: context), 4)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProgramWorkoutLink>()).allSatisfy { $0.trainingProgramRevisionID == revision.id })
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).allSatisfy { $0.trainingPreferenceSnapshotJSON == preference.snapshotJSON })
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 0)
    }

    func testCorruptCurrentPreferenceCannotFallBackToOlderVersion() throws {
        let store = try container(), context = store.mainContext
        let original = try XCTUnwrap(TrainingPreferenceService.ensureConfirmedProfile(in: context))
        let broken = TrainingPreferenceRevision(id: UUID(), revisionCode: "BROKEN", revision: 2,
            effectiveAt: original.effectiveAt, createdAt: .now, reason: "损坏样本", snapshotJSON: "{}")
        context.insert(broken); try context.save()
        XCTAssertThrowsError(try TrainingPreferenceService.current(in: context, on: original.effectiveAt))
        XCTAssertThrowsError(try TrainingPreferenceService.ensureConfirmedProfile(in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPreferenceRevision>()).count, 2)
    }

    func testLoadPreviewUsesCompletedCompatibleHistoryAndPreservesWeightSide() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let week = FatLossCalendar.date(2026, 9, 8)
        let previous = FatLossCalendar.adding(-2, to: week)
        let exercise = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        let session = WorkoutSession(templateName: "既有胸部训练", plannedDate: previous,
            startedAt: previous, completedAt: previous.addingTimeInterval(3600), status: .completed)
        let item = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
            order: 0, targetSets: 1, minReps: 6, maxReps: 8, targetWeight: 20, restSeconds: 180, muscleGroup: "胸部")
        let log = SetLog(sessionID: session.id, sessionExerciseID: item.id, exerciseID: exercise.id,
            setNumber: 1, targetWeight: 20, targetReps: 8, actualWeight: 20, actualReps: 8, rir: 3,
            isCompleted: true, completedAt: previous.addingTimeInterval(60), actualWeightSide: .single)
        context.insert(exercise); context.insert(session); context.insert(item); context.insert(log); try context.save()
        let normal = try FatLossService.importPreview(program: program, from: week, in: context)
        XCTAssertEqual(normal.first?.loadPlans[exercise.name]?.weight, 20)
        let low = try FatLossService.importPreview(program: program, from: week, lowEnergyMorning: true, in: context)
        XCTAssertEqual(low.first?.loadPlans[exercise.name]?.weight, 18)
        XCTAssertEqual(low.first?.loadPlans[exercise.name]?.weightSide, .single)
        XCTAssertNil(low.first?.loadPlans["上斜哑铃卧推"])
        XCTAssertThrowsError(try FatLossService.importWorkouts(program: program, from: week, lowEnergyMorning: true, expectedPreview: normal, in: context))
        _ = try FatLossService.importWorkouts(program: program, from: week, lowEnergyMorning: true, expectedPreview: low, in: context)
        let imported = try XCTUnwrap(context.fetch(FetchDescriptor<TemplateExercise>()).first { $0.exerciseID == exercise.id })
        XCTAssertEqual(imported.targetWeight, 18)
        XCTAssertEqual(imported.plannedSets.first?.weightSide, .single)
        XCTAssertEqual(Set(imported.plannedSets.map(\.id)).count, imported.plannedSets.count)
        XCTAssertFalse(imported.plannedSets.contains { $0.id == log.id })
        XCTAssertEqual(log.actualWeight, 20)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
    }

    func testImportKeepsSameNameDifferentEquipmentAsSeparateExercise() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let existing = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "不同器械")
        context.insert(existing); try context.save()
        let week = FatLossCalendar.date(2026, 9, 8)
        let preview = try FatLossService.importPreview(program: program, from: week, in: context)
        XCTAssertNil(preview.first?.loadPlans[existing.name])
        _ = try FatLossService.importWorkouts(program: program, from: week, expectedPreview: preview, in: context)
        let created = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.name == existing.name && $0.equipment == "杠铃" })
        XCTAssertNotEqual(created.id, existing.id)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TemplateExercise>()).contains { $0.exerciseID == created.id })
        XCTAssertFalse(try context.fetch(FetchDescriptor<TemplateExercise>()).contains { $0.exerciseID == existing.id })
    }

    func testAmbiguousMatchingExercisesRejectImportBeforeAnyPlanWrite() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        for _ in 0..<2 { context.insert(Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")) }
        try context.save()
        XCTAssertThrowsError(try FatLossService.importWorkouts(program: program, from: FatLossCalendar.date(2026, 9, 8), in: context))
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ScheduledWorkout>()).isEmpty)
    }

    func testUnilateralLoadRequiresMatchingRepetitionSide() throws {
        let store = try container(), context = store.mainContext
        let program = try FatLossService.createProgram(in: context)
        let day = FatLossCalendar.date(2026, 9, 13), previous = FatLossCalendar.date(2026, 9, 7)
        let exercise = Exercise(name: "地雷管推举", muscleGroup: "肩部", equipment: "杠铃")
        let session = WorkoutSession(templateName: "历史肩部", plannedDate: previous, startedAt: previous,
            completedAt: previous.addingTimeInterval(3600), status: .completed)
        let item = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
            order: 0, targetSets: 1, minReps: 8, maxReps: 10, targetWeight: 20, restSeconds: 120, muscleGroup: "肩部")
        let log = SetLog(sessionID: session.id, sessionExerciseID: item.id, exerciseID: exercise.id,
            setNumber: 1, targetWeight: 20, targetReps: 12, actualWeight: 20, actualReps: 12, rir: 3,
            isCompleted: true, completedAt: previous.addingTimeInterval(60), actualRepsSide: .bilateral)
        context.insert(exercise); context.insert(session); context.insert(item); context.insert(log); try context.save()
        XCTAssertNil(try FatLossService.importPreview(program: program, from: day, days: 1, in: context).first?.loadPlans[exercise.name])
        log.actualRepsSide = .single; try context.save()
        XCTAssertEqual(try FatLossService.importPreview(program: program, from: day, days: 1, in: context).first?.loadPlans[exercise.name]?.weight, 20)
    }

}
