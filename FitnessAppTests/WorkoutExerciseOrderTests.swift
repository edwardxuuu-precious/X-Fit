import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class WorkoutExerciseOrderTests: XCTestCase {
    func testReorderUsesSessionSnapshotIDsAndPreservesActualsPlansAndRestAcrossContexts() throws {
        let fixture = try makeFixture()
        let context = fixture.container.mainContext
        let beforeSession = sessionState(fixture.session)
        let beforeExercises = Dictionary(uniqueKeysWithValues: fixture.snapshots.map { ($0.id, exerciseState($0)) })
        let beforeLogs = Dictionary(uniqueKeysWithValues: fixture.logs.map { ($0.id, logState($0)) })
        let beforeTemplate = fixture.templateItem.plannedSetsJSON
        let orderedIDs = [fixture.snapshots[2].id, fixture.snapshots[0].id, fixture.snapshots[1].id]

        try WorkoutService.reorderExercises(sessionID: fixture.session.id,
            orderedSessionExerciseIDs: orderedIDs, in: context)

        let readback = ModelContext(fixture.container)
        let currentSession = try XCTUnwrap(readback.fetch(FetchDescriptor<WorkoutSession>()).first {
            $0.id == fixture.session.id
        })
        let currentExercises = try readback.fetch(FetchDescriptor<SessionExercise>())
        XCTAssertEqual(currentExercises.filter { $0.sessionID == fixture.session.id }
            .sorted { $0.order < $1.order }.map(\.id), orderedIDs)
        XCTAssertEqual(currentExercises.first { $0.id == fixture.snapshots[3].id }?.order, 40)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: currentExercises.map { ($0.id, exerciseState($0)) }), beforeExercises)
        XCTAssertEqual(sessionState(currentSession), beforeSession)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: try readback.fetch(FetchDescriptor<SetLog>()).map {
            ($0.id, logState($0))
        }), beforeLogs)
        let templateItem = try XCTUnwrap(readback.fetch(FetchDescriptor<TemplateExercise>()).first)
        XCTAssertEqual(templateItem.order, 7)
        XCTAssertEqual(templateItem.plannedSetsJSON, beforeTemplate)
        XCTAssertFalse(context.hasChanges)
    }

    func testReorderRejectsMissingDuplicateForeignAndUnknownIDsBeforeMutating() throws {
        let fixture = try makeFixture()
        let context = fixture.container.mainContext
        let ids = fixture.snapshots.prefix(3).map(\.id)
        let foreignID = fixture.snapshots[3].id
        let invalidOrders = [[], Array(ids.dropLast()), [ids[0], ids[0], ids[2]],
            [ids[0], foreignID, ids[2]], [ids[0], UUID(), ids[2]], ids + [foreignID]]
        for proposed in invalidOrders {
            XCTAssertThrowsError(try WorkoutService.reorderExercises(sessionID: fixture.session.id,
                orderedSessionExerciseIDs: proposed, in: context)) { error in
                guard case WorkoutServiceError.invalidExerciseOrder = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(fixture.snapshots.map(\.order), [0, 1, 2, 40])
            XCTAssertFalse(context.hasChanges, "An invalid order must not leave a partial sort for autosave")
        }
    }

    func testReorderRejectsEndedOrMissingSession() throws {
        let fixture = try makeFixture()
        let context = fixture.container.mainContext
        fixture.session.status = .completed
        try context.save()
        for sessionID in [fixture.session.id, UUID()] {
            XCTAssertThrowsError(try WorkoutService.reorderExercises(sessionID: sessionID,
                orderedSessionExerciseIDs: fixture.snapshots.prefix(3).map(\.id), in: context)) { error in
                guard case WorkoutServiceError.sessionNotInProgress = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(fixture.snapshots.map(\.order), [0, 1, 2, 40])
            XCTAssertFalse(context.hasChanges)
        }
    }

    private struct Fixture {
        let container: ModelContainer
        let session: WorkoutSession
        let snapshots: [SessionExercise]
        let logs: [SetLog]
        let templateItem: TemplateExercise
    }

    private func makeFixture() throws -> Fixture {
        let schema = Schema([WorkoutSession.self, SessionExercise.self, SetLog.self, TemplateExercise.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = container.mainContext
        context.autosaveEnabled = false
        let date = Date(timeIntervalSince1970: 1_792_540_000)
        let templateID = UUID(), scheduleID = UUID(), sharedExerciseID = UUID()
        let session = WorkoutSession(scheduledWorkoutID: scheduleID, templateID: templateID,
            templateName: "保留原处方", plannedDate: date, startedAt: date, notes: "原备注",
            restEndDate: date.addingTimeInterval(180), restMode: .freestyle, defaultPlanPattern: .pyramidUp)
        session.trainingLocalDay = "2026-10-21"
        session.trainingTimeZoneIdentifier = "Asia/Shanghai"
        let other = WorkoutSession(templateName: "另一场次", plannedDate: date)
        context.insert(session); context.insert(other)
        var snapshots: [SessionExercise] = [], logs: [SetLog] = []
        for index in 0..<4 {
            // Two independent snapshots may share the same catalog exercise ID.
            let exerciseID = index < 2 ? sharedExerciseID : UUID()
            let snapshot = SessionExercise(sessionID: index == 3 ? other.id : session.id,
                exerciseID: exerciseID, exerciseName: "动作\(index)", order: index == 3 ? 40 : index,
                targetSets: 1, minReps: 8, maxReps: 12, targetWeight: 20, restSeconds: 90,
                muscleGroup: "背部", exerciseNotes: "原机配重说明\(index)", referenceURL: "https://example.com/\(index)",
                performanceNotes: "本人原备注\(index)", plannedSets: [WorkoutSetPlan(weight: 20, reps: 8)],
                planPattern: .pyramidUp, feeling: index == 0 ? .strong : nil,
                exerciseStartedAt: index == 0 ? date : nil,
                exerciseCompletedAt: index == 0 ? date.addingTimeInterval(20) : nil,
                equipmentSnapshot: "同一器械")
            let log = SetLog(sessionID: snapshot.sessionID, sessionExerciseID: snapshot.id, exerciseID: exerciseID,
                setNumber: 1, targetWeight: 20, targetReps: 8, actualWeight: 27.5, actualReps: 9,
                rir: nil, isWarmup: index == 1, isCompleted: index == 0, startedAt: date,
                completedAt: index == 0 ? date.addingTimeInterval(20) : nil,
                restStartedAt: index == 0 ? date.addingTimeInterval(20) : nil,
                restEndedAt: nil, restDurationSeconds: nil, actualWeightSide: .unknown,
                actualRepsSide: .single, actualEntrySource: index == 2 ? .blank : .manual,
                sourceHistorySetID: UUID(), actualWeightIsBlank: index == 2)
            snapshots.append(snapshot); logs.append(log)
            context.insert(snapshot); context.insert(log)
        }
        let templateItem = TemplateExercise(templateID: templateID, exerciseID: sharedExerciseID,
            order: 7, targetSets: 1, minReps: 8, maxReps: 12, targetWeight: 20, restSeconds: 90)
        context.insert(templateItem)
        try context.save()
        return Fixture(container: container, session: session, snapshots: snapshots, logs: logs, templateItem: templateItem)
    }

    private func state(_ values: [Any?]) -> [String] {
        values.map { $0.map { String(describing: $0) } ?? "<nil>" }
    }

    private func sessionState(_ row: WorkoutSession) -> [String] {
        state([row.id, row.scheduledWorkoutID, row.templateID, row.templateName, row.plannedDate,
            row.trainingLocalDay, row.trainingTimeZoneIdentifier, row.startedAt, row.startTimeKnownRaw,
            row.completedAt, row.statusRaw, row.notes, row.restEndDate, row.restModeRaw,
            row.importIdentifier, row.defaultPlanPatternRaw, row.cardioResistanceLevel])
    }

    /// Deliberately excludes only order, the one field owned by reordering.
    private func exerciseState(_ row: SessionExercise) -> [String] {
        state([row.id, row.sessionID, row.exerciseID, row.exerciseName, row.targetSets, row.minReps,
            row.maxReps, row.targetWeight, row.restSeconds, row.muscleGroup, row.exerciseNotes,
            row.referenceURL, row.volumeUnitRaw, row.performanceNotes, row.plannedSetsJSON,
            row.planPatternRaw, row.patternSourceRaw, row.feelingRaw, row.exerciseStartedAt,
            row.exerciseCompletedAt, row.bodyWeightKgSnapshot, row.bodyWeightSnapshotSourceDate,
            row.equipmentSnapshot])
    }

    private func logState(_ row: SetLog) -> [String] {
        state([row.id, row.sessionID, row.sessionExerciseID, row.exerciseID, row.setNumber, row.targetWeight,
            row.targetReps, row.actualWeight, row.actualReps, row.rir, row.isWarmup, row.isCompleted,
            row.startedAt, row.completedAt, row.restStartedAt, row.restEndedAt, row.restDurationSeconds,
            row.targetWeightSideRaw, row.targetRepsSideRaw, row.actualWeightSideRaw, row.actualRepsSideRaw,
            row.actualEntrySourceRaw, row.sourceHistorySetID, row.actualWeightIsBlank])
    }
}

@MainActor
final class WorkoutExerciseReplacementTests: XCTestCase {
    func testZeroCompletedReplacementKeepsPositionAndTwoRemainingSetsAcrossContexts() throws {
        let fixture = try makeFixture(setCount: 2)
        let context = fixture.container.mainContext
        let before = try storedState(in: context)
        let review = try review(fixture)
        let sourceID = fixture.source.id
        let sourceLogIDs = fixture.sourceLogs.map(\.id)
        XCTAssertEqual(review.defaultSetCount, 2)
        XCTAssertFalse(review.requiresEnteredDataConfirmation)

        let replacement = try replace(fixture, review: review)

        let readback = ModelContext(fixture.container)
        let snapshots = try readback.fetch(FetchDescriptor<SessionExercise>())
        XCTAssertEqual(snapshots.filter { $0.sessionID == fixture.session.id }.sorted { $0.order < $1.order }.map(\.id),
            [fixture.before.id, replacement.id, fixture.after.id])
        XCTAssertFalse(snapshots.contains { $0.id == sourceID })
        let logs = try readback.fetch(FetchDescriptor<SetLog>())
        XCTAssertFalse(logs.contains { $0.sessionExerciseID == sourceID })
        let newRows = logs.filter { $0.sessionExerciseID == replacement.id }.sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(newRows.map(\.setNumber), [1, 2])
        XCTAssertEqual(newRows.map(\.actualWeight), [7.5, 10])
        XCTAssertTrue(newRows.allSatisfy { !$0.isCompleted && $0.completedAt == nil && $0.sourceHistorySetID == nil })
        XCTAssertEqual(replacement.targetSets, 2)
        var expected = before
        expected.snapshots.removeValue(forKey: sourceID)
        sourceLogIDs.forEach { expected.logs.removeValue(forKey: $0) }
        var actual = try storedState(in: readback)
        actual.snapshots.removeValue(forKey: replacement.id)
        newRows.forEach { actual.logs.removeValue(forKey: $0.id) }
        XCTAssertEqual(actual, expected)
        XCTAssertFalse(context.hasChanges)
    }

    func testPartialReplacementPreservesAllOldFieldsPlansAndOtherSessionsAcrossContexts() throws {
        let fixture = try makeFixture(completedCount: 2, includesReducedRow: true)
        let context = fixture.container.mainContext
        let review = try review(fixture)
        XCTAssertEqual(review.defaultSetCount, 2)
        let originalPlan = fixture.source.plannedSetsJSON
        let originalSource = snapshotState(fixture.source, excludingReplacementFields: true)
        let oldRows = Dictionary(uniqueKeysWithValues: fixture.sourceLogs.map { ($0.id, logState($0)) })
        let oldRowsWithoutReduction = Dictionary(uniqueKeysWithValues: fixture.sourceLogs.map {
            ($0.id, logState($0, excludingReduction: true))
        })
        let followingSnapshot = snapshotState(fixture.after, excludingOrder: true)
        let untouched = try storedState(in: context)
        let oldVolume = TrainingMetrics.volume(for: fixture.sourceLogs)

        let replacement = try replace(fixture, review: review)

        let readback = ModelContext(fixture.container)
        let snapshots = try readback.fetch(FetchDescriptor<SessionExercise>())
        let source = try XCTUnwrap(snapshots.first { $0.id == fixture.source.id })
        XCTAssertEqual(snapshotState(source, excludingReplacementFields: true), originalSource)
        XCTAssertEqual(source.plannedSetsJSON, originalPlan)
        XCTAssertEqual(source.targetSets, 2)
        XCTAssertEqual(source.hasManuallyReducedSets, true)
        let allRows = try readback.fetch(FetchDescriptor<SetLog>())
        let oldReadback = allRows.filter { $0.sessionExerciseID == source.id }
        XCTAssertEqual(oldReadback.count, 5)
        for row in oldReadback {
            if row.setNumber == 3 || row.setNumber == 4 {
                XCTAssertGreaterThan(try XCTUnwrap(row.reductionOrder), 7)
                XCTAssertEqual(logState(row, excludingReduction: true),
                    oldRowsWithoutReduction[row.id])
            } else {
                XCTAssertEqual(logState(row), oldRows[row.id])
            }
        }
        XCTAssertEqual(oldReadback.first { $0.setNumber == 5 }?.reductionOrder, 7)
        XCTAssertEqual(snapshots.filter { $0.sessionID == fixture.session.id }.sorted { $0.order < $1.order }.map(\.id),
            [fixture.before.id, source.id, replacement.id, fixture.after.id])
        XCTAssertEqual(TrainingMetrics.volume(for: allRows.filter { $0.sessionExerciseID == source.id || $0.sessionExerciseID == replacement.id }), oldVolume)
        let current = try storedState(in: readback)
        for snapshot in [fixture.before, fixture.foreign] {
            XCTAssertEqual(current.snapshots[snapshot.id], untouched.snapshots[snapshot.id])
        }
        XCTAssertEqual(snapshotState(try XCTUnwrap(snapshots.first { $0.id == fixture.after.id }), excludingOrder: true),
            followingSnapshot)
        for (id, row) in untouched.logs where !fixture.sourceLogs.contains(where: { $0.id == id }) {
            XCTAssertEqual(current.logs[id], row)
        }
        XCTAssertEqual(current.sessions, untouched.sessions)
        XCTAssertEqual(current.templates, untouched.templates)
        XCTAssertFalse(context.hasChanges)
    }

    func testEnteredRemainingDataRequiresConfirmationForManualLegacyRIRAndStartedRows() throws {
        for variation in 0..<4 {
            let fixture = try makeFixture()
            let context = fixture.container.mainContext
            let row = fixture.sourceLogs[3]
            switch variation {
            case 0: row.actualEntrySource = .manual; row.actualWeight = 123
            case 1: row.actualEntrySourceRaw = nil
            case 2: row.rir = 2
            default: row.startedAt = Date(timeIntervalSince1970: 1_792_540_080)
            }
            try context.save()
            let review = try review(fixture)
            XCTAssertTrue(review.requiresEnteredDataConfirmation)
            let before = try storedState(in: ModelContext(fixture.container))
            XCTAssertThrowsError(try replace(fixture, review: review)) { error in
                guard case WorkoutServiceError.replacementNeedsConfirmation = error else { return XCTFail("\(error)") }
            }
            XCTAssertEqual(try storedState(in: ModelContext(fixture.container)), before)
            XCTAssertFalse(context.hasChanges)
            _ = try WorkoutService.replaceRemainingExercise(review: review, with: fixture.replacement,
                configuration: configuration(count: review.defaultSetCount), confirmingEnteredData: true, in: context)
        }
    }

    func testZeroCompletedReplacementAlsoConfirmsPreviouslyReducedDraftsBeforeDeletion() throws {
        let fixture = try makeFixture(includesReducedRow: true)
        let context = fixture.container.mainContext
        let review = try review(fixture)
        XCTAssertEqual(review.defaultSetCount, 4)
        XCTAssertTrue(review.requiresEnteredDataConfirmation)
        let before = try storedState(in: ModelContext(fixture.container))
        XCTAssertThrowsError(try replace(fixture, review: review)) { error in
            guard case WorkoutServiceError.replacementNeedsConfirmation = error else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try storedState(in: ModelContext(fixture.container)), before)
        XCTAssertFalse(context.hasChanges)
        _ = try WorkoutService.replaceRemainingExercise(review: review, with: fixture.replacement,
            configuration: configuration(count: review.defaultSetCount), confirmingEnteredData: true, in: context)
    }

    func testPartialLegacyReplacementFreezesEveryOriginalFallbackPlanBeforeReducingTarget() throws {
        let fixture = try makeFixture(completedCount: 2)
        let context = fixture.container.mainContext
        fixture.source.plannedSetsJSON = nil
        try context.save()
        let originalPlans = fixture.source.plannedSets.map(planValues)
        XCTAssertEqual(originalPlans.count, 4)

        _ = try replace(fixture, review: review(fixture))

        let source = try XCTUnwrap(ModelContext(fixture.container).fetch(FetchDescriptor<SessionExercise>())
            .first { $0.id == fixture.source.id })
        XCTAssertEqual(source.targetSets, 2)
        XCTAssertNotNil(source.plannedSetsJSON)
        XCTAssertEqual(source.plannedSets.map(planValues), originalPlans)
    }

    func testCompletedAndFullyReducedExercisesHaveNoReplacementReview() throws {
        for fullyReduced in [false, true] {
            let fixture = try makeFixture(completedCount: fullyReduced ? 0 : 4)
            let context = fixture.container.mainContext
            if fullyReduced {
                for (index, row) in fixture.sourceLogs.enumerated() { row.reductionOrder = index + 1 }
                fixture.source.targetSets = 0
                fixture.source.hasManuallyReducedSets = true
                try context.save()
            }
            let before = try storedState(in: context)
            XCTAssertThrowsError(try review(fixture)) { error in
                guard case WorkoutServiceError.noIncompleteSet = error else { return XCTFail("\(error)") }
            }
            XCTAssertEqual(try storedState(in: ModelContext(fixture.container)), before)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testSameExistingArchivedAndMissingActionsAreRejectedWithoutMutation() throws {
        let fixture = try makeFixture()
        let context = fixture.container.mainContext
        let review = try review(fixture)
        let existing = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.id == fixture.before.exerciseID })
        for selected in [fixture.sourceExercise, existing] {
            XCTAssertThrowsError(try WorkoutService.replaceRemainingExercise(review: review, with: selected,
                configuration: configuration(), in: context)) { error in
                guard case WorkoutServiceError.exerciseAlreadyAdded = error else { return XCTFail("\(error)") }
            }
            XCTAssertFalse(context.hasChanges)
        }
        fixture.replacement.isArchived = true
        try context.save()
        XCTAssertThrowsError(try replace(fixture, review: review)) { error in
            guard case WorkoutServiceError.archivedExercise = error else { return XCTFail("\(error)") }
        }
        let missing = Exercise(name: "未入库动作", muscleGroup: "背部", equipment: "哑铃")
        XCTAssertThrowsError(try WorkoutService.replaceRemainingExercise(review: review, with: missing,
            configuration: configuration(), in: context)) { error in
            guard case WorkoutServiceError.missingExerciseReference = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).count, 4)
    }

    func testForeignSourceAndEndedOrMissingSessionAreRejected() throws {
        let fixture = try makeFixture()
        let context = fixture.container.mainContext
        let review = try review(fixture)
        XCTAssertThrowsError(try WorkoutService.replacementReview(sessionID: fixture.session.id,
            sourceSessionExerciseID: fixture.foreign.id, in: context)) { error in
            guard case WorkoutServiceError.replacementSourceChanged = error else { return XCTFail("\(error)") }
        }
        fixture.session.status = .completed
        try context.save()
        XCTAssertThrowsError(try replace(fixture, review: review)) { error in
            guard case WorkoutServiceError.sessionNotInProgress = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try WorkoutService.replacementReview(sessionID: UUID(),
            sourceSessionExerciseID: fixture.source.id, in: context)) { error in
            guard case WorkoutServiceError.sessionNotInProgress = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(context.hasChanges)
    }

    func testDirtyContextIsRejectedWithoutDiscardingUnsavedInput() throws {
        let fixture = try makeFixture()
        let context = fixture.container.mainContext
        let review = try review(fixture)
        let originalWeight = fixture.sourceLogs[3].actualWeight
        fixture.sourceLogs[3].actualWeight = 47.5
        XCTAssertThrowsError(try replace(fixture, review: review)) { error in
            guard case WorkoutServiceError.pendingChangesBeforeReplacement = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try self.review(fixture))
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(fixture.sourceLogs[3].actualWeight, 47.5)
        let persisted = try ModelContext(fixture.container).fetch(FetchDescriptor<SetLog>())
        XCTAssertEqual(persisted.first { $0.id == fixture.sourceLogs[3].id }?.actualWeight, originalWeight)
        try context.save()
        XCTAssertThrowsError(try replace(fixture, review: review)) { error in
            guard case WorkoutServiceError.replacementSourceChanged = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(context.hasChanges)
    }

    func testStaleReviewRejectsSavedSetMembershipAndCompletionChanges() throws {
        for variation in 0..<3 {
            let fixture = try makeFixture()
            let context = fixture.container.mainContext
            let review = try review(fixture)
            switch variation {
            case 0:
                fixture.sourceLogs[3].isCompleted = true
                fixture.sourceLogs[3].completedAt = .now
            case 1:
                _ = try WorkoutService.addSet(to: fixture.source, in: context)
            default:
                fixture.source.order = 5
            }
            try context.save()
            let before = try storedState(in: ModelContext(fixture.container))
            XCTAssertThrowsError(try replace(fixture, review: review)) { error in
                guard case WorkoutServiceError.replacementSourceChanged = error else { return XCTFail("\(error)") }
            }
            XCTAssertEqual(try storedState(in: ModelContext(fixture.container)), before)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testDuplicateSubmissionNeverCreatesASecondReplacement() throws {
        for completedCount in [0, 2] {
            let fixture = try makeFixture(completedCount: completedCount)
            let context = fixture.container.mainContext
            let review = try review(fixture)
            _ = try replace(fixture, review: review)
            let before = try storedState(in: ModelContext(fixture.container))
            XCTAssertThrowsError(try replace(fixture, review: review))
            XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).filter {
                $0.sessionID == fixture.session.id && $0.exerciseID == fixture.replacement.id
            }.count, 1)
            XCTAssertEqual(try storedState(in: ModelContext(fixture.container)), before)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testFailedZeroCompletedSaveRestoresDeletedSourceAndAllowsRetry() throws {
        try assertFailedSaveRestoresEverything(completedCount: 0)
    }

    func testFailedPartialSaveRestoresArchivedRowsAndAllowsRetry() throws {
        try assertFailedSaveRestoresEverything(completedCount: 2)
    }

    func testFinishSkipsReplacedSourceTemplateButUpdatesOtherActionsNormally() throws {
        let fixture = try makeFixture(completedCount: 2)
        let context = fixture.container.mainContext
        let sourceTemplate = fixture.templateItems[1]
        let originalSourcePlan = sourceTemplate.plannedSetsJSON
        _ = try replace(fixture, review: review(fixture))
        try WorkoutService.finish(session: fixture.session, schedules: [], in: context)

        let readback = ModelContext(fixture.container)
        let items = try readback.fetch(FetchDescriptor<TemplateExercise>())
        XCTAssertEqual(items.count, 3, "临时替换不能自动加入长期模板")
        XCTAssertEqual(items.first { $0.id == sourceTemplate.id }?.plannedSetsJSON, originalSourcePlan)
        for snapshot in [fixture.before, fixture.after] {
            let updated = try XCTUnwrap(items.first { $0.exerciseID == snapshot.exerciseID })
            XCTAssertEqual(updated.plannedSets.map(\.weight), [27.5])
            XCTAssertEqual(updated.plannedSets.map(\.reps), [9])
        }
    }

    func testFinishOfOneOffReplacementKeepsAllTemplatePlansUnchanged() throws {
        let fixture = try makeFixture(completedCount: 2, isOneOff: true)
        let context = fixture.container.mainContext
        let before = Dictionary(uniqueKeysWithValues: fixture.templateItems.map { ($0.id, $0.plannedSetsJSON) })
        _ = try replace(fixture, review: review(fixture))
        try WorkoutService.finish(session: fixture.session, schedules: [], in: context)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: try ModelContext(fixture.container)
            .fetch(FetchDescriptor<TemplateExercise>()).map { ($0.id, $0.plannedSetsJSON) }), before)
    }

    func testExplicitRestoreAfterReplacementOnlyRestoresOneOriginalSet() throws {
        let fixture = try makeFixture(completedCount: 2)
        let context = fixture.container.mainContext
        let replacement = try replace(fixture, review: review(fixture))
        let newPlan = replacement.plannedSetsJSON
        try WorkoutService.restoreReducedSet(for: fixture.source, in: context)
        let readback = ModelContext(fixture.container)
        let snapshots = try readback.fetch(FetchDescriptor<SessionExercise>())
        XCTAssertEqual(snapshots.first { $0.id == fixture.source.id }?.targetSets, 3)
        XCTAssertEqual(snapshots.first { $0.id == replacement.id }?.plannedSetsJSON, newPlan)
        XCTAssertEqual(try readback.fetch(FetchDescriptor<SetLog>()).filter {
            $0.sessionExerciseID == fixture.source.id && $0.reductionOrder == nil
        }.count, 3)
    }

    private func assertFailedSaveRestoresEverything(completedCount: Int) throws {
        let fixture = try makeFixture(completedCount: completedCount)
        let context = fixture.container.mainContext
        let review = try review(fixture)
        let before = try storedState(in: ModelContext(fixture.container))
        context.autosaveEnabled = true
        var saves = 0
        struct SaveFailure: Error {}
        XCTAssertThrowsError(try WorkoutService.replaceRemainingExercise(review: review,
            with: fixture.replacement, configuration: configuration(), in: context, save: { transaction in
                saves += 1
                XCTAssertFalse(transaction.autosaveEnabled)
                throw SaveFailure()
            })) { error in XCTAssertTrue(error is SaveFailure) }
        XCTAssertEqual(saves, 1)
        XCTAssertTrue(context.autosaveEnabled)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try storedState(in: ModelContext(fixture.container)), before)
        XCTAssertEqual(try storedState(in: context), before, "当前上下文也必须恢复，不能只在新上下文中看起来正确")
        XCTAssertEqual(try self.review(fixture), review)
        _ = try replace(fixture, review: review)
        XCTAssertEqual(try ModelContext(fixture.container).fetch(FetchDescriptor<SessionExercise>()).filter {
            $0.exerciseID == fixture.replacement.id
        }.count, 1)
    }

    private struct Fixture {
        let container: ModelContainer
        let session: WorkoutSession
        let sourceExercise: Exercise
        let replacement: Exercise
        let before: SessionExercise
        let source: SessionExercise
        let after: SessionExercise
        let foreign: SessionExercise
        let sourceLogs: [SetLog]
        let templateItems: [TemplateExercise]
    }

    private func makeFixture(setCount: Int = 4, completedCount: Int = 0,
        includesReducedRow: Bool = false, isOneOff: Bool = false) throws -> Fixture {
        let schema = Schema([Exercise.self, WorkoutSession.self, SessionExercise.self, SetLog.self,
            WorkoutTemplate.self, TemplateExercise.self, ScheduledWorkout.self, BodyMeasurement.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        let context = container.mainContext
        context.autosaveEnabled = false
        let date = Date(timeIntervalSince1970: 1_792_540_000)
        let template = WorkoutTemplate(name: "长期模板", weekday: 1, isOneOff: isOneOff)
        let session = WorkoutSession(templateID: template.id, templateName: "本次训练", plannedDate: date,
            startedAt: date, notes: "原训练备注", restEndDate: date.addingTimeInterval(90), restMode: .freestyle)
        let other = WorkoutSession(templateName: "旧历史", plannedDate: date.addingTimeInterval(-86_400),
            startedAt: date.addingTimeInterval(-86_400), completedAt: date.addingTimeInterval(-85_000), status: .completed)
        context.insert(template); context.insert(session); context.insert(other)
        let catalog = (0..<4).map { Exercise(name: "测试动作\($0)", muscleGroup: "背部", equipment: "器械\($0)") }
        catalog.forEach(context.insert)
        var snapshots: [SessionExercise] = [], templateItems: [TemplateExercise] = []
        var sourceLogs: [SetLog] = []
        for index in 0..<4 {
            let count = index == 1 ? setCount : 1
            let exercise = catalog[index == 3 ? 1 : index]
            let plans = (0..<count).map { number in
                WorkoutSetPlan(weight: 60 + Double(number), reps: 8 + number,
                    weightSide: .single, repsSide: .bilateral, actualDefaultPolicy: .plan,
                    prescription: WorkoutSetPrescription(label: "原处方\(number)", repsLower: 8, repsUpper: 12,
                        rirLower: 1, rirUpper: 3, restLowerSeconds: 90, restUpperSeconds: 120))
            }
            let snapshot = SessionExercise(sessionID: index == 3 ? other.id : session.id,
                exerciseID: exercise.id, exerciseName: exercise.name, order: index == 3 ? 40 : index,
                targetSets: count, minReps: 8, maxReps: 12, targetWeight: 60, restSeconds: 120,
                muscleGroup: "背部", exerciseNotes: "原动作说明", referenceURL: "https://example.com/original",
                performanceNotes: "原表现备注", plannedSets: plans, planPattern: .pyramidUp, feeling: .strong,
                exerciseStartedAt: date, bodyWeightKgSnapshot: 72.5, bodyWeightSnapshotSourceDate: date,
                equipmentSnapshot: exercise.equipment)
            snapshots.append(snapshot); context.insert(snapshot)
            for number in 0..<count {
                let done = index != 1 || number < completedCount
                let row = SetLog(sessionID: snapshot.sessionID, sessionExerciseID: snapshot.id,
                    exerciseID: exercise.id, setNumber: number + 1, targetWeight: 60 + Double(number), targetReps: 8,
                    actualWeight: done ? 27.5 : 60, actualReps: done ? 9 : 8, rir: done ? 2 : nil,
                    isWarmup: index == 1 && number == 1, isCompleted: done,
                    startedAt: done ? date.addingTimeInterval(Double(number * 20)) : nil,
                    completedAt: done ? date.addingTimeInterval(Double(number * 20 + 10)) : nil,
                    restStartedAt: done ? date.addingTimeInterval(Double(number * 20 + 10)) : nil,
                    restEndedAt: done ? date.addingTimeInterval(Double(number * 20 + 15)) : nil,
                    restDurationSeconds: done ? 5 : nil, targetWeightSide: .single, targetRepsSide: .bilateral,
                    actualWeightSide: .unknown, actualRepsSide: .single, actualEntrySource: done ? .manual : .plan,
                    sourceHistorySetID: UUID(), actualWeightIsBlank: false)
                context.insert(row)
                if index == 1 { sourceLogs.append(row) }
            }
            if index < 3 {
                let item = TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: index,
                    targetSets: count, minReps: 8, maxReps: 12, targetWeight: 60, restSeconds: 120, plannedSets: plans)
                context.insert(item); templateItems.append(item)
            }
        }
        if includesReducedRow {
            let archived = SetLog(sessionID: session.id, sessionExerciseID: snapshots[1].id,
                exerciseID: catalog[1].id, setNumber: 5, targetWeight: 11, targetReps: 3,
                actualWeight: 99, actualReps: 2, actualEntrySource: .manual)
            archived.reductionOrder = 7
            context.insert(archived); sourceLogs.append(archived)
            snapshots[1].hasManuallyReducedSets = true
        }
        try context.save()
        return Fixture(container: container, session: session, sourceExercise: catalog[1], replacement: catalog[3],
            before: snapshots[0], source: snapshots[1], after: snapshots[2], foreign: snapshots[3],
            sourceLogs: sourceLogs, templateItems: templateItems)
    }

    private func review(_ fixture: Fixture) throws -> WorkoutExerciseReplacementReview {
        try WorkoutService.replacementReview(sessionID: fixture.session.id,
            sourceSessionExerciseID: fixture.source.id, in: fixture.container.mainContext)
    }

    private func configuration(count: Int = 2) -> ExerciseSetupDraft {
        ExerciseSetupDraft(pattern: .fixed, plannedSets: (0..<count).map {
            WorkoutSetPlan(weight: 7.5 + Double($0) * 2.5, reps: 11, actualDefaultPolicy: .plan)
        }, restSeconds: 60, previousDate: nil)
    }

    private func replace(_ fixture: Fixture, review: WorkoutExerciseReplacementReview) throws -> SessionExercise {
        try WorkoutService.replaceRemainingExercise(review: review, with: fixture.replacement,
            configuration: configuration(count: review.defaultSetCount), in: fixture.container.mainContext)
    }

    private struct StoredState: Equatable {
        var sessions: [UUID: [String]]
        var snapshots: [UUID: [String]]
        var logs: [UUID: [String]]
        var templates: [UUID: [String]]
    }

    private func storedState(in context: ModelContext) throws -> StoredState {
        StoredState(sessions: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<WorkoutSession>()).map {
            ($0.id, state([$0.id, $0.scheduledWorkoutID, $0.templateID, $0.templateName, $0.plannedDate,
                $0.trainingLocalDay, $0.trainingTimeZoneIdentifier, $0.startedAt, $0.startTimeKnownRaw,
                $0.completedAt, $0.statusRaw, $0.notes, $0.restEndDate, $0.restModeRaw,
                $0.importIdentifier, $0.defaultPlanPatternRaw, $0.cardioResistanceLevel]))
        }), snapshots: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SessionExercise>()).map {
            ($0.id, snapshotState($0))
        }), logs: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SetLog>()).map {
            ($0.id, logState($0))
        }), templates: Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TemplateExercise>()).map {
            ($0.id, state([$0.id, $0.templateID, $0.exerciseID, $0.order, $0.targetSets, $0.minReps,
                $0.maxReps, $0.targetWeight, $0.restSeconds, $0.plannedSetsJSON, $0.planPatternRaw, $0.patternSourceRaw]))
        }))
    }

    private func state(_ values: [Any?]) -> [String] {
        values.map { $0.map { String(describing: $0) } ?? "<nil>" }
    }

    private func planValues(_ plan: WorkoutSetPlan) -> [String] {
        state([plan.weight, plan.reps, plan.weightSide.rawValue, plan.repsSide.rawValue,
            plan.actualDefaultPolicyRaw, plan.prescription])
    }

    private func snapshotState(_ row: SessionExercise, excludingReplacementFields: Bool = false,
        excludingOrder: Bool = false) -> [String] {
        state([row.id, row.sessionID, row.exerciseID, row.exerciseName, excludingOrder ? nil : row.order,
            excludingReplacementFields ? nil : row.targetSets, row.minReps, row.maxReps, row.targetWeight,
            row.restSeconds, row.muscleGroup, row.exerciseNotes, row.referenceURL, row.volumeUnitRaw,
            row.performanceNotes, row.plannedSetsJSON, excludingReplacementFields ? nil : row.hasManuallyReducedSets,
            row.planPatternRaw, row.patternSourceRaw, row.feelingRaw, row.exerciseStartedAt, row.exerciseCompletedAt,
            row.bodyWeightKgSnapshot, row.bodyWeightSnapshotSourceDate, row.equipmentSnapshot])
    }

    private func logState(_ row: SetLog, excludingReduction: Bool = false) -> [String] {
        state([row.id, row.sessionID, row.sessionExerciseID, row.exerciseID, row.setNumber,
            excludingReduction ? nil : row.reductionOrder, row.targetWeight, row.targetReps,
            row.actualWeight, row.actualReps, row.rir, row.isWarmup, row.isCompleted, row.startedAt,
            row.completedAt, row.restStartedAt, row.restEndedAt, row.restDurationSeconds,
            row.targetWeightSideRaw, row.targetRepsSideRaw, row.actualWeightSideRaw, row.actualRepsSideRaw,
            row.actualEntrySourceRaw, row.sourceHistorySetID, row.actualWeightIsBlank])
    }
}
