import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class NotesCatalogSupplementTests: XCTestCase {
    func testCatalogSupplementIsIdempotentAndPreservesCompletedHistoryAndUnknowns() throws {
        let context = try makeContext()
        let original = Exercise(name: "杠铃片侧边挤压", muscleGroup: "核心", equipment: "杠铃片",
                                notes: "原始计重仍未知", volumeUnit: .kilogram)
        let date = Date(timeIntervalSince1970: 1_792_540_800)
        let session = WorkoutSession(templateName: "Notes原始训练", plannedDate: date,
                                     startedAt: date, completedAt: date, status: .completed,
                                     notes: "保持原名与未知", importIdentifier: "stable-notes-source")
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: original.id,
                                       exerciseName: "原始侧边挤压", order: 2, targetSets: 1,
                                       minReps: 10, maxReps: 10, targetWeight: 20,
                                       restSeconds: 90, muscleGroup: "核心", exerciseNotes: "原始说明")
        let log = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id,
                         exerciseID: original.id, setNumber: 1, targetWeight: 20,
                         targetReps: 10, actualWeight: 20, actualReps: 10,
                         isCompleted: true, completedAt: date)
        log.actualWeightSideRaw = nil
        log.actualRepsSideRaw = nil
        context.insert(original); context.insert(session); context.insert(snapshot); context.insert(log)
        try context.save()
        let historyPlan = snapshot.plannedSetsJSON
        let originalUpdated = original.updatedAt

        let first = try ExerciseCatalogService.ensureNotesCatalogSupplement(in: context)
        let second = try ExerciseCatalogService.ensureNotesCatalogSupplement(in: context)
        XCTAssertEqual(first.createdIDs.count, ExerciseCatalogService.notesSupplementEntries.count)
        XCTAssertEqual(Set(first.createdIDs).count, first.createdIDs.count)
        XCTAssertTrue(first.conflictingNames.isEmpty)
        XCTAssertTrue(second.createdIDs.isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).count, first.createdIDs.count + 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SessionExercise>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).count, 1)
        XCTAssertEqual(original.updatedAt, originalUpdated)
        XCTAssertEqual(original.name, "杠铃片侧边挤压")
        XCTAssertEqual(original.notes, "原始计重仍未知")
        XCTAssertEqual(snapshot.exerciseID, original.id)
        XCTAssertEqual(snapshot.exerciseName, "原始侧边挤压")
        XCTAssertEqual(snapshot.order, 2)
        XCTAssertEqual(snapshot.plannedSetsJSON, historyPlan)
        XCTAssertEqual(log.sessionID, session.id)
        XCTAssertEqual(log.sessionExerciseID, snapshot.id)
        XCTAssertEqual(log.exerciseID, original.id)
        XCTAssertEqual(log.actualWeight, 20)
        XCTAssertEqual(log.actualReps, 10)
        XCTAssertTrue(log.isCompleted)
        XCTAssertNil(log.rir)
        XCTAssertNil(log.actualWeightSideRaw)
        XCTAssertNil(log.actualRepsSideRaw)
        XCTAssertEqual(session.importIdentifier, "stable-notes-source")
        XCTAssertEqual(session.completedAt, date)
    }

    func testPlateRotationIsFoundByAllOwnerKeywordsAndSearchHintsDoNotMergeIdentity() throws {
        let context = try makeContext()
        try ExerciseCatalogService.ensureNotesCatalogSupplement(in: context)
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        let rotation = try XCTUnwrap(catalog.first { $0.name == "杠铃片胸前转体" })
        for query in ["杠铃片", "胸前", "转体", "腹部杠铃片胸前转体", "杠铃片胸前转体（单边）"] {
            XCTAssertTrue(ExerciseCatalogService.search(catalog, query: query).contains { $0.id == rotation.id }, query)
        }
        let row = Exercise(name: "双滑轮低位划船", muscleGroup: "背部", equipment: "双滑轮器械")
        XCTAssertTrue(ExerciseCatalogService.search([row], query: "Dual Pulley Low Row").contains { $0.id == row.id })
        XCTAssertNil(ExerciseCatalogService.exactNameMatch(named: "Dual Pulley Low Row", in: [row]))
        XCTAssertNil(row.approvedCanonicalID)
        XCTAssertEqual(row.name, "双滑轮低位划船")
        XCTAssertEqual(row.terminologyDecision, .pending)
        XCTAssertNil(ExerciseCatalogService.exactNameMatch(named: "腹部杠铃片胸前转体", in: catalog))
    }

    func testExistingOwnerFieldsArchiveAndNameConflictsAreNeverOverwritten() throws {
        let context = try makeContext()
        let existing = Exercise(name: "杠铃片胸前转体", muscleGroup: "核心", equipment: "杠铃片",
                                defaultRestSeconds: 123, isBuiltIn: false, isArchived: true,
                                notes: "本人备注", referenceURL: "https://example.com/owner")
        let conflict = Exercise(name: "平板支撑", muscleGroup: "手臂", equipment: "自定义机器",
                                volumeUnit: .kilogram)
        context.insert(existing); context.insert(conflict); try context.save()
        let result = try ExerciseCatalogService.ensureNotesCatalogSupplement(in: context)
        XCTAssertEqual(result.conflictingNames, ["平板支撑"])
        XCTAssertEqual(result.createdIDs.count, ExerciseCatalogService.notesSupplementEntries.count - 2)
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(catalog.filter { $0.name == "杠铃片胸前转体" }.count, 1)
        XCTAssertTrue(existing.isArchived)
        XCTAssertEqual(existing.defaultRestSeconds, 123)
        XCTAssertEqual(existing.notes, "本人备注")
        XCTAssertEqual(existing.referenceURL, "https://example.com/owner")
        XCTAssertEqual(conflict.muscleGroup, "手臂")
        XCTAssertEqual(conflict.equipment, "自定义机器")
        XCTAssertEqual(conflict.volumeUnit, .kilogram)
    }

    func testRenamedStableSupplementItemIsNotRecreatedOrRestored() throws {
        let context = try makeContext()
        try ExerciseCatalogService.ensureNotesCatalogSupplement(in: context)
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        let item = try XCTUnwrap(catalog.first { $0.name == "杠铃片胸前转体" })
        let originalID = item.id
        item.name = "本人重新命名转体"; item.isArchived = true; item.notes = "新的本人资料"
        try context.save()
        let result = try ExerciseCatalogService.ensureNotesCatalogSupplement(in: context)
        XCTAssertTrue(result.createdIDs.isEmpty)
        XCTAssertEqual(item.id, originalID)
        XCTAssertEqual(item.name, "本人重新命名转体")
        XCTAssertEqual(item.notes, "新的本人资料")
        XCTAssertTrue(item.isArchived)
        XCTAssertFalse(try context.fetch(FetchDescriptor<Exercise>()).contains { $0.name == "杠铃片胸前转体" })
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Exercise.self, WorkoutSession.self, SessionExercise.self, SetLog.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        return ModelContext(container)
    }
}
