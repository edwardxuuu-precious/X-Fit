import Foundation
import SwiftData
import XCTest
@testable import FitnessApp

final class MealExchangeServiceTests: XCTestCase {
    @MainActor
    func testMealHistoryKeepsSelectedInstantAndLegacyTimeRemainsUnknown() throws {
        let selected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-23T14:30:00Z"))
        XCTAssertEqual(NutritionView(initialDate: selected).selectedDate, selected)
        let meal = MealEntry(date: selected, mealType: .snack, name: "旧文字餐食",
            calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        XCTAssertEqual(MealPhotoPresentation.time(meal), "时间未记录")
        meal.recordedTimeKnown = true
        meal.captureTimeZoneIdentifier = "Australia/Sydney"
        XCTAssertEqual(MealPhotoPresentation.time(meal), "00:30")
    }

    @MainActor
    func testManualMealEditorKeepsSelectedLocalInstantForAustralia() throws {
        let selected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-23T14:30:00Z"))
        let editor = MealEditorView(meal: nil, date: selected)
        XCTAssertEqual(editor.date, selected)
    }

    func testRequestsRejectPathTraversalAndRequireExactApprovedPayloadDigest() throws {
        let request = MealExchangeRequest(version: 1, id: UUID(), operation: .applyReview,
            startLocalDay: nil, endLocalDay: nil, payloadFileName: "../outside.json", approvedSHA256: String(repeating: "a", count: 64))
        XCTAssertThrowsError(try request.validate())
        let unconfirmed = MealExchangeRequest(version: 1, id: UUID(), operation: .applyReview,
            startLocalDay: nil, endLocalDay: nil, payloadFileName: "review.json", approvedSHA256: nil)
        XCTAssertThrowsError(try unconfirmed.validate())
        let export = MealExchangeRequest(version: 1, id: UUID(), operation: .exportWeek,
            startLocalDay: "2026-09-21", endLocalDay: "2026-09-27", payloadFileName: nil, approvedSHA256: nil)
        XCTAssertNoThrow(try export.validate())
        let correctionWithoutDigest = MealExchangeRequest(version: 1, id: UUID(), operation: .correctHistoricalExercise,
            startLocalDay: nil, endLocalDay: nil, payloadFileName: "correction.json", approvedSHA256: nil)
        XCTAssertThrowsError(try correctionWithoutDigest.validate())
        let correction = MealExchangeRequest(version: 1, id: UUID(), operation: .correctHistoricalExercise,
            startLocalDay: nil, endLocalDay: nil, payloadFileName: "correction.json", approvedSHA256: String(repeating: "a", count: 64))
        XCTAssertNoThrow(try correction.validate())
    }

    @MainActor
    func testHistoricalCorrectionPreservesAllOtherFieldsAndRetryDoesNotWrite() throws {
        let fixture = try correctionFixture()
        let context = fixture.container.mainContext
        let packet = try JSONDecoder().decode(HistoricalExerciseCorrectionPacket.self, from: JSONEncoder().encode(fixture.packet))
        let otherSnapshot = HistoricalCorrectionSnapshotState(fixture.otherSnapshot)
        let otherSet = HistoricalCorrectionSetState(fixture.otherSet)

        var saveCount = 0
        let result = try HistoricalExerciseCorrectionService.apply(packet, in: context) { context in
            saveCount += 1
            try context.save()
        }
        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.preservedSetCount, 4)
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(fixture.source.name, "坐姿腿弯举")
        XCTAssertEqual(fixture.snapshot.exerciseID, packet.target.id)
        XCTAssertEqual(fixture.snapshot.exerciseName, packet.target.name)
        XCTAssertEqual(fixture.snapshot.performanceNotes,
            "原始备注\n本人确认动作更正为「坐姿腿屈伸（器械未确认）」；原名称「坐姿腿弯举」。确认依据：本人确认。具体机器未知。")
        var normalizedSnapshot = HistoricalCorrectionSnapshotState(fixture.snapshot)
        normalizedSnapshot.exerciseID = packet.expectedSnapshot.exerciseID
        normalizedSnapshot.exerciseName = packet.expectedSnapshot.exerciseName
        normalizedSnapshot.performanceNotes = packet.expectedSnapshot.performanceNotes
        XCTAssertEqual(normalizedSnapshot, packet.expectedSnapshot)
        let actualSets = fixture.logs.map { log -> HistoricalCorrectionSetState in
            var state = HistoricalCorrectionSetState(log)
            XCTAssertEqual(state.exerciseID, packet.target.id)
            state.exerciseID = packet.expectedSnapshot.exerciseID
            return state
        }
        XCTAssertEqual(actualSets, packet.expectedSets)
        XCTAssertEqual(HistoricalCorrectionSnapshotState(fixture.otherSnapshot), otherSnapshot)
        XCTAssertEqual(HistoricalCorrectionSetState(fixture.otherSet), otherSet)
        XCTAssertEqual(fixture.otherSession.notes, "另一场记录")
        let target = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.id == packet.target.id })
        XCTAssertEqual(target.name, packet.target.name)
        XCTAssertEqual(target.muscleGroup, packet.target.muscleGroup)
        XCTAssertEqual(target.equipment, packet.target.equipment)
        XCTAssertEqual(target.volumeUnit, packet.target.volumeUnit)
        XCTAssertFalse(context.hasChanges)

        let retry = try HistoricalExerciseCorrectionService.apply(packet, in: context) { _ in
            XCTFail("同包重试不能保存")
        }
        XCTAssertFalse(retry.applied)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).filter { $0.id == packet.target.id }.count, 1)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(HistoricalCorrectionSnapshotState(fixture.otherSnapshot), otherSnapshot)
        XCTAssertEqual(HistoricalCorrectionSetState(fixture.otherSet), otherSet)
    }

    @MainActor
    func testHistoricalCorrectionRejectsDriftWithoutWriting() throws {
        let mutations: [(CorrectionFixture) -> Void] = [
            { $0.logs[0].actualWeight += 1 },
            { $0.logs[1].rir = 3 },
            { $0.logs[2].completedAt = Date(timeIntervalSinceReferenceDate: 987_654) },
            { $0.logs[3].isWarmup = true },
            { $0.snapshot.performanceNotes = "训练后补充的备注" }
        ]
        for mutate in mutations {
            let fixture = try correctionFixture()
            let context = fixture.container.mainContext
            mutate(fixture)
            try context.save()
            let snapshotBefore = HistoricalCorrectionSnapshotState(fixture.snapshot)
            let setsBefore = fixture.logs.map(HistoricalCorrectionSetState.init)
            XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context)) {
                XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .changedRecord)
            }
            XCTAssertEqual(HistoricalCorrectionSnapshotState(fixture.snapshot), snapshotBefore)
            XCTAssertEqual(fixture.logs.map(HistoricalCorrectionSetState.init), setsBefore)
            XCTAssertFalse(try context.fetch(FetchDescriptor<Exercise>()).contains { $0.id == fixture.packet.target.id })
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testHistoricalCorrectionRejectsConflictingTargetIdentity() throws {
        for useConflictingID in [false, true] {
            let fixture = try correctionFixture()
            let context = fixture.container.mainContext
            let packet = fixture.packet
            let conflict = Exercise(id: useConflictingID ? packet.target.id : UUID(), name: packet.target.name,
                muscleGroup: packet.target.muscleGroup, equipment: "不同的器械", isBuiltIn: false,
                notes: packet.target.notes, volumeUnit: packet.target.volumeUnit)
            context.insert(conflict)
            try context.save()
            XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(packet, in: context)) {
                XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .conflictingTarget)
            }
            XCTAssertEqual(HistoricalCorrectionSnapshotState(fixture.snapshot), packet.expectedSnapshot)
            XCTAssertEqual(fixture.logs.map(HistoricalCorrectionSetState.init), packet.expectedSets)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testHistoricalCorrectionMayReuseOnlyExactUniqueTarget() throws {
        let fixture = try correctionFixture()
        let context = fixture.container.mainContext
        let target = fixture.packet.target
        context.insert(Exercise(id: target.id, name: target.name, muscleGroup: target.muscleGroup,
            equipment: target.equipment, isBuiltIn: false, notes: target.notes, volumeUnit: target.volumeUnit))
        try context.save()
        XCTAssertTrue(try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context).applied)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).filter { $0.id == target.id }.count, 1)
        context.insert(Exercise(name: target.name, muscleGroup: target.muscleGroup, equipment: target.equipment,
            isBuiltIn: false, notes: target.notes, volumeUnit: target.volumeUnit))
        try context.save()
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context)) {
            XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .conflictingTarget)
        }
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    func testHistoricalCorrectionRejectsAnUnfinishedSessionOrExtraSet() throws {
        let unfinished = try correctionFixture()
        let unfinishedContext = unfinished.container.mainContext
        let session = try XCTUnwrap(unfinishedContext.fetch(FetchDescriptor<WorkoutSession>())
            .first { $0.id == unfinished.packet.sessionID })
        session.status = .inProgress
        try unfinishedContext.save()
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(unfinished.packet, in: unfinishedContext)) {
            XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .changedRecord)
        }
        XCTAssertEqual(HistoricalCorrectionSnapshotState(unfinished.snapshot), unfinished.packet.expectedSnapshot)
        XCTAssertFalse(unfinishedContext.hasChanges)

        let extra = try correctionFixture()
        let extraContext = extra.container.mainContext
        extraContext.insert(SetLog(sessionID: extra.packet.sessionID, sessionExerciseID: extra.snapshot.id,
            exerciseID: extra.source.id, setNumber: 5, targetWeight: 0, targetReps: 0,
            actualWeight: 0, actualReps: 0, isCompleted: false))
        try extraContext.save()
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(extra.packet, in: extraContext)) {
            XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .changedRecord)
        }
        XCTAssertEqual(HistoricalCorrectionSnapshotState(extra.snapshot), extra.packet.expectedSnapshot)
        XCTAssertFalse(extraContext.hasChanges)
    }

    @MainActor
    func testHistoricalCorrectionRejectsPartialStateAndDifferentConfirmationOnRetry() throws {
        let fixture = try correctionFixture()
        let context = fixture.container.mainContext
        fixture.snapshot.exerciseID = fixture.packet.target.id
        try context.save()
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context)) {
            XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .changedRecord)
        }
        XCTAssertFalse(try context.fetch(FetchDescriptor<Exercise>()).contains { $0.id == fixture.packet.target.id })
        XCTAssertEqual(fixture.logs.map(HistoricalCorrectionSetState.init), fixture.packet.expectedSets)
        XCTAssertFalse(context.hasChanges)

        let other = try correctionFixture()
        let otherContext = other.container.mainContext
        _ = try HistoricalExerciseCorrectionService.apply(other.packet, in: otherContext)
        var differentPacket = other.packet
        differentPacket.confirmationReference = "另一份确认"
        let correctedSnapshot = HistoricalCorrectionSnapshotState(other.snapshot)
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(differentPacket, in: otherContext)) {
            XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .changedRecord)
        }
        XCTAssertEqual(HistoricalCorrectionSnapshotState(other.snapshot), correctedSnapshot)
        XCTAssertFalse(otherContext.hasChanges)
    }

    @MainActor
    func testHistoricalCorrectionProtectsUnrelatedPendingEditsAndRestoresAfterSaveFailure() throws {
        let pending = try correctionFixture()
        let pendingContext = pending.container.mainContext
        pending.otherSession.notes = "尚未保存的用户编辑"
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(pending.packet, in: pendingContext)) {
            XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .pendingChanges)
        }
        XCTAssertEqual(pending.otherSession.notes, "尚未保存的用户编辑")
        XCTAssertTrue(pendingContext.hasChanges)
        XCTAssertEqual(HistoricalCorrectionSnapshotState(pending.snapshot), pending.packet.expectedSnapshot)
        XCTAssertFalse(try pendingContext.fetch(FetchDescriptor<Exercise>()).contains { $0.id == pending.packet.target.id })

        let failure = try correctionFixture()
        let failureContext = failure.container.mainContext
        var saveCount = 0
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(failure.packet, in: failureContext) { _ in
            saveCount += 1
            throw InjectedSaveFailure.failed
        })
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(HistoricalCorrectionSnapshotState(failure.snapshot), failure.packet.expectedSnapshot)
        XCTAssertEqual(failure.logs.map(HistoricalCorrectionSetState.init), failure.packet.expectedSets)
        XCTAssertEqual(failure.otherSession.notes, "另一场记录")
        XCTAssertFalse(try failureContext.fetch(FetchDescriptor<Exercise>()).contains { $0.id == failure.packet.target.id })
    }

    @MainActor
    func testBlankActualCorrectionThroughWirePreservesHistoryAndRetriesInFreshContext() throws {
        let fixture = try blankCorrectionFixture()
        let context = fixture.base.container.mainContext
        let packet = fixture.packet
        let sessionBefore = HistoricalCorrectionSessionState(fixture.session)
        let targetBefore = HistoricalCorrectionCatalogState(fixture.target)
        let sourceBefore = HistoricalCorrectionCatalogState(fixture.base.source)
        let otherSnapshot = HistoricalBlankSnapshotState(fixture.base.otherSnapshot)
        let otherSet = HistoricalBlankSetState(fixture.base.otherSet)
        let data = try JSONEncoder().encode(packet)
        let decoded = try JSONDecoder().decode(HistoricalBlankActualCorrectionPacket.self, from: data)
        XCTAssertEqual(decoded.existingTarget, targetBefore)
        XCTAssertEqual(decoded.expectedSets, packet.expectedSets)
        var saves = 0
        let result = try HistoricalExerciseCorrectionService.apply(data, in: context) { context in
            saves += 1
            try context.save()
        }
        XCTAssertTrue(result.applied)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(result.preservedSetCount, 4)
        XCTAssertEqual(fixture.base.snapshot.id, packet.expectedSnapshot.id)
        XCTAssertEqual(fixture.base.snapshot.exerciseID, targetBefore.id)
        XCTAssertEqual(fixture.base.snapshot.exerciseName, "器械下斜卧推")
        XCTAssertEqual(fixture.base.snapshot.plannedSetsJSON, packet.expectedSnapshot.plannedSetsJSON)
        XCTAssertEqual(fixture.base.snapshot.exerciseNotes, packet.expectedSnapshot.exerciseNotes)
        XCTAssertEqual(fixture.base.snapshot.exerciseStartedAt?.timeIntervalSinceReferenceDate,
            packet.expectedSnapshot.exerciseStartedAtReferenceSeconds)
        XCTAssertNil(fixture.base.snapshot.exerciseCompletedAt)
        XCTAssertTrue(fixture.base.snapshot.performanceNotes.contains("原计划动作「坐姿飞鸟」"))
        XCTAssertTrue(fixture.base.snapshot.performanceNotes.contains("不含机器空载"))
        XCTAssertTrue(fixture.base.snapshot.performanceNotes.contains("RIR、组起止与休息未知"))
        var preservedSnapshot = HistoricalBlankSnapshotState(fixture.base.snapshot)
        preservedSnapshot.exerciseID = packet.expectedSnapshot.exerciseID
        preservedSnapshot.exerciseName = packet.expectedSnapshot.exerciseName
        preservedSnapshot.performanceNotes = packet.expectedSnapshot.performanceNotes
        XCTAssertEqual(preservedSnapshot, packet.expectedSnapshot)
        let weights = [25.0, 27.5, 30.0, 32.5]
        let reps = [12, 12, 10, 10]
        for (index, log) in fixture.base.logs.enumerated() {
            let old = packet.expectedSets[index]
            XCTAssertEqual(log.id, old.id)
            XCTAssertEqual(log.exerciseID, targetBefore.id)
            XCTAssertEqual(log.actualWeight, weights[index])
            XCTAssertEqual(log.actualReps, reps[index])
            XCTAssertEqual(log.actualWeightSide, .single)
            XCTAssertEqual(log.actualRepsSide, .unknown)
            XCTAssertEqual(log.actualEntrySource, .manual)
            XCTAssertEqual(log.actualWeightIsBlank, false)
            XCTAssertTrue(log.isCompleted)
            XCTAssertNil(log.rir)
            XCTAssertNil(log.startedAt)
            XCTAssertNil(log.completedAt)
            XCTAssertNil(log.restStartedAt)
            XCTAssertNil(log.restEndedAt)
            XCTAssertNil(log.restDurationSeconds)
            var preserved = HistoricalBlankSetState(log)
            preserved.exerciseID = old.exerciseID
            preserved.actualWeight = old.actualWeight
            preserved.actualReps = old.actualReps
            preserved.actualWeightSideRaw = old.actualWeightSideRaw
            preserved.actualEntrySourceRaw = old.actualEntrySourceRaw
            preserved.actualWeightIsBlank = old.actualWeightIsBlank
            preserved.isCompleted = old.isCompleted
            XCTAssertEqual(preserved, old)
        }
        XCTAssertEqual(HistoricalCorrectionSessionState(fixture.session), sessionBefore)
        XCTAssertEqual(HistoricalCorrectionCatalogState(fixture.target), targetBefore)
        XCTAssertEqual(HistoricalCorrectionCatalogState(fixture.base.source), sourceBefore)
        XCTAssertEqual(HistoricalBlankSnapshotState(fixture.base.otherSnapshot), otherSnapshot)
        XCTAssertEqual(HistoricalBlankSetState(fixture.base.otherSet), otherSet)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 5)
        XCTAssertFalse(context.hasChanges)

        let fresh = ModelContext(fixture.base.container)
        fresh.autosaveEnabled = false
        let retry = try HistoricalExerciseCorrectionService.apply(data, in: fresh) { _ in
            XCTFail("完整目标状态重试不能再次保存")
        }
        XCTAssertFalse(retry.applied)
        XCTAssertFalse(fresh.hasChanges)
        let reread = try XCTUnwrap(fresh.fetch(FetchDescriptor<SessionExercise>()).first { $0.id == result.snapshotID })
        XCTAssertEqual(reread.performanceNotes, fixture.base.snapshot.performanceNotes)
        XCTAssertEqual(try fresh.fetchCount(FetchDescriptor<SetLog>()), 5)
    }

    @MainActor
    func testBlankActualWireRequiresExplicitNullableStateAndRejectsUnknownContract() throws {
        let fixture = try blankCorrectionFixture()
        let data = try JSONEncoder().encode(fixture.packet)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let fields = [("expectedSession", "restEndDateReferenceSeconds"),
                      ("expectedSnapshot", "feelingRaw"), ("existingTarget", "volumeUnitRaw")]
        for (section, key) in fields {
            var changed = original
            var state = try XCTUnwrap(changed[section] as? [String: Any])
            XCTAssertTrue(state[key] is NSNull)
            state.removeValue(forKey: key)
            changed[section] = state
            XCTAssertThrowsError(try JSONDecoder().decode(HistoricalBlankActualCorrectionPacket.self,
                from: JSONSerialization.data(withJSONObject: changed)))
        }
        var missingSet = original
        var sets = try XCTUnwrap(missingSet["expectedSets"] as? [[String: Any]])
        XCTAssertTrue(sets[0]["reductionOrder"] is NSNull)
        sets[0].removeValue(forKey: "reductionOrder")
        missingSet["expectedSets"] = sets
        XCTAssertThrowsError(try JSONDecoder().decode(HistoricalBlankActualCorrectionPacket.self,
            from: JSONSerialization.data(withJSONObject: missingSet)))
        var unknown = original
        unknown["version"] = 3
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(
            JSONSerialization.data(withJSONObject: unknown), in: fixture.base.container.mainContext)) {
            XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .invalidPacket)
        }
        unknown = original
        unknown["weightConvention"] = "machineTotal"
        XCTAssertThrowsError(try JSONDecoder().decode(HistoricalBlankActualCorrectionPacket.self,
            from: JSONSerialization.data(withJSONObject: unknown)))
        unknown = original
        unknown.removeValue(forKey: "confirmedActuals")
        XCTAssertThrowsError(try JSONDecoder().decode(HistoricalBlankActualCorrectionPacket.self,
            from: JSONSerialization.data(withJSONObject: unknown)))
        XCTAssertFalse(fixture.base.container.mainContext.hasChanges)
    }

    @MainActor
    func testBlankActualCorrectionRejectsInvalidTransitionsAndActuals() throws {
        let mutations: [(inout HistoricalBlankActualCorrectionPacket) -> Void] = [
            { $0.version = 1 },
            { $0.confirmationReference = " " },
            { $0.expectedSession.statusRaw = WorkoutSessionStatus.inProgress.rawValue },
            { $0.expectedSession.trainingLocalDay = nil },
            { $0.expectedSession.trainingTimeZoneIdentifier = "invalid-zone" },
            { $0.expectedSnapshot.volumeUnitRaw = ExerciseVolumeUnit.meter.rawValue },
            { $0.existingTarget.volumeUnitRaw = ExerciseVolumeUnit.bodyweight.rawValue },
            { $0.expectedSnapshot.muscleGroup = "背部" },
            { $0.expectedSnapshot.hasManuallyReducedSets = true },
            { $0.expectedSets[0].actualWeight = 1 },
            { $0.expectedSets[0].isCompleted = true },
            { $0.expectedSets[0].isWarmup = true },
            { $0.expectedSets[0].actualEntrySourceRaw = WorkoutActualEntrySource.manual.rawValue },
            { $0.expectedSets[0].actualWeightIsBlank = nil },
            { $0.expectedSets[0].rir = 0 },
            { $0.expectedSets[0].startedAtReferenceSeconds = 100 },
            { $0.expectedSets[0].restDurationSeconds = 0 },
            { $0.expectedSets[0].reductionOrder = 0 },
            { $0.expectedSets[0].sourceHistorySetID = UUID() },
            { $0.expectedSets[0].setNumber = 2 },
            { $0.expectedSets[0].id = $0.expectedSets[1].id },
            { $0.confirmedActuals.removeLast() },
            { $0.confirmedActuals[0].setID = $0.confirmedActuals[1].setID },
            { $0.confirmedActuals[0].kilogramsPerSide = 0 },
            { $0.confirmedActuals[0].kilogramsPerSide = -1 },
            { $0.confirmedActuals[0].kilogramsPerSide = .infinity },
            { $0.confirmedActuals[0].kilogramsPerSide = .nan },
            { $0.confirmedActuals[0].reps = 0 }
        ]
        for mutate in mutations {
            let fixture = try blankCorrectionFixture()
            let context = fixture.base.container.mainContext
            var packet = fixture.packet
            mutate(&packet)
            XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(packet, in: context) { _ in
                XCTFail("非法变更不能保存")
            }) {
                XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .invalidPacket)
            }
            XCTAssertEqual(HistoricalBlankSnapshotState(fixture.base.snapshot), fixture.packet.expectedSnapshot)
            XCTAssertEqual(fixture.base.logs.map(HistoricalBlankSetState.init), fixture.packet.expectedSets)
            XCTAssertEqual(HistoricalCorrectionCatalogState(fixture.target), fixture.packet.existingTarget)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testBlankActualCorrectionRejectsAllObservedStateDrift() throws {
        let mutations: [(BlankCorrectionFixture) -> Void] = [
            { $0.session.notes = "后来编辑" },
            { $0.session.completedAt = Date(timeIntervalSinceReferenceDate: 900_000_000) },
            { $0.session.restModeRaw = nil },
            { $0.session.cardioResistanceLevel = 2 },
            { $0.base.snapshot.plannedSetsJSON = "变更处方" },
            { $0.base.snapshot.hasManuallyReducedSets = true },
            { $0.base.snapshot.exerciseStartedAt = nil },
            { $0.base.snapshot.equipmentSnapshot = "另一机器" },
            { $0.base.logs[0].actualWeight = 2 },
            { $0.base.logs[0].rir = 2 },
            { $0.base.logs[0].actualWeightSideRaw = nil },
            { $0.base.logs[0].reductionOrder = 1 },
            { $0.base.logs[0].restEndedAt = Date(timeIntervalSinceReferenceDate: 900_000_000) },
            { $0.base.logs[0].sourceHistorySetID = UUID() }
        ]
        for mutate in mutations {
            let fixture = try blankCorrectionFixture()
            let context = fixture.base.container.mainContext
            mutate(fixture)
            try context.save()
            let beforeSession = HistoricalCorrectionSessionState(fixture.session)
            let beforeSnapshot = HistoricalBlankSnapshotState(fixture.base.snapshot)
            let beforeSets = fixture.base.logs.map(HistoricalBlankSetState.init)
            XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context) { _ in
                XCTFail("漂移记录不能保存")
            }) {
                XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .changedRecord)
            }
            XCTAssertEqual(HistoricalCorrectionSessionState(fixture.session), beforeSession)
            XCTAssertEqual(HistoricalBlankSnapshotState(fixture.base.snapshot), beforeSnapshot)
            XCTAssertEqual(fixture.base.logs.map(HistoricalBlankSetState.init), beforeSets)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testBlankActualCorrectionRequiresUnchangedUniqueExistingReviewedTarget() throws {
        let mutations: [(BlankCorrectionFixture, ModelContext) -> Void] = [
            { fixture, _ in fixture.target.volumeUnitRaw = ExerciseVolumeUnit.kilogram.rawValue },
            { fixture, _ in fixture.target.terminologyReviewNote = "新的审核" },
            { fixture, _ in fixture.target.terminologyDecisionRaw = nil },
            { fixture, _ in fixture.target.updatedAt = fixture.target.updatedAt.addingTimeInterval(1) },
            { fixture, _ in fixture.target.isArchived = true },
            { fixture, context in context.delete(fixture.target) },
            { fixture, context in context.insert(Exercise(name: " 器械下斜卧推 ", muscleGroup: "胸部", equipment: "另一器械")) },
            { fixture, context in context.insert(Exercise(id: fixture.target.id, name: "重复UUID", muscleGroup: "胸部", equipment: "器械")) }
        ]
        for mutate in mutations {
            let fixture = try blankCorrectionFixture()
            let context = fixture.base.container.mainContext
            mutate(fixture, context)
            try context.save()
            let catalogBefore = try context.fetch(FetchDescriptor<Exercise>()).map(HistoricalCorrectionCatalogState.init)
            XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context) { _ in
                XCTFail("冲突目录不能保存")
            }) {
                XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .conflictingTarget)
            }
            XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).map(HistoricalCorrectionCatalogState.init), catalogBefore)
            XCTAssertEqual(HistoricalBlankSnapshotState(fixture.base.snapshot), fixture.packet.expectedSnapshot)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testBlankActualCorrectionRejectsMissingExtraOrDuplicateOriginalRows() throws {
        for mode in 0..<3 {
            let fixture = try blankCorrectionFixture()
            let context = fixture.base.container.mainContext
            if mode == 0 { context.delete(fixture.base.logs[0]) }
            else {
                context.insert(SetLog(id: mode == 2 ? fixture.base.logs[0].id : UUID(),
                    sessionID: fixture.session.id,
                    sessionExerciseID: mode == 2 ? fixture.base.otherSnapshot.id : fixture.base.snapshot.id,
                    exerciseID: fixture.base.source.id, setNumber: 5, targetWeight: 0, targetReps: 0,
                    actualWeight: 0, actualReps: 0, actualEntrySource: .blank, actualWeightIsBlank: true))
            }
            try context.save()
            let count = try context.fetchCount(FetchDescriptor<SetLog>())
            XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context)) {
                XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .changedRecord)
            }
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), count)
            XCTAssertEqual(HistoricalBlankSnapshotState(fixture.base.snapshot), fixture.packet.expectedSnapshot)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testBlankActualCorrectionRejectsPartialOrChangedRetry() throws {
        for mode in 0..<4 {
            let fixture = try blankCorrectionFixture()
            let context = fixture.base.container.mainContext
            _ = try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context)
            var packet = fixture.packet
            if mode == 0 { fixture.base.logs[0].isCompleted = false }
            if mode == 1 { packet.confirmationReference = "另一份确认" }
            if mode == 2 { packet.confirmedActuals[0].kilogramsPerSide += 1 }
            if mode == 3 { fixture.base.logs[0].actualReps += 1 }
            try context.save()
            let snapshotBefore = HistoricalBlankSnapshotState(fixture.base.snapshot)
            let setsBefore = fixture.base.logs.map(HistoricalBlankSetState.init)
            XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(packet, in: context) { _ in
                XCTFail("部分或变化后的重试不能保存")
            }) {
                XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .changedRecord)
            }
            XCTAssertEqual(HistoricalBlankSnapshotState(fixture.base.snapshot), snapshotBefore)
            XCTAssertEqual(fixture.base.logs.map(HistoricalBlankSetState.init), setsBefore)
            XCTAssertFalse(context.hasChanges)
        }
    }

    @MainActor
    func testBlankActualCorrectionProtectsPendingEditsAndRollsBackFailedSave() throws {
        let pending = try blankCorrectionFixture()
        let pendingContext = pending.base.container.mainContext
        pending.base.otherSession.notes = "未保存编辑"
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(pending.packet, in: pendingContext)) {
            XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .pendingChanges)
        }
        XCTAssertEqual(pending.base.otherSession.notes, "未保存编辑")
        XCTAssertTrue(pendingContext.hasChanges)
        XCTAssertEqual(pending.base.logs.map(HistoricalBlankSetState.init), pending.packet.expectedSets)

        let fixture = try blankCorrectionFixture()
        let context = fixture.base.container.mainContext
        context.autosaveEnabled = true
        var saves = 0
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context) { context in
            XCTAssertFalse(context.autosaveEnabled)
            saves += 1
            throw InjectedSaveFailure.failed
        })
        XCTAssertEqual(saves, 1)
        XCTAssertTrue(context.autosaveEnabled)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(HistoricalBlankSnapshotState(fixture.base.snapshot), fixture.packet.expectedSnapshot)
        XCTAssertEqual(fixture.base.logs.map(HistoricalBlankSetState.init), fixture.packet.expectedSets)
        XCTAssertEqual(HistoricalCorrectionSessionState(fixture.session), fixture.packet.expectedSession)
        XCTAssertEqual(HistoricalCorrectionCatalogState(fixture.target), fixture.packet.existingTarget)
        let fresh = ModelContext(fixture.base.container)
        let persisted = try XCTUnwrap(fresh.fetch(FetchDescriptor<SessionExercise>()).first { $0.id == fixture.base.snapshot.id })
        let persistedSets = try fresh.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionExerciseID == persisted.id }
        XCTAssertEqual(HistoricalBlankSnapshotState(persisted), fixture.packet.expectedSnapshot)
        XCTAssertEqual(persistedSets.map(HistoricalBlankSetState.init).sorted { $0.setNumber < $1.setNumber }, fixture.packet.expectedSets)
        context.autosaveEnabled = false

        _ = try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context)
        fixture.base.otherSession.notes = "重试前尚未保存"
        XCTAssertThrowsError(try HistoricalExerciseCorrectionService.apply(fixture.packet, in: context)) {
            XCTAssertEqual($0 as? HistoricalExerciseCorrectionError, .pendingChanges)
        }
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(fixture.base.otherSession.notes, "重试前尚未保存")
    }

    @MainActor
    func testVersionOneWireStillUsesOriginalIdentityOnlyContract() throws {
        let fixture = try correctionFixture()
        let data = try JSONEncoder().encode(fixture.packet)
        XCTAssertTrue(try HistoricalExerciseCorrectionService.apply(data, in: fixture.container.mainContext).applied)
        XCTAssertEqual(fixture.logs.map(\.actualWeight), fixture.packet.expectedSets.map(\.actualWeight))
        XCTAssertFalse(try HistoricalExerciseCorrectionService.apply(data, in: fixture.container.mainContext).applied)
    }

}

