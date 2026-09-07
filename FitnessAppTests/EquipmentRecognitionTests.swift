import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class EquipmentRecognitionTests: XCTestCase {
    func testBodyweightIsExplicitAndCountsRepetitions() {
        XCTAssertEqual(ExerciseVolumeUnit.bodyweight.symbol, "kg·次")
        XCTAssertFalse(ExerciseVolumeUnit.bodyweight.recordsNumericLoad)
        XCTAssertEqual(ExerciseVolumeUnit.bodyweight.volume(weight: 92, reps: 12), 1_104)
    }

    func testEquipmentEnglishNameAndAliasParticipateInExerciseSearch() {
        let exercise = Exercise(
            name: "史密斯机上斜卧推",
            muscleGroup: "胸部",
            equipment: "史密斯机"
        )

        XCTAssertEqual(
            ExerciseCatalogService.search([exercise], query: "smith machine").map(\.id),
            [exercise.id]
        )
        XCTAssertEqual(EquipmentCatalogService.englishName(for: "史密斯"), "Smith Machine")
    }

    func testExerciseEditorEquipmentChoicesCoverCommonFreeWeights() {
        XCTAssertTrue(EquipmentCatalogService.commonChoices.contains("自重"))
        XCTAssertTrue(EquipmentCatalogService.commonChoices.contains("哑铃"))
        XCTAssertTrue(EquipmentCatalogService.commonChoices.contains("杠铃"))
        XCTAssertTrue(EquipmentCatalogService.commonChoices.contains("壶铃"))
        XCTAssertEqual(EquipmentCatalogService.englishName(for: "壶铃"), "Kettlebell")
    }

    func testPreviousSettingsCopyCompletedWorkingSetsWithoutMutatingHistory() throws {
        let exercise = Exercise(
            name: "单臂划船",
            muscleGroup: "背部",
            equipment: "哑铃"
        )
        let session = WorkoutSession(
            templateName: "拉日",
            plannedDate: .now.addingTimeInterval(-86_400),
            completedAt: .now.addingTimeInterval(-80_000),
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 2,
            minReps: 10,
            maxReps: 12,
            targetWeight: 24,
            restSeconds: 120,
            volumeUnit: .kilogram
        )
        let first = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 24,
            targetReps: 12,
            actualWeight: 26,
            actualReps: 11,
            isCompleted: true,
            targetWeightSide: .single,
            targetRepsSide: .single
        )
        let second = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 2,
            targetWeight: 24,
            targetReps: 12,
            actualWeight: 26,
            actualReps: 10,
            isCompleted: true,
            targetWeightSide: .single,
            targetRepsSide: .single
        )

        let draft = ExerciseSetupDraft.suggested(
            for: exercise,
            sessions: [session],
            sessionExercises: [snapshot],
            setLogs: [first, second]
        )

        XCTAssertEqual(draft.plannedSets.map { $0.weight }, [26, 26])
        XCTAssertEqual(draft.plannedSets.map { $0.reps }, [11, 10])
        XCTAssertEqual(draft.measurementSide, MeasurementSide.single)
        XCTAssertEqual(draft.restSeconds, 120)
        XCTAssertNotNil(draft.previousDate)
        XCTAssertEqual(first.actualWeight, 26)
        XCTAssertEqual(snapshot.targetWeight, 24)
    }

    func testConfiguredTemporaryExerciseUsesDraftAndKeepsExistingHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "器械腿举", muscleGroup: "腿部", equipment: "腿举机")
        let session = WorkoutSession(templateName: "腿日", plannedDate: .now)
        context.insert(exercise)
        context.insert(session)
        try context.save()

        let draft = ExerciseSetupDraft(
            pattern: .fixed,
            plannedSets: [
                WorkoutSetPlan(weight: 80, reps: 12, weightSide: .bilateral, repsSide: .bilateral),
                WorkoutSetPlan(weight: 90, reps: 10, weightSide: .bilateral, repsSide: .bilateral)
            ],
            restSeconds: 150,
            previousDate: .now.addingTimeInterval(-86_400)
        )
        let snapshot = try WorkoutService.addExercise(
            exercise,
            to: session,
            configuration: draft,
            in: context
        )
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == snapshot.id }
            .sorted { $0.setNumber < $1.setNumber }

        XCTAssertEqual(snapshot.targetSets, 2)
        XCTAssertEqual(snapshot.restSeconds, 150)
        XCTAssertEqual(logs.map(\.actualWeight), [80, 90])
        XCTAssertEqual(logs.map(\.actualReps), [12, 10])
    }

    func testMockRecognitionAlwaysRequiresHumanConfirmation() {
        let result = EquipmentRecognitionService.mockResponse
        XCTAssertTrue(result.needsConfirmation)
        XCTAssertFalse(result.machine.nameZH.isEmpty)
        XCTAssertFalse(result.machine.nameEN.isEmpty)
        XCTAssertFalse(result.exerciseCandidates.isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self,
            WorkoutSession.self,
            SessionExercise.self,
            SetLog.self,
            ScheduledWorkout.self,
            WorkoutTemplate.self,
            TemplateExercise.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }
}
