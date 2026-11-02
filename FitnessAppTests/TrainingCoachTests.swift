import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class TrainingCoachTests: XCTestCase {
    private func schema(coach: Bool = true) -> Schema {
        var types: [any PersistentModel.Type] = [Exercise.self, WorkoutTemplate.self, TemplateExercise.self, ScheduledWorkout.self,
            WorkoutSession.self, SessionExercise.self, SetLog.self, NutritionTarget.self, MealEntry.self, BodyMeasurement.self,
            DailyBodyCheckIn.self, HydrationEntry.self, JumpRopeEntry.self, SedentarySession.self, FatLossProgram.self,
            ProgramTargetRevision.self, RecipeVersion.self, PlannedMeal.self, ProgramDailyLog.self, ProgramHealthRecord.self,
            ProgramWeeklyReview.self, ProgramWorkoutLink.self, TrainingPreferenceRevision.self, TrainingProgramRevision.self]
        if coach { types.append(TrainingCoachRecord.self) }
        return Schema(types)
    }
    private func container() throws -> ModelContainer {
        let schema = schema()
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
    @discardableResult private func seed(_ context: ModelContext) throws -> UUID {
        let day = Date.now.startOfDay.addingDays(-2)
        var preference = TrainingPreferenceSnapshot.confirmed; preference.revisionCode = "TP-COACH-TEST"
        _ = try TrainingPreferenceService.append(snapshot: preference, effectiveAt: day.addingDays(-30), reason: "隔离测试", in: context)
        let exercise = Exercise(name: "测试腿举", muscleGroup: "腿部", equipment: "同一测试机器")
        context.insert(exercise)
        let old = ScheduledWorkout(templateID: UUID(), templateName: "旧计划仍待完成", plannedDate: day)
        context.insert(old)
        let session = WorkoutSession(templateName: "测试综合", plannedDate: day, startedAt: day.addingTimeInterval(3600),
            completedAt: day.addingTimeInterval(7200), status: .completed, notes: "原始备注保留")
        context.insert(session)
        let plans = (0..<4).map { _ in WorkoutSetPlan(weight: 20, reps: 10, weightSide: .single,
            repsSide: .bilateral, actualDefaultPolicy: .blank, prescription: WorkoutSetPrescription(label: "工作组",
                repsLower: 10, repsUpper: 12, rirLower: 2, rirUpper: 3, restLowerSeconds: 120, restUpperSeconds: 180)) }
        let item = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name, order: 0,
            targetSets: 4, minReps: 10, maxReps: 12, targetWeight: 20, restSeconds: 180,
            muscleGroup: "腿部", plannedSets: plans, equipmentSnapshot: exercise.equipment)
        context.insert(item)
        for index in 0..<4 {
            context.insert(SetLog(sessionID: session.id, sessionExerciseID: item.id, exerciseID: exercise.id,
                setNumber: index + 1, targetWeight: 20, targetReps: 10, actualWeight: 30, actualReps: 10,
                isCompleted: true, completedAt: day.addingTimeInterval(Double(3600 + index * 120)),
                targetWeightSide: .single, actualEntrySource: .manual))
        }
        try context.save()
        return session.id
    }
    private func ready(_ id: UUID, in context: ModelContext) throws {
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first { $0.sessionID == id })
        var after = CoachFeedback(stage: "after", pain: "none")
        after.lastRIR[item.id.uuidString] = 5
        after.loadConventions[item.id.uuidString] = "同机每侧加片，不含空载"
        try TrainingCoachService.saveFeedback(after, sessionID: id, in: context)
        try TrainingCoachService.saveFeedback(CoachFeedback(stage: "morning", pain: "none", function: "normal", recovery: "good"), sessionID: id, in: context)
    }
    private func draft(_ id: UUID, in context: ModelContext) throws -> CoachDraft {
        try ready(id, in: context)
        return try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(4), in: context)
    }

    func testFeedbackIsAppendOnlyIdempotentAndDoesNotFillRawRIR() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let initial = try TrainingCoachService.review(sessionID: id, in: context)
        try ready(id, in: context)
        try ready(id, in: context)
        XCTAssertEqual(try TrainingCoachService.records(sessionID: id, in: context).count, 2)
        XCTAssertEqual(try TrainingCoachService.review(sessionID: id, in: context).observations, initial.observations)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SetLog>()).allSatisfy { $0.rir == nil && $0.actualWeight == 30 })
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).first?.status, .planned)
    }

    func testUnknownRecoveryAndFutureMorningCannotBecomeNormal() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertThrowsError(try TrainingCoachService.saveFeedback(CoachFeedback(stage: "morning", pain: "none", function: "normal", recovery: "good"), sessionID: id, now: session.plannedDate, in: context))
        let draft = try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(4), in: context)
        XCTAssertTrue(try TrainingCoachService.blockingReasons(draft, in: context).contains { $0.contains("恢复") })
        XCTAssertThrowsError(try TrainingCoachService.prepareConfirmation(draft, in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 1)
    }

    func testActualLoadOnlyCalibratesWithCompatibleIdentityAndExplicitFeedback() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let unknown = try TrainingCoachService.makeDraft(sessionID: id, in: context)
        XCTAssertEqual(unknown.items[0].exercise.plannedSets.map(\.weight), [20, 20, 20, 20])
        let calibrated = try draft(id, in: context)
        XCTAssertEqual(calibrated.items[0].exercise.plannedSets.map(\.weight), [30, 30, 30, 30])
        XCTAssertTrue(calibrated.items[0].reason.contains("起点校准"))
        XCTAssertTrue(calibrated.items[0].exercise.plannedSets.allSatisfy { $0.actualDefaultPolicy == .blank })
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first)
        item.equipmentSnapshot = "另一台机器"; try context.save()
        let mismatch = try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(4), in: context)
        XCTAssertFalse(mismatch.items[0].unitVerified)
        XCTAssertEqual(mismatch.items[0].exercise.plannedSets.map(\.weight), [20, 20, 20, 20])
    }

    func testTechnicalWorkUsesQualityAndExcludesWarmupsBeforeNormalDoseConfirmation() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first)
        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first)
        item.exerciseName = "杠铃高翻"; exercise.name = "杠铃高翻"
        context.insert(SetLog(sessionID: id, sessionExerciseID: item.id, exerciseID: exercise.id,
            setNumber: 0, targetWeight: 5, targetReps: 3, actualWeight: 100, actualReps: 3,
            isWarmup: true, isCompleted: true, targetWeightSide: .single, actualEntrySource: .manual))
        try context.save(); try ready(id, in: context)
        let proposed = try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(4), in: context)
        XCTAssertEqual(proposed.items[0].exercise.plannedSets.map(\.reps), [3, 3, 3, 3])
        XCTAssertTrue(proposed.items[0].exercise.plannedSets.allSatisfy { $0.prescription?.rirLower == nil && $0.weight == 20 })
        XCTAssertEqual(try TrainingCoachService.review(sessionID: id, in: context).technicalCount, 4)
        XCTAssertThrowsError(try TrainingCoachService.prepareConfirmation(proposed, in: context))
        var feedback = try TrainingCoachService.latestFeedback("after", rows: TrainingCoachService.records(sessionID: id, in: context))
        feedback.quality[item.id.uuidString] = "stable"
        try TrainingCoachService.saveFeedback(feedback, sessionID: id, in: context)
        let next = try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(4), in: context)
        XCTAssertNoThrow(try TrainingCoachService.prepareConfirmation(next, in: context))
    }

    func testFeedbackRevisionOrderSurvivesSameSecondBackupTimestamps() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let stamp = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        let first = TrainingCoachRecord(id: UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!, sessionID: id, kind: "after",
            payloadJSON: try TrainingCoachService.encode(CoachFeedback(stage: "after", pain: "none")), createdAt: stamp, sequence: 1)
        let latest = TrainingCoachRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, sessionID: id, kind: "after",
            payloadJSON: try TrainingCoachService.encode(CoachFeedback(stage: "after", pain: "yes")), createdAt: stamp, sequence: 2)
        context.insert(first); context.insert(latest); try context.save()
        let url = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: url) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: url), into: restored.mainContext)
        let rows = try TrainingCoachService.records(sessionID: id, in: restored.mainContext)
        XCTAssertEqual(rows.last?.id, latest.id)
        XCTAssertEqual(try TrainingCoachService.latestFeedback("after", rows: rows).pain, "yes")
        XCTAssertEqual(try restored.mainContext.fetch(FetchDescriptor<SetLog>()).count, 4)
    }

    func testBodyweightCandidateKeepsSelfLoadAndDoesNotTurnLegacyNumbersIntoExternalWeight() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first)
        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first)
        item.volumeUnit = .bodyweight; exercise.volumeUnit = .bodyweight
        item.equipmentSnapshot = nil
        try context.save()
        let proposed = try draft(id, in: context)
        XCTAssertTrue(proposed.items[0].unitVerified)
        XCTAssertTrue(proposed.items[0].exercise.plannedSets.allSatisfy { $0.weight == 0 && $0.actualDefaultPolicy == .blank })
        XCTAssertNoThrow(try TrainingCoachService.prepareConfirmation(proposed, in: context))
    }

    func testReviewKeepsUnknownEffortDistinctFromHardAndEasyFeedback() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let review = try TrainingCoachService.review(sessionID: id, in: context)
        let item = try XCTUnwrap(review.observations.first)
        XCTAssertTrue(TrainingCoachService.insight(for: item, after: review.after).contains("未知"))
        var easy = review.after; easy.lastRIR[item.id.uuidString] = 5
        XCTAssertTrue(TrainingCoachService.insight(for: item, after: easy).contains("余力较多"))
        var hard = review.after; hard.lastRIR[item.id.uuidString] = 0
        XCTAssertTrue(TrainingCoachService.insight(for: item, after: hard).contains("接近力竭"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).filter { $0.rir == nil }.count, 4)
    }

    func testLastSetFeedbackDoesNotFlattenTopAndBackoffPrescriptions() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first)
        var plans = item.plannedSets
        plans[0].prescription?.label = "顶组"; plans[0].prescription?.repsLower = 8; plans[0].prescription?.repsUpper = 10; plans[0].reps = 8
        for index in 1..<plans.count { plans[index].weight = 10; plans[index].prescription?.label = "回退组" }
        item.plannedSets = plans; try context.save()
        let proposed = try draft(id, in: context)
        XCTAssertEqual(proposed.items[0].exercise.plannedSets.map(\.weight), [20, 10, 10, 30])
        XCTAssertEqual(proposed.items[0].exercise.plannedSets.first?.prescription?.label, "顶组")
        XCTAssertEqual(proposed.items[0].exercise.plannedSets.last?.prescription?.label, "回退组")
        XCTAssertTrue(try context.fetch(FetchDescriptor<SetLog>()).allSatisfy { $0.rir == nil })
    }

    func testOldSourceDoesNotAutomaticallyReuseStaleLoadAndCountSideNeedsClarification() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        try ready(id, in: context)
        let old = try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(60), in: context)
        XCTAssertTrue(old.items[0].exercise.plannedSets.allSatisfy { $0.weight == 0 })
        let last = try XCTUnwrap(context.fetch(FetchDescriptor<SetLog>()).max { $0.setNumber < $1.setNumber })
        last.actualRepsSide = .unknown; try context.save()
        let unresolved = try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(4), in: context)
        XCTAssertTrue(unresolved.items[0].exercise.plannedSets.allSatisfy { $0.weight == 20 })
        var feedback = try TrainingCoachService.latestFeedback("after", rows: TrainingCoachService.records(sessionID: id, in: context))
        feedback.repsSides[last.sessionExerciseID.uuidString] = .bilateral
        try TrainingCoachService.saveFeedback(feedback, sessionID: id, in: context)
        let clarified = try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(4), in: context)
        XCTAssertTrue(clarified.items[0].exercise.plannedSets.allSatisfy { $0.weight == 30 })
        XCTAssertEqual(last.actualRepsSide, .unknown)
    }

    func testComparableHistoryExcludesWarmupsAndUnknownSides() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let current = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first)
        let day = Date.now.startOfDay.addingDays(-8)
        let previous = WorkoutSession(templateName: "上次同机训练", plannedDate: day, startedAt: day.addingTimeInterval(3600), completedAt: day.addingTimeInterval(7200), status: .completed)
        context.insert(previous)
        let snapshot = SessionExercise(sessionID: previous.id, exerciseID: current.exerciseID, exerciseName: current.exerciseName,
            order: 0, targetSets: 4, minReps: 10, maxReps: 12, targetWeight: 20, restSeconds: 180,
            plannedSets: current.plannedSets, equipmentSnapshot: current.equipmentSnapshot)
        context.insert(snapshot)
        for index in 0..<4 {
            context.insert(SetLog(sessionID: previous.id, sessionExerciseID: snapshot.id, exerciseID: current.exerciseID,
                setNumber: index + 1, targetWeight: 20, targetReps: 10, actualWeight: 25, actualReps: 10,
                rir: 3, isCompleted: true, targetWeightSide: .single, actualEntrySource: .manual))
        }
        context.insert(SetLog(sessionID: previous.id, sessionExerciseID: snapshot.id, exerciseID: current.exerciseID,
            setNumber: 0, targetWeight: 5, targetReps: 3, actualWeight: 100, actualReps: 1, isWarmup: true,
            isCompleted: true, targetWeightSide: .single, actualEntrySource: .manual))
        try context.save()
        let review = try TrainingCoachService.review(sessionID: id, in: context)
        XCTAssertEqual(review.observations[0].previous.count, 1)
        let previousEvidence = try XCTUnwrap(review.observations[0].previous.first)
        XCTAssertEqual(previousEvidence.actual.count, 4)
        XCTAssertEqual(previousEvidence.actual.map(\.weight), [25, 25, 25, 25])
        let first = try XCTUnwrap(context.fetch(FetchDescriptor<SetLog>()).first { $0.sessionID == previous.id && !$0.isWarmup })
        first.actualWeightSide = .unknown; try context.save()
        XCTAssertTrue(try TrainingCoachService.review(sessionID: id, in: context).observations[0].previous.isEmpty)
    }

    func testDateConflictStopsAppendAndPreservesAllOriginalRecords() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let proposed = try draft(id, in: context)
        let date = try XCTUnwrap(proposed.localDay.flatMap { TrainingLocalDate.date($0, timeZone: .current) })
        let conflict = ScheduledWorkout(templateID: UUID(), templateName: "本人已确认另一项安排", plannedDate: date)
        context.insert(conflict); try context.save()
        XCTAssertThrowsError(try TrainingCoachService.prepareConfirmation(proposed, in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).count, 4)
        XCTAssertEqual(conflict.templateName, "本人已确认另一项安排")
    }

    func testConfirmationReadbackIsIdempotentAndOldSnapshotSurvivesFeedbackChange() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let source = try TrainingCoachService.review(sessionID: id, in: context).observations
        let proposed = try draft(id, in: context)
        let confirmation = try TrainingCoachService.prepareConfirmation(proposed, in: context)
        let first = try TrainingCoachService.confirm(confirmation, in: context)
        XCTAssertEqual(try TrainingCoachService.confirm(confirmation, in: context), first)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 2)
        XCTAssertEqual(try TrainingCoachService.review(sessionID: id, in: context).observations, source)
        try TrainingCoachService.saveFeedback(CoachFeedback(stage: "morning", pain: "yes", function: "limited", recovery: "poor"), sessionID: id, in: context)
        XCTAssertThrowsError(try TrainingCoachService.prepareConfirmation(proposed, in: context))
        let updated = try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(5), in: context)
        XCTAssertGreaterThan(updated.revision, proposed.revision)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: first.scheduleID, in: ModelContext(store))?.packet, confirmation.preview.packet)
        XCTAssertEqual(try TrainingCoachService.confirmations(rows: TrainingCoachService.records(sessionID: id, in: context)).first?.draft, proposed)
    }

    func testSourceAndNewDraftChangesInvalidateAnOpenConfirmation() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let proposed = try draft(id, in: context)
        let confirmation = try TrainingCoachService.prepareConfirmation(proposed, in: context)
        var edited = proposed; edited.items[0].exercise.plannedSets[0].weight = 25
        let newer = try TrainingCoachService.revise(edited, in: context)
        XCTAssertNotEqual(newer.id, proposed.id)
        XCTAssertThrowsError(try TrainingCoachService.confirm(confirmation, in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 1)
    }

    func testCancelledUnwrittenRequestCanOnlyContinueThroughANewReviewedVersion() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let proposed = try draft(id, in: context)
        let confirmation = try TrainingCoachService.prepareConfirmation(proposed, in: context)
        try TrainingCoachService.append(confirmation, kind: "confirmation", sessionID: id, id: confirmation.id, in: context)
        XCTAssertNil(try TrainingCoachService.reconcile(confirmation, in: context))
        try TrainingCoachService.cancelUnwritten(confirmation, in: context)
        XCTAssertThrowsError(try TrainingCoachService.confirm(confirmation, in: context))
        let revised = try TrainingCoachService.makeDraft(sessionID: id, date: .now.addingDays(4), in: context)
        XCTAssertNotEqual(revised.id, proposed.id)
        XCTAssertGreaterThan(revised.revision, proposed.revision)
        let newConfirmation = try TrainingCoachService.prepareConfirmation(revised, in: context)
        _ = try TrainingCoachService.confirm(newConfirmation, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 2)
    }

    func testLostReceiptReconcilesTheSameStableRequestWithoutAnotherSchedule() throws {
        let store = try container(), context = store.mainContext, id = try seed(context)
        let proposed = try draft(id, in: context)
        let confirmation = try TrainingCoachService.prepareConfirmation(proposed, in: context)
        try TrainingCoachService.append(confirmation, kind: "confirmation", sessionID: id, id: confirmation.id, in: context)
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: confirmation.preview, in: context)
        let receipt = try XCTUnwrap(TrainingCoachService.reconcile(confirmation, in: context))
        XCTAssertEqual(receipt.scheduleID, proposed.id)
        XCTAssertEqual(try TrainingCoachService.reconcile(confirmation, in: context), receipt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 2)
        XCTAssertEqual(try TrainingCoachService.records(sessionID: id, in: context).filter { $0.kind == "receipt" }.count, 1)
    }

    func testDatabaseAddingCoachEntityPreservesExistingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store")
        let originalID: UUID = try autoreleasepool {
            let old = schema(coach: false)
            let container = try ModelContainer(for: old, configurations: [ModelConfiguration(schema: old, url: url)])
            return try seed(container.mainContext)
        }
        let current = schema()
        let reopened = try ModelContainer(for: current, configurations: [ModelConfiguration(schema: current, url: url)])
        let context = reopened.mainContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.id, originalID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).map(\.actualWeight), [30, 30, 30, 30])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 1)
        try ready(originalID, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingCoachRecord>()).count, 2)
    }

    func testBackupRestoresCoachRecordsWithoutOverwritingHistoryAndReadsLegacyBackup() throws {
        let source = try container(), context = source.mainContext, id = try seed(context)
        _ = try draft(id, in: context)
        let url = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        XCTAssertEqual(try DataExportService.preview(data).trainingCoachRecords, 3)
        let destination = try container()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<TrainingCoachRecord>()).count, 3)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<SetLog>()).map(\.actualWeight), [30, 30, 30, 30])
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<TrainingCoachRecord>()).count, 3)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "trainingCoachRecords"); object["schemaVersion"] = 16
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let empty = try container()
        _ = try DataExportService.importBackup(legacy, into: empty.mainContext)
        XCTAssertEqual(try empty.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first?.id, id)
        XCTAssertEqual(try empty.mainContext.fetch(FetchDescriptor<TrainingCoachRecord>()).count, 0)
    }
}