private enum InjectedSaveFailure: Error { case failed }

@MainActor
private struct CorrectionFixture {
    let container: ModelContainer
    let source: Exercise
    let snapshot: SessionExercise
    let logs: [SetLog]
    let otherSession: WorkoutSession
    let otherSnapshot: SessionExercise
    let otherSet: SetLog
    let packet: HistoricalExerciseCorrectionPacket
}

@MainActor
private func correctionFixture() throws -> CorrectionFixture {
    let schema = Schema([Exercise.self, WorkoutSession.self, SessionExercise.self, SetLog.self])
    let container = try ModelContainer(for: schema, configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    ])
    let context = container.mainContext
    context.autosaveEnabled = false
    let source = Exercise(name: "坐姿腿弯举", muscleGroup: "腿部", equipment: "器械")
    let started = Date(timeIntervalSinceReferenceDate: 814_000_000)
    let session = WorkoutSession(templateName: "训练", plannedDate: started, startedAt: started,
        completedAt: started.addingTimeInterval(1_200), status: .completed, notes: "场次备注", importIdentifier: "")
    session.trainingLocalDay = nil
    let snapshot = SessionExercise(sessionID: session.id, exerciseID: source.id, exerciseName: source.name,
        order: 2, targetSets: 4, minReps: 8, maxReps: 14, targetWeight: 40, restSeconds: 90,
        muscleGroup: "腿部", exerciseNotes: "快照动作备注", referenceURL: "", performanceNotes: "原始备注",
        exerciseStartedAt: started, exerciseCompletedAt: started.addingTimeInterval(600),
        bodyWeightKgSnapshot: 70.5, bodyWeightSnapshotSourceDate: started, equipmentSnapshot: "旧器械描述")
    let loads = [40.0, 45.0, 50.0, 55.0]
    let reps = [14, 12, 10, 8]
    let logs = (0..<4).map { index in
        SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: source.id,
            setNumber: index + 1, targetWeight: loads[index], targetReps: reps[index],
            actualWeight: loads[index], actualReps: reps[index], rir: index,
            isWarmup: false, isCompleted: true, startedAt: started.addingTimeInterval(Double(index * 100)),
            completedAt: started.addingTimeInterval(Double(index * 100 + 50)),
            restStartedAt: started.addingTimeInterval(Double(index * 100 + 50)),
            restEndedAt: started.addingTimeInterval(Double(index * 100 + 80)), restDurationSeconds: 30,
            sourceHistorySetID: UUID(), actualWeightIsBlank: false)
    }
    let otherSession = WorkoutSession(templateName: "另一场", plannedDate: started, status: .completed,
        notes: "另一场记录")
    let otherSnapshot = SessionExercise(sessionID: otherSession.id, exerciseID: source.id, exerciseName: source.name,
        order: 1, targetSets: 1, minReps: 5, maxReps: 5, targetWeight: 30, restSeconds: 90,
        performanceNotes: "另一场动作备注")
    let otherSet = SetLog(sessionID: otherSession.id, sessionExerciseID: otherSnapshot.id, exerciseID: source.id,
        setNumber: 1, targetWeight: 30, targetReps: 5, actualWeight: 30, actualReps: 5, isCompleted: true)
    context.insert(source)
    context.insert(session)
    context.insert(snapshot)
    for log in logs { context.insert(log) }
    context.insert(otherSession)
    context.insert(otherSnapshot)
    context.insert(otherSet)
    try context.save()
    let target = HistoricalCorrectionTarget(id: UUID(), name: "坐姿腿屈伸（器械未确认）", muscleGroup: "腿部",
        equipment: "未记录", volumeUnit: .kilogram, notes: "具体机器未知")
    let packet = HistoricalExerciseCorrectionPacket(version: 1, sessionID: session.id,
        expectedLocalDay: session.trainingLocalDay, expectedImportIdentifier: session.importIdentifier,
        expectedSnapshot: HistoricalCorrectionSnapshotState(snapshot),
        expectedSets: logs.map(HistoricalCorrectionSetState.init), target: target,
        confirmationReference: "本人确认", correctionNote: "具体机器未知。")
    return CorrectionFixture(container: container, source: source, snapshot: snapshot, logs: logs,
        otherSession: otherSession, otherSnapshot: otherSnapshot, otherSet: otherSet, packet: packet)
}


