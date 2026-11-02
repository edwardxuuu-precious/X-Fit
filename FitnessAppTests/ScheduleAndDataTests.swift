import SwiftData
import SwiftUI
import UIKit
import UserNotifications
import XCTest
@testable import FitnessApp

private actor RecordingRestNotificationCenter: RestNotificationCenter {
    private var pending: [String: UNNotificationRequest] = [:]
    private var delivered: Set<String> = []

    func add(_ request: UNNotificationRequest) async throws {
        pending[request.identifier] = request
    }

    func removePending(withIdentifiers identifiers: [String]) async {
        identifiers.forEach { pending[$0] = nil }
    }

    func removeDelivered(withIdentifiers identifiers: [String]) async {
        delivered.subtract(identifiers)
    }

    func summary(for identifier: String) -> (count: Int, title: String?, repeats: Bool?) {
        let request = pending[identifier]
        return (request == nil ? 0 : 1, request?.content.title, request?.trigger?.repeats)
    }
}

@MainActor
final class ScheduleAndDataTests: XCTestCase {
    func testCardioLevelBackupRoundTripAndLegacyMissingField() throws {
        let source = try makeContainer(), context = source.mainContext
        let session = WorkoutSession(templateName: "本人单车", plannedDate: .now, isStartTimeKnown: false, status: .completed)
        session.cardioResistanceLevel = 10
        context.insert(session); try context.save()
        let data = try Data(contentsOf: DataExportService.createBackup(in: context))
        let restored = try makeContainer()
        _ = try DataExportService.importBackup(data, into: restored.mainContext)
        let actual = try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first)
        XCTAssertEqual(actual.id, session.id); XCTAssertEqual(actual.cardioResistanceLevel, 10)
        XCTAssertFalse(actual.isStartTimeKnown); XCTAssertNil(actual.completedAt)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rows = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        rows[0].removeValue(forKey: "cardioResistanceLevel"); json["sessions"] = rows
        let legacy = try makeContainer()
        _ = try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: legacy.mainContext)
        XCTAssertNil(try legacy.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first?.cardioResistanceLevel)
    }
    func testMenuRemovalPreflightsManualAndStartedRowsBeforeChangingAnyData() throws {
        for manual in [true, false] {
            let container = try makeContainer(), context = container.mainContext
            let kept = Exercise(name: "保留动作", muscleGroup: "背部", equipment: "哑铃")
            let removable = Exercise(name: "未编辑可移除动作", muscleGroup: "背部", equipment: "哑铃")
            let protected = Exercise(name: "保护实际动作", muscleGroup: "背部", equipment: "哑铃")
            let session = WorkoutSession(templateName: "原名称", plannedDate: .now, defaultPlanPattern: .fixed)
            context.insert(session)
            var snapshots: [SessionExercise] = []
            var rows: [SetLog] = []
            for (index, exercise) in [kept, removable, protected].enumerated() {
                context.insert(exercise)
                let snapshot = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
                    order: index, targetSets: 1, minReps: 8, maxReps: 8, targetWeight: 24, restSeconds: 90,
                    plannedSets: [WorkoutSetPlan(weight: 24, reps: 8)])
                let row = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
                    setNumber: 1, targetWeight: 24, targetReps: 8, actualWeight: index == 2 ? 25.125 : 24,
                    actualReps: 8, startedAt: index == 2 && !manual ? .now : nil,
                    actualEntrySource: index == 2 && manual ? .manual : .plan)
                context.insert(snapshot); context.insert(row)
                snapshots.append(snapshot); rows.append(row)
            }
            try context.save()
            var rejected = false
            do {
                try WorkoutService.syncMenu([DailyPlanExerciseInput(exerciseID: kept.id,
                    plannedSets: [WorkoutSetPlan(weight: 50, reps: 12)], planPattern: .pyramidUp, restSeconds: 180)],
                    to: session, muscleGroups: ["胸部"], defaultPlanPattern: .pyramidUp, in: context)
            } catch WorkoutServiceError.cannotRemoveStartedExercise {
                rejected = true
            }
            XCTAssertTrue(rejected, "Menu synchronization must reject removal of manual or started actual data")
            XCTAssertEqual(session.defaultPlanPattern, .fixed)
            XCTAssertEqual(session.templateName, "原名称")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 3)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 3)
            XCTAssertEqual(snapshots[0].targetWeight, 24)
            XCTAssertEqual(snapshots[0].restSeconds, 90)
            XCTAssertEqual(rows[0].actualWeight, 24)
            XCTAssertEqual(rows[2].actualWeight, 25.125)
            XCTAssertTrue(!context.hasChanges, "Preflight rejection must not leave partial mutations to autosave")
        }
    }

    func testMenuShrinkKeepsManuallyEditedActualRowsSeparateFromThreeSetPlanButRemovesUntouchedExtraRows() throws {
        for source in [WorkoutActualEntrySource.manual, .plan] {
            let container = try makeContainer(), context = container.mainContext
            let exercise = Exercise(name: "缩组保护", muscleGroup: "胸部", equipment: "哑铃")
            let session = WorkoutSession(templateName: "四组变三组", plannedDate: .now)
            let originalPlan = Array(repeating: WorkoutSetPlan(weight: 24, reps: 8), count: 4)
            let snapshot = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
                order: 0, targetSets: 4, minReps: 8, maxReps: 8, targetWeight: 24, restSeconds: 90, plannedSets: originalPlan)
            context.insert(exercise); context.insert(session); context.insert(snapshot)
            var rows: [SetLog] = []
            for index in 1...4 {
                let row = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
                    setNumber: index, targetWeight: 24, targetReps: 8,
                    actualWeight: index == 4 && source == .manual ? 25.125 : 24,
                    actualReps: index == 4 && source == .manual ? 12 : 8,
                    actualEntrySource: index == 4 ? source : .plan)
                rows.append(row); context.insert(row)
            }
            try context.save()
            try WorkoutService.syncMenu([DailyPlanExerciseInput(exerciseID: exercise.id,
                plannedSets: Array(repeating: WorkoutSetPlan(weight: 30, reps: 10), count: 3),
                planPattern: .fixed, restSeconds: 90)], to: session, in: context)
            let actual = try context.fetch(FetchDescriptor<SetLog>()).sorted { $0.setNumber < $1.setNumber }
            XCTAssertEqual(snapshot.plannedSets.count, 3, "Preserving actual input must not silently add a planned set")
            XCTAssertEqual(snapshot.targetSets, 3)
            XCTAssertEqual(actual.count, source == .manual ? 4 : 3)
            if source == .manual {
                XCTAssertEqual(actual.last?.id, rows[3].id)
                XCTAssertEqual(actual.last?.actualWeight, 25.125)
                XCTAssertEqual(actual.last?.actualReps, 12)
                XCTAssertEqual(actual.last?.actualEntrySource, .manual)
                XCTAssertEqual(actual.last?.targetWeight, 24)
                XCTAssertNil(actual.last?.startedAt)
                XCTAssertEqual(actual.last?.isCompleted, false)
            }
        }
    }

    func testFailedWorkoutSaveSurvivesLeavingConsumerAndOnlySameContextSuccessfulRetryClearsIt() throws {
        let container = try makeContainer(), context = container.mainContext
        context.autosaveEnabled = false
        let session = WorkoutSession(templateName: "保存错误回归", plannedDate: .now)
        context.insert(session); try context.save()
        session.notes = "仅保留在模型，不复制到提示状态"
        var shouldFail = true
        let state = WorkoutSaveIssueState { context in
            if shouldFail { throw NSError(domain: "TestSaveFailure", code: 1) }
            try context.save()
        }
        XCTAssertTrue(!state.save(sessionID: session.id, in: context))
        XCTAssertEqual(state.issue?.sessionID, session.id)
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(session.notes, "仅保留在模型，不复制到提示状态")
        let originalEvent = state.issue?.id ?? UUID()
        let otherConsumer = state
        XCTAssertTrue(!otherConsumer.retry(in: context))
        XCTAssertTrue(state.issue != nil, "Leaving the input view must not clear a failed save")
        XCTAssertTrue(state.issue?.id != originalEvent)
        state.resolveSavedEvent(originalEvent, in: context)
        XCTAssertTrue(state.issue != nil, "An older success must not clear a newer error")
        let unrelatedContainer = try makeContainer()
        let unrelated = unrelatedContainer.mainContext
        shouldFail = false
        XCTAssertTrue(!otherConsumer.retry(in: unrelated), "Do not acknowledge a different model context")
        XCTAssertTrue(state.issue != nil)
        XCTAssertTrue(otherConsumer.retry(in: context))
        XCTAssertNil(state.issue)
        XCTAssertTrue(!context.hasChanges)
        XCTAssertEqual(session.status, .inProgress)
        XCTAssertNil(session.completedAt)
        XCTAssertEqual(session.notes, "仅保留在模型，不复制到提示状态")
    }

    func testActiveWorkoutDataLoadsOnlyItsSessionAndRefreshesMembershipWithoutReseeding() throws {
        let container = try makeContainer(), context = container.mainContext
        let currentSchedule = ScheduledWorkout(templateID: UUID(), templateName: "当前", plannedDate: .now)
        let otherSchedule = ScheduledWorkout(templateID: UUID(), templateName: "其他", plannedDate: .now)
        let current = WorkoutSession(scheduledWorkoutID: currentSchedule.id, templateName: "当前", plannedDate: .now)
        let other = WorkoutSession(scheduledWorkoutID: otherSchedule.id, templateName: "其他", plannedDate: .now)
        let currentExercise = SessionExercise(sessionID: current.id, exerciseID: UUID(), exerciseName: "当前动作",
            order: 0, targetSets: 1, minReps: 8, maxReps: 8, targetWeight: 24, restSeconds: 90)
        let otherExercise = SessionExercise(sessionID: other.id, exerciseID: UUID(), exerciseName: "其他动作",
            order: 0, targetSets: 1, minReps: 8, maxReps: 8, targetWeight: 99, restSeconds: 90)
        let currentRow = SetLog(sessionID: current.id, sessionExerciseID: currentExercise.id, exerciseID: currentExercise.exerciseID,
            setNumber: 1, targetWeight: 24, targetReps: 8, actualWeight: 25.125, actualReps: 12, actualEntrySource: .manual)
        let otherRow = SetLog(sessionID: other.id, sessionExerciseID: otherExercise.id, exerciseID: otherExercise.exerciseID,
            setNumber: 1, targetWeight: 99, targetReps: 8, actualWeight: 99, actualReps: 8)
        context.insert(currentSchedule); context.insert(otherSchedule)
        context.insert(current); context.insert(other); context.insert(currentExercise); context.insert(otherExercise)
        context.insert(currentRow); context.insert(otherRow); try context.save()
        let data = ActiveWorkoutData(sessionID: current.id)
        try data.reload(in: context)
        XCTAssertEqual(data.session?.id, current.id)
        XCTAssertEqual(data.exercises.map(\.id), [currentExercise.id])
        XCTAssertEqual(data.logs.map(\.id), [currentRow.id])
        XCTAssertEqual(data.schedules.map(\.id), [currentSchedule.id])
        XCTAssertTrue(data.hasLoaded)
        XCTAssertTrue(data.logs.first === currentRow, "Retain observed model objects, not detached copies")
        currentRow.actualWeight = 27.375
        XCTAssertEqual(data.logs.first?.actualWeight, 27.375, "Editing the model needs no query refresh")
        current.status = .completed
        XCTAssertEqual(data.session?.status, .completed, "Finish/discard status uses the same observed session")
        current.status = .inProgress
        let addedExercise = SessionExercise(sessionID: current.id, exerciseID: UUID(), exerciseName: "新增动作",
            order: 1, targetSets: 1, minReps: 8, maxReps: 8, targetWeight: 20, restSeconds: 90)
        context.insert(addedExercise)
        let added = SetLog(sessionID: current.id, sessionExerciseID: currentExercise.id, exerciseID: currentExercise.exerciseID,
            setNumber: 2, targetWeight: 24, targetReps: 8, actualWeight: 24, actualReps: 8)
        context.insert(added); try context.save()
        try data.reload(in: context)
        XCTAssertEqual(data.logs.map(\.id), [currentRow.id, added.id])
        XCTAssertEqual(data.exercises.map(\.id), [currentExercise.id, addedExercise.id])
        XCTAssertEqual(data.logs.first?.actualEntrySource, .manual)
        context.delete(added); context.delete(currentExercise); context.delete(addedExercise); try context.save()
        try data.reload(in: context)
        XCTAssertTrue(data.exercises.isEmpty)
        XCTAssertEqual(data.logs.map(\.id), [currentRow.id])
        XCTAssertEqual(currentRow.actualWeight, 27.375)
        context.delete(current); try context.save()
        try data.reload(in: context)
        XCTAssertNil(data.session)
        XCTAssertTrue(data.exercises.isEmpty && data.logs.isEmpty && data.schedules.isEmpty)
    }
    func testInputDraftProvenanceAndEquipmentPersistAfterStoreReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xfit-input-reopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("input.store")
        let sessionID = UUID(), snapshotID = UUID(), rowID = UUID(), historyID = UUID()
        do {
            let store = try makePersistentContainer(at: url)
            let session = WorkoutSession(id: sessionID, templateName: "持久草稿", plannedDate: .now, notes: "中文备注末字")
            let snapshot = SessionExercise(id: snapshotID, sessionID: sessionID, exerciseID: UUID(), exerciseName: "草稿",
                order: 0, targetSets: 1, minReps: 8, maxReps: 8, targetWeight: 24, restSeconds: 90, equipmentSnapshot: "哑铃")
            let row = SetLog(id: rowID, sessionID: sessionID, sessionExerciseID: snapshotID, exerciseID: snapshot.exerciseID,
                setNumber: 1, targetWeight: 24, targetReps: 8, actualWeight: 25.125, actualReps: 12,
                actualWeightSide: .single, actualRepsSide: .bilateral, actualEntrySource: .manual, sourceHistorySetID: historyID)
            store.mainContext.insert(session); store.mainContext.insert(snapshot); store.mainContext.insert(row)
            try store.mainContext.save()
        }
        let reopened = try makePersistentContainer(at: url)
        let row = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<SetLog>()).first { $0.id == rowID })
        XCTAssertEqual(row.actualWeight, 25.125)
        XCTAssertEqual(row.actualEntrySource, .manual)
        XCTAssertEqual(row.sourceHistorySetID, historyID)
        XCTAssertEqual(row.actualWeightSide, .single)
        XCTAssertEqual(row.actualRepsSide, .bilateral)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<SessionExercise>()).first?.equipmentSnapshot, "哑铃")
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first?.notes, "中文备注末字")
    }
    func testHistoryResolverRejectsWrongIdentityUnitEquipmentAndUnfinishedOrWarmupRows() throws {
        let exerciseID = UUID(), date = Date.now.addingTimeInterval(-1000)
        let session = WorkoutSession(templateName: "历史", plannedDate: date, startedAt: date, completedAt: date, status: .completed)
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: exerciseID, exerciseName: "同名不同ID不能用",
            order: 0, targetSets: 2, minReps: 8, maxReps: 12, targetWeight: 25, restSeconds: 90, equipmentSnapshot: "哑铃")
        let first = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exerciseID,
            setNumber: 1, targetWeight: 24, targetReps: 8, actualWeight: 25, actualReps: 12, isCompleted: true,
            actualWeightSide: .single, actualRepsSide: .bilateral)
        let warmup = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exerciseID,
            setNumber: 0, targetWeight: 10, targetReps: 10, actualWeight: 10, actualReps: 10, isWarmup: true, isCompleted: true)
        let draft = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exerciseID,
            setNumber: 2, targetWeight: 25, targetReps: 8, actualWeight: 27, actualReps: 15)
        func resolve(_ id: UUID? = nil, unit: ExerciseVolumeUnit = .kilogram, equipment: String = "哑铃") -> WorkoutHistoryReference? {
            WorkoutHistoryResolver.latest(exerciseID: id ?? exerciseID, unit: unit, equipment: equipment, before: .now,
                sessions: [session], snapshots: [snapshot], logs: [warmup, draft, first])
        }
        let result = try XCTUnwrap(resolve())
        XCTAssertEqual(result.sets.map(\.id), [first.id])
        XCTAssertEqual(result.sets.first?.weightSide, .single)
        XCTAssertEqual(result.sets.first?.repsSide, .bilateral)
        XCTAssertNil(resolve(UUID()))
        XCTAssertNil(resolve(unit: .second))
        XCTAssertNil(resolve(equipment: "杠铃"))
        session.status = .inProgress
        XCTAssertNil(resolve())
        session.status = .completed
        snapshot.equipmentSnapshot = nil
        XCTAssertEqual(resolve()?.equipmentVerified, false)
        snapshot.equipmentSnapshot = "哑铃"
        first.actualRepsSideRaw = nil
        XCTAssertEqual(resolve()?.sets.first?.repsSide, .unknown)
        XCTAssertEqual(resolve()?.sets.first?.canPrefill(unit: .kilogram), false)
        XCTAssertEqual(first.actualWeight, 25)
    }

    func testStartUsesCompatibleHistoryBeforeBlankAndPlanAndDoesNotExtendShortHistory() throws {
        let container = try makeContainer(), date = Date.now.addingTimeInterval(-1000)
        let context = container.mainContext
        let exercise = Exercise(name: "多组默认", muscleGroup: "胸部", equipment: "哑铃")
        let template = WorkoutTemplate(name: "默认边界", weekday: 1)
        let plans = [WorkoutSetPlan(weight: 24, reps: 8), WorkoutSetPlan(weight: 24, reps: 8, actualDefaultPolicy: .blank),
            WorkoutSetPlan(weight: 26, reps: 9), WorkoutSetPlan(weight: 27, reps: 10, actualDefaultPolicy: .plan)]
        let plan = TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: 0,
            targetSets: 4, minReps: 8, maxReps: 10, targetWeight: 24, restSeconds: 90, plannedSets: plans)
        let old = WorkoutSession(templateName: "历史", plannedDate: date, startedAt: date, completedAt: date, status: .completed)
        let snapshot = SessionExercise(sessionID: old.id, exerciseID: exercise.id, exerciseName: exercise.name,
            order: 0, targetSets: 2, minReps: 10, maxReps: 12, targetWeight: 21, restSeconds: 90, equipmentSnapshot: "哑铃")
        let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name, plannedDate: .now)
        context.insert(exercise); context.insert(template); context.insert(plan); context.insert(old); context.insert(snapshot); context.insert(schedule)
        for index in 1...2 {
            context.insert(SetLog(sessionID: old.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
                setNumber: index, targetWeight: 20, targetReps: 8, actualWeight: Double(20 + index), actualReps: 12,
                isCompleted: true, actualWeightSide: .single, actualRepsSide: .bilateral))
        }
        try context.save()
        let id = try WorkoutService.start(schedule: schedule, in: context)
        let rows = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionID == id }.sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(rows.map(\.actualWeight), [21, 22, 26, 27])
        XCTAssertEqual(rows.map(\.actualReps), [12, 12, 9, 10])
        XCTAssertEqual(rows.map(\.actualEntrySource), [.history, .history, .plan, .plan])
        XCTAssertEqual(rows.first?.actualWeightSide, .single)
        XCTAssertEqual(rows.first?.actualRepsSide, .bilateral)
        XCTAssertEqual(plan.plannedSets, plans)
        rows[1].actualReps = 10; rows[1].markActualEntryEdited()
        XCTAssertFalse(rows[1].isActualWeightBlank, "Editing reps preserves the compatible historical load")
        XCTAssertEqual(rows[1].actualWeight, 22)
    }

    func testInputProvenanceEquipmentAndCivilDateSurviveBackupAndLegacyDecode() throws {
        let source = try makeContainer(), context = source.mainContext
        let template = WorkoutTemplate(name: "备份", weekday: 1, isOneOff: true)
        let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name, plannedDate: .now,
            isManuallyScheduled: true)
        schedule.plannedLocalDay = "2026-09-27"; schedule.plannedTimeZoneIdentifier = "Australia/Sydney"
        let session = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: "备份", plannedDate: .now)
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: UUID(), exerciseName: "备份",
            order: 0, targetSets: 1, minReps: 8, maxReps: 8, targetWeight: 24, restSeconds: 90,
            plannedSets: [WorkoutSetPlan(weight: 24, reps: 8, actualDefaultPolicy: .blank)], equipmentSnapshot: "哑铃")
        let row = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: snapshot.exerciseID,
            setNumber: 1, targetWeight: 24, targetReps: 8, actualWeight: 25, actualReps: 12,
            actualWeightSide: .single, actualRepsSide: .bilateral, actualEntrySource: .manual, sourceHistorySetID: UUID(), actualWeightIsBlank: false)
        context.insert(template); context.insert(schedule); context.insert(session); context.insert(snapshot); context.insert(row); try context.save()
        let data = try Data(contentsOf: DataExportService.createBackup(in: context))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedSchedules = try XCTUnwrap(json["schedules"] as? [[String: Any]])
        let exportedSchedule = try XCTUnwrap(exportedSchedules.first { ($0["id"] as? String) == schedule.id.uuidString })
        XCTAssertEqual(exportedSchedule["plannedLocalDay"] as? String, "2026-09-27")
        XCTAssertEqual(exportedSchedule["plannedTimeZoneIdentifier"] as? String, "Australia/Sydney")
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SetLog>()).first)
        XCTAssertEqual(restored.actualEntrySource, .manual)
        XCTAssertEqual(restored.sourceHistorySetID, row.sourceHistorySetID)
        XCTAssertEqual(restored.actualWeightIsBlank, false)
        XCTAssertEqual(restored.actualWeightSide, .single)
        XCTAssertEqual(restored.actualRepsSide, .bilateral)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first?.equipmentSnapshot, "哑铃")
        let restoredSchedule = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == schedule.id })
        XCTAssertEqual(restoredSchedule.plannedLocalDay, "2026-09-27")
        XCTAssertEqual(restoredSchedule.plannedTimeZoneIdentifier, "Australia/Sydney")
        for name in ["setLogs", "sessionExercises", "schedules"] {
            if var records = json[name] as? [[String: Any]] {
                for i in records.indices {
                    for key in ["actualEntrySourceRaw", "sourceHistorySetID", "actualWeightIsBlank", "actualWeightSideRaw", "actualRepsSideRaw", "equipmentSnapshot", "plannedLocalDay", "plannedTimeZoneIdentifier"] { records[i].removeValue(forKey: key) }
                }
                json[name] = records
            }
        }
        let legacy = try makeContainer()
        _ = try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: legacy.mainContext)
        XCTAssertEqual(try legacy.mainContext.fetch(FetchDescriptor<SetLog>()).first?.actualEntrySource, .legacy)
        XCTAssertNil(try legacy.mainContext.fetch(FetchDescriptor<SessionExercise>()).first?.equipmentSnapshot)
        XCTAssertNil(try legacy.mainContext.fetch(FetchDescriptor<SetLog>()).first?.actualRepsSideRaw)
        let legacySchedule = try XCTUnwrap(legacy.mainContext.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == schedule.id })
        XCTAssertNil(legacySchedule.plannedLocalDay)
        XCTAssertNil(legacySchedule.plannedTimeZoneIdentifier)
    }
    func testRestorePlanDefaultsChangesOnlyUnstartedRowsAndKeepsBlankPolicy() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = WorkoutSession(templateName: "恢复默认", plannedDate: .now)
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: UUID(), exerciseName: "恢复",
            order: 0, targetSets: 3, minReps: 8, maxReps: 8, targetWeight: 24, restSeconds: 90,
            plannedSets: [WorkoutSetPlan(weight: 24, reps: 8), WorkoutSetPlan(weight: 24, reps: 8),
                WorkoutSetPlan(weight: 0, reps: 8, actualDefaultPolicy: .blank)])
        context.insert(session); context.insert(snapshot)
        let done = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: snapshot.exerciseID,
            setNumber: 1, targetWeight: 24, targetReps: 8, actualWeight: 25, actualReps: 12, isCompleted: true,
            actualEntrySource: .manual)
        let started = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: snapshot.exerciseID,
            setNumber: 2, targetWeight: 24, targetReps: 8, actualWeight: 25, actualReps: 12, startedAt: .now,
            actualEntrySource: .manual)
        let draft = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: snapshot.exerciseID,
            setNumber: 3, targetWeight: 0, targetReps: 8, actualWeight: 25, actualReps: 12,
            actualWeightSide: .single, actualEntrySource: .manual, sourceHistorySetID: UUID())
        context.insert(done); context.insert(started); context.insert(draft); try context.save()
        try WorkoutService.restorePlanDefaults(for: snapshot, in: context)
        XCTAssertEqual(done.actualWeight, 25)
        XCTAssertEqual(started.actualWeight, 25)
        XCTAssertEqual(draft.actualWeight, 0)
        XCTAssertEqual(draft.actualReps, 8)
        XCTAssertEqual(draft.actualWeightSide, .bilateral)
        XCTAssertEqual(draft.actualEntrySource, .blank)
        XCTAssertEqual(draft.sourceHistorySetID, nil)
        XCTAssertEqual(snapshot.plannedSets.last?.actualDefaultPolicy, .blank)
    }

    func testTextDraftKeepsCompositionLocalAndFlushesCommittedFinalCharacter() async throws {
        var values: [String] = []
        let draft = WorkoutInputDraft { values.append($0) }
        draft.edit("zhong", isComposing: true)
        try await Task.sleep(for: .milliseconds(400))
        draft.flush()
        XCTAssertTrue(values.isEmpty, "Unconfirmed IME candidates must not enter the model")
        draft.edit("中文", isComposing: false)
        draft.edit("中文备注", isComposing: false)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(values, ["中文备注"])
        draft.edit("中文备注末字", isComposing: false)
        draft.flush()
        XCTAssertEqual(values, ["中文备注", "中文备注末字"])
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(values.count, 2)
    }
    func testActualSideChoicePreservesPlannedBlankPolicyAndMarksManualEntry() {
        let planned = WorkoutSetPlan(weight: 0, reps: 8, weightSide: .bilateral,
            repsSide: .bilateral, actualDefaultPolicy: .blank)
        let snapshot = SessionExercise(sessionID: UUID(), exerciseID: UUID(), exerciseName: "侧别保护",
            order: 0, targetSets: 1, minReps: 8, maxReps: 8, targetWeight: 0, restSeconds: 90,
            plannedSets: [planned])
        let log = SetLog(sessionID: snapshot.sessionID, sessionExerciseID: snapshot.id,
            exerciseID: snapshot.exerciseID, setNumber: 1, targetWeight: 0, targetReps: 8,
            actualWeight: 0, actualReps: 8, actualEntrySource: .blank)
        WorkoutMeasurementSideEditing.apply(.single, to: snapshot, logs: [log])
        XCTAssertEqual(snapshot.plannedSets, [planned], "Changing actual units must not change the frozen plan or its blank policy")
        XCTAssertEqual(log.targetWeightSide, .bilateral)
        XCTAssertEqual(log.targetRepsSide, .bilateral)
        XCTAssertEqual(log.actualWeightSide, .single)
        XCTAssertEqual(log.actualRepsSide, .single)
        XCTAssertEqual(log.actualEntrySource, .manual)
    }

    func testNumericDraftCoalescesPersistenceAndFlushesLastDecimalOnBlur() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let log = SetLog(sessionID: UUID(), sessionExerciseID: UUID(), exerciseID: UUID(),
            setNumber: 1, targetWeight: 24, targetReps: 8, actualWeight: 24, actualReps: 8)
        context.insert(log)
        try context.save()
        var saves = 0
        let input = StableNumericTextField("重量", value: Binding(
            get: { log.actualWeight },
            set: { value in
                guard log.actualWeight != value else { return }
                log.actualWeight = value
                try! context.save()
                saves += 1
            }), accessibilityIdentifier: "coalescing-weight", commitDelay: 0.3)
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        for text in ["2", "25", "25.", "25.1", "25.125"] {
            field.text = text
            coordinator.editingChanged(field)
        }
        XCTAssertEqual(saves, 0, "During a rapid edit the model must not save each intermediate number")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(log.actualWeight, 25.125)
        field.text = "26.375"
        coordinator.editingChanged(field)
        coordinator.textFieldDidEndEditing(field)
        XCTAssertEqual(log.actualWeight, 26.375, "Blur must flush the last digit without waiting for debounce")
        XCTAssertEqual(saves, 2)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(saves, 2, "Cancelled debounce must not publish a second stale save")
    }

    func testScheduledStartPrefillsEveryCompatibleHistoricalWorkingSetWithoutChangingPlan() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "历史整组预填", muscleGroup: "胸部", equipment: "哑铃")
        let template = WorkoutTemplate(name: "默认值回归", weekday: 2)
        let plan = TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: 0,
            targetSets: 4, minReps: 8, maxReps: 8, targetWeight: 24, restSeconds: 90,
            plannedSets: (0..<4).map { _ in WorkoutSetPlan(weight: 24, reps: 8, weightSide: .single, repsSide: .single) })
        let oldDate = Date.now.addingTimeInterval(-60 * 86_400)
        let oldSchedule = ScheduledWorkout(templateID: template.id, templateName: "上次", plannedDate: oldDate,
            status: .completed, planSnapshot: [ScheduledWorkoutExerciseSnapshot(exerciseID: exercise.id,
                exerciseName: exercise.name, muscleGroup: "胸部", equipment: "哑铃", exerciseNotes: "",
                referenceURL: "", volumeUnit: .kilogram, order: 0, targetSets: 4, minReps: 8, maxReps: 12,
                targetWeight: 25, restSeconds: 90, plannedSets: [], planPattern: .fixed, patternSource: .dayDefault)])
        let old = WorkoutSession(scheduledWorkoutID: oldSchedule.id, templateName: "上次", plannedDate: oldDate, startedAt: oldDate,
            completedAt: oldDate.addingTimeInterval(600), status: .completed)
        let previous = SessionExercise(sessionID: old.id, exerciseID: exercise.id, exerciseName: exercise.name,
            order: 0, targetSets: 4, minReps: 8, maxReps: 12, targetWeight: 25, restSeconds: 90)
        let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name, plannedDate: .now)
        context.insert(exercise); context.insert(template); context.insert(plan)
        context.insert(oldSchedule); context.insert(old); context.insert(previous); context.insert(schedule)
        for index in 1...4 {
            context.insert(SetLog(sessionID: old.id, sessionExerciseID: previous.id, exerciseID: exercise.id,
                setNumber: index, targetWeight: 24, targetReps: 8, actualWeight: 25, actualReps: 12,
                rir: 0, isCompleted: true, completedAt: old.completedAt))
        }
        try context.save()
        let id = try WorkoutService.start(schedule: schedule, in: context)
        let rows = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionID == id }
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.actualWeight), [25, 25, 25, 25])
        XCTAssertEqual(rows.map(\.actualReps), [12, 12, 12, 12])
        XCTAssertTrue(rows.allSatisfy { $0.actualWeightSide == .bilateral && $0.actualRepsSide == .bilateral })
        XCTAssertTrue(rows.allSatisfy { $0.targetWeight == 24 && $0.targetReps == 8 && $0.targetWeightSide == .single })
        XCTAssertTrue(rows.allSatisfy { $0.rir == nil && !$0.isCompleted && $0.completedAt == nil })
        rows[0].actualWeight = 22
        XCTAssertEqual(try WorkoutService.start(schedule: schedule, in: context), id)
        XCTAssertEqual(rows[0].actualWeight, 22)
    }

    private var savedWorkoutReminderSetting: Any?

    override func setUp() {
        super.setUp()
        savedWorkoutReminderSetting = UserDefaults.standard.object(forKey: NotificationService.workoutEnabledKey)
        UserDefaults.standard.set(false, forKey: NotificationService.workoutEnabledKey)
    }

    override func tearDown() {
        if let savedWorkoutReminderSetting {
            UserDefaults.standard.set(savedWorkoutReminderSetting, forKey: NotificationService.workoutEnabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: NotificationService.workoutEnabledKey)
        }
        savedWorkoutReminderSetting = nil
        super.tearDown()
    }

    func testUITestingDisablesExternalSideEffectsByDefault() {
        let arguments = ["FitnessApp", "--ui-testing", "--ui-testing-persistent"]

        XCTAssertFalse(CloudSyncRuntime.shouldSyncWorkoutReminders(arguments: arguments))
        XCTAssertFalse(CloudSyncRuntime.shouldReadShareDraft(arguments: arguments))
    }

    func testBodyweightVolumeUsesSnapshotAndNeverFallsBackToZeroKilograms() {
        XCTAssertEqual(ExerciseVolumeUnit.bodyweight.volume(weight: 72.5, reps: 10), 725)
        XCTAssertNil(ExerciseVolumeUnit.bodyweight.volume(weight: nil, reps: 10))
        XCTAssertEqual(ExerciseVolumeUnit.count.volume(weight: nil, reps: 10), 10)
    }

    func testExerciseTimingStartsFirstExerciseCompletesOnFinalSetAndStartsNext() {
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let first = SessionExercise(
            sessionID: sessionID,
            exerciseID: UUID(),
            exerciseName: "深蹲",
            order: 0,
            targetSets: 2,
            minReps: 8,
            maxReps: 8,
            targetWeight: 50,
            restSeconds: 90
        )
        let second = SessionExercise(
            sessionID: sessionID,
            exerciseID: UUID(),
            exerciseName: "硬拉",
            order: 1,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 60,
            restSeconds: 90
        )
        let firstLog = makeSet(sessionID: sessionID, setNumber: 1, sessionExerciseID: first.id)
        let lastLog = makeSet(sessionID: sessionID, setNumber: 2, sessionExerciseID: first.id)

        WorkoutExerciseTracking.startFirstExercise(in: [second, first], at: base)
        XCTAssertEqual(first.exerciseStartedAt, base)
        XCTAssertNil(second.exerciseStartedAt)

        firstLog.isCompleted = true
        WorkoutExerciseTracking.updateAfterSetChange(
            exercise: first,
            logs: [firstLog, lastLog],
            followingExercise: second,
            at: base.addingTimeInterval(90)
        )
        XCTAssertNil(first.exerciseCompletedAt)

        lastLog.isCompleted = true
        WorkoutExerciseTracking.updateAfterSetChange(
            exercise: first,
            logs: [firstLog, lastLog],
            followingExercise: second,
            at: base.addingTimeInterval(180)
        )
        XCTAssertEqual(first.exerciseCompletedAt, base.addingTimeInterval(180))
        XCTAssertEqual(second.exerciseStartedAt, base.addingTimeInterval(180))
        XCTAssertEqual(first.durationSeconds, 180)

        lastLog.isCompleted = false
        WorkoutExerciseTracking.updateAfterSetChange(
            exercise: first,
            logs: [firstLog, lastLog],
            followingExercise: second,
            at: base.addingTimeInterval(200)
        )
        XCTAssertNil(first.exerciseCompletedAt)
        XCTAssertEqual(first.exerciseStartedAt, base)
    }

    func testExerciseTimingAllowsOverlappingIntervals() {
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let first = SessionExercise(
            sessionID: sessionID, exerciseID: UUID(), exerciseName: "A", order: 0,
            targetSets: 1, minReps: 1, maxReps: 1, targetWeight: 0, restSeconds: 0
        )
        let second = SessionExercise(
            sessionID: sessionID, exerciseID: UUID(), exerciseName: "B", order: 1,
            targetSets: 1, minReps: 1, maxReps: 1, targetWeight: 0, restSeconds: 0
        )

        WorkoutExerciseTracking.startFirstExercise(in: [first, second], at: base)
        WorkoutExerciseTracking.recordInteraction(with: second, at: base.addingTimeInterval(15))

        XCTAssertEqual(first.exerciseStartedAt, base)
        XCTAssertEqual(second.exerciseStartedAt, base.addingTimeInterval(15))
        XCTAssertNil(first.exerciseCompletedAt)
        XCTAssertNil(second.exerciseCompletedAt)
    }

    func testBodyWeightResolverUsesLatestValueOnOrBeforeWorkoutThenCurrentFallback() {
        let workoutDate = Date(timeIntervalSince1970: 1_800_000_000)
        let earlier = BodyMeasurement(date: workoutDate.addingTimeInterval(-86_400), weightKg: 71)
        let later = BodyMeasurement(date: workoutDate.addingTimeInterval(86_400), weightKg: 72)

        XCTAssertEqual(
            BodyWeightSnapshotResolver.resolve(
                for: workoutDate,
                measurements: [later, earlier],
                currentHealthWeightKg: 73
            ),
            71
        )
        XCTAssertEqual(
            BodyWeightSnapshotResolver.resolve(
                for: workoutDate,
                measurements: [later],
                currentHealthWeightKg: 73
            ),
            73
        )
        XCTAssertNil(
            BodyWeightSnapshotResolver.resolve(
                for: workoutDate,
                measurements: [],
                currentHealthWeightKg: nil
            )
        )
    }

    func testBodyWeightSnapshotResolverKeepsMeasurementSourceDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let measurementDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 23, hour: 8, minute: 3
        )))
        let workoutDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 12, hour: 12
        )))
        let measurement = BodyMeasurement(date: measurementDate, weightKg: 87.4)

        let snapshot = BodyWeightSnapshotResolver.resolveSnapshot(
            for: workoutDate,
            measurements: [measurement],
            currentHealthWeightKg: nil
        )

        XCTAssertEqual(snapshot?.weightKg, 87.4)
        XCTAssertEqual(snapshot?.sourceDate, measurementDate)
        XCTAssertNil(BodyWeightSnapshotResolver.resolveSnapshot(
            for: workoutDate,
            measurements: [],
            currentHealthWeightKg: 87.4
        )?.sourceDate)
    }

    func testQuickWeightSaveUpdatesSameDayManualRecordWithoutTouchingHealthSource() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let evening = morning.addingTimeInterval(4 * 3_600)
        let manual = BodyMeasurement(
            date: morning,
            weightKg: 83.8,
            waistCm: 80,
            source: .manual
        )
        let health = BodyMeasurement(
            date: morning.addingTimeInterval(60),
            weightKg: 83.7,
            source: .healthKit
        )
        context.insert(manual)
        context.insert(health)
        try context.save()

        let saved = try BodyMeasurementService.saveQuickEntry(
            BodyMeasurementQuickEntry(
                date: evening,
                weightKg: 84,
                bodyFatPercent: nil,
                waistCm: nil,
                chestCm: nil,
                armCm: nil,
                notes: "晚间复测"
            ),
            in: context,
            calendar: calendar
        )
        let records = try context.fetch(FetchDescriptor<BodyMeasurement>())

        XCTAssertEqual(saved.id, manual.id)
        XCTAssertEqual(saved.weightKg, 84)
        XCTAssertEqual(saved.date, evening)
        XCTAssertEqual(saved.waistCm, 80, "快速录入未展开的旧扩展数据应保留")
        XCTAssertEqual(saved.notes, "晚间复测")
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(health.weightKg, 83.7)
        XCTAssertEqual(health.source, .healthKit)
    }

    func testDailyRepresentativeWeightPrefersManualThenLatestHealthRecord() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let dayOne = Date(timeIntervalSince1970: 1_800_000_000)
        let dayTwo = calendar.date(byAdding: .day, value: 1, to: dayOne)!
        let healthBeforeManual = BodyMeasurement(
            date: dayOne,
            weightKg: 83.5,
            source: .healthKit
        )
        let manual = BodyMeasurement(
            date: dayOne.addingTimeInterval(60),
            weightKg: 84,
            source: .manual
        )
        let healthAfterManual = BodyMeasurement(
            date: dayOne.addingTimeInterval(120),
            weightKg: 84.2,
            source: .healthKit
        )
        let olderHealth = BodyMeasurement(
            date: dayTwo,
            weightKg: 84.1,
            source: .healthKit
        )
        let latestHealth = BodyMeasurement(
            date: dayTwo.addingTimeInterval(120),
            weightKg: 84.4,
            source: .healthKit
        )
        let invalid = BodyMeasurement(
            date: dayTwo.addingTimeInterval(180),
            weightKg: 0,
            source: .manual
        )

        let values = BodyMeasurementService.dailyRepresentativeWeights(
            from: [healthBeforeManual, manual, healthAfterManual, olderHealth, latestHealth, invalid],
            calendar: calendar
        )

        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[0].measurementID, manual.id)
        XCTAssertEqual(values[0].weightKg, 84)
        XCTAssertEqual(values[0].source, .manual)
        XCTAssertEqual(values[1].measurementID, latestHealth.id)
        XCTAssertEqual(values[1].weightKg, 84.4)
        XCTAssertEqual(values[1].source, .healthKit)
    }

    func testWeightTrendUsesSevenDayMovingAverageAndPeriodFiltering() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!
        let firstDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let values = (0..<8).map { offset in
            BodyWeightDailyValue(
                date: calendar.date(byAdding: .day, value: offset, to: firstDay)!,
                weightKg: 70 + Double(offset),
                source: .manual,
                measurementID: UUID()
            )
        }

        let points = BodyMeasurementService.trendPoints(from: values)

        XCTAssertEqual(points.count, 8)
        XCTAssertNil(points[5].movingAverageKg)
        XCTAssertEqual(points[6].movingAverageKg, 73)
        XCTAssertEqual(points[7].movingAverageKg, 74)
        XCTAssertEqual(
            BodyMeasurementService.filteredTrendPoints(
                points,
                period: .oneMonth,
                through: values.last!.date,
                calendar: calendar
            ).count,
            8
        )
    }

    func testBodyweightHealthBackfillUsesHistoricalWeightThenCurrentFallbackAndSnapshotsLogs() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "引体向上",
            muscleGroup: "背部",
            equipment: "自重",
            volumeUnit: .bodyweight
        )
        context.insert(exercise)

        let historicalDate = Date(timeIntervalSince1970: 1_800_000_000)
        let fallbackDate = historicalDate.addingTimeInterval(86_400)
        let historicalSession = WorkoutSession(
            templateName: "历史体重",
            plannedDate: historicalDate,
            startedAt: historicalDate,
            completedAt: historicalDate.addingTimeInterval(1_800),
            status: .completed
        )
        let fallbackSession = WorkoutSession(
            templateName: "当前体重回退",
            plannedDate: fallbackDate,
            startedAt: fallbackDate,
            completedAt: fallbackDate.addingTimeInterval(1_800),
            status: .completed
        )
        context.insert(historicalSession)
        context.insert(fallbackSession)

        let historicalSnapshot = SessionExercise(
            sessionID: historicalSession.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 0,
            restSeconds: 0,
            volumeUnit: .bodyweight
        )
        let fallbackSnapshot = SessionExercise(
            sessionID: fallbackSession.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 0,
            restSeconds: 0,
            volumeUnit: .bodyweight
        )
        context.insert(historicalSnapshot)
        context.insert(fallbackSnapshot)

        let historicalLog = SetLog(
            sessionID: historicalSession.id,
            sessionExerciseID: historicalSnapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 0,
            targetReps: 8,
            actualWeight: 0,
            actualReps: 8,
            isCompleted: true
        )
        let fallbackLog = SetLog(
            sessionID: fallbackSession.id,
            sessionExerciseID: fallbackSnapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 0,
            targetReps: 10,
            actualWeight: 0,
            actualReps: 10,
            isCompleted: true
        )
        context.insert(historicalLog)
        context.insert(fallbackLog)

        try BodyweightVolumeMigration.applyHealthWeightFallbacks(
            in: context,
            historicalWeightKg: { date in
                date == historicalDate ? 84 : nil
            },
            currentWeightKg: 90
        )

        XCTAssertEqual(historicalSnapshot.bodyWeightKgSnapshot, 84)
        XCTAssertEqual(historicalLog.actualWeight, 84)
        XCTAssertEqual(historicalLog.targetWeight, 84)
        XCTAssertEqual(fallbackSnapshot.bodyWeightKgSnapshot, 90)
        XCTAssertEqual(fallbackLog.actualWeight, 90)
        XCTAssertEqual(fallbackLog.targetWeight, 90)
    }

    func testBodyweightBackfillUsesLatestStoredSnapshotWhenLocalAndHealthWeightsAreUnavailable() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "仰卧起坐",
            muscleGroup: "核心",
            equipment: "自重",
            volumeUnit: .bodyweight
        )
        let importedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let knownDate = importedDate.addingTimeInterval(86_400)
        let importedSession = WorkoutSession(
            templateName: "导入训练",
            plannedDate: importedDate,
            startedAt: importedDate,
            completedAt: importedDate.addingTimeInterval(1_800),
            status: .completed
        )
        let knownSession = WorkoutSession(
            templateName: "已有体重快照",
            plannedDate: knownDate,
            startedAt: knownDate,
            completedAt: knownDate.addingTimeInterval(1_800),
            status: .completed
        )
        let importedSnapshot = SessionExercise(
            sessionID: importedSession.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 12,
            maxReps: 12,
            targetWeight: 0,
            restSeconds: 0,
            volumeUnit: .bodyweight
        )
        let knownSnapshot = SessionExercise(
            sessionID: knownSession.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 84,
            restSeconds: 0,
            volumeUnit: .bodyweight,
            bodyWeightKgSnapshot: 84
        )
        let importedLog = SetLog(
            sessionID: importedSession.id,
            sessionExerciseID: importedSnapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 0,
            targetReps: 12,
            actualWeight: 0,
            actualReps: 12,
            isCompleted: true
        )
        context.insert(exercise)
        context.insert(importedSession)
        context.insert(knownSession)
        context.insert(importedSnapshot)
        context.insert(knownSnapshot)
        context.insert(importedLog)

        try BodyweightVolumeMigration.applyHealthWeightFallbacks(
            in: context,
            historicalWeightKg: { _ in nil },
            currentWeightKg: nil
        )

        XCTAssertEqual(importedSnapshot.bodyWeightKgSnapshot, 84)
        XCTAssertEqual(importedLog.actualWeight, 84)
        XCTAssertEqual(importedLog.targetWeight, 84)
    }

    func testConfirmedAliasConsolidationArchivesGroupsAndKeepsHistorySnapshotIdentity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "别名测试", weekday: 2)
        context.insert(template)
        var historicalDuplicateID: UUID?

        for group in ExerciseCatalogService.confirmedAliasGroups {
            let primary = Exercise(
                name: group.primaryName,
                muscleGroup: "测试肌群",
                equipment: "测试器械",
                isBuiltIn: false
            )
            let duplicate = Exercise(
                name: group.aliases.first(where: { $0 != group.primaryName }) ?? group.primaryName,
                muscleGroup: "测试肌群",
                equipment: "测试器械",
                isBuiltIn: false
            )
            context.insert(primary)
            context.insert(duplicate)
            context.insert(TemplateExercise(
                templateID: template.id,
                exerciseID: duplicate.id,
                order: 0,
                targetSets: 1,
                minReps: 10,
                maxReps: 10,
                targetWeight: 10,
                restSeconds: 60
            ))
            if historicalDuplicateID == nil {
                historicalDuplicateID = duplicate.id
                context.insert(SessionExercise(
                    sessionID: UUID(),
                    exerciseID: duplicate.id,
                    exerciseName: duplicate.name,
                    order: 0,
                    targetSets: 1,
                    minReps: 10,
                    maxReps: 10,
                    targetWeight: 10,
                    restSeconds: 60
                ))
            }
        }
        try context.save()

        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)
        try ExerciseCatalogService.consolidateConfirmedAliases(in: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        for group in ExerciseCatalogService.confirmedAliasGroups {
            XCTAssertEqual(exercises.filter { $0.name == group.primaryName && !$0.isArchived }.count, 1)
            XCTAssertTrue(exercises.filter {
                group.aliases.contains($0.name) && $0.name != group.primaryName
            }.allSatisfy(\.isArchived))
        }
        let history = try context.fetch(FetchDescriptor<SessionExercise>())
        XCTAssertEqual(history.first?.exerciseID, historicalDuplicateID)
    }

    func testBodyweightMigrationUsesAllowlistAndLeavesMisclassifiedWeightedMovesUntouched() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let bodyweight = Exercise(
            name: "举腿", muscleGroup: "核心", equipment: "自重", isBuiltIn: false
        )
        let weighted = Exercise(
            name: "传统硬拉", muscleGroup: "腿部", equipment: "自重", isBuiltIn: false
        )
        let session = WorkoutSession(
            templateName: "历史",
            plannedDate: date,
            startedAt: date,
            completedAt: date.addingTimeInterval(3_600),
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: bodyweight.id,
            exerciseName: bodyweight.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 0,
            restSeconds: 0
        )
        let log = makeSet(sessionID: session.id, setNumber: 1, sessionExerciseID: snapshot.id)
        log.actualWeight = 0
        context.insert(bodyweight)
        context.insert(weighted)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        context.insert(BodyMeasurement(date: date.addingTimeInterval(-60), weightKg: 72))
        try context.save()

        try BodyweightVolumeMigration.applyConfirmedAllowlist(in: context)

        XCTAssertEqual(bodyweight.volumeUnit, .bodyweight)
        XCTAssertEqual(snapshot.bodyWeightKgSnapshot, 72)
        XCTAssertEqual(log.actualWeight, 72)
        XCTAssertEqual(weighted.volumeUnit, .kilogram)
    }

    func testWeightedEquipmentCorrectionFixesOnlyConfirmedMisclassifiedCatalogEntries() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let deadlift = Exercise(name: "传统硬拉", muscleGroup: "腿部", equipment: "自重")
        let dumbbellSideSquat = Exercise(name: "哑铃侧边蹲", muscleGroup: "其他", equipment: "自重")
        let landmineRotation = Exercise(name: "地雷杆转体", muscleGroup: "核心", equipment: "杠铃")
        let landmineZercher = Exercise(name: "地雷杆泽奇蹲", muscleGroup: "其他", equipment: "自重")
        let unrelated = Exercise(name: "未确认动作", muscleGroup: "其他", equipment: "自重")
        [deadlift, dumbbellSideSquat, landmineRotation, landmineZercher, unrelated].forEach(context.insert)

        try WeightedExerciseIdentityMigration.applyConfirmedCorrections(in: context)

        XCTAssertEqual(deadlift.equipment, "杠铃")
        XCTAssertEqual(deadlift.muscleGroup, "腿部")
        XCTAssertEqual(deadlift.volumeUnit, .kilogram)
        XCTAssertEqual(dumbbellSideSquat.equipment, "哑铃")
        XCTAssertEqual(dumbbellSideSquat.muscleGroup, "腿部")
        XCTAssertEqual(landmineRotation.equipment, "地雷杆")
        XCTAssertEqual(landmineRotation.muscleGroup, "核心")
        XCTAssertEqual(landmineZercher.equipment, "地雷杆")
        XCTAssertEqual(landmineZercher.muscleGroup, "腿部")
        XCTAssertEqual(unrelated.equipment, "自重")
    }

    func testVolumeSummaryKeepsKilogramsCountsMetersAndBodyweightSeparate() {
        let sessionID = UUID()
        let kilogram = SessionExercise(
            sessionID: sessionID, exerciseID: UUID(), exerciseName: "负重", order: 0,
            targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 20, restSeconds: 0,
            volumeUnit: .kilogram
        )
        let count = SessionExercise(
            sessionID: sessionID, exerciseID: UUID(), exerciseName: "跳绳", order: 1,
            targetSets: 1, minReps: 100, maxReps: 100, targetWeight: 0, restSeconds: 0,
            volumeUnit: .count
        )
        let meter = SessionExercise(
            sessionID: sessionID, exerciseID: UUID(), exerciseName: "步行", order: 2,
            targetSets: 1, minReps: 1, maxReps: 1, targetWeight: 6000, restSeconds: 0,
            volumeUnit: .meter
        )
        let bodyweight = SessionExercise(
            sessionID: sessionID, exerciseID: UUID(), exerciseName: "举腿", order: 3,
            targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 0, restSeconds: 0,
            volumeUnit: .bodyweight, bodyWeightKgSnapshot: 70
        )
        let specs: [(SessionExercise, Double, Int)] = [
            (kilogram, 20, 10), (count, 0, 100), (meter, 6000, 1), (bodyweight, 0, 10)
        ]
        let logs = specs.map { snapshot, weight, reps in
            let log = makeSet(sessionID: sessionID, setNumber: 1, sessionExerciseID: snapshot.id)
            log.actualWeight = weight
            log.actualReps = reps
            log.isCompleted = true
            return log
        }

        let summary = TrainingMetrics.volumeSummary(
            sessionExercises: specs.map(\.0),
            setLogs: logs
        )
        XCTAssertEqual(summary[.kilogram], 200)
        XCTAssertEqual(summary[.count], 100)
        XCTAssertEqual(summary[.meter], 6000)
        XCTAssertEqual(summary[.bodyweight], 700)
    }

    func testNotesImportPackageHasThirteenSessionsAndIsIdempotent() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repositoryRoot
            .appendingPathComponent("outputs/notes-import/20260831/notes-workouts-2026-08.csv")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Notes 导入包只存在于仓库主机；其内容与幂等性由 non-device 门禁验证。")
        }
        let data = try Data(contentsOf: url)
        let container = try makeContainer()
        let context = container.mainContext

        let preview = try HistoricalWorkoutCSVService.preview(data, in: context)
        XCTAssertEqual(preview.sessions, 13)
        XCTAssertEqual(preview.duplicateSessions, 0)

        let first = try HistoricalWorkoutCSVService.importCSV(data, into: context)
        let second = try HistoricalWorkoutCSVService.importCSV(data, into: context)
        XCTAssertEqual(first.importedSessions, 13)
        XCTAssertEqual(second.importedSessions, 0)
        XCTAssertEqual(second.skippedSessions, 13)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let august22 = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 22))!
        XCTAssertFalse(sessions.contains { $0.plannedDate.isSameDay(as: august22) })
    }

    func testConfirmedNotesSyncImportsTrainingWeightsBodyMealsAndIsIdempotent() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageURL = repositoryRoot
            .appendingPathComponent("outputs/notes-import/20260909/confirmed-notes-sync.json")
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            throw XCTSkip("确认后的 Notes 同步包只存在于仓库主机。")
        }
        let data = try Data(contentsOf: packageURL)
        let container = try makeContainer()
        let context = container.mainContext

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let september9 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 9)))
        let september4 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 4)))
        let program = FatLossProgram(
            startDate: september4,
            endDate: september4.addingDays(91)
        )
        let schedule = ScheduledWorkout(
            templateID: UUID(),
            templateName: "背部＋二头 · 高集中容量",
            plannedDate: september9
        )
        let link = ProgramWorkoutLink(
            programID: program.id,
            scheduledWorkoutID: schedule.id,
            templateCode: "BACK_BI_R2",
            originalDate: september9
        )
        let stale = WorkoutSession(
            templateName: "推 · 胸肩三头",
            plannedDate: september4,
            startedAt: september4.addingTimeInterval(9 * 3_600),
            status: .inProgress
        )
        let staleExercise = Exercise(name: "旧卧推", muscleGroup: "胸部", equipment: "杠铃")
        let staleSnapshot = SessionExercise(
            sessionID: stale.id,
            exerciseID: staleExercise.id,
            exerciseName: staleExercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 40,
            restSeconds: 120,
            muscleGroup: "胸部"
        )
        let staleLog = SetLog(
            sessionID: stale.id,
            sessionExerciseID: staleSnapshot.id,
            exerciseID: staleExercise.id,
            setNumber: 1,
            targetWeight: 40,
            targetReps: 8,
            actualWeight: 0,
            actualReps: 0
        )
        context.insert(program)
        context.insert(schedule)
        context.insert(link)
        context.insert(stale)
        context.insert(staleExercise)
        context.insert(staleSnapshot)
        context.insert(staleLog)
        try context.save()

        let first = try ConfirmedNotesImportService.importPackage(data, into: context)
        let sessionsAfterFirst = try context.fetch(FetchDescriptor<WorkoutSession>())
        let importedIDsAfterFirst = Set(sessionsAfterFirst.map(\.id))
        let second = try ConfirmedNotesImportService.importPackage(data, into: context)

        XCTAssertEqual(first.importedSessions, 2)
        XCTAssertEqual(first.importedSessionExercises, 15)
        XCTAssertEqual(first.importedSets, 62)
        XCTAssertEqual(first.importedBodyMeasurements, 3)
        XCTAssertEqual(first.importedMeals, 7)
        XCTAssertEqual(first.linkedSchedules, 1)
        XCTAssertEqual(first.discardedStaleSessions, 1)
        XCTAssertEqual(second.importedSessions, 0)
        XCTAssertEqual(second.skippedSessions, 2)
        XCTAssertEqual(second.importedBodyMeasurements, 0)
        XCTAssertEqual(second.skippedBodyMeasurements, 3)
        XCTAssertEqual(second.importedMeals, 0)
        XCTAssertEqual(second.skippedMeals, 7)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id)), importedIDsAfterFirst)
        XCTAssertEqual(schedule.status, .completed)
        XCTAssertEqual(stale.status, .discarded)

        let importedSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            .filter { $0.importIdentifier.hasPrefix("confirmed-notes:") }
        let importedSessionIDs = Set(importedSessions.map(\.id))
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { importedSessionIDs.contains($0.sessionID) }
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { importedSessionIDs.contains($0.sessionID) }
        XCTAssertEqual(snapshots.count, 15)
        XCTAssertEqual(logs.count, 62)
        XCTAssertTrue(logs.allSatisfy { $0.isCompleted && $0.rir == nil })
        let benchID = try XCTUnwrap(snapshots.first { $0.exerciseName == "杠铃卧推" }?.id)
        XCTAssertEqual(
            logs.filter { $0.sessionExerciseID == benchID }
                .sorted { $0.setNumber < $1.setNumber }
                .map(\.actualWeight),
            [20, 25, 30, 35, 40]
        )
        XCTAssertTrue(logs.filter { $0.sessionExerciseID == benchID }.allSatisfy { $0.actualWeightSide == .single })
        let rotationID = try XCTUnwrap(snapshots.first { $0.exerciseName == "绳索伸展转体" }?.id)
        XCTAssertTrue(logs.filter { $0.sessionExerciseID == rotationID }.allSatisfy {
            $0.actualWeightSide == .single && $0.actualRepsSide == .single
        })

        let measurements = try context.fetch(FetchDescriptor<BodyMeasurement>())
            .sorted { $0.date < $1.date }
        XCTAssertEqual(measurements.map { $0.weightKg ?? 0 }, [87.65, 87.55, 86.7])
        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        XCTAssertEqual(meals.count, 7)
        XCTAssertTrue(meals.allSatisfy { !$0.isNutritionKnown && $0.knownNutritionFieldsRaw == "" })
    }

    func testConfirmedNotesImportFreezesSourceDayAndRepairsOnlyMissingUnknownTimeMetadata() throws {
        let store = try makeContainer(), context = store.mainContext
        let sourceTimeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let sourceMidnight = try XCTUnwrap(sourceCalendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let packageID = "fixture-date-only-notes"
        let importID = "confirmed-notes:\(packageID):2026-10-12-oct12-notes-workout"
        let exercise = Exercise(name: "颈前深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let existing = WorkoutSession(templateName: "颈前深蹲", plannedDate: sourceMidnight,
            startedAt: sourceMidnight, status: .completed, notes: "原有备注", importIdentifier: importID)
        context.insert(exercise)
        context.insert(existing)
        try context.save()

        let data = Data("""
        {"version":1,"packageID":"fixture-date-only-notes","timeZoneIdentifier":"Asia/Shanghai",
         "workouts":[{"id":"2026-10-12-oct12-notes-workout","date":"2026-10-12","name":"颈前深蹲",
          "durationMinutes":null,"notes":"Notes 原始记录","scheduleTemplateCode":null,"startTimeKnown":false,
          "exercises":[{"name":"颈前深蹲","muscleGroup":"腿部","equipment":"杠铃","volumeUnit":"kilogram","notes":"",
           "sets":[{"weight":10,"reps":15,"weightSide":"unknown","repsSide":"unknown"}]}]}],
         "bodyMeasurements":[],"meals":[],"jumpRopeEntries":[],"voidMealIDs":[],"staleSession":null}
        """.utf8)

        let result = try ConfirmedNotesImportService.importPackage(data, into: context)

        XCTAssertEqual(result.importedSessions, 0)
        XCTAssertEqual(result.skippedSessions, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertEqual(existing.id, try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first?.id))
        XCTAssertEqual(existing.trainingLocalDay, "2026-10-12")
        XCTAssertEqual(existing.trainingTimeZoneIdentifier, "Asia/Shanghai")
        XCTAssertFalse(existing.isStartTimeKnown)
        XCTAssertEqual(existing.startedAt, sourceMidnight)
        XCTAssertEqual(existing.notes, "原有备注")
        XCTAssertTrue(try context.fetch(FetchDescriptor<SessionExercise>()).isEmpty)

        let repeated = try ConfirmedNotesImportService.importPackage(data, into: context)
        XCTAssertEqual(repeated.importedSessions, 0)
        XCTAssertEqual(repeated.skippedSessions, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertEqual(existing.trainingLocalDay, "2026-10-12")
        XCTAssertFalse(existing.isStartTimeKnown)
    }

    func testConfirmedNotesNewDateOnlyWorkoutStoresSourceDayAndUnknownTime() throws {
        let store = try makeContainer(), context = store.mainContext
        let sydney = try XCTUnwrap(TimeZone(identifier: "Australia/Sydney"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sydney
        let expectedStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let exercise = Exercise(name: "颈前深蹲", muscleGroup: "腿部", equipment: "杠铃")
        context.insert(exercise)
        try context.save()
        let data = Data("""
        {"version":1,"packageID":"fixture-new-date-only","timeZoneIdentifier":"Australia/Sydney",
         "workouts":[{"id":"workout-2026-10-12","date":"2026-10-12","name":"Oct 12",
          "durationMinutes":null,"notes":"","scheduleTemplateCode":null,
          "exercises":[{"name":"颈前深蹲","muscleGroup":"腿部","equipment":"杠铃","volumeUnit":"kilogram","notes":"",
           "sets":[{"weight":30,"reps":6,"weightSide":"unknown","repsSide":"unknown"}]}]}],
         "bodyMeasurements":[],"meals":[],"jumpRopeEntries":[],"voidMealIDs":[],"staleSession":null}
        """.utf8)

        let result = try ConfirmedNotesImportService.importPackage(data, into: context)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)

        XCTAssertEqual(result.importedSessions, 1)
        XCTAssertEqual(result.importedSessionExercises, 1)
        XCTAssertEqual(result.importedSets, 1)
        XCTAssertEqual(session.trainingLocalDay, "2026-10-12")
        XCTAssertEqual(session.trainingTimeZoneIdentifier, "Australia/Sydney")
        XCTAssertFalse(session.isStartTimeKnown)
        XCTAssertEqual(session.startedAt, expectedStart)
    }

    func testConfirmedNotesDateMetadataRepairPreservesAnOwnerEditedStartTime() throws {
        let store = try makeContainer(), context = store.mainContext
        let sourceTimeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let sourceMidnight = try XCTUnwrap(sourceCalendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let ownerEditedStart = sourceMidnight.addingTimeInterval(10 * 3_600)
        let packageID = "fixture-owner-edited-time"
        let importID = "confirmed-notes:\(packageID):2026-10-12-oct12-notes-workout"
        context.insert(Exercise(name: "颈前深蹲", muscleGroup: "腿部", equipment: "杠铃"))
        let existing = WorkoutSession(templateName: "颈前深蹲", plannedDate: sourceMidnight,
            startedAt: ownerEditedStart, status: .completed, importIdentifier: importID)
        context.insert(existing)
        try context.save()

        let data = Data("""
        {"version":1,"packageID":"fixture-owner-edited-time","timeZoneIdentifier":"Asia/Shanghai",
         "workouts":[{"id":"2026-10-12-oct12-notes-workout","date":"2026-10-12","name":"颈前深蹲",
          "durationMinutes":null,"notes":"Notes 原始记录","scheduleTemplateCode":null,"startTimeKnown":false,
          "exercises":[{"name":"颈前深蹲","muscleGroup":"腿部","equipment":"杠铃","volumeUnit":"kilogram","notes":"",
           "sets":[{"weight":10,"reps":15,"weightSide":"unknown","repsSide":"unknown"}]}]}],
         "bodyMeasurements":[],"meals":[],"jumpRopeEntries":[],"voidMealIDs":[],"staleSession":null}
        """.utf8)

        _ = try ConfirmedNotesImportService.importPackage(data, into: context)

        XCTAssertEqual(existing.trainingLocalDay, "2026-10-12")
        XCTAssertEqual(existing.trainingTimeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(existing.startedAt, ownerEditedStart)
        XCTAssertTrue(existing.isStartTimeKnown)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
    }

    func testRevokeAllUnfinishedPlansPreservesCompletedSchedulesAndEveryIdentifier() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = FatLossCalendar.date(2026, 9, 14)
        let planned = ScheduledWorkout(templateID: UUID(), templateName: "旧计划一", plannedDate: day)
        let inProgress = ScheduledWorkout(templateID: UUID(), templateName: "旧计划二", plannedDate: day, status: .inProgress)
        let completed = ScheduledWorkout(templateID: UUID(), templateName: "已完成计划", plannedDate: day, status: .completed)
        let alreadySkipped = ScheduledWorkout(templateID: UUID(), templateName: "已撤销计划", plannedDate: day, status: .skipped, skipReason: "旧原因")
        [planned, inProgress, completed, alreadySkipped].forEach(context.insert)
        try context.save()
        let ids = Set([planned.id, inProgress.id, completed.id, alreadySkipped.id])

        let first = try ScheduleService.revokeAllUnfinished(reason: "本周未使用 App；按确认方案撤销旧计划", in: context)
        let second = try ScheduleService.revokeAllUnfinished(reason: "本周未使用 App；按确认方案撤销旧计划", in: context)

        XCTAssertEqual(first, 2)
        XCTAssertEqual(second, 0)
        XCTAssertEqual(planned.status, .skipped)
        XCTAssertEqual(inProgress.status, .skipped)
        XCTAssertEqual(planned.skipReason, "本周未使用 App；按确认方案撤销旧计划")
        XCTAssertEqual(inProgress.skipReason, "本周未使用 App；按确认方案撤销旧计划")
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(alreadySkipped.skipReason, "旧原因")
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<ScheduledWorkout>()).map(\.id)), ids)
    }

    func testConfirmedNotesIncrementV2ImportsJumpRopeVoidsConflictsAndIsIdempotent() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let packageURL = repositoryRoot
            .appendingPathComponent("outputs/notes-import/20260914/confirmed-notes-increment-v2.json")
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            throw XCTSkip("确认后的 Notes 增量同步包只存在于仓库主机。")
        }
        let data = try Data(contentsOf: packageURL)
        let container = try makeContainer()
        let context = container.mainContext
        let oldLunch = MealEntry(
            id: try XCTUnwrap(UUID(uuidString: "62D4995B-2477-5088-973A-CE071BF70807")),
            date: FatLossCalendar.date(2026, 9, 9),
            mealType: .lunch,
            name: "鸡肉咖喱饭",
            calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0
        )
        let oldSnack = MealEntry(
            id: try XCTUnwrap(UUID(uuidString: "870C5D6F-9C03-5AAB-A079-C368EE6793EC")),
            date: FatLossCalendar.date(2026, 9, 9),
            mealType: .snack,
            name: "香蕉 1 根；青瓜 1 根",
            calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0
        )
        context.insert(oldLunch)
        context.insert(oldSnack)
        try context.save()

        let first = try ConfirmedNotesImportService.importPackage(data, into: context)
        let firstSessionIDs = Set(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id))
        let firstMealIDs = Set(try context.fetch(FetchDescriptor<MealEntry>()).map(\.id))
        let second = try ConfirmedNotesImportService.importPackage(data, into: context)

        XCTAssertEqual(first.importedSessions, 2)
        XCTAssertEqual(first.importedSessionExercises, 15)
        XCTAssertEqual(first.importedSets, 63)
        XCTAssertEqual(first.importedBodyMeasurements, 9)
        XCTAssertEqual(first.importedMeals, 16)
        XCTAssertEqual(first.importedJumpRopeEntries, 1)
        XCTAssertEqual(first.voidedMeals, 2)
        XCTAssertEqual(first.alreadyVoidedMeals, 0)
        XCTAssertEqual(second.importedSessions, 0)
        XCTAssertEqual(second.skippedSessions, 2)
        XCTAssertEqual(second.importedBodyMeasurements, 0)
        XCTAssertEqual(second.skippedBodyMeasurements, 9)
        XCTAssertEqual(second.importedMeals, 0)
        XCTAssertEqual(second.skippedMeals, 16)
        XCTAssertEqual(second.importedJumpRopeEntries, 0)
        XCTAssertEqual(second.skippedJumpRopeEntries, 1)
        XCTAssertEqual(second.voidedMeals, 0)
        XCTAssertEqual(second.alreadyVoidedMeals, 2)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id)), firstSessionIDs)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<MealEntry>()).map(\.id)), firstMealIDs)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let sessionIDs = Set(sessions.map(\.id))
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>()).filter { sessionIDs.contains($0.sessionID) }
        let logs = try context.fetch(FetchDescriptor<SetLog>()).filter { sessionIDs.contains($0.sessionID) }
        XCTAssertEqual(snapshots.count, 15)
        XCTAssertEqual(logs.count, 63)
        XCTAssertTrue(logs.allSatisfy { $0.rir == nil && $0.isCompleted })
        let reverseFly = try XCTUnwrap(snapshots.first { $0.exerciseName == "器械坐姿反向飞鸟" })
        XCTAssertEqual(logs.filter { $0.sessionExerciseID == reverseFly.id }.sorted { $0.setNumber < $1.setNumber }.map(\.actualReps), [10, 10, 10, 10])
        let standingReverseFly = try XCTUnwrap(snapshots.first { $0.exerciseName == "哑铃站姿反向飞鸟" })
        let standingReverseFlyExercise = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first { $0.id == standingReverseFly.exerciseID })
        XCTAssertEqual(standingReverseFlyExercise.equipment, "哑铃")
        XCTAssertTrue(logs.filter { $0.sessionExerciseID == standingReverseFly.id }.allSatisfy { $0.actualWeightSide == .unknown })

        let weights = try context.fetch(FetchDescriptor<BodyMeasurement>()).sorted { $0.date < $1.date }
        XCTAssertEqual(weights.count, 9)
        XCTAssertEqual(weights.first?.weightKg, 89.15)
        XCTAssertEqual(weights.last?.weightKg, 87.05)
        let ropes = try context.fetch(FetchDescriptor<JumpRopeEntry>())
        XCTAssertEqual(ropes.count, 1)
        XCTAssertEqual(ropes.first?.count, 1_600)
        XCTAssertNil(ropes.first?.activeDurationSeconds)
        XCTAssertNil(ropes.first?.elapsedDurationSeconds)

        let meals = try context.fetch(FetchDescriptor<MealEntry>())
        XCTAssertEqual(meals.count, 18)
        XCTAssertEqual(meals.filter(\.isActiveMeal).count, 16)
        XCTAssertTrue(oldLunch.isVoided == true && oldSnack.isVoided == true)
        XCTAssertTrue(meals.contains { $0.mealType == .lunch && $0.name == "卤肉饭；麻婆豆腐 150 g" && $0.isActiveMeal })
        XCTAssertFalse(meals.contains { FatLossCalendar.sameDay($0.date, FatLossCalendar.date(2026, 9, 13)) })
        XCTAssertTrue(meals.filter(\.isActiveMeal).allSatisfy { !$0.isNutritionKnown })
    }

    func testNotesV3ImportsOwnerCaloriesWithoutInventingMacrosAndRepeatsSafely() throws {
        let store = try makeContainer(), context = store.mainContext
        let data = Data("""
        {"version":3,"packageID":"v3-owner-calories","timeZoneIdentifier":"Asia/Shanghai",
         "workouts":[],"bodyMeasurements":[],"meals":[
          {"id":"461C781F-ED46-4032-BE0B-72002D21F111","date":"2026-09-15","mealType":"dinner",
           "name":"聚会用餐算一千卡","calories":1000,"estimationSource":"本人估算（Notes）"}
         ]}
        """.utf8)
        let first = try ConfirmedNotesImportService.importPackage(data, into: context)
        XCTAssertEqual(first.importedMeals, 1)
        let repeated = try ConfirmedNotesImportService.importPackage(data, into: context)
        XCTAssertEqual(repeated.importedMeals, 0)
        XCTAssertEqual(repeated.skippedMeals, 1)
        let program = FatLossProgram(startDate: FatLossCalendar.date(2026, 9, 15), endDate: FatLossCalendar.date(2026, 9, 16))
        let day = try XCTUnwrap(FatLossService.timeline(program: program, in: context).first)
        XCTAssertEqual(day.knownCalories, 1000)
        XCTAssertEqual(day.unknownNutritionMeals, 1)
        XCTAssertFalse(day.nutritionComplete)
        let csvURL = try FatLossService.exportCSV(program: program, in: context)
        defer { try? FileManager.default.removeItem(at: csvURL) }
        XCTAssertTrue(try String(contentsOf: csvURL, encoding: .utf8).contains("本人估算（Notes）"))
    }

    func testNotesV3RecognizesNaturalDuplicatesButKeepsSeparateSameDayMeasurements() throws {
        let store = try makeContainer(), context = store.mainContext
        let old = Data("""
        {"version":2,"packageID":"original","timeZoneIdentifier":"Asia/Shanghai","workouts":[],
         "bodyMeasurements":[{"id":"9D985B30-ED01-4914-811F-202609160010","recordedAt":"2026-09-16 07:50","weightJin":173.1,"notes":"原始记录"}],
         "meals":[{"id":"9D985B30-ED01-4914-811F-202609140020","date":"2026-09-14","mealType":"snack","name":"玉米一根"}]}
        """.utf8)
        _ = try ConfirmedNotesImportService.importPackage(old, into: context)
        let fresh = Data("""
        {"version":3,"packageID":"new-package","timeZoneIdentifier":"Asia/Shanghai","workouts":[],
         "bodyMeasurements":[
          {"id":"9D985B30-ED01-4914-811F-202609160011","recordedAt":"2026-09-16 07:50","weightJin":173.1,"notes":"确认保留"},
          {"id":"9D985B30-ED01-4914-811F-202609160012","recordedAt":"2026-09-16 07:52","weightJin":173.1,"notes":"另一次测量"}],
         "meals":[{"id":"9D985B30-ED01-4914-811F-202609140021","date":"2026-09-14","mealType":"snack","name":"玉米一根"}]}
        """.utf8)
        let result = try ConfirmedNotesImportService.importPackage(fresh, into: context)
        XCTAssertEqual(result.importedBodyMeasurements, 1)
        XCTAssertEqual(result.skippedBodyMeasurements, 1)
        XCTAssertEqual(result.importedMeals, 0)
        XCTAssertEqual(result.skippedMeals, 1)
    }

    func testNotesV3RejectsMealConflictBeforeImportingAnyMeasurements() throws {
        let store = try makeContainer(), context = store.mainContext
        let old = Data("""
        {"version":2,"packageID":"original-conflict","timeZoneIdentifier":"Asia/Shanghai","workouts":[],"bodyMeasurements":[],
         "meals":[{"id":"1D985B30-ED01-4914-811F-202609160010","date":"2026-09-16","mealType":"dinner","name":"本人后来手填的晚餐"}]}
        """.utf8)
        _ = try ConfirmedNotesImportService.importPackage(old, into: context)
        let conflicting = Data("""
        {"version":3,"packageID":"conflict","timeZoneIdentifier":"Asia/Shanghai","workouts":[],
         "bodyMeasurements":[{"id":"1D985B30-ED01-4914-811F-202609160011","recordedAt":"2026-09-16 07:50","weightJin":173.1,"notes":"原始体重"}],
         "meals":[{"id":"1D985B30-ED01-4914-811F-202609160020","date":"2026-09-16","mealType":"dinner","name":"广西菜 味精重 算一千卡","calories":1000,"estimationSource":"本人估算（Notes）"}]}
        """.utf8)
        XCTAssertThrowsError(try ConfirmedNotesImportService.importPackage(conflicting, into: context))
        let program = FatLossProgram(startDate: FatLossCalendar.date(2026, 9, 16), endDate: FatLossCalendar.date(2026, 9, 17))
        let day = try XCTUnwrap(FatLossService.timeline(program: program, in: context).first)
        XCTAssertNil(day.weightKg)
        XCTAssertEqual(day.loggedMeals, 1)
    }

    func testConfirmedSeptember20NotesPackageContainsOnlyApprovedIncrementAndIsIdempotent() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("outputs/notes-import/20260920/confirmed-notes-increment-v3.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("确认的 Notes 包仅位于仓库主机") }
        let data = try Data(contentsOf: url)
        let store = try makeContainer(), context = store.mainContext
        let preview = try ConfirmedNotesImportService.previewPackage(data, in: context)
        XCTAssertEqual(preview.importedBodyMeasurements, 7)
        XCTAssertEqual(preview.importedMeals, 10)
        XCTAssertEqual(preview.ownerEstimatedMeals, 4)
        let result = try ConfirmedNotesImportService.importPackage(data, into: context)
        XCTAssertEqual(result.importedBodyMeasurements, 7)
        XCTAssertEqual(result.importedMeals, 10)
        let again = try ConfirmedNotesImportService.importPackage(data, into: context)
        XCTAssertEqual(again.importedBodyMeasurements, 0)
        XCTAssertEqual(again.importedMeals, 0)
        let program = FatLossProgram(startDate: FatLossCalendar.date(2026, 9, 13), endDate: FatLossCalendar.date(2026, 9, 20))
        let days = try FatLossService.timeline(program: program, in: context)
        XCTAssertEqual(days.map(\.loggedMeals), [0, 4, 3, 3, 0, 0, 0, 0])
        XCTAssertEqual(days.map(\.knownCalories), [0, 0, 1000, 2200, 0, 0, 0, 0])
        XCTAssertEqual(days.reduce(0) { $0 + $1.unknownNutritionMeals }, 10)
    }

    func testDedicatedUITestsMustExplicitlyEnableExternalSideEffects() {
        XCTAssertTrue(CloudSyncRuntime.shouldSyncWorkoutReminders(arguments: [
            "FitnessApp", "--ui-testing", "--ui-testing-workout-reminders"
        ]))
        XCTAssertTrue(CloudSyncRuntime.shouldReadShareDraft(arguments: [
            "FitnessApp", "--ui-testing", "--ui-testing-share-draft"
        ]))
        XCTAssertTrue(CloudSyncRuntime.shouldSyncWorkoutReminders(arguments: ["FitnessApp"]))
        XCTAssertTrue(CloudSyncRuntime.shouldReadShareDraft(arguments: ["FitnessApp"]))
    }

    func testReschedulePreservesOriginalDateAndPreventsRegeneration() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalDate = Date.now.startOfDay
        let template = WorkoutTemplate(
            name: "测试训练",
            weekday: originalDate.weekdayNumber
        )
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: originalDate
        )
        context.insert(template)
        context.insert(schedule)
        try context.save()

        let newDate = originalDate.addingDays(1)
        try ScheduleService.reschedule(schedule, to: newDate, in: context)
        try ScheduleService.refreshUpcoming(in: context, days: 3)

        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        XCTAssertEqual(schedules.count, 1)
        XCTAssertTrue(schedule.plannedDate.isSameDay(as: newDate))
        XCTAssertTrue(schedule.originalPlannedDate?.isSameDay(as: originalDate) == true)
    }

    func testRefreshUpcomingRetiresAutomaticPlansWithoutTouchingUserOwnedSchedules() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let today = Date.now.startOfDay
        let tomorrow = today.addingDays(1)
        let template = WorkoutTemplate(
            name: "手动模板",
            weekday: tomorrow.weekdayNumber,
            isActive: true
        )
        let untouchedAutomatic = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: tomorrow
        )
        let manual = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: tomorrow.addingDays(1),
            isManuallyScheduled: true
        )
        let rescheduledByUser = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: tomorrow.addingDays(2),
            originalPlannedDate: today
        )
        let skippedByUser = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: tomorrow.addingDays(3),
            status: .skipped,
            skipReason: "用户已处理"
        )
        let completed = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: tomorrow.addingDays(4),
            status: .completed
        )
        context.insert(template)
        [untouchedAutomatic, manual, rescheduledByUser, skippedByUser, completed]
            .forEach(context.insert)
        try context.save()

        try ScheduleService.refreshUpcoming(in: context, days: 14)

        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        XCTAssertFalse(template.isActive)
        XCTAssertFalse(schedules.contains { $0.id == untouchedAutomatic.id })
        XCTAssertTrue(schedules.contains { $0.id == manual.id })
        XCTAssertTrue(schedules.contains { $0.id == rescheduledByUser.id })
        XCTAssertTrue(schedules.contains { $0.id == skippedByUser.id })
        XCTAssertTrue(schedules.contains { $0.id == completed.id })
        XCTAssertEqual(schedules.count, 4)
    }

    func testSkipAndRestoreSchedule() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "推", weekday: Date.now.weekdayNumber)
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: .now
        )
        context.insert(template)
        context.insert(schedule)

        try ScheduleService.skip(schedule, reason: "出差", in: context)
        XCTAssertEqual(schedule.status, .skipped)
        XCTAssertEqual(schedule.skipReason, "出差")

        try ScheduleService.restore(schedule, in: context)
        XCTAssertEqual(schedule.status, .planned)
        XCTAssertTrue(schedule.skipReason.isEmpty)
    }

    func testManualScheduleRejectsDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "腿", weekday: Date.now.weekdayNumber)
        context.insert(template)

        _ = try ScheduleService.addManual(template: template, on: .now, in: context)
        XCTAssertThrowsError(try ScheduleService.addManual(template: template, on: .now, in: context)) { error in
            XCTAssertEqual(error as? ScheduleServiceError, .duplicateSchedule)
        }
    }

    func testJSONBackupImportsIntoEmptyDatabase() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        sourceContext.insert(Exercise(
            name: "自定义划船",
            muscleGroup: "背部",
            equipment: "弹力带",
            isBuiltIn: false,
            volumeUnit: .meter
        ))
        sourceContext.insert(MealEntry(
            mealType: .lunch,
            name: "鸡胸饭",
            calories: 520,
            proteinGrams: 42,
            carbsGrams: 58,
            fatGrams: 12
        ))
        sourceContext.insert(DailyBodyCheckIn(
            date: .now,
            conditionScore: 4,
            discomfortNotes: "右肩前侧发紧",
            bodyMarkers: [
                BodyMapMarker(regionID: "front-right-shoulder", kind: .area),
                BodyMapMarker(regionID: "front-right-knee", kind: .jointFascia)
            ]
        ))
        try sourceContext.save()

        let backupURL = try DataExportService.createBackup(in: sourceContext)
        let data = try Data(contentsOf: backupURL)
        let preview = try DataExportService.preview(data)
        XCTAssertEqual(preview.exercises, 1)
        XCTAssertEqual(preview.meals, 1)
        XCTAssertEqual(preview.bodyCheckIns, 1)

        let destination = try makeContainer()
        let summary = try DataExportService.importBackup(data, into: destination.mainContext)
        XCTAssertEqual(summary.imported, 3)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<Exercise>()).count, 1)
        XCTAssertEqual(
            try destination.mainContext.fetch(FetchDescriptor<Exercise>()).first?.volumeUnit,
            .meter
        )
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<MealEntry>()).count, 1)
        let importedCheckIn = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<DailyBodyCheckIn>()).first
        )
        XCTAssertEqual(importedCheckIn.conditionScore, 4)
        XCTAssertEqual(importedCheckIn.discomfortNotes, "右肩前侧发紧")
        XCTAssertEqual(importedCheckIn.bodyMarkers.count, 2)
    }

    func testBackupAndCSVPreserveExerciseAndSessionVolumeUnits() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let run = Exercise(
            name: "测试折返跑",
            muscleGroup: "有氧",
            equipment: "无",
            volumeUnit: .meter
        )
        let jump = Exercise(
            name: "测试开合跳",
            muscleGroup: "有氧",
            equipment: "无",
            volumeUnit: .count
        )
        let hold = Exercise(
            name: "测试平板支撑",
            muscleGroup: "核心",
            equipment: "自重",
            volumeUnit: .second
        )
        let session = WorkoutSession(
            templateName: "有氧测试",
            plannedDate: .now,
            status: .completed
        )
        let runSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: run.id,
            exerciseName: run.name,
            order: 0,
            targetSets: 1,
            minReps: 2,
            maxReps: 2,
            targetWeight: 500,
            restSeconds: 60,
            volumeUnit: .meter
        )
        let jumpSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: jump.id,
            exerciseName: jump.name,
            order: 1,
            targetSets: 1,
            minReps: 40,
            maxReps: 40,
            targetWeight: 0,
            restSeconds: 30,
            volumeUnit: .count
        )
        let holdSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: hold.id,
            exerciseName: hold.name,
            order: 2,
            targetSets: 1,
            minReps: 45,
            maxReps: 45,
            targetWeight: 0,
            restSeconds: 60,
            volumeUnit: .second
        )
        let logs = [
            SetLog(
                sessionID: session.id, sessionExerciseID: runSnapshot.id, exerciseID: run.id,
                setNumber: 1, targetWeight: 500, targetReps: 2, actualWeight: 500, actualReps: 2,
                isCompleted: true
            ),
            SetLog(
                sessionID: session.id, sessionExerciseID: jumpSnapshot.id, exerciseID: jump.id,
                setNumber: 1, targetWeight: 0, targetReps: 40, actualWeight: 0, actualReps: 40,
                isCompleted: true
            ),
            SetLog(
                sessionID: session.id, sessionExerciseID: holdSnapshot.id, exerciseID: hold.id,
                setNumber: 1, targetWeight: 0, targetReps: 45, actualWeight: 0, actualReps: 45,
                isCompleted: true
            )
        ]
        context.insert(run)
        context.insert(jump)
        context.insert(hold)
        context.insert(session)
        context.insert(runSnapshot)
        context.insert(jumpSnapshot)
        context.insert(holdSnapshot)
        logs.forEach(context.insert)
        try context.save()

        let backup = try Data(contentsOf: DataExportService.createBackup(in: context))
        let csv = try String(contentsOf: DataExportService.createCSV(in: context), encoding: .utf8)
        XCTAssertTrue(csv.contains("volume_unit"))
        XCTAssertTrue(csv.contains(",meter,"))
        XCTAssertTrue(csv.contains(",count,"))
        XCTAssertTrue(csv.contains(",second,"))

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(backup, into: destination.mainContext)
        let importedExercises = try destination.mainContext.fetch(FetchDescriptor<Exercise>())
        let importedSnapshots = try destination.mainContext.fetch(FetchDescriptor<SessionExercise>())

        XCTAssertEqual(importedExercises.first(where: { $0.name == run.name })?.volumeUnit, .meter)
        XCTAssertEqual(importedExercises.first(where: { $0.name == jump.name })?.volumeUnit, .count)
        XCTAssertEqual(importedExercises.first(where: { $0.name == hold.name })?.volumeUnit, .second)
        XCTAssertEqual(importedSnapshots.first(where: { $0.exerciseName == run.name })?.volumeUnit, .meter)
        XCTAssertEqual(importedSnapshots.first(where: { $0.exerciseName == jump.name })?.volumeUnit, .count)
        XCTAssertEqual(importedSnapshots.first(where: { $0.exerciseName == hold.name })?.volumeUnit, .second)
    }

    func testLegacyBackupWithoutVolumeUnitDefaultsToKilogram() throws {
        let source = try makeContainer()
        let exercise = Exercise(
            name: "旧版动作",
            muscleGroup: "背部",
            equipment: "器械",
            volumeUnit: .meter
        )
        source.mainContext.insert(exercise)
        try source.mainContext.save()

        let currentData = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))
        let currentJSON = try XCTUnwrap(String(data: currentData, encoding: .utf8))
        let legacyJSON = currentJSON.replacingOccurrences(
            of: "volumeUnitRaw",
            with: "legacyVolumeUnitRaw"
        )
        XCTAssertFalse(legacyJSON.contains("\"volumeUnitRaw\""))

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(Data(legacyJSON.utf8), into: destination.mainContext)
        let restored = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<Exercise>()).first
        )
        XCTAssertEqual(restored.volumeUnit, .kilogram)
    }

    func testWorkoutFeelingHasFiveOrderedEmojiAndSurvivesBackup() throws {
        XCTAssertEqual(WorkoutFeeling.allCases.count, 5)
        XCTAssertEqual(WorkoutFeeling.allCases.map(\.emoji), ["😣", "😥", "😮", "🙂", "😄"])

        let source = try makeContainer()
        let exercise = Exercise(name: "测试推举", muscleGroup: "肩部", equipment: "哑铃")
        let session = WorkoutSession(templateName: "测试", plannedDate: .now)
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 10,
            targetWeight: 10,
            restSeconds: 60,
            feeling: .painful
        )
        source.mainContext.insert(exercise)
        source.mainContext.insert(session)
        source.mainContext.insert(snapshot)
        try source.mainContext.save()

        let data = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        let imported = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first
        )
        XCTAssertEqual(imported.feeling, .painful)
    }

    func testDailyBodyCheckInNormalizesScoreAndMarkers() {
        let checkIn = DailyBodyCheckIn(
            conditionScore: 9,
            bodyMarkers: [
                BodyMapMarker(regionID: "front-left-knee", kind: .jointFascia),
                BodyMapMarker(regionID: "front-left-knee", kind: .jointFascia)
            ]
        )

        XCTAssertEqual(checkIn.conditionScore, 5)
        XCTAssertEqual(checkIn.bodyMarkers, [
            BodyMapMarker(regionID: "front-left-knee", kind: .jointFascia)
        ])
    }

    func testDailyBodyCheckInClampsBothBoundsAndNormalizesDate() {
        let rawDate = Date(timeIntervalSince1970: 1_800_123_456)
        let low = DailyBodyCheckIn(date: rawDate, conditionScore: Int.min)
        let high = DailyBodyCheckIn(date: rawDate, conditionScore: Int.max)

        XCTAssertEqual(low.conditionScore, 1)
        XCTAssertEqual(high.conditionScore, 5)
        XCTAssertEqual(low.date, rawDate.startOfDay)
        XCTAssertEqual(high.date, rawDate.startOfDay)
    }

    func testDailyBodyCheckInInvalidMarkerJSONFailsClosed() {
        let checkIn = DailyBodyCheckIn(conditionScore: 3)
        checkIn.bodyMarkersJSON = "{not-json"

        XCTAssertEqual(checkIn.bodyMarkers, [])
    }

    func testDailyBodyCheckInSupportsAreaAndJointMarkerOnSameRegion() {
        let checkIn = DailyBodyCheckIn(
            conditionScore: 3,
            bodyMarkers: [
                BodyMapMarker(regionID: "front-right-shoulder", kind: .area),
                BodyMapMarker(regionID: "front-right-shoulder", kind: .jointFascia)
            ]
        )

        XCTAssertEqual(Set(checkIn.bodyMarkers.map(\.id)), [
            "front-right-shoulder:area",
            "front-right-shoulder:jointFascia"
        ])
    }

    func testDailyBodyCheckInServiceUpsertsSameDayAndTrimsNotes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = Date(timeIntervalSince1970: 1_800_100_000)
        let preferred = DailyBodyCheckIn(date: day, conditionScore: 2, discomfortNotes: "旧备注")
        let duplicate = DailyBodyCheckIn(date: day.addingTimeInterval(3_600), conditionScore: 5)
        let tomorrow = DailyBodyCheckIn(date: day.addingDays(1), conditionScore: 4)
        context.insert(preferred)
        context.insert(duplicate)
        context.insert(tomorrow)
        try context.save()

        try DailyBodyCheckInService.save(
            existing: preferred,
            date: day,
            conditionScore: 6,
            discomfortNotes: "  右肩前侧发紧  \n",
            bodyMarkers: [
                BodyMapMarker(regionID: "front-right-shoulder", kind: .area),
                BodyMapMarker(regionID: "front-right-shoulder", kind: .jointFascia)
            ],
            in: context
        )

        let records = try context.fetch(FetchDescriptor<DailyBodyCheckIn>())
        XCTAssertEqual(records.filter { $0.date.isSameDay(as: day) }.count, 1)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(preferred.conditionScore, 5)
        XCTAssertEqual(preferred.discomfortNotes, "右肩前侧发紧")
        XCTAssertEqual(preferred.bodyMarkers.count, 2)
    }

    func testBodyRegionCatalogIsCompleteUniqueAndWithinBounds() {
        let regions = BodyRegionCatalog.all
        XCTAssertEqual(regions.count, 34)
        XCTAssertEqual(Set(regions.map(\.id)).count, 34)
        XCTAssertEqual(regions.filter { $0.side == .front }.count, 17)
        XCTAssertEqual(regions.filter { $0.side == .back }.count, 17)

        for region in regions {
            XCTAssertTrue((0...1).contains(region.x), region.id)
            XCTAssertTrue((0...1).contains(region.y), region.id)
            XCTAssertTrue((0...1).contains(region.width), region.id)
            XCTAssertTrue((0...1).contains(region.height), region.id)
        }

        for left in regions where left.id.contains("left") {
            let rightID = left.id.replacingOccurrences(of: "left", with: "right")
            guard let right = regions.first(where: { $0.id == rightID }) else {
                return XCTFail("缺少对称区域：\(left.id)")
            }
            XCTAssertEqual(left.x + right.x, 1, accuracy: 0.001, left.id)
            XCTAssertEqual(left.y, right.y, accuracy: 0.001, left.id)
        }
    }

    func testBodyRegionImageLayoutMapsFrontAndBackOntoSharedAnatomyAsset() throws {
        let front = try XCTUnwrap(BodyRegionCatalog.definition(for: "front-right-shoulder"))
        let back = try XCTUnwrap(BodyRegionCatalog.definition(for: "back-left-glute"))

        let frontPlacement = BodyRegionImageLayout.placement(for: front)
        XCTAssertEqual(frontPlacement.x, 0.3684, accuracy: 0.0001)
        XCTAssertEqual(frontPlacement.y, 0.2516, accuracy: 0.0001)
        XCTAssertEqual(frontPlacement.width, 0.0884, accuracy: 0.0001)
        XCTAssertEqual(frontPlacement.height, 0.0690, accuracy: 0.0001)

        let backPlacement = BodyRegionImageLayout.placement(for: back)
        XCTAssertEqual(backPlacement.x, 0.6855, accuracy: 0.0001)
        XCTAssertEqual(backPlacement.y, 0.5828, accuracy: 0.0001)
        XCTAssertEqual(backPlacement.width, 0.0935, accuracy: 0.0001)
        XCTAssertEqual(backPlacement.height, 0.1104, accuracy: 0.0001)

        for region in BodyRegionCatalog.all {
            let placement = BodyRegionImageLayout.placement(for: region)
            XCTAssertTrue((0...1).contains(placement.x), region.id)
            XCTAssertTrue((0...1).contains(placement.y), region.id)
            XCTAssertGreaterThan(placement.width, 0, region.id)
            XCTAssertGreaterThan(placement.height, 0, region.id)
        }
    }

    func testBodyMarkerInferenceDisambiguatesFrontBackAndIgnoresNegation() {
        let result = BodyRegionCatalog.inferMarkers(
            in: "右肩前侧抬手疼，但左膝不疼",
            kind: .area
        )

        XCTAssertEqual(result.markers, [
            BodyMapMarker(regionID: "front-right-shoulder", kind: .area)
        ])
        XCTAssertFalse(result.requiresConfirmation)
        XCTAssertEqual(result.ignoredNegatedTerms, ["左膝不疼"])
    }

    func testBodyMarkerInferenceRequiresConfirmationForAmbiguousRegion() {
        let result = BodyRegionCatalog.inferMarkers(in: "右肩疼", kind: .jointFascia)

        XCTAssertTrue(result.markers.isEmpty)
        XCTAssertEqual(result.unresolvedTerms, ["肩部"])
        XCTAssertTrue(result.requiresConfirmation)
    }

    func testBodyMarkerInferenceSupportsBilateralAndMultipleSpecificRegions() {
        let result = BodyRegionCatalog.inferMarkers(
            in: "双侧肩前侧酸，左膝后侧紧",
            kind: .area
        )

        XCTAssertEqual(Set(result.markers.map(\.regionID)), [
            "front-left-shoulder",
            "front-right-shoulder",
            "back-left-knee"
        ])
        XCTAssertFalse(result.requiresConfirmation)
    }

    func testBackupImportKeepsOneBodyCheckInPerDay() throws {
        let source = try makeContainer()
        // The former fixed timestamp plus two hours crosses midnight in Sydney.
        // This test requires two readings on the same current-calendar day.
        let day = try XCTUnwrap(Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now))
        XCTAssertTrue(Calendar.current.isDate(day, inSameDayAs: day.addingTimeInterval(7_200)))
        source.mainContext.insert(DailyBodyCheckIn(date: day, conditionScore: 2))
        source.mainContext.insert(DailyBodyCheckIn(date: day.addingTimeInterval(7_200), conditionScore: 4))
        try source.mainContext.save()
        let data = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))

        let destination = try makeContainer()
        let summary = try DataExportService.importBackup(data, into: destination.mainContext)
        let imported = try destination.mainContext.fetch(FetchDescriptor<DailyBodyCheckIn>())

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.skipped, 1)
    }

    func testUnknownWorkoutFeelingDoesNotBlockBackupImport() throws {
        let source = try makeContainer()
        let exercise = Exercise(name: "未知体验测试", muscleGroup: "背部", equipment: "器械")
        let session = WorkoutSession(templateName: "未知体验", plannedDate: .now)
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 20,
            restSeconds: 60,
            feeling: .painful
        )
        source.mainContext.insert(exercise)
        source.mainContext.insert(session)
        source.mainContext.insert(snapshot)
        try source.mainContext.save()

        let original = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var snapshots = try XCTUnwrap(object["sessionExercises"] as? [[String: Any]])
        snapshots[0]["feelingRaw"] = "future-feeling"
        object["sessionExercises"] = snapshots
        let modified = try JSONSerialization.data(withJSONObject: object)

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(modified, into: destination.mainContext)
        let imported = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first
        )
        XCTAssertNil(imported.feeling)
        XCTAssertEqual(imported.exerciseName, "未知体验测试")
    }

    func testJSONImportKeepsExistingNutritionTargetSingleton() throws {
        let source = try makeContainer()
        source.mainContext.insert(NutritionTarget(
            calories: 2_600,
            proteinGrams: 180,
            carbsGrams: 300,
            fatGrams: 75
        ))
        try source.mainContext.save()
        let data = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))

        let destination = try makeContainer()
        let currentTarget = NutritionTarget(
            calories: 2_100,
            proteinGrams: 150,
            carbsGrams: 220,
            fatGrams: 65
        )
        destination.mainContext.insert(currentTarget)
        try destination.mainContext.save()

        let summary = try DataExportService.importBackup(data, into: destination.mainContext)
        let targets = try destination.mainContext.fetch(FetchDescriptor<NutritionTarget>())

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.id, currentTarget.id)
        XCTAssertEqual(targets.first?.calories, 2_100)
        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.skipped, 1)
    }

    func testShareDraftInboxOnlyClearsMatchingDraft() throws {
        let suiteName = "xfit-share-inbox-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let draft = ExerciseShareDraft(
            sharedText: "单臂绳索下拉\n保持肩胛下沉",
            sourceURL: URL(string: "https://example.com/pulldown")
        )
        defaults.set(
            try JSONEncoder().encode(draft),
            forKey: ExerciseShareDraftStorage.pendingDraftKey
        )
        let inbox = ExerciseShareDraftInbox(defaults: defaults)

        XCTAssertEqual(inbox.pendingDraft(), draft)
        XCTAssertEqual(inbox.pendingDraft()?.suggestedExerciseName, "单臂绳索下拉")
        inbox.clearPendingDraft(matching: UUID())
        XCTAssertNotNil(inbox.pendingDraft())
        inbox.clearPendingDraft(matching: draft.id)
        XCTAssertNil(inbox.pendingDraft())
    }

    func testDiscardRestoresScheduleWithoutCompletedHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "测试", weekday: Date.now.weekdayNumber)
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: .now,
            status: .inProgress
        )
        let session = WorkoutSession(
            scheduledWorkoutID: schedule.id,
            templateID: template.id,
            templateName: template.name,
            plannedDate: .now
        )
        context.insert(template)
        context.insert(schedule)
        context.insert(session)

        try WorkoutService.discard(session: session, schedules: [schedule], in: context)

        XCTAssertEqual(session.status, .discarded)
        XCTAssertEqual(schedule.status, .planned)
        XCTAssertNotNil(session.completedAt)
    }

    func testScheduledBackfillRestoresDiscardedSessionInPlaceAndIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_789_318_800).startOfDay
        let exercise = Exercise(
            name: "前蹲",
            muscleGroup: "腿部",
            equipment: "杠铃",
            defaultRestSeconds: 150,
            volumeUnit: .kilogram
        )
        let template = WorkoutTemplate(name: "下肢前链＋足踝", weekday: date.weekdayNumber)
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: date,
            status: .planned
        )
        let session = WorkoutSession(
            scheduledWorkoutID: schedule.id,
            templateID: template.id,
            templateName: template.name,
            plannedDate: date,
            startedAt: date.addingTimeInterval(86_400),
            completedAt: date.addingTimeInterval(90_000),
            status: .discarded
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 2,
            minReps: 5,
            maxReps: 8,
            targetWeight: 0,
            restSeconds: 150,
            muscleGroup: exercise.muscleGroup,
            volumeUnit: .kilogram
        )
        let firstLog = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 0,
            targetReps: 5,
            actualWeight: 0,
            actualReps: 5
        )
        let secondLog = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 2,
            targetWeight: 0,
            targetReps: 5,
            actualWeight: 0,
            actualReps: 5
        )
        context.insert(exercise)
        context.insert(template)
        context.insert(schedule)
        context.insert(session)
        context.insert(snapshot)
        context.insert(firstLog)
        context.insert(secondLog)
        try context.save()

        let input = ScheduledWorkoutBackfillInput(
            scheduleID: schedule.id,
            existingSessionID: session.id,
            name: template.name,
            date: date,
            startedAt: nil,
            durationMinutes: nil,
            notes: "周一实际完成",
            exercises: [
                ScheduledWorkoutBackfillExerciseInput(
                    existingSnapshotID: snapshot.id,
                    exerciseID: exercise.id,
                    sets: [
                        ScheduledWorkoutBackfillSetInput(
                            existingLogID: firstLog.id,
                            weight: 25,
                            reps: 8,
                            rir: 3,
                            weightSide: .bilateral,
                            repsSide: .bilateral
                        ),
                        ScheduledWorkoutBackfillSetInput(
                            existingLogID: secondLog.id,
                            weight: 25,
                            reps: 8,
                            rir: 3,
                            weightSide: .bilateral,
                            repsSide: .bilateral
                        )
                    ],
                    performanceNotes: "杠铃总重",
                    feeling: .good,
                    isWarmup: false
                )
            ]
        )

        let firstResult = try HistoricalWorkoutService.recordScheduledBackfill(input, in: context)
        let secondResult = try HistoricalWorkoutService.recordScheduledBackfill(input, in: context)

        XCTAssertEqual(firstResult.id, session.id)
        XCTAssertEqual(secondResult.id, session.id)
        XCTAssertEqual(schedule.status, .completed)
        XCTAssertEqual(session.status, .completed)
        XCTAssertFalse(session.isStartTimeKnown)
        XCTAssertNil(session.completedAt)
        XCTAssertEqual(session.notes, "周一实际完成")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).map(\.id), [snapshot.id])
        let logs = try context.fetch(FetchDescriptor<SetLog>()).sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(logs.map(\.id), [firstLog.id, secondLog.id])
        XCTAssertEqual(logs.map(\.actualWeight), [25, 25])
        XCTAssertEqual(logs.map(\.actualReps), [8, 8])
        XCTAssertEqual(logs.map(\.rir), [3, 3])
        XCTAssertTrue(logs.allSatisfy(\.isCompleted))
    }

    func testManualScheduleFreezesExercisePlanForLaterBackfill() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_789_405_200).startOfDay
        let exercise = Exercise(
            name: "钟摆深蹲",
            muscleGroup: "腿部",
            equipment: "器械",
            defaultRestSeconds: 120,
            notes: "保持躯干稳定",
            volumeUnit: .kilogram
        )
        let template = WorkoutTemplate(name: "下肢前链", weekday: date.weekdayNumber)
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 10,
            targetWeight: 55,
            restSeconds: 120,
            plannedSets: [
                WorkoutSetPlan(weight: 55, reps: 8),
                WorkoutSetPlan(weight: 55, reps: 8),
                WorkoutSetPlan(weight: 55, reps: 8)
            ]
        )
        context.insert(exercise)
        context.insert(template)
        context.insert(item)
        try context.save()

        let schedule = try ScheduleService.addManual(template: template, on: date, in: context)
        item.plannedSets = [WorkoutSetPlan(weight: 80, reps: 5)]
        exercise.name = "模板后来改名"
        try context.save()

        let frozen = try XCTUnwrap(schedule.planSnapshot.first)
        XCTAssertEqual(schedule.planSnapshot.count, 1)
        XCTAssertEqual(frozen.exerciseName, "钟摆深蹲")
        XCTAssertEqual(frozen.volumeUnit, .kilogram)
        XCTAssertEqual(frozen.restSeconds, 120)
        XCTAssertEqual(frozen.plannedSets.map(\.weight), [55, 55, 55])
        XCTAssertEqual(frozen.plannedSets.map(\.reps), [8, 8, 8])
        let preparation = try HistoricalWorkoutService.prepareScheduledBackfill(
            scheduleID: schedule.id,
            in: context
        )
        XCTAssertEqual(preparation.name, "下肢前链")
        XCTAssertEqual(preparation.exercises.count, 1)
        XCTAssertEqual(preparation.exercises[0].sets.map(\.weight), [55, 55, 55])
        XCTAssertEqual(preparation.exercises[0].sets.map(\.reps), [8, 8, 8])
    }

    func testPastSkippedJumpRopeScheduleCanBeBackfilledOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_789_491_600).startOfDay
        let schedule = ScheduledWorkout(
            templateID: UUID(),
            templateName: "跳绳",
            plannedDate: date,
            status: .skipped,
            skipReason: "临时有事"
        )
        context.insert(schedule)
        try context.save()

        _ = try WellnessToolService.recordJumpRope(
            count: 1_200,
            activeDurationSeconds: 600,
            elapsedDurationSeconds: 900,
            at: date.addingTimeInterval(20 * 3_600),
            scheduledWorkoutID: schedule.id,
            in: context
        )

        XCTAssertEqual(schedule.status, .completed)
        XCTAssertEqual(schedule.skipReason, "")
        XCTAssertEqual(try context.fetch(FetchDescriptor<JumpRopeEntry>()).count, 1)
        XCTAssertThrowsError(try WellnessToolService.recordJumpRope(
            count: 1_200,
            activeDurationSeconds: nil,
            elapsedDurationSeconds: nil,
            at: date.addingTimeInterval(21 * 3_600),
            scheduledWorkoutID: schedule.id,
            in: context
        ))
        XCTAssertEqual(try context.fetch(FetchDescriptor<JumpRopeEntry>()).count, 1)
    }

    func testConfirmedSeptemberBackfillPreservesExistingRowsAndIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let workoutDate = FatLossCalendar.date(2026, 9, 14)
        let ropeDate = FatLossCalendar.date(2026, 9, 19)
        let template = WorkoutTemplate(name: "下肢前链＋足踝", weekday: workoutDate.weekdayNumber)
        let workoutSchedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: workoutDate
        )
        let session = WorkoutSession(
            scheduledWorkoutID: workoutSchedule.id,
            templateID: template.id,
            templateName: template.name,
            plannedDate: workoutDate,
            startedAt: workoutDate.addingDays(1),
            completedAt: workoutDate.addingDays(1).addingTimeInterval(3_600),
            status: .discarded
        )
        context.insert(template)
        context.insert(workoutSchedule)
        context.insert(session)

        let specs: [(String, ExerciseVolumeUnit, Int, Int, Double)] = [
            ("膝触墙踝背屈", .count, 2, 8, 0),
            ("前蹲", .kilogram, 4, 5, 0),
            ("钟摆深蹲", .kilogram, 3, 8, 0),
            ("保加利亚分腿蹲", .kilogram, 3, 8, 0),
            ("腿屈伸", .kilogram, 3, 12, 0),
            ("坐姿比目鱼肌等长", .second, 3, 30, 0),
            ("胫骨前肌抬脚", .count, 2, 12, 0),
            ("农夫走", .meter, 6, 1, 30)
        ]
        var originalSnapshotIDs = Set<UUID>()
        var originalLogIDs = Set<UUID>()
        for (order, spec) in specs.enumerated() {
            let exercise = Exercise(
                name: spec.0,
                muscleGroup: spec.0 == "农夫走" ? "全身" : "腿部",
                equipment: "测试器械",
                defaultRestSeconds: 90,
                volumeUnit: spec.1
            )
            let snapshot = SessionExercise(
                sessionID: session.id,
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                order: order,
                targetSets: spec.2,
                minReps: spec.3,
                maxReps: spec.3,
                targetWeight: spec.4,
                restSeconds: 90,
                muscleGroup: exercise.muscleGroup,
                volumeUnit: spec.1
            )
            context.insert(exercise)
            context.insert(snapshot)
            originalSnapshotIDs.insert(snapshot.id)
            for index in 0..<spec.2 {
                let log = SetLog(
                    sessionID: session.id,
                    sessionExerciseID: snapshot.id,
                    exerciseID: exercise.id,
                    setNumber: index + 1,
                    targetWeight: spec.4,
                    targetReps: spec.3,
                    actualWeight: spec.4,
                    actualReps: spec.3,
                    isCompleted: spec.0 == "膝触墙踝背屈"
                )
                context.insert(log)
                originalLogIDs.insert(log.id)
            }
        }
        let ropeSchedule = ScheduledWorkout(
            templateID: UUID(),
            templateName: "跳绳混合间歇 · 燃脂",
            plannedDate: ropeDate
        )
        let ropeLink = ProgramWorkoutLink(
            programID: UUID(),
            scheduledWorkoutID: ropeSchedule.id,
            templateCode: "ROPE_SAT_LB3",
            originalDate: ropeDate
        )
        context.insert(ropeSchedule)
        context.insert(ropeLink)
        try context.save()

        let first = try ConfirmedHistoricalBackfillService.apply(in: context)
        let second = try ConfirmedHistoricalBackfillService.apply(in: context)

        XCTAssertEqual(first.workoutSessionID, session.id)
        XCTAssertEqual(second.workoutSessionID, session.id)
        XCTAssertEqual(first.createdExerciseCount, 3)
        XCTAssertEqual(second.createdExerciseCount, 0)
        XCTAssertEqual(session.status, .completed)
        XCTAssertFalse(session.isStartTimeKnown)
        XCTAssertNil(session.completedAt)
        XCTAssertEqual(workoutSchedule.status, .completed)
        XCTAssertEqual(ropeSchedule.status, .skipped)
        XCTAssertEqual(ropeSchedule.skipReason, "拼家具")
        XCTAssertTrue(try context.fetch(FetchDescriptor<JumpRopeEntry>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        let storedSnapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let storedLogs = try context.fetch(FetchDescriptor<SetLog>())
        XCTAssertEqual(storedSnapshots.count, 11)
        XCTAssertEqual(storedLogs.count, 30)
        XCTAssertTrue(originalSnapshotIDs.isSubset(of: Set(storedSnapshots.map(\.id))))
        XCTAssertTrue(originalLogIDs.isSubset(of: Set(storedLogs.map(\.id))))
        let front = try XCTUnwrap(storedSnapshots.first { $0.exerciseName == "前蹲" })
        let frontLogs = storedLogs.filter { $0.sessionExerciseID == front.id }
            .sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(frontLogs.map(\.actualWeight), [25, 25, 25, 25])
        XCTAssertEqual(frontLogs.map(\.actualReps), [8, 8, 8, 8])
        XCTAssertEqual(frontLogs.map(\.rir), [3, 3, 3, 3])
    }

    func testFreestyleRestRecordsBoundaryWhenNextSetStarts() {
        let base = Date(timeIntervalSince1970: 1_800_100_000)
        let session = WorkoutSession(
            templateName: "自由训练",
            plannedDate: base,
            restMode: .freestyle
        )
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let second = makeSet(sessionID: session.id, setNumber: 2)
        let logs = [first, second]

        WorkoutRestTracking.startSet(first, session: session, logs: logs, at: base)
        first.isCompleted = true
        first.completedAt = base.addingTimeInterval(40)
        WorkoutRestTracking.begin(
            after: first,
            session: session,
            logs: logs,
            plannedRestSeconds: 120,
            at: base.addingTimeInterval(40)
        )

        XCTAssertNil(session.restEndDate)
        XCTAssertEqual(WorkoutRestTracking.activeLog(in: logs)?.id, first.id)

        let recorded = WorkoutRestTracking.startSet(
            second,
            session: session,
            logs: logs,
            at: base.addingTimeInterval(125)
        )

        XCTAssertEqual(recorded, 85)
        XCTAssertEqual(first.restDurationSeconds, 85)
        XCTAssertEqual(first.restEndedAt, base.addingTimeInterval(125))
        XCTAssertEqual(second.startedAt, base.addingTimeInterval(125))
        XCTAssertNil(WorkoutRestTracking.activeLog(in: logs))
    }

    func testCountdownRestRecordsAdjustedActualDuration() {
        let base = Date(timeIntervalSince1970: 1_800_200_000)
        let session = WorkoutSession(
            templateName: "固定倒计时",
            plannedDate: base,
            restMode: .countdown
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)

        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: 120,
            at: base
        )
        XCTAssertEqual(session.restEndDate, base.addingTimeInterval(120))

        let recorded = WorkoutRestTracking.finish(
            session: session,
            logs: [log],
            at: base.addingTimeInterval(75)
        )

        XCTAssertEqual(recorded, 75)
        XCTAssertEqual(log.restDurationSeconds, 75)
        XCTAssertNil(session.restEndDate)
    }

    func testStartingAnotherRestDoesNotInventDurationForMissedTap() {
        let base = Date(timeIntervalSince1970: 1_800_300_000)
        let session = WorkoutSession(
            templateName: "漏点保护",
            plannedDate: base,
            restMode: .freestyle
        )
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let second = makeSet(sessionID: session.id, setNumber: 2)
        let logs = [first, second]

        WorkoutRestTracking.begin(
            after: first,
            session: session,
            logs: logs,
            plannedRestSeconds: 90,
            at: base
        )
        WorkoutRestTracking.begin(
            after: second,
            session: session,
            logs: logs,
            plannedRestSeconds: 90,
            at: base.addingTimeInterval(180)
        )

        XCTAssertNil(first.restDurationSeconds)
        XCTAssertNil(first.restStartedAt)
        XCTAssertEqual(WorkoutRestTracking.activeLog(in: logs)?.id, second.id)
    }

    func testFreestyleRestFinishIsIdempotent() {
        let base = Date(timeIntervalSince1970: 1_800_350_000)
        let session = WorkoutSession(
            templateName: "幂等结束",
            plannedDate: base,
            restMode: .freestyle
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)

        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: 90,
            at: base
        )
        let firstResult = WorkoutRestTracking.finish(
            session: session,
            logs: [log],
            at: base.addingTimeInterval(42)
        )
        let secondResult = WorkoutRestTracking.finish(
            session: session,
            logs: [log],
            at: base.addingTimeInterval(90)
        )

        XCTAssertEqual(firstResult, 42)
        XCTAssertNil(secondResult)
        XCTAssertEqual(log.restDurationSeconds, 42)
        XCTAssertEqual(log.restEndedAt, base.addingTimeInterval(42))
        XCTAssertNil(session.restEndDate)
    }

    func testAbandonFreestyleRestClearsProvisionalTiming() {
        let base = Date(timeIntervalSince1970: 1_800_360_000)
        let session = WorkoutSession(
            templateName: "稍后补录",
            plannedDate: base,
            restMode: .freestyle
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)

        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: 90,
            at: base
        )
        WorkoutRestTracking.abandon(session: session, logs: [log])

        XCTAssertNil(log.restStartedAt)
        XCTAssertNil(log.restEndedAt)
        XCTAssertNil(log.restDurationSeconds)
        XCTAssertNil(WorkoutRestTracking.activeLog(in: [log]))
        XCTAssertNil(session.restEndDate)
    }

    func testStartingSetWithoutActiveRestDoesNotInventDuration() {
        let base = Date(timeIntervalSince1970: 1_800_370_000)
        let session = WorkoutSession(
            templateName: "无休息直接开组",
            plannedDate: base,
            restMode: .freestyle
        )
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let second = makeSet(sessionID: session.id, setNumber: 2)
        first.startedAt = base.addingTimeInterval(-20)

        let recorded = WorkoutRestTracking.startSet(
            second,
            session: session,
            logs: [first, second],
            at: base
        )

        XCTAssertNil(recorded)
        XCTAssertNil(first.startedAt)
        XCTAssertEqual(second.startedAt, base)
        XCTAssertNil(first.restDurationSeconds)
        XCTAssertNil(second.restDurationSeconds)
    }

    func testCountdownNegativePlannedRestClampsToImmediateBoundary() {
        let base = Date(timeIntervalSince1970: 1_800_380_000)
        let session = WorkoutSession(
            templateName: "非法倒计时保护",
            plannedDate: base,
            restMode: .countdown
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)

        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: -30,
            at: base
        )

        XCTAssertEqual(session.restEndDate, base)
        XCTAssertEqual(log.restStartedAt, base)
        XCTAssertNil(log.restDurationSeconds)
    }

    func testHistoricalBackfillIgnoresLegacyRestInputAndWritesNoNewRestValues() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "补录测试动作", muscleGroup: "背部", equipment: "器械")
        context.insert(exercise)

        let input = HistoricalWorkoutInput(
            name: "补录休息测试",
            startedAt: Date(timeIntervalSince1970: 1_800_390_000),
            durationMinutes: 30,
            notes: "",
            exercises: [
                HistoricalExerciseInput(
                    exerciseID: exercise.id,
                    sets: [
                        HistoricalSetInput(weight: 30, reps: 10, rir: 2, restDurationSeconds: 0),
                        HistoricalSetInput(
                            weight: 30,
                            reps: 9,
                            rir: 1,
                            restDurationSeconds: RestDurationInput.maximumSeconds
                        ),
                        HistoricalSetInput(weight: 30, reps: 8, rir: 0, restDurationSeconds: nil)
                    ],
                    performanceNotes: ""
                )
            ]
        )

        let session = try HistoricalWorkoutService.record(input, in: context)
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionID == session.id }
            .sorted { $0.setNumber < $1.setNumber }

        XCTAssertEqual(logs.map(\.restDurationSeconds), [nil, nil, nil])
        XCTAssertTrue(logs.allSatisfy(\.isCompleted))
    }

    func testHistoricalBackfillRejectsOutOfRangeRestValues() throws {
        for invalidValue in [-1, RestDurationInput.maximumSeconds + 1] {
            let container = try makeContainer()
            let context = container.mainContext
            let exercise = Exercise(name: "非法补录 \(invalidValue)", muscleGroup: "背部", equipment: "器械")
            context.insert(exercise)
            let input = HistoricalWorkoutInput(
                name: "非法休息",
                startedAt: Date(timeIntervalSince1970: 1_800_395_000),
                durationMinutes: 30,
                notes: "",
                exercises: [
                    HistoricalExerciseInput(
                        exerciseID: exercise.id,
                        sets: [
                            HistoricalSetInput(
                                weight: 30,
                                reps: 10,
                                rir: 2,
                                restDurationSeconds: invalidValue
                            )
                        ],
                        performanceNotes: ""
                    )
                ]
            )

            XCTAssertThrowsError(try HistoricalWorkoutService.record(input, in: context)) { error in
                guard case HistoricalWorkoutServiceError.invalidRestDuration = error else {
                    return XCTFail("应拒绝超范围休息，实际错误：\(error)")
                }
            }
            XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
        }
    }

    func testHistoricalCSVRejectsNegativeRestDuration() throws {
        let container = try makeContainer()
        let csv = """
        session_id,date,workout,exercise,set,weight_kg,reps,rest_seconds
        negative-rest,2026-08-20T10:00:00Z,自由训练,深蹲,1,60,8,-1
        """

        XCTAssertThrowsError(
            try HistoricalWorkoutCSVService.preview(Data(csv.utf8), in: container.mainContext)
        ) { error in
            guard case let HistoricalWorkoutCSVError.invalidValue(line, field) = error else {
                return XCTFail("应拒绝负数组间休息，实际错误：\(error)")
            }
            XCTAssertEqual(line, 2)
            XCTAssertEqual(field, "rest_seconds")
        }
    }

    func testRestDurationInputRejectsSilentCharacterRewritingAndOverflow() {
        XCTAssertEqual(RestDurationInput.validate(""), .empty)
        XCTAssertEqual(RestDurationInput.validate(" 95 "), .valid(95))
        XCTAssertEqual(RestDurationInput.validate("0"), .valid(0))
        XCTAssertEqual(
            RestDurationInput.validate(String(RestDurationInput.maximumSeconds)),
            .valid(RestDurationInput.maximumSeconds)
        )

        for invalid in ["-30", "1a2", "１２", "1.5", "86 400", "999999999999999999999999"] {
            guard case .invalid = RestDurationInput.validate(invalid) else {
                return XCTFail("应严格拒绝而不是改写输入：\(invalid)")
            }
        }
        guard case .invalid = RestDurationInput.validate(
            String(RestDurationInput.maximumSeconds + 1)
        ) else {
            return XCTFail("应拒绝超过 24 小时的组间休息")
        }
    }

    func testReconcileMultipleActiveRestsKeepsOnlyNewestAndAbandonClearsAll() {
        let base = Date(timeIntervalSince1970: 1_800_397_000)
        let session = WorkoutSession(
            templateName: "脏状态收敛",
            plannedDate: base,
            restEndDate: base.addingTimeInterval(90),
            restMode: .freestyle
        )
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let second = makeSet(sessionID: session.id, setNumber: 2)
        let newest = makeSet(sessionID: session.id, setNumber: 3)
        first.restStartedAt = base
        second.restStartedAt = base.addingTimeInterval(10)
        newest.restStartedAt = base.addingTimeInterval(20)
        let logs = [first, second, newest]

        XCTAssertTrue(WorkoutRestTracking.reconcile(session: session, logs: logs))
        XCTAssertNil(first.restStartedAt)
        XCTAssertNil(second.restStartedAt)
        XCTAssertEqual(newest.restStartedAt, base.addingTimeInterval(20))
        XCTAssertEqual(WorkoutRestTracking.activeLogs(in: logs).map(\.id), [newest.id])
        XCTAssertNil(session.restEndDate)

        first.restStartedAt = base.addingTimeInterval(30)
        WorkoutRestTracking.abandon(session: session, logs: logs)
        XCTAssertTrue(WorkoutRestTracking.activeLogs(in: logs).isEmpty)
        XCTAssertTrue(logs.allSatisfy { $0.restDurationSeconds == nil })
    }

    func testClockRollbackProducesConsistentZeroLengthInterval() {
        let base = Date(timeIntervalSince1970: 1_800_398_000)
        let session = WorkoutSession(
            templateName: "时间回拨",
            plannedDate: base,
            restMode: .freestyle
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)
        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: 90,
            at: base
        )

        let duration = WorkoutRestTracking.finish(
            session: session,
            logs: [log],
            at: base.addingTimeInterval(-300)
        )

        XCTAssertEqual(duration, 0)
        XCTAssertEqual(log.restStartedAt, base)
        XCTAssertEqual(log.restEndedAt, base)
        XCTAssertEqual(log.restDurationSeconds, 0)
    }

    func testLastSetCompletionDoesNotStartOrphanRest() {
        let session = WorkoutSession(templateName: "最后一组", plannedDate: .now)
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let last = makeSet(sessionID: session.id, setNumber: 2)
        first.isCompleted = true
        last.isCompleted = true

        XCTAssertFalse(WorkoutRestTracking.shouldBeginRest(after: last, logs: [first, last]))
        first.isCompleted = false
        XCTAssertTrue(WorkoutRestTracking.shouldBeginRest(after: last, logs: [first, last]))
    }

    func testUndoCompletedSetClearsItsRecordedAndProvisionalRest() {
        let base = Date(timeIntervalSince1970: 1_800_398_500)
        let session = WorkoutSession(
            templateName: "撤销完成组",
            plannedDate: base,
            restMode: .freestyle
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)
        log.isCompleted = true
        log.restStartedAt = base
        log.restEndedAt = base.addingTimeInterval(30)
        log.restDurationSeconds = 30
        log.isCompleted = false
        log.completedAt = nil
        WorkoutRestTracking.clearRest(on: log)

        XCTAssertFalse(log.isCompleted)
        XCTAssertNil(log.completedAt)
        XCTAssertNil(log.restStartedAt)
        XCTAssertNil(log.restEndedAt)
        XCTAssertNil(log.restDurationSeconds)
        XCTAssertTrue(WorkoutRestTracking.activeLogs(in: [log]).isEmpty)
    }

    func testRestStateMachineIsStableAcrossOneHundredBoundaryCycles() {
        let base = Date(timeIntervalSince1970: 1_800_399_000)
        for index in 0..<100 {
            let session = WorkoutSession(
                templateName: "稳定性 \(index)",
                plannedDate: base,
                restMode: index.isMultiple(of: 2) ? .freestyle : .countdown
            )
            let first = makeSet(sessionID: session.id, setNumber: 1)
            let second = makeSet(sessionID: session.id, setNumber: 2)
            let startedAt = base.addingTimeInterval(TimeInterval(index * 10))
            WorkoutRestTracking.begin(
                after: first,
                session: session,
                logs: [first, second],
                plannedRestSeconds: index - 50,
                at: startedAt
            )
            let endedAt = index.isMultiple(of: 7)
                ? startedAt.addingTimeInterval(-1)
                : startedAt.addingTimeInterval(TimeInterval(index))
            let recorded = WorkoutRestTracking.startSet(
                second,
                session: session,
                logs: [first, second],
                at: endedAt
            )
            XCTAssertEqual(recorded, index.isMultiple(of: 7) ? 0 : index)
            XCTAssertEqual(first.restEndedAt, max(startedAt, endedAt))
            XCTAssertEqual(first.restDurationSeconds, recorded)
            XCTAssertEqual(second.startedAt, endedAt)
            XCTAssertTrue(WorkoutRestTracking.activeLogs(in: [first, second]).isEmpty)
        }
    }

    func testPersistentStoreRecoversActiveRestAfterContainerRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "XFit-Rest-Persistence-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "test.store")
        let sessionID = UUID()
        let logID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_399_500)

        var firstContainer: ModelContainer? = try makePersistentContainer(at: storeURL)
        do {
            let context = try XCTUnwrap(firstContainer).mainContext
            let session = WorkoutSession(
                id: sessionID,
                templateName: "强杀恢复",
                plannedDate: base,
                startedAt: base,
                restMode: .freestyle
            )
            let log = SetLog(
                id: logID,
                sessionID: session.id,
                sessionExerciseID: UUID(),
                exerciseID: UUID(),
                setNumber: 1,
                targetWeight: 50,
                targetReps: 10,
                actualWeight: 50,
                actualReps: 10,
                isCompleted: true,
                completedAt: base
            )
            context.insert(session)
            context.insert(log)
            WorkoutRestTracking.begin(
                after: log,
                session: session,
                logs: [log],
                plannedRestSeconds: 90,
                at: base
            )
            try context.save()
        }
        firstContainer = nil

        let reopened = try makePersistentContainer(at: storeURL)
        let context = reopened.mainContext
        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == sessionID }
        )
        let log = try XCTUnwrap(
            context.fetch(FetchDescriptor<SetLog>()).first { $0.id == logID }
        )
        XCTAssertEqual(log.restStartedAt, base)
        XCTAssertNil(log.restEndedAt)
        XCTAssertEqual(
            WorkoutRestTracking.finish(
                session: session,
                logs: [log],
                at: base.addingTimeInterval(45)
            ),
            45
        )
        try context.save()
        XCTAssertEqual(log.restDurationSeconds, 45)
    }

    func testRestNotificationReplacementAndCancellationAreExactlyOnce() async {
        let center = RecordingRestNotificationCenter()
        let sessionID = UUID()
        let identifier = NotificationService.restRequestIdentifier(sessionID: sessionID)

        for offset in [120.0, 150.0, 180.0] {
            let request = NotificationService.makeRestEndRequest(
                sessionID: sessionID,
                at: Date.now.addingTimeInterval(offset)
            )
            try? await NotificationService.replaceRestEndRequest(
                request,
                identifier: identifier,
                using: center
            )
        }
        let scheduled = await center.summary(for: identifier)
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.title, "休息结束")
        XCTAssertEqual(scheduled.repeats, false)

        await NotificationService.cancelRestEndRequest(identifier: identifier, using: center)
        let cancelled = await center.summary(for: identifier)
        XCTAssertEqual(cancelled.count, 0)
    }

    func testCSVExportIncludesAuthoritativeRestAndFreestyleMode() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_800_399_800)
        let exercise = Exercise(name: "导出动作", muscleGroup: "背部", equipment: "器械")
        let session = WorkoutSession(
            templateName: "导出自由训练",
            plannedDate: base,
            startedAt: base,
            completedAt: base.addingTimeInterval(600),
            status: .completed,
            restMode: .freestyle
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 30,
            restSeconds: 90,
            muscleGroup: exercise.muscleGroup
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 30,
            targetReps: 10,
            actualWeight: 30,
            actualReps: 10,
            isCompleted: true,
            completedAt: base,
            restDurationSeconds: 95
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        let csvURL = try DataExportService.createCSV(in: context)
        let rows = try String(contentsOf: csvURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let header = try XCTUnwrap(rows.first?.split(separator: ",").map(String.init))
        let values = try XCTUnwrap(rows.last?.split(separator: ",", omittingEmptySubsequences: false).map(String.init))
        let restIndex = try XCTUnwrap(header.firstIndex(of: "rest_seconds"))
        let modeIndex = try XCTUnwrap(header.firstIndex(of: "rest_mode"))
        XCTAssertEqual(values[restIndex], "95")
        XCTAssertEqual(values[modeIndex], WorkoutRestMode.freestyle.rawValue)
    }

    func testBackupRoundTripPreservesRestModeAndSetTiming() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let base = Date(timeIntervalSince1970: 1_800_400_000)
        let exercise = Exercise(name: "自由卧推", muscleGroup: "胸部", equipment: "杠铃")
        let session = WorkoutSession(
            templateName: "自由训练",
            plannedDate: base,
            startedAt: base,
            completedAt: base.addingTimeInterval(3_600),
            status: .completed,
            restMode: .freestyle
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 12,
            targetWeight: 60,
            restSeconds: 120,
            muscleGroup: exercise.muscleGroup
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 60,
            targetReps: 10,
            actualWeight: 60,
            actualReps: 10,
            isCompleted: true,
            startedAt: base.addingTimeInterval(300),
            completedAt: base.addingTimeInterval(340),
            restStartedAt: base.addingTimeInterval(340),
            restEndedAt: base.addingTimeInterval(430),
            restDurationSeconds: 90
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        let data = try Data(contentsOf: DataExportService.createBackup(in: context))
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)

        let restoredSession = try destination.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first
        let restoredLog = try destination.mainContext.fetch(FetchDescriptor<SetLog>()).first
        XCTAssertEqual(restoredSession?.restMode, .freestyle)
        XCTAssertEqual(restoredLog?.startedAt, log.startedAt)
        XCTAssertEqual(restoredLog?.restStartedAt, log.restStartedAt)
        XCTAssertEqual(restoredLog?.restEndedAt, log.restEndedAt)
        XCTAssertEqual(restoredLog?.restDurationSeconds, 90)
    }

    func testBackupRoundTripPreservesExerciseReferenceURLs() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let exercise = Exercise(
            name: "参考动作",
            muscleGroup: "核心",
            equipment: "自重",
            isBuiltIn: false,
            referenceURL: "https://example.com/exercise"
        )
        let session = WorkoutSession(
            templateName: "参考训练",
            plannedDate: .now,
            status: .completed
        )
        let bodyWeightSourceDate = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 0,
            restSeconds: 60,
            muscleGroup: exercise.muscleGroup,
            referenceURL: exercise.referenceURL,
            volumeUnit: .bodyweight,
            bodyWeightKgSnapshot: 87.4,
            bodyWeightSnapshotSourceDate: bodyWeightSourceDate
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(snapshot)
        try context.save()

        let data = try Data(contentsOf: DataExportService.createBackup(in: context))
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)

        XCTAssertEqual(
            try destination.mainContext.fetch(FetchDescriptor<Exercise>()).first?.referenceURL,
            exercise.referenceURL
        )
        XCTAssertEqual(
            try destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first?.referenceURL,
            exercise.referenceURL
        )
        let restoredSnapshot = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first
        )
        XCTAssertEqual(restoredSnapshot.bodyWeightKgSnapshot, 87.4)
        XCTAssertEqual(restoredSnapshot.bodyWeightSnapshotSourceDate, bodyWeightSourceDate)
    }

    func testDeviceHistoryMergePreservesAllSetStatesAndIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_800_000_000.123456)
        let phoneExercise = Exercise(
            name: "负重俯卧撑",
            muscleGroup: "胸部",
            equipment: "自重",
            volumeUnit: .bodyweight
        )
        let phoneTemplate = WorkoutTemplate(name: "推 · 胸肩三头", weekday: date.weekdayNumber)
        let phoneSchedule = ScheduledWorkout(
            templateID: phoneTemplate.id,
            templateName: phoneTemplate.name,
            plannedDate: date
        )
        context.insert(phoneExercise)
        context.insert(phoneTemplate)
        context.insert(phoneSchedule)
        try context.save()

        let sessionID = UUID()
        let snapshotID = UUID()
        let bodyWeightSourceDate = Date(timeIntervalSince1970: 1_799_000_000)
        let package = DeviceHistoryMergePackage(
            schemaVersion: 1,
            source: "test-simulator",
            sessions: [
                DeviceHistoryMergeSession(
                    id: sessionID,
                    templateName: phoneTemplate.name,
                    plannedDate: date,
                    startedAt: date.addingTimeInterval(1_800),
                    completedAt: date.addingTimeInterval(2_100),
                    startedAtTimeIntervalSince1970: date.addingTimeInterval(1_800).timeIntervalSince1970,
                    completedAtTimeIntervalSince1970: date.addingTimeInterval(2_100).timeIntervalSince1970,
                    statusRaw: WorkoutSessionStatus.completed.rawValue,
                    notes: "保留原备注",
                    restEndDate: nil,
                    importIdentifier: "",
                    exercises: [
                        DeviceHistoryMergeExercise(
                            id: snapshotID,
                            sourceExerciseID: UUID(),
                            exerciseName: phoneExercise.name,
                            order: 0,
                            targetSets: 2,
                            minReps: 8,
                            maxReps: 12,
                            targetWeight: 20,
                            restSeconds: 120,
                            muscleGroup: phoneExercise.muscleGroup,
                            equipment: phoneExercise.equipment,
                            exerciseNotes: "肩胛稳定",
                            referenceURL: "https://example.com/bench-press",
                            volumeUnitRaw: ExerciseVolumeUnit.bodyweight.rawValue,
                            performanceNotes: "第一组完成",
                            bodyWeightKgSnapshot: 87.4,
                            bodyWeightSnapshotSourceDate: bodyWeightSourceDate,
                            sets: [
                                DeviceHistoryMergeSet(
                                    id: UUID(),
                                    setNumber: 1,
                                    targetWeight: 20,
                                    targetReps: 10,
                                    actualWeight: 20,
                                    actualReps: 10,
                                    rir: 2,
                                    isWarmup: false,
                                    isCompleted: true,
                                    completedAt: date.addingTimeInterval(1_900),
                                    completedAtTimeIntervalSince1970: date.addingTimeInterval(1_900).timeIntervalSince1970
                                ),
                                DeviceHistoryMergeSet(
                                    id: UUID(),
                                    setNumber: 2,
                                    targetWeight: 20,
                                    targetReps: 10,
                                    actualWeight: 20,
                                    actualReps: 10,
                                    rir: nil,
                                    isWarmup: false,
                                    isCompleted: false,
                                    completedAt: nil
                                )
                            ]
                        )
                    ]
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(package)

        let first = try DeviceHistoryMergeService.importPackage(data, into: context)
        let second = try DeviceHistoryMergeService.importPackage(data, into: context)
        let importedSession = try context.fetch(FetchDescriptor<WorkoutSession>()).first
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())

        XCTAssertEqual(first.importedSessions, 1)
        XCTAssertEqual(first.importedSessionExercises, 1)
        XCTAssertEqual(first.importedSetLogs, 2)
        XCTAssertEqual(first.importedCompletedSetLogs, 1)
        XCTAssertEqual(first.updatedSchedules, 1)
        XCTAssertEqual(second.importedSessions, 0)
        XCTAssertEqual(second.skippedSessions, 1)
        XCTAssertEqual(importedSession?.id, sessionID)
        XCTAssertEqual(importedSession?.templateID, phoneTemplate.id)
        XCTAssertEqual(importedSession?.scheduledWorkoutID, phoneSchedule.id)
        XCTAssertNotNil(importedSession)
        XCTAssertEqual(
            importedSession!.startedAt.timeIntervalSince1970,
            date.addingTimeInterval(1_800).timeIntervalSince1970,
            accuracy: 0.000_001
        )
        XCTAssertEqual(snapshots.first?.id, snapshotID)
        XCTAssertEqual(snapshots.first?.exerciseID, phoneExercise.id)
        XCTAssertEqual(snapshots.first?.referenceURL, "https://example.com/bench-press")
        XCTAssertEqual(snapshots.first?.bodyWeightKgSnapshot, 87.4)
        XCTAssertEqual(snapshots.first?.bodyWeightSnapshotSourceDate, bodyWeightSourceDate)
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.filter(\.isCompleted).count, 1)
        XCTAssertEqual(phoneSchedule.status, .completed)
    }

    func testCloudRestorePreparationDoesNotSeedAnEmptyStore() throws {
        let container = try makeContainer()
        let context = container.mainContext

        try SeedDataService.prepareIfNeeded(in: context, allowInitialSeed: false)

        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<NutritionTarget>()).isEmpty)
    }

    func testSetPlanPresetsFollowExpectedWeightAndRepDirections() {
        let fixed = WorkoutSetPlan.preset(.fixed, count: 3, baseWeight: 40, baseReps: 10)
        XCTAssertEqual(fixed.map(\.weight), [40, 40, 40])
        XCTAssertEqual(fixed.map(\.reps), [10, 10, 10])

        let ascending = WorkoutSetPlan.preset(.pyramidUp, count: 3, baseWeight: 40, baseReps: 10)
        XCTAssertEqual(ascending.map(\.weight), [40, 42.5, 45])
        XCTAssertEqual(ascending.map(\.reps), [10, 8, 6])

        let descending = WorkoutSetPlan.preset(.pyramidDown, count: 3, baseWeight: 40, baseReps: 10)
        XCTAssertEqual(descending.map(\.weight), [45, 42.5, 40])
        XCTAssertEqual(descending.map(\.reps), [6, 8, 10])
    }

    func testDailyPlanPersistsDayPatternAndExerciseOverrideIntoWorkoutSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let bench = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        let fly = Exercise(name: "绳索夹胸", muscleGroup: "胸部", equipment: "龙门架")
        context.insert(bench)
        context.insert(fly)

        let schedule = try DailyPlanService.create(
            on: .now,
            muscleGroups: ["胸部"],
            defaultPlanPattern: .pyramidUp,
            exercises: [
                DailyPlanExerciseInput(
                    exerciseID: bench.id,
                    plannedSets: WorkoutSetPlan.preset(.pyramidUp, count: 3, baseWeight: 40, baseReps: 10),
                    planPattern: .pyramidUp,
                    patternSource: .dayDefault,
                    restSeconds: 120
                ),
                DailyPlanExerciseInput(
                    exerciseID: fly.id,
                    plannedSets: WorkoutSetPlan.preset(.fixed, count: 3, baseWeight: 10, baseReps: 12),
                    planPattern: .fixed,
                    patternSource: .exerciseOverride,
                    restSeconds: 90
                )
            ],
            replaceExistingPlans: true,
            in: context
        )

        let template = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutTemplate>()).first { $0.id == schedule.templateID }
        )
        let items = try context.fetch(FetchDescriptor<TemplateExercise>())
            .filter { $0.templateID == template.id }
            .sorted { $0.order < $1.order }
        XCTAssertEqual(template.defaultPlanPattern, .pyramidUp)
        XCTAssertEqual(items.map(\.patternSource), [.dayDefault, .exerciseOverride])
        XCTAssertEqual(items.map(\.planPattern), [.pyramidUp, .fixed])

        let sessionID = try WorkoutService.start(schedule: schedule, in: context)
        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == sessionID }
        )
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == sessionID }
            .sorted { $0.order < $1.order }
        XCTAssertEqual(session.defaultPlanPattern, .pyramidUp)
        XCTAssertEqual(snapshots.map(\.patternSource), [.dayDefault, .exerciseOverride])
        XCTAssertEqual(snapshots.map(\.planPattern), [.pyramidUp, .fixed])
    }

    func testDayPatternChangeOnlyUpdatesInheritedExercisesAndRestoreRejoinsDefault() {
        let inheritedID = UUID()
        let overrideID = UUID()
        let originalOverridePlans = WorkoutSetPlan.preset(
            .fixed,
            count: 3,
            baseWeight: 20,
            baseReps: 12
        )
        let targets = [
            inheritedID: DailyPlanPatternTarget(
                pattern: .fixed,
                patternSource: .dayDefault,
                plannedSets: WorkoutSetPlan.preset(.fixed, count: 3, baseWeight: 40, baseReps: 10),
                restSeconds: 120
            ),
            overrideID: DailyPlanPatternTarget(
                pattern: .fixed,
                patternSource: .exerciseOverride,
                plannedSets: originalOverridePlans,
                restSeconds: 90
            )
        ]

        let change = DailyPlanPatternPolicy.applying(
            .pyramidUp,
            to: targets,
            orderedIDs: [inheritedID, overrideID]
        )

        XCTAssertEqual(change.updatedCount, 1)
        XCTAssertEqual(change.overrideCount, 1)
        XCTAssertEqual(change.targets[inheritedID]?.pattern, .pyramidUp)
        XCTAssertEqual(change.targets[inheritedID]?.plannedSets.map(\.weight), [40, 42.5, 45])
        XCTAssertEqual(change.targets[overrideID]?.pattern, .fixed)
        XCTAssertEqual(change.targets[overrideID]?.plannedSets, originalOverridePlans)

        let restored = DailyPlanPatternPolicy.restoring(
            try! XCTUnwrap(change.targets[overrideID]),
            to: .pyramidDown
        )
        XCTAssertEqual(restored.patternSource, .dayDefault)
        XCTAssertEqual(restored.pattern, .pyramidDown)
        XCTAssertEqual(restored.plannedSets.map(\.weight), [25, 22.5, 20])
    }

    func testLegacyPatternMetadataInfersUniformPlansButPreservesMixedPlansAsOverrides() {
        let firstID = UUID()
        let secondID = UUID()

        let uniform = DailyPlanPatternMetadataPolicy.resolve(
            explicitPatternRaw: nil,
            itemPatterns: [
                (firstID, .pyramidUp, nil),
                (secondID, .pyramidUp, nil)
            ]
        )
        XCTAssertEqual(uniform.dayPattern, .pyramidUp)
        XCTAssertFalse(uniform.isLegacyMixed)
        XCTAssertEqual(uniform.sources[firstID], .dayDefault)
        XCTAssertEqual(uniform.sources[secondID], .dayDefault)

        let mixed = DailyPlanPatternMetadataPolicy.resolve(
            explicitPatternRaw: nil,
            itemPatterns: [
                (firstID, .fixed, nil),
                (secondID, .pyramidDown, nil)
            ]
        )
        XCTAssertEqual(mixed.dayPattern, .fixed)
        XCTAssertTrue(mixed.isLegacyMixed)
        XCTAssertEqual(mixed.sources[firstID], .exerciseOverride)
        XCTAssertEqual(mixed.sources[secondID], .exerciseOverride)

        let explicit = DailyPlanPatternMetadataPolicy.resolve(
            explicitPatternRaw: SetPlanPattern.pyramidDown.rawValue,
            itemPatterns: [
                (firstID, .pyramidDown, PlanPatternSource.dayDefault.rawValue),
                (secondID, .fixed, PlanPatternSource.exerciseOverride.rawValue)
            ]
        )
        XCTAssertEqual(explicit.dayPattern, .pyramidDown)
        XCTAssertEqual(explicit.sources[firstID], .dayDefault)
        XCTAssertEqual(explicit.sources[secondID], .exerciseOverride)
    }

    func testWorkoutStartCopiesPerSetPlanAndSideModesIntoLogs() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "哑铃推举",
            muscleGroup: "肩部",
            equipment: "哑铃",
            volumeUnit: .meter
        )
        let template = WorkoutTemplate(name: "肩部", weekday: Date.now.weekdayNumber)
        let plans = [
            WorkoutSetPlan(weight: 10, reps: 12, weightSide: .single, repsSide: .bilateral),
            WorkoutSetPlan(weight: 12.5, reps: 10, weightSide: .single, repsSide: .bilateral),
            WorkoutSetPlan(weight: 15, reps: 8, weightSide: .single, repsSide: .bilateral)
        ]
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: plans.count,
            minReps: 8,
            maxReps: 12,
            targetWeight: 10,
            restSeconds: 90,
            plannedSets: plans,
            planPattern: .pyramidUp
        )
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: .now
        )
        context.insert(exercise)
        context.insert(template)
        context.insert(item)
        context.insert(schedule)
        try context.save()

        let sessionID = try WorkoutService.start(schedule: schedule, in: context)
        let snapshot = try XCTUnwrap(
            context.fetch(FetchDescriptor<SessionExercise>()).first { $0.sessionID == sessionID }
        )
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionID == sessionID }
            .sorted { $0.setNumber < $1.setNumber }

        XCTAssertEqual(snapshot.planPattern, .pyramidUp)
        XCTAssertEqual(snapshot.plannedSets, plans)
        XCTAssertEqual(snapshot.volumeUnit, .meter)
        XCTAssertEqual(logs.map(\.targetWeight), [10, 12.5, 15])
        XCTAssertEqual(logs.map(\.targetReps), [12, 10, 8])
        XCTAssertTrue(logs.allSatisfy { $0.targetWeightSide == .single })
        XCTAssertTrue(logs.allSatisfy { $0.actualWeightSide == .single })

        exercise.volumeUnit = .count
        try context.save()
        XCTAssertEqual(snapshot.volumeUnit, .meter)
    }

    func testConfirmedStrictSquatDuplicateConsolidatesWithoutRenamingHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let squat = Exercise(name: "深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let strictSquat = Exercise(name: "严格深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let template = WorkoutTemplate(name: "腿", weekday: Date.now.weekdayNumber)
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: strictSquat.id,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 50,
            restSeconds: 120
        )
        let snapshot = SessionExercise(
            sessionID: UUID(),
            exerciseID: strictSquat.id,
            exerciseName: "严格深蹲",
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 50,
            restSeconds: 120
        )
        context.insert(squat)
        context.insert(strictSquat)
        context.insert(template)
        context.insert(item)
        context.insert(snapshot)
        try context.save()

        try ExerciseCatalogService.consolidateConfirmedSquatDuplicate(in: context)

        XCTAssertEqual(item.exerciseID, squat.id)
        XCTAssertEqual(snapshot.exerciseID, squat.id)
        XCTAssertEqual(snapshot.exerciseName, "严格深蹲")
        XCTAssertTrue(strictSquat.isArchived)
        XCTAssertEqual(
            ExerciseCatalogService.exactNameMatch(named: "严格深蹲", in: [squat, strictSquat])?.id,
            squat.id
        )
    }

    func testEditingBuiltInExerciseUpdatesCatalogWithoutRewritingHistorySnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "测试内置深蹲",
            muscleGroup: "腿部",
            equipment: "杠铃",
            defaultRestSeconds: 120,
            isBuiltIn: true,
            notes: "原始动作提醒",
            referenceURL: "https://example.com/original",
            volumeUnit: .kilogram
        )
        let snapshot = SessionExercise(
            sessionID: UUID(),
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 60,
            restSeconds: exercise.defaultRestSeconds,
            muscleGroup: exercise.muscleGroup,
            exerciseNotes: exercise.notes,
            referenceURL: exercise.referenceURL,
            volumeUnit: exercise.volumeUnit
        )
        context.insert(exercise)
        context.insert(snapshot)
        try context.save()

        let result = try ExerciseCatalogService.save(
            exercise: exercise,
            name: "测试内置高杠深蹲",
            muscleGroup: "臀部",
            equipment: "力量架",
            volumeUnit: .count,
            defaultRestSeconds: 90,
            notes: "更新后的动作提醒",
            referenceURL: "https://example.com/updated",
            allExercises: [exercise],
            in: context
        )

        XCTAssertEqual(result.kind, .updated)
        XCTAssertTrue(exercise.isBuiltIn)
        XCTAssertEqual(exercise.name, "测试内置高杠深蹲")
        XCTAssertEqual(exercise.muscleGroup, "臀部")
        XCTAssertEqual(exercise.equipment, "力量架")
        XCTAssertEqual(exercise.volumeUnit, .count)
        XCTAssertEqual(exercise.defaultRestSeconds, 90)
        XCTAssertEqual(exercise.notes, "更新后的动作提醒")
        XCTAssertEqual(exercise.referenceURL, "https://example.com/updated")

        XCTAssertEqual(snapshot.exerciseName, "测试内置深蹲")
        XCTAssertEqual(snapshot.muscleGroup, "腿部")
        XCTAssertEqual(snapshot.restSeconds, 120)
        XCTAssertEqual(snapshot.exerciseNotes, "原始动作提醒")
        XCTAssertEqual(snapshot.referenceURL, "https://example.com/original")
        XCTAssertEqual(snapshot.volumeUnit, .kilogram)
    }

    func testSetPlanPresetClampsUnsafeInputsAndPreservesSideModes() {
        let minimum = WorkoutSetPlan.preset(
            .pyramidUp,
            count: -4,
            baseWeight: -20,
            baseReps: -3,
            weightSide: .single,
            repsSide: .single
        )
        XCTAssertEqual(minimum.count, 1)
        XCTAssertEqual(minimum.first?.weight, 0)
        XCTAssertEqual(minimum.first?.reps, 1)
        XCTAssertEqual(minimum.first?.weightSide, .single)
        XCTAssertEqual(minimum.first?.repsSide, .single)

        let maximum = WorkoutSetPlan.preset(
            .pyramidUp,
            count: 99,
            baseWeight: 10,
            baseReps: 5
        )
        XCTAssertEqual(maximum.count, 12)
        XCTAssertTrue(zip(maximum, maximum.dropFirst()).allSatisfy { pair in
            pair.0.weight <= pair.1.weight
        })
        XCTAssertTrue(zip(maximum, maximum.dropFirst()).allSatisfy { pair in
            pair.0.reps >= pair.1.reps
        })
        XCTAssertTrue(maximum.allSatisfy { $0.weight >= 0 && $0.reps >= 1 })
    }

    func testMalformedPlanAndSideStorageFallsBackWithoutCrashing() {
        let templateItem = TemplateExercise(
            templateID: UUID(),
            exerciseID: UUID(),
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 12,
            targetWeight: 40,
            restSeconds: 90
        )
        templateItem.plannedSetsJSON = "{not-json"
        templateItem.planPatternRaw = "unknown-pattern"
        XCTAssertEqual(templateItem.planPattern, .fixed)
        XCTAssertEqual(templateItem.plannedSets.map(\.weight), [40, 40, 40])
        XCTAssertEqual(templateItem.plannedSets.map(\.reps), [8, 8, 8])

        templateItem.plannedSets = []
        XCTAssertEqual(templateItem.targetSets, 1)
        XCTAssertEqual(templateItem.plannedSets.count, 1)

        let log = SetLog(
            sessionID: UUID(),
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 1,
            targetWeight: 20,
            targetReps: 10,
            actualWeight: 20,
            actualReps: 10,
            targetWeightSide: .single,
            targetRepsSide: .single
        )
        log.targetWeightSideRaw = "invalid"
        log.targetRepsSideRaw = nil
        log.actualWeightSideRaw = nil
        log.actualRepsSideRaw = "invalid"
        XCTAssertEqual(log.targetWeightSide, .bilateral)
        XCTAssertEqual(log.targetRepsSide, .bilateral)
        XCTAssertEqual(log.actualWeightSide, .bilateral)
        XCTAssertEqual(log.actualRepsSide, .bilateral)
    }

    func testReducingAndRestoringPlannedSetsKeepsDraftAndPlanAcrossContexts() throws {
        let container = try makeContainer(), context = container.mainContext
        let session = WorkoutSession(templateName: "减组", plannedDate: .now, status: .inProgress)
        let exercise = Exercise(name: "腿举", muscleGroup: "腿部", equipment: "器械")
        let plans = (1...4).map { WorkoutSetPlan(weight: Double($0 * 10), reps: 8 + $0) }
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
            order: 0, targetSets: 4, minReps: 9, maxReps: 12, targetWeight: 10, restSeconds: 90, plannedSets: plans)
        let sourceID = UUID()
        let started = Date(timeIntervalSince1970: 1_760_000_000)
        context.insert(session); context.insert(exercise); context.insert(snapshot)
        let sets = plans.enumerated().map { index, plan in
            SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
                setNumber: index + 1, targetWeight: plan.weight, targetReps: plan.reps,
                actualWeight: index == 3 ? 47.5 : plan.weight, actualReps: index == 3 ? 7 : plan.reps,
                rir: index == 3 ? 2 : nil, isCompleted: index < 2, startedAt: index == 3 ? started : nil,
                actualWeightSide: .single, actualRepsSide: .bilateral,
                actualEntrySource: index == 3 ? .manual : .plan, sourceHistorySetID: index == 3 ? sourceID : nil)
        }
        sets.forEach(context.insert)
        try context.save()
        let originalPlan = snapshot.plannedSetsJSON
        let fourth = try XCTUnwrap(WorkoutService.reductionCandidate(for: snapshot, in: context))
        XCTAssertEqual(fourth.id, sets[3].id)
        XCTAssertThrowsError(try WorkoutService.reduceSet(from: snapshot, candidateID: fourth.id,
            confirmingEnteredData: false, in: context), "已录入组必须先得到确认")
        XCTAssertNil(fourth.reductionOrder)
        try WorkoutService.reduceSet(from: snapshot, candidateID: fourth.id, confirmingEnteredData: true, in: context)
        let third = try XCTUnwrap(WorkoutService.reductionCandidate(for: snapshot, in: context))
        try WorkoutService.reduceSet(from: snapshot, candidateID: third.id, confirmingEnteredData: false, in: context)
        XCTAssertEqual(snapshot.targetSets, 2)
        XCTAssertEqual(snapshot.plannedSetsJSON, originalPlan)
        XCTAssertNotNil(snapshot.exerciseCompletedAt)
        XCTAssertEqual(sets.filter { $0.reductionOrder == nil && $0.isCompleted }.count, 2)
        XCTAssertEqual(sets.filter { $0.reductionOrder == nil }.map(\.setNumber), [1, 2])
        XCTAssertThrowsError(try WorkoutService.reduceSet(from: snapshot, candidateID: fourth.id,
            confirmingEnteredData: true, in: context), "旧确认不能减掉另一组")

        let reentered = ModelContext(container)
        let reloadedSnapshot = try XCTUnwrap(reentered.fetch(FetchDescriptor<SessionExercise>()).first { $0.id == snapshot.id })
        try WorkoutService.restoreReducedSet(for: reloadedSnapshot, in: reentered)
        XCTAssertNil(reloadedSnapshot.exerciseCompletedAt)
        var reloaded = try reentered.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionExerciseID == snapshot.id }
        XCTAssertNil(try XCTUnwrap(reloaded.first { $0.id == sets[2].id }).reductionOrder)
        XCTAssertNotNil(try XCTUnwrap(reloaded.first { $0.id == sets[3].id }).reductionOrder)
        try WorkoutService.restoreReducedSet(for: reloadedSnapshot, in: reentered)
        reloaded = try reentered.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionExerciseID == snapshot.id }
        let restored = try XCTUnwrap(reloaded.first { $0.id == sets[3].id })
        XCTAssertNil(restored.reductionOrder)
        XCTAssertEqual(restored.setNumber, 4)
        XCTAssertEqual(restored.actualWeight, 47.5)
        XCTAssertEqual(restored.actualReps, 7)
        XCTAssertEqual(restored.rir, 2)
        XCTAssertEqual(restored.startedAt, started)
        XCTAssertEqual(restored.sourceHistorySetID, sourceID)
        XCTAssertEqual(restored.actualEntrySource, .manual)
        XCTAssertEqual(restored.actualWeightSide, .single)
        XCTAssertEqual(reloadedSnapshot.hasManuallyReducedSets, true)
        XCTAssertEqual(reloadedSnapshot.plannedSetsJSON, originalPlan)
    }

    func testReducedSetSurvivesPersistentStoreCloseAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xfit-reduced-reopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("training.store")
        let snapshotID = UUID(), rowID = UUID(), sessionID = UUID(), exerciseID = UUID()
        do {
            let store = try makePersistentContainer(at: url), context = store.mainContext
            let session = WorkoutSession(id: sessionID, templateName: "持久减组", plannedDate: .now, status: .inProgress)
            let snapshot = SessionExercise(id: snapshotID, sessionID: sessionID, exerciseID: exerciseID,
                exerciseName: "持久减组", order: 0, targetSets: 1, minReps: 8, maxReps: 8,
                targetWeight: 20, restSeconds: 90)
            let row = SetLog(id: rowID, sessionID: sessionID, sessionExerciseID: snapshotID, exerciseID: exerciseID,
                setNumber: 1, targetWeight: 20, targetReps: 8, actualWeight: 22.5, actualReps: 7,
                actualEntrySource: .manual)
            context.insert(session); context.insert(snapshot); context.insert(row); try context.save()
            try WorkoutService.reduceSet(from: snapshot, candidateID: rowID, confirmingEnteredData: true, in: context)
        }
        let reopened = try makePersistentContainer(at: url), context = reopened.mainContext
        let snapshot = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first { $0.id == snapshotID })
        let row = try XCTUnwrap(context.fetch(FetchDescriptor<SetLog>()).first { $0.id == rowID })
        XCTAssertNotNil(row.reductionOrder)
        XCTAssertEqual(snapshot.hasManuallyReducedSets, true)
        XCTAssertEqual(snapshot.targetSets, 0)
        try WorkoutService.restoreReducedSet(for: snapshot, in: context)
        XCTAssertNil(row.reductionOrder)
        XCTAssertEqual(row.actualWeight, 22.5)
        XCTAssertEqual(row.actualReps, 7)
        XCTAssertEqual(snapshot.hasManuallyReducedSets, true)
    }

    func testReducingNonLastUnfinishedSetPreservesCompletedNumberAndCanSkipAll() throws {
        let container = try makeContainer(), context = container.mainContext
        let session = WorkoutSession(templateName: "非顺序完成", plannedDate: .now, status: .inProgress)
        let exercise = Exercise(name: "推胸", muscleGroup: "胸部", equipment: "器械")
        let plans = (1...4).map { WorkoutSetPlan(weight: Double($0 * 10), reps: 10) }
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
            order: 0, targetSets: 4, minReps: 10, maxReps: 10, targetWeight: 10, restSeconds: 90, plannedSets: plans)
        context.insert(session); context.insert(exercise); context.insert(snapshot)
        let sets = plans.enumerated().map { index, plan in
            SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
                setNumber: index + 1, targetWeight: plan.weight, targetReps: plan.reps,
                actualWeight: plan.weight, actualReps: plan.reps, isCompleted: index == 3, actualEntrySource: .plan)
        }
        sets.forEach(context.insert); try context.save()
        let completedID = sets[3].id
        for expected in [3, 2, 1] {
            let candidate = try XCTUnwrap(WorkoutService.reductionCandidate(for: snapshot, in: context))
            XCTAssertEqual(candidate.setNumber, expected)
            try WorkoutService.reduceSet(from: snapshot, candidateID: candidate.id, confirmingEnteredData: false, in: context)
        }
        XCTAssertNil(try WorkoutService.reductionCandidate(for: snapshot, in: context))
        XCTAssertTrue(sets[3].isCompleted)
        XCTAssertEqual(sets[3].id, completedID)
        XCTAssertEqual(sets[3].setNumber, 4)
        XCTAssertEqual(sets[3].targetWeight, 40)
        XCTAssertEqual(snapshot.plannedSets.map(\.weight), [10, 20, 30, 40])
        sets[3].isCompleted = false; try context.save()
        let last = try XCTUnwrap(WorkoutService.reductionCandidate(for: snapshot, in: context))
        try WorkoutService.reduceSet(from: snapshot, candidateID: last.id, confirmingEnteredData: false, in: context)
        XCTAssertEqual(snapshot.targetSets, 0)
        XCTAssertTrue(sets.allSatisfy { $0.reductionOrder != nil })
        try WorkoutService.restoreReducedSet(for: snapshot, in: context)
        XCTAssertNil(sets[3].reductionOrder, "先恢复最后一次减掉的组")
        XCTAssertEqual(snapshot.targetSets, 1)
    }

    func testMenuAndRestoreDefaultsCannotEraseReducedDraftOrBlockOtherExerciseEdits() throws {
        let container = try makeContainer(), context = container.mainContext
        let session = WorkoutSession(templateName: "菜单保护", plannedDate: .now, status: .inProgress)
        let reduced = Exercise(name: "减组动作", muscleGroup: "腿部", equipment: "器械")
        let other = Exercise(name: "其他动作", muscleGroup: "背部", equipment: "器械")
        let reducedPlans = [WorkoutSetPlan(weight: 20, reps: 10), WorkoutSetPlan(weight: 25, reps: 8)]
        let otherPlans = [WorkoutSetPlan(weight: 30, reps: 10)]
        let reducedSnapshot = SessionExercise(sessionID: session.id, exerciseID: reduced.id, exerciseName: reduced.name,
            order: 0, targetSets: 2, minReps: 8, maxReps: 10, targetWeight: 20, restSeconds: 90, plannedSets: reducedPlans)
        let otherSnapshot = SessionExercise(sessionID: session.id, exerciseID: other.id, exerciseName: other.name,
            order: 1, targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 30, restSeconds: 90, plannedSets: otherPlans)
        let first = SetLog(sessionID: session.id, sessionExerciseID: reducedSnapshot.id, exerciseID: reduced.id,
            setNumber: 1, targetWeight: 20, targetReps: 10, actualWeight: 20, actualReps: 10, actualEntrySource: .plan)
        let draft = SetLog(sessionID: session.id, sessionExerciseID: reducedSnapshot.id, exerciseID: reduced.id,
            setNumber: 2, targetWeight: 25, targetReps: 8, actualWeight: 47.5, actualReps: 6, rir: 2, actualEntrySource: .manual)
        let otherRow = SetLog(sessionID: session.id, sessionExerciseID: otherSnapshot.id, exerciseID: other.id,
            setNumber: 1, targetWeight: 30, targetReps: 10, actualWeight: 30, actualReps: 10, actualEntrySource: .plan)
        context.insert(session); context.insert(reduced); context.insert(other)
        context.insert(reducedSnapshot); context.insert(otherSnapshot)
        context.insert(first); context.insert(draft); context.insert(otherRow); try context.save()
        try WorkoutService.reduceSet(from: reducedSnapshot, candidateID: draft.id, confirmingEnteredData: true, in: context)
        let originalPlan = reducedSnapshot.plannedSetsJSON
        try WorkoutService.restorePlanDefaults(for: reducedSnapshot, in: context)
        XCTAssertEqual(draft.actualWeight, 47.5)
        XCTAssertEqual(draft.actualReps, 6)
        let replacement = [WorkoutSetPlan(weight: 40, reps: 9)]
        try WorkoutService.syncMenu([
            DailyPlanExerciseInput(exerciseID: reduced.id, plannedSets: reducedPlans, planPattern: .fixed, restSeconds: 90),
            DailyPlanExerciseInput(exerciseID: other.id, plannedSets: replacement, planPattern: .fixed, restSeconds: 90)
        ], to: session, in: context)
        XCTAssertEqual(otherSnapshot.plannedSets.map(\.weight), [40])
        XCTAssertEqual(reducedSnapshot.plannedSetsJSON, originalPlan)
        XCTAssertEqual(draft.actualWeight, 47.5)
        XCTAssertNotNil(draft.reductionOrder)
        XCTAssertThrowsError(try WorkoutService.removeExercise(reducedSnapshot, from: session, in: context))
        XCTAssertThrowsError(try WorkoutService.syncMenu([
            DailyPlanExerciseInput(exerciseID: reduced.id, plannedSets: replacement, planPattern: .fixed, restSeconds: 90),
            DailyPlanExerciseInput(exerciseID: other.id, plannedSets: replacement, planPattern: .fixed, restSeconds: 90)
        ], to: session, in: context))
        XCTAssertEqual(reducedSnapshot.plannedSetsJSON, originalPlan)
        XCTAssertEqual(draft.actualWeight, 47.5)
        try WorkoutService.restoreReducedSet(for: reducedSnapshot, in: context)
        XCTAssertNil(draft.reductionOrder)
        XCTAssertEqual(draft.actualWeight, 47.5)
    }

    func testBackfillKeepsEntirelyReducedExerciseEmptyWithoutLosingItsDraft() throws {
        let container = try makeContainer(), context = container.mainContext
        let skipped = Exercise(name: "今天不做", muscleGroup: "腿部", equipment: "器械")
        let completed = Exercise(name: "已做", muscleGroup: "背部", equipment: "器械")
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "部分训练", plannedDate: .now, status: .inProgress)
        let session = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: schedule.templateName, plannedDate: .now, status: .inProgress)
        context.insert(skipped); context.insert(completed); context.insert(schedule); context.insert(session)
        var snapshots: [SessionExercise] = []
        var rows: [SetLog] = []
        for (index, exercise) in [skipped, completed].enumerated() {
            let snapshot = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
                order: index, targetSets: 1, minReps: 8, maxReps: 8, targetWeight: 20, restSeconds: 90)
            let row = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
                setNumber: 1, targetWeight: 20, targetReps: 8, actualWeight: 25, actualReps: 7,
                isCompleted: index == 1, actualEntrySource: index == 0 ? .manual : .plan)
            context.insert(snapshot); context.insert(row); snapshots.append(snapshot); rows.append(row)
        }
        try context.save()
        try WorkoutService.reduceSet(from: snapshots[0], candidateID: rows[0].id, confirmingEnteredData: true, in: context)
        try WorkoutService.finish(session: session, schedules: [schedule], in: context)
        let progress = try TrainingWorkingSetProgressLoader.load(schedules: [schedule], sessions: [session], in: context)
        XCTAssertEqual(progress[session.id], TrainingWorkSetProgress(completed: 1, total: 1))
        let preparation = try HistoricalWorkoutService.prepareScheduledBackfill(scheduleID: schedule.id, in: context)
        XCTAssertEqual(preparation.exercises.first { $0.exerciseID == skipped.id }?.sets.count, 0)
        let input = ScheduledWorkoutBackfillInput(scheduleID: schedule.id, existingSessionID: session.id,
            name: preparation.name, date: preparation.date, startedAt: preparation.startedAt,
            durationMinutes: preparation.durationMinutes, notes: preparation.notes,
            exercises: preparation.exercises.map { item in
                ScheduledWorkoutBackfillExerciseInput(existingSnapshotID: item.existingSnapshotID, exerciseID: item.exerciseID,
                    sets: item.sets.map { set in
                        ScheduledWorkoutBackfillSetInput(existingLogID: set.existingLogID, weight: set.weight,
                            reps: set.reps, rir: set.rir, weightSide: set.weightSide, repsSide: set.repsSide)
                    }, performanceNotes: item.performanceNotes, feeling: item.feeling, isWarmup: item.isWarmup)
            })
        _ = try HistoricalWorkoutService.recordScheduledBackfill(input, in: context)
        XCTAssertNotNil(rows[0].reductionOrder)
        XCTAssertFalse(rows[0].isCompleted)
        XCTAssertEqual(rows[0].actualWeight, 25)
        XCTAssertTrue(rows[1].isCompleted)
    }

    func testOnlyManuallyReducedExerciseKeepsItsLongTermTemplateAfterRestore() throws {
        let container = try makeContainer(), context = container.mainContext
        let template = WorkoutTemplate(name: "长期模板", weekday: Date.now.weekdayNumber)
        let reduced = Exercise(name: "疲劳减组", muscleGroup: "腿部", equipment: "器械")
        let regular = Exercise(name: "普通动作", muscleGroup: "背部", equipment: "器械")
        let session = WorkoutSession(templateID: template.id, templateName: template.name, plannedDate: .now, status: .inProgress)
        context.insert(template); context.insert(reduced); context.insert(regular); context.insert(session)
        var items: [TemplateExercise] = []
        var snapshots: [SessionExercise] = []
        for (index, exercise) in [reduced, regular].enumerated() {
            let plans = [WorkoutSetPlan(weight: 20, reps: 10), WorkoutSetPlan(weight: 25, reps: 8)]
            let item = TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: index,
                targetSets: 2, minReps: 8, maxReps: 10, targetWeight: 20, restSeconds: 90, plannedSets: plans)
            let snapshot = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
                order: index, targetSets: 2, minReps: 8, maxReps: 10, targetWeight: 20, restSeconds: 90, plannedSets: plans)
            context.insert(item); context.insert(snapshot); items.append(item); snapshots.append(snapshot)
            for setNumber in 1...2 {
                context.insert(SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
                    setNumber: setNumber, targetWeight: 20, targetReps: 10,
                    actualWeight: Double(50 + index * 20 + setNumber), actualReps: 8 - setNumber,
                    isCompleted: index == 1 || setNumber == 1, actualEntrySource: .plan))
            }
        }
        try context.save()
        let originalReducedPlan = items[0].plannedSetsJSON
        let candidate = try XCTUnwrap(WorkoutService.reductionCandidate(for: snapshots[0], in: context))
        try WorkoutService.reduceSet(from: snapshots[0], candidateID: candidate.id, confirmingEnteredData: false, in: context)
        try WorkoutService.restoreReducedSet(for: snapshots[0], in: context)
        try WorkoutService.finish(session: session, schedules: [], in: context)
        XCTAssertEqual(items[0].plannedSetsJSON, originalReducedPlan, "撤销减组后仍保留该动作的长期模板")
        XCTAssertEqual(items[0].targetSets, 2)
        XCTAssertEqual(items[1].plannedSets.map(\.weight), [71, 72], "其他动作继续按实际回写")
        XCTAssertEqual(items[1].plannedSets.map(\.reps), [7, 6])
    }

    func testReducedDraftAndTemplateExceptionSurviveBackupAndLegacyImport() throws {
        let source = try makeContainer(), context = source.mainContext
        let session = WorkoutSession(templateName: "减组备份", plannedDate: .now, status: .inProgress)
        let exercise = Exercise(name: "腿举", muscleGroup: "腿部", equipment: "器械")
        let plans = [WorkoutSetPlan(weight: 30, reps: 10), WorkoutSetPlan(weight: 35, reps: 8)]
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
            order: 0, targetSets: 2, minReps: 8, maxReps: 10, targetWeight: 30, restSeconds: 90, plannedSets: plans)
        let first = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
            setNumber: 1, targetWeight: 30, targetReps: 10, actualWeight: 31, actualReps: 10,
            isCompleted: true, actualEntrySource: .manual)
        let draft = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
            setNumber: 2, targetWeight: 35, targetReps: 8, actualWeight: 42.5, actualReps: 6,
            rir: 2, actualEntrySource: .manual)
        context.insert(session); context.insert(exercise); context.insert(snapshot); context.insert(first); context.insert(draft)
        try context.save()
        try WorkoutService.reduceSet(from: snapshot, candidateID: draft.id, confirmingEnteredData: true, in: context)
        let data = try Data(contentsOf: DataExportService.createBackup(in: context))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 19)
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        let importedSnapshot = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first { $0.id == snapshot.id })
        let importedDraft = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SetLog>()).first { $0.id == draft.id })
        XCTAssertEqual(importedSnapshot.hasManuallyReducedSets, true)
        XCTAssertNotNil(importedDraft.reductionOrder)
        XCTAssertEqual(importedDraft.actualWeight, 42.5)
        try WorkoutService.restoreReducedSet(for: importedSnapshot, in: destination.mainContext)
        XCTAssertNil(importedDraft.reductionOrder)
        XCTAssertEqual(importedDraft.actualReps, 6)
        XCTAssertEqual(importedDraft.rir, 2)

        var forgedOldVersion = json
        forgedOldVersion["schemaVersion"] = 18
        let rejected = try makeContainer()
        XCTAssertThrowsError(try DataExportService.importBackup(JSONSerialization.data(withJSONObject: forgedOldVersion), into: rejected.mainContext))
        XCTAssertEqual(try rejected.mainContext.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        var conflictingState = json
        var conflictingLogs = try XCTUnwrap(conflictingState["setLogs"] as? [[String: Any]])
        let reducedIndex = try XCTUnwrap(conflictingLogs.firstIndex { $0["reductionOrder"] != nil })
        conflictingLogs[reducedIndex]["isCompleted"] = true
        conflictingState["setLogs"] = conflictingLogs
        XCTAssertThrowsError(try DataExportService.importBackup(JSONSerialization.data(withJSONObject: conflictingState), into: rejected.mainContext))
        XCTAssertEqual(try rejected.mainContext.fetchCount(FetchDescriptor<SetLog>()), 0)

        json["schemaVersion"] = 18
        var snapshots = try XCTUnwrap(json["sessionExercises"] as? [[String: Any]])
        snapshots[0].removeValue(forKey: "hasManuallyReducedSets")
        json["sessionExercises"] = snapshots
        var logs = try XCTUnwrap(json["setLogs"] as? [[String: Any]])
        for index in logs.indices { logs[index].removeValue(forKey: "reductionOrder") }
        json["setLogs"] = logs
        let legacy = try makeContainer()
        _ = try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: legacy.mainContext)
        let legacySnapshot = try XCTUnwrap(legacy.mainContext.fetch(FetchDescriptor<SessionExercise>()).first)
        XCTAssertNil(legacySnapshot.hasManuallyReducedSets)
        XCTAssertTrue(try legacy.mainContext.fetch(FetchDescriptor<SetLog>()).allSatisfy { $0.reductionOrder == nil })
    }

    func testDynamicSetAdjustmentCopiesLastValuesAllowsPlanDeltaAndProtectsCompletedSet() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = WorkoutSession(templateName: "鲁棒性训练", plannedDate: .now, status: .inProgress)
        let exercise = Exercise(name: "单臂划船", muscleGroup: "背部", equipment: "哑铃")
        let plans = WorkoutSetPlan.preset(
            .pyramidUp,
            count: 3,
            baseWeight: 20,
            baseReps: 12,
            weightSide: .single,
            repsSide: .single
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 12,
            targetWeight: 20,
            restSeconds: 90,
            plannedSets: plans,
            planPattern: .pyramidUp
        )
        context.insert(session)
        context.insert(exercise)
        context.insert(snapshot)
        for (index, plan) in plans.enumerated() {
            context.insert(SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: exercise.id,
                setNumber: index + 1,
                targetWeight: plan.weight,
                targetReps: plan.reps,
                actualWeight: plan.weight + 1,
                actualReps: plan.reps + 1,
                targetWeightSide: plan.weightSide,
                targetRepsSide: plan.repsSide,
                actualWeightSide: .bilateral,
                actualRepsSide: .bilateral
            ))
        }
        try context.save()

        let extra = try WorkoutService.addSet(to: snapshot, in: context)
        XCTAssertEqual(extra.setNumber, 4)
        XCTAssertEqual(extra.targetWeight, 25)
        XCTAssertEqual(extra.targetReps, 8)
        XCTAssertEqual(extra.actualWeight, 26)
        XCTAssertEqual(extra.actualReps, 9)
        XCTAssertEqual(extra.targetWeightSide, .single)
        XCTAssertEqual(extra.actualWeightSide, .bilateral)
        XCTAssertEqual(snapshot.targetSets, 4)
        XCTAssertEqual(snapshot.plannedSets.count, 3, "加练组不能改写原计划快照")

        let addedCandidate = try XCTUnwrap(WorkoutService.reductionCandidate(for: snapshot, in: context))
        try WorkoutService.reduceSet(from: snapshot, candidateID: addedCandidate.id, confirmingEnteredData: true, in: context)
        let plannedCandidate = try XCTUnwrap(WorkoutService.reductionCandidate(for: snapshot, in: context))
        try WorkoutService.reduceSet(from: snapshot, candidateID: plannedCandidate.id, confirmingEnteredData: true, in: context)
        XCTAssertEqual(snapshot.targetSets, 2)
        XCTAssertEqual(snapshot.plannedSets.count, 3, "少做一组应保留计划差异")

        let remaining = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == snapshot.id && $0.reductionOrder == nil }
            .sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(remaining.map(\.setNumber), [1, 2])
        remaining[1].isCompleted = true
        try context.save()
        XCTAssertEqual(try WorkoutService.reductionCandidate(for: snapshot, in: context)?.id, remaining[0].id,
                       "完成的末组不能阻止减少之前未完成的组")
        remaining[0].isCompleted = true
        try context.save()
        XCTAssertNil(try WorkoutService.reductionCandidate(for: snapshot, in: context))

        session.status = .completed
        try context.save()
        XCTAssertThrowsError(try WorkoutService.addSet(to: snapshot, in: context)) { error in
            XCTAssertEqual(error as? WorkoutServiceError, .sessionNotInProgress)
        }
    }

    func testFinishingPersistentTemplateUpdatesOnlyExistingExercisesFromCompletedWorkingSets() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let squat = Exercise(name: "深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let row = Exercise(name: "坐姿划船", muscleGroup: "背部", equipment: "器械")
        let temporary = Exercise(name: "临时加练", muscleGroup: "核心", equipment: "自重")
        let template = WorkoutTemplate(name: "力量专项", weekday: Date.now.weekdayNumber)
        let squatItem = TemplateExercise(
            templateID: template.id,
            exerciseID: squat.id,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 50,
            restSeconds: 120
        )
        let rowItem = TemplateExercise(
            templateID: template.id,
            exerciseID: row.id,
            order: 1,
            targetSets: 3,
            minReps: 10,
            maxReps: 10,
            targetWeight: 40,
            restSeconds: 90
        )
        let originalRowPlan = rowItem.plannedSets
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: .now,
            status: .inProgress
        )
        let session = WorkoutSession(
            scheduledWorkoutID: schedule.id,
            templateID: template.id,
            templateName: template.name,
            plannedDate: .now
        )
        let squatSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: squat.id,
            exerciseName: squat.name,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 50,
            restSeconds: 120
        )
        let rowSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: row.id,
            exerciseName: row.name,
            order: 1,
            targetSets: 3,
            minReps: 10,
            maxReps: 10,
            targetWeight: 40,
            restSeconds: 90
        )
        let temporarySnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: temporary.id,
            exerciseName: temporary.name,
            order: 2,
            targetSets: 1,
            minReps: 12,
            maxReps: 12,
            targetWeight: 0,
            restSeconds: 60,
            volumeUnit: .count
        )
        let logs = [
            SetLog(sessionID: session.id, sessionExerciseID: squatSnapshot.id, exerciseID: squat.id, setNumber: 1, targetWeight: 20, targetReps: 10, actualWeight: 20, actualReps: 10, isWarmup: true, isCompleted: true),
            SetLog(sessionID: session.id, sessionExerciseID: squatSnapshot.id, exerciseID: squat.id, setNumber: 2, targetWeight: 50, targetReps: 8, actualWeight: 62.5, actualReps: 8, isCompleted: true, actualWeightSide: .single, actualRepsSide: .bilateral),
            SetLog(sessionID: session.id, sessionExerciseID: squatSnapshot.id, exerciseID: squat.id, setNumber: 3, targetWeight: 50, targetReps: 8, actualWeight: 65, actualReps: 6, isCompleted: true),
            SetLog(sessionID: session.id, sessionExerciseID: squatSnapshot.id, exerciseID: squat.id, setNumber: 4, targetWeight: 67.5, targetReps: 5, actualWeight: 67.5, actualReps: 4),
            SetLog(sessionID: session.id, sessionExerciseID: rowSnapshot.id, exerciseID: row.id, setNumber: 1, targetWeight: 40, targetReps: 10, actualWeight: 45, actualReps: 8),
            SetLog(sessionID: session.id, sessionExerciseID: temporarySnapshot.id, exerciseID: temporary.id, setNumber: 1, targetWeight: 0, targetReps: 12, actualWeight: 0, actualReps: 15, isCompleted: true)
        ]

        context.insert(squat)
        context.insert(row)
        context.insert(temporary)
        context.insert(template)
        context.insert(squatItem)
        context.insert(rowItem)
        context.insert(schedule)
        context.insert(session)
        context.insert(squatSnapshot)
        context.insert(rowSnapshot)
        context.insert(temporarySnapshot)
        logs.forEach(context.insert)
        try context.save()

        try WorkoutService.finish(session: session, schedules: [schedule], in: context)

        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(schedule.status, .completed)
        XCTAssertEqual(squatItem.plannedSets.map(\.weight), [62.5, 65])
        XCTAssertEqual(squatItem.plannedSets.map(\.reps), [8, 6])
        XCTAssertEqual(squatItem.plannedSets.map(\.weightSide), [.single, .bilateral])
        XCTAssertEqual(squatItem.targetSets, 2)
        XCTAssertEqual(squatItem.minReps, 6)
        XCTAssertEqual(squatItem.maxReps, 8)
        XCTAssertEqual(rowItem.plannedSets, originalRowPlan, "未完成有效组的模板动作必须保持原计划")
        XCTAssertFalse(
            try context.fetch(FetchDescriptor<TemplateExercise>()).contains { $0.exerciseID == temporary.id },
            "临时加练动作不能自动加入模板"
        )

        let storedLogs = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionID == session.id }
        XCTAssertEqual(storedLogs.count, logs.count)
        XCTAssertEqual(storedLogs.first { $0.setNumber == 2 && $0.exerciseID == squat.id }?.actualWeight, 62.5)
    }

    func testFinishingOneOffWorkoutDoesNotRewriteTemplatePlan() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let template = WorkoutTemplate(
            name: "当天菜单",
            weekday: Date.now.weekdayNumber,
            isActive: false,
            isOneOff: true,
            plannedForDate: .now
        )
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 50,
            restSeconds: 120
        )
        let originalPlan = item.plannedSets
        let session = WorkoutSession(templateID: template.id, templateName: template.name, plannedDate: .now)
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 50,
            restSeconds: 120
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 50,
            targetReps: 8,
            actualWeight: 70,
            actualReps: 5,
            isCompleted: true
        )
        context.insert(exercise)
        context.insert(template)
        context.insert(item)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        try WorkoutService.finish(session: session, schedules: [], in: context)

        XCTAssertEqual(item.plannedSets, originalPlan)
    }

    func testBackupRoundTripPreservesPerSetPlansPatternsAndIndependentSideModes() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let exercise = Exercise(name: "保加利亚分腿蹲", muscleGroup: "腿部", equipment: "哑铃")
        let template = WorkoutTemplate(
            name: "逐组计划",
            weekday: Date.now.weekdayNumber,
            defaultPlanPattern: .pyramidUp
        )
        let plans = [
            WorkoutSetPlan(weight: 12, reps: 12, weightSide: .single, repsSide: .single),
            WorkoutSetPlan(weight: 14, reps: 10, weightSide: .single, repsSide: .bilateral)
        ]
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: 2,
            minReps: 10,
            maxReps: 12,
            targetWeight: 12,
            restSeconds: 90,
            plannedSets: plans,
            planPattern: .pyramidUp,
            patternSource: .dayDefault
        )
        let session = WorkoutSession(
            templateName: template.name,
            plannedDate: .now,
            status: .completed,
            defaultPlanPattern: .pyramidUp
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 2,
            minReps: 10,
            maxReps: 12,
            targetWeight: 12,
            restSeconds: 90,
            plannedSets: plans,
            planPattern: .pyramidUp,
            patternSource: .dayDefault
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 12,
            targetReps: 12,
            actualWeight: 13,
            actualReps: 11,
            isCompleted: true,
            targetWeightSide: .single,
            targetRepsSide: .single,
            actualWeightSide: .bilateral,
            actualRepsSide: .bilateral
        )
        context.insert(exercise)
        context.insert(template)
        context.insert(item)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        let data = try Data(contentsOf: DataExportService.createBackup(in: context))
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)

        let importedItem = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<TemplateExercise>()).first)
        let importedTemplate = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<WorkoutTemplate>()).first)
        let importedSession = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first)
        let importedSnapshot = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first)
        let importedLog = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SetLog>()).first)
        XCTAssertEqual(importedTemplate.defaultPlanPattern, .pyramidUp)
        XCTAssertEqual(importedItem.planPattern, .pyramidUp)
        XCTAssertEqual(importedItem.patternSource, .dayDefault)
        XCTAssertEqual(importedItem.plannedSets, plans)
        XCTAssertEqual(importedSession.defaultPlanPattern, .pyramidUp)
        XCTAssertEqual(importedSnapshot.planPattern, .pyramidUp)
        XCTAssertEqual(importedSnapshot.patternSource, .dayDefault)
        XCTAssertEqual(importedSnapshot.plannedSets, plans)
        XCTAssertEqual(importedLog.targetWeightSide, .single)
        XCTAssertEqual(importedLog.targetRepsSide, .single)
        XCTAssertEqual(importedLog.actualWeightSide, .bilateral)
        XCTAssertEqual(importedLog.actualRepsSide, .bilateral)
    }

    func testLegacyBackupWithoutPerSetFieldsUsesFixedBilateralFallbacks() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let exercise = Exercise(name: "旧版卧推", muscleGroup: "胸部", equipment: "杠铃")
        let template = WorkoutTemplate(name: "旧版计划", weekday: Date.now.weekdayNumber)
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: 2,
            minReps: 8,
            maxReps: 10,
            targetWeight: 40,
            restSeconds: 90
        )
        let session = WorkoutSession(templateName: template.name, plannedDate: .now)
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 2,
            minReps: 8,
            maxReps: 10,
            targetWeight: 40,
            restSeconds: 90
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 40,
            targetReps: 8,
            actualWeight: 42.5,
            actualReps: 7
        )
        context.insert(exercise)
        context.insert(template)
        context.insert(item)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        let currentData = try Data(contentsOf: DataExportService.createBackup(in: context))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        var legacy = object
        legacy["schemaVersion"] = 7
        legacy["templates"] = (object["templates"] as? [[String: Any]] ?? []).map { record in
            record.filter { $0.key != "defaultPlanPatternRaw" }
        }
        legacy["templateExercises"] = (object["templateExercises"] as? [[String: Any]] ?? []).map { record in
            record.filter { !["plannedSetsJSON", "planPatternRaw", "patternSourceRaw"].contains($0.key) }
        }
        legacy["sessions"] = (object["sessions"] as? [[String: Any]] ?? []).map { record in
            record.filter { $0.key != "defaultPlanPatternRaw" }
        }
        legacy["sessionExercises"] = (object["sessionExercises"] as? [[String: Any]] ?? []).map { record in
            record.filter { !["plannedSetsJSON", "planPatternRaw", "patternSourceRaw"].contains($0.key) }
        }
        legacy["setLogs"] = (object["setLogs"] as? [[String: Any]] ?? []).map { record in
            record.filter {
                !["targetWeightSideRaw", "targetRepsSideRaw", "actualWeightSideRaw", "actualRepsSideRaw"]
                    .contains($0.key)
            }
        }
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(legacyData, into: destination.mainContext)
        let importedItem = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<TemplateExercise>()).first)
        let importedSnapshot = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first)
        let importedLog = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SetLog>()).first)
        XCTAssertEqual(importedItem.planPattern, .fixed)
        XCTAssertEqual(importedItem.plannedSets.map(\.weight), [40, 40])
        XCTAssertEqual(importedSnapshot.planPattern, .fixed)
        XCTAssertEqual(importedSnapshot.plannedSets.map(\.reps), [8, 8])
        XCTAssertEqual(importedLog.targetWeightSide, .bilateral)
        XCTAssertEqual(importedLog.targetRepsSide, .bilateral)
        XCTAssertEqual(importedLog.actualWeightSide, .bilateral)
        XCTAssertEqual(importedLog.actualRepsSide, .bilateral)
    }

    func testStrictSquatConsolidationIsIdempotentRemovesPlanCollisionAndRemapsLogs() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let squat = Exercise(name: "深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let strict = Exercise(name: "严格深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let template = WorkoutTemplate(name: "腿", weekday: Date.now.weekdayNumber)
        let primaryItem = TemplateExercise(
            templateID: template.id, exerciseID: squat.id, order: 0,
            targetSets: 3, minReps: 6, maxReps: 8, targetWeight: 60, restSeconds: 120
        )
        let duplicateItem = TemplateExercise(
            templateID: template.id, exerciseID: strict.id, order: 1,
            targetSets: 3, minReps: 6, maxReps: 8, targetWeight: 60, restSeconds: 120
        )
        let snapshot = SessionExercise(
            sessionID: UUID(), exerciseID: strict.id, exerciseName: "严格深蹲", order: 0,
            targetSets: 1, minReps: 6, maxReps: 6, targetWeight: 60, restSeconds: 120
        )
        let log = SetLog(
            sessionID: snapshot.sessionID, sessionExerciseID: snapshot.id, exerciseID: strict.id,
            setNumber: 1, targetWeight: 60, targetReps: 6, actualWeight: 62.5, actualReps: 5
        )
        context.insert(squat)
        context.insert(strict)
        context.insert(template)
        context.insert(primaryItem)
        context.insert(duplicateItem)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        try ExerciseCatalogService.consolidateConfirmedSquatDuplicate(in: context)
        // An unchanged archived alias must retain its last real modification.
        let archivedAt = Date(timeIntervalSince1970: 1_700_000_000)
        strict.updatedAt = archivedAt
        try context.save()
        try ExerciseCatalogService.consolidateConfirmedSquatDuplicate(in: context)
        try context.save()

        XCTAssertEqual(strict.updatedAt, archivedAt)

        let templateItems = try context.fetch(FetchDescriptor<TemplateExercise>())
            .filter { $0.templateID == template.id }
        XCTAssertEqual(templateItems.count, 1)
        XCTAssertEqual(templateItems.first?.exerciseID, squat.id)
        XCTAssertEqual(snapshot.exerciseID, squat.id)
        XCTAssertEqual(snapshot.exerciseName, "严格深蹲")
        XCTAssertEqual(log.exerciseID, squat.id)
        XCTAssertTrue(strict.isArchived)
        XCTAssertEqual(ExerciseCatalogService.search([squat], query: "严格深蹲").map(\.id), [squat.id])
    }

    func testRunningWorkoutMenuSyncUsesBuilderOrderAndPreservesCompletedFacts() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let fly = Exercise(name: "绳索反向飞鸟", muscleGroup: "肩部", equipment: "龙门架")
        let decline = Exercise(name: "MTS 下斜卧推", muscleGroup: "胸部", equipment: "固定器械")
        let schedule = ScheduledWorkout(
            templateID: UUID(),
            templateName: "肩部 + 胸部 · 当天菜单",
            plannedDate: .now,
            status: .inProgress
        )
        let session = WorkoutSession(
            scheduledWorkoutID: schedule.id,
            templateName: "肩部 + 胸部 · 当天菜单",
            plannedDate: .now,
            status: .inProgress
        )
        let flySnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: fly.id,
            exerciseName: fly.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 5,
            restSeconds: 90
        )
        let declineSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: decline.id,
            exerciseName: decline.name,
            order: 1,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 25,
            restSeconds: 90
        )
        let completedFlySet = SetLog(
            sessionID: session.id,
            sessionExerciseID: flySnapshot.id,
            exerciseID: fly.id,
            setNumber: 1,
            targetWeight: 5,
            targetReps: 10,
            actualWeight: 8.875,
            actualReps: 12,
            rir: 3,
            isCompleted: true,
            completedAt: .now
        )
        let pendingDeclineSet = SetLog(
            sessionID: session.id,
            sessionExerciseID: declineSnapshot.id,
            exerciseID: decline.id,
            setNumber: 1,
            targetWeight: 25,
            targetReps: 10,
            actualWeight: 25,
            actualReps: 10,
            actualEntrySource: .manual
        )
        [fly, decline].forEach(context.insert)
        context.insert(schedule)
        context.insert(session)
        [flySnapshot, declineSnapshot].forEach(context.insert)
        [completedFlySet, pendingDeclineSet].forEach(context.insert)
        try context.save()

        try WorkoutService.syncMenu(
            [
                DailyPlanExerciseInput(
                    exerciseID: decline.id,
                    plannedSets: [WorkoutSetPlan(weight: 30.125, reps: 8)],
                    planPattern: .pyramidUp,
                    patternSource: .dayDefault,
                    restSeconds: 120
                ),
                DailyPlanExerciseInput(
                    exerciseID: fly.id,
                    plannedSets: [
                        WorkoutSetPlan(weight: 5, reps: 10),
                        WorkoutSetPlan(weight: 7.5, reps: 8)
                    ],
                    planPattern: .fixed,
                    restSeconds: 150
                )
            ],
            to: session,
            muscleGroups: ["背部", "核心"],
            defaultPlanPattern: .pyramidUp,
            in: context
        )

        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == session.id }
            .sorted { $0.order < $1.order }
        XCTAssertEqual(snapshots.map(\.exerciseID), [fly.id, decline.id])
        XCTAssertEqual(session.templateName, "背部 + 核心 · 当天菜单")
        XCTAssertEqual(schedule.templateName, "背部 + 核心 · 当天菜单")
        XCTAssertEqual(session.defaultPlanPattern, .pyramidUp)
        XCTAssertEqual(declineSnapshot.patternSource, .dayDefault)
        XCTAssertEqual(declineSnapshot.restSeconds, 120)
        XCTAssertEqual(flySnapshot.restSeconds, 150)
        XCTAssertEqual(flySnapshot.plannedSets.map(\.weight), [5, 7.5])
        XCTAssertEqual(pendingDeclineSet.targetWeight, 30.125, accuracy: 0.0001)
        XCTAssertEqual(pendingDeclineSet.actualWeight, 25, accuracy: 0.0001)
        XCTAssertEqual(pendingDeclineSet.actualEntrySource, .manual)
        XCTAssertEqual(completedFlySet.actualWeight, 8.875, accuracy: 0.0001)
        XCTAssertEqual(completedFlySet.targetWeight, 5, accuracy: 0.0001)
        let pendingFlySet = try XCTUnwrap(
            try context.fetch(FetchDescriptor<SetLog>())
                .first { $0.sessionExerciseID == flySnapshot.id && $0.setNumber == 2 }
        )
        XCTAssertEqual(pendingFlySet.targetWeight, 7.5, accuracy: 0.0001)
        XCTAssertEqual(pendingFlySet.targetReps, 8)
        XCTAssertEqual(flySnapshot.order, 0, "已开始动作的顺序不应被外部编排改写")
        XCTAssertTrue(completedFlySet.isCompleted)
    }

    func testWeightFormatterShowsUpToThreeDecimalsWithoutPadding() {
        XCTAssertEqual(TrainingFormatters.weight(5), "5")
        XCTAssertTrue(TrainingFormatters.weight(8.875).contains("875"))
    }

    func testLocalAgentPreviewsJumpRopeWithoutWriting() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let interpretation = LocalWellnessAgent.interpret("刚跳绳 1200 个", now: now)

        XCTAssertEqual(
            interpretation,
            .pending(.recordJumpRope(count: 1_200, durationMinutes: nil, at: now))
        )
    }

    func testLocalAgentPreviewsWaterAndRejectsUnsupportedRequests() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            LocalWellnessAgent.interpret("喝了 300ml 水", now: now),
            .pending(.recordWater(milliliters: 300, at: now))
        )
        XCTAssertEqual(
            LocalWellnessAgent.interpret("帮我制定减脂食谱", now: now),
            .unsupported(message: "我暂时只能处理跳绳、喝水、久坐和体重记录。")
        )
    }

    func testWellnessToolExecutesWaterAndBuildsTodaySummary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let result = try WellnessToolService.execute(
            .recordWater(milliliters: 300, at: date),
            in: context
        )

        XCTAssertEqual(result.message, "已记录 300 ml 饮水")
        let entries = try context.fetch(FetchDescriptor<HydrationEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.milliliters, 300)
        XCTAssertEqual(
            WellnessToolService.todaySummary(
                on: date,
                hydrationEntries: entries,
                jumpRopeEntries: [],
                sedentarySessions: []
            ).waterMilliliters,
            300
        )
    }

    func testLocalAgentPreviewsSedentaryWeightAndSummaryCommands() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            LocalWellnessAgent.interpret("开始久坐", now: now),
            .pending(.startSedentary(at: now))
        )
        XCTAssertEqual(
            LocalWellnessAgent.interpret("刚才坐了 90 分钟", now: now),
            .pending(.recordSedentary(
                startedAt: now.addingTimeInterval(-5_400),
                durationMinutes: 90
            ))
        )
        XCTAssertEqual(
            LocalWellnessAgent.interpret("体重 83.6 kg", now: now),
            .pending(.recordWeight(kilograms: 83.6, at: now))
        )
        XCTAssertEqual(
            LocalWellnessAgent.interpret("我今天喝了多少水？", now: now),
            .pending(.queryTodaySummary(on: now))
        )
    }

    func testWellnessToolExecutesJumpRopeAndSedentaryLifecycle() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try WellnessToolService.execute(
            .recordJumpRope(count: 1_200, durationMinutes: 12, at: start),
            in: context
        )
        let started = try WellnessToolService.execute(.startSedentary(at: start), in: context)
        XCTAssertThrowsError(try WellnessToolService.execute(.startSedentary(at: start), in: context)) { error in
            XCTAssertEqual(error as? WellnessToolError, .sedentaryAlreadyActive)
        }
        let stopped = try WellnessToolService.execute(
            .stopSedentary(at: start.addingTimeInterval(5_400)),
            in: context
        )

        let jumps = try context.fetch(FetchDescriptor<JumpRopeEntry>())
        let sedentary = try context.fetch(FetchDescriptor<SedentarySession>())
        let summary = WellnessToolService.todaySummary(
            on: start.addingTimeInterval(5_400),
            hydrationEntries: [],
            jumpRopeEntries: jumps,
            sedentarySessions: sedentary
        )
        XCTAssertEqual(jumps.first?.durationSeconds, 720)
        XCTAssertEqual(summary.jumpRopeCount, 1_200)
        XCTAssertEqual(summary.sedentaryMinutes, 90)
        XCTAssertEqual(started.message, "久坐计时已开始")
        XCTAssertEqual(stopped.message, "已记录久坐 90 分钟")
    }

    func testWellnessToolSupportsManualSedentaryAndUndo() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try WellnessToolService.execute(
            .recordSedentary(startedAt: start, durationMinutes: 45),
            in: context
        )
        let undo = try XCTUnwrap(result.undoAction)

        XCTAssertEqual(try context.fetch(FetchDescriptor<SedentarySession>()).count, 1)
        try WellnessToolService.undo(undo, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SedentarySession>()).count, 0)
    }

    func testBackupRoundTripsWellnessToolRecordsIdempotently() throws {
        let source = try makeContainer()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        source.mainContext.insert(HydrationEntry(milliliters: 250, date: date))
        source.mainContext.insert(JumpRopeEntry(count: 1_200, durationSeconds: 720, date: date))
        source.mainContext.insert(SedentarySession(
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600)
        ))
        try source.mainContext.save()

        let url = try DataExportService.createBackup(in: source.mainContext)
        let data = try Data(contentsOf: url)
        let preview = try DataExportService.preview(data)
        XCTAssertEqual(preview.hydrationEntries, 1)
        XCTAssertEqual(preview.jumpRopeEntries, 1)
        XCTAssertEqual(preview.sedentarySessions, 1)

        let destination = try makeContainer()
        let first = try DataExportService.importBackup(data, into: destination.mainContext)
        let second = try DataExportService.importBackup(data, into: destination.mainContext)
        XCTAssertEqual(first.imported, 3)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<HydrationEntry>()).count, 1)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<JumpRopeEntry>()).count, 1)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<SedentarySession>()).count, 1)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            ScheduledWorkout.self,
            WorkoutSession.self,
            SessionExercise.self,
            SetLog.self,
            NutritionTarget.self,
            MealEntry.self,
            DailyBodyCheckIn.self,
            BodyMeasurement.self,
            HydrationEntry.self,
            JumpRopeEntry.self,
            SedentarySession.self,
            FatLossProgram.self,
            ProgramWorkoutLink.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makePersistentContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            WorkoutTemplate.self,
            TemplateExercise.self,
            ScheduledWorkout.self,
            WorkoutSession.self,
            SessionExercise.self,
            SetLog.self,
            NutritionTarget.self,
            MealEntry.self,
            DailyBodyCheckIn.self,
            BodyMeasurement.self,
            HydrationEntry.self,
            JumpRopeEntry.self,
            SedentarySession.self
        ])
        let configuration = ModelConfiguration(
            "RestPersistenceTests",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSet(
        sessionID: UUID,
        setNumber: Int,
        sessionExerciseID: UUID = UUID()
    ) -> SetLog {
        SetLog(
            sessionID: sessionID,
            sessionExerciseID: sessionExerciseID,
            exerciseID: UUID(),
            setNumber: setNumber,
            targetWeight: 50,
            targetReps: 10,
            actualWeight: 50,
            actualReps: 10
        )
    }
}