@MainActor
private struct BlankCorrectionFixture {
    let base: CorrectionFixture
    let session: WorkoutSession
    let target: Exercise
    let packet: HistoricalBlankActualCorrectionPacket
}

@MainActor
private func blankCorrectionFixture() throws -> BlankCorrectionFixture {
    let base = try correctionFixture()
    let context = base.container.mainContext
    let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == base.packet.sessionID })
    base.source.name = "坐姿飞鸟"
    base.source.muscleGroup = "胸部"
    base.snapshot.exerciseName = base.source.name
    base.snapshot.muscleGroup = "胸部"
    base.snapshot.volumeUnitRaw = ExerciseVolumeUnit.kilogram.rawValue
    base.snapshot.targetWeight = 0
    base.snapshot.exerciseCompletedAt = nil
    base.snapshot.plannedSetsJSON = " [{\"weight\":0,\"reps\":14},{\"weight\":0,\"reps\":12}] "
    session.trainingLocalDay = "2026-11-02"
    session.trainingTimeZoneIdentifier = "Asia/Shanghai"
    for log in base.logs {
        log.targetWeight = 0
        log.actualWeight = 0
        log.actualReps = 0
        log.rir = nil
        log.isCompleted = false
        log.startedAt = nil
        log.completedAt = nil
        log.restStartedAt = nil
        log.restEndedAt = nil
        log.restDurationSeconds = nil
        log.sourceHistorySetID = nil
        log.actualEntrySource = .blank
        log.actualWeightIsBlank = true
        log.actualWeightSide = .unknown
        log.actualRepsSide = .unknown
    }
    let target = Exercise(name: "器械下斜卧推", muscleGroup: "胸部", equipment: "器械", isBuiltIn: false,
        notes: "原目录备注", terminologyCanonicalID: "machine_decline_chest_press",
        terminologyStandardNameZH: "坐姿下斜推胸机", terminologyStandardNameEN: "Decline Chest Press Machine",
        terminologyDecision: .accepted, terminologyMergeGroup: "merge_machine_decline_chest_press",
        terminologyReviewNote: "需确认是同一器械与负重口径", terminologyCatalogVersion: "原术语版本")
    target.volumeUnitRaw = nil
    target.terminologyReviewStatusRaw = "mergeReview"
    context.insert(target)
    try context.save()
    let actuals = zip(base.logs, zip([25.0, 27.5, 30.0, 32.5], [12, 12, 10, 10])).map {
        HistoricalConfirmedPlateActual(setID: $0.0.id, kilogramsPerSide: $0.1.0, reps: $0.1.1)
    }
    let packet = HistoricalBlankActualCorrectionPacket(version: 2, weightConvention: .platesPerSideExcludingMachine,
        expectedSession: HistoricalCorrectionSessionState(session), expectedSnapshot: HistoricalBlankSnapshotState(base.snapshot),
        expectedSets: base.logs.map(HistoricalBlankSetState.init), existingTarget: HistoricalCorrectionCatalogState(target),
        confirmedActuals: actuals, confirmationReference: "本人确认四组实际与每侧片重", correctionNote: "只改这次原位置。")
    return BlankCorrectionFixture(base: base, session: session, target: target, packet: packet)
}
