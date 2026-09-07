import XCTest
@testable import FitnessApp

@MainActor
final class MuscleCoverageTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_783_000_000)
    private func session(status: WorkoutSessionStatus = .completed, offset: TimeInterval = 0) -> WorkoutSession {
        WorkoutSession(templateName: "测试", plannedDate: date, startedAt: date.addingTimeInterval(offset),
            completedAt: status == .completed ? date.addingTimeInterval(offset + 60) : nil, status: status)
    }
    private func snapshot(_ session: WorkoutSession, group: String = "胸部", order: Int = 0, exerciseID: UUID = UUID(), unit: ExerciseVolumeUnit = .kilogram) -> SessionExercise {
        SessionExercise(sessionID: session.id, exerciseID: exerciseID, exerciseName: "动作", order: order,
            targetSets: 2, minReps: 8, maxReps: 12, targetWeight: 99, restSeconds: 90, muscleGroup: group, volumeUnit: unit)
    }
    private func log(_ snapshot: SessionExercise, completed: Bool = true, warmup: Bool = false) -> SetLog {
        SetLog(sessionID: snapshot.sessionID, sessionExerciseID: snapshot.id, exerciseID: snapshot.exerciseID,
            setNumber: 1, targetWeight: 99, targetReps: 12, actualWeight: 25, actualReps: 8,
            isWarmup: warmup, isCompleted: completed, completedAt: completed ? date.addingTimeInterval(30) : nil)
    }
    func testCoverageUsesCompletedSnapshotWorkOnlyAndDeduplicatesIDs() {
        let valid = session()
        let discarded = session(status: .discarded)
        let original = snapshot(valid, group: "胸部 / 三头")
        let removed = snapshot(discarded, group: "腿部")
        let completed = log(original)
        let crossSession = log(original); crossSession.sessionID = discarded.id
        let orphan = log(original); orphan.sessionExerciseID = UUID()
        let values = MuscleCoverageService.coverage(from: date, through: date.addingTimeInterval(100),
            sessions: [valid, discarded], snapshots: [original, removed],
            logs: [completed, completed, log(original, completed: false), log(original, warmup: true), log(removed), crossSession, orphan])
        XCTAssertEqual(values.first { $0.group == "胸部" }?.completedSets, 1)
        XCTAssertEqual(values.first { $0.group == "手臂" }?.completedSets, 1)
        XCTAssertEqual(values.first { $0.group == "腿部" }?.completedSets, 0)
        XCTAssertEqual(original.muscleGroup, "胸部 / 三头")
    }
    func testCoverageKeepsUnmappedGroupsAndHonorsDateRange() {
        let workout = session()
        let exercise = snapshot(workout, group: "自定义稳定肌")
        let completed = log(exercise)
        let values = MuscleCoverageService.coverage(from: date, through: date.addingTimeInterval(100), sessions: [workout], snapshots: [exercise], logs: [completed])
        XCTAssertEqual(values.first { $0.group == "自定义稳定肌" }?.completedSets, 1)
        let outside = MuscleCoverageService.coverage(from: date.addingTimeInterval(50), through: date.addingTimeInterval(100), sessions: [workout], snapshots: [exercise], logs: [completed])
        XCTAssertEqual(outside.reduce(0) { $0 + $1.completedSets }, 0)
    }
    func testCompletedExerciseDoesNotMoveAheadOfOriginalOrder() {
        let workout = session(status: .inProgress)
        let first = snapshot(workout, order: 0)
        let second = snapshot(workout, order: 1)
        let completed = log(second)
        let ordered = MuscleCoverageService.stableOrder([second, first], sessionID: workout.id)
        XCTAssertEqual(ordered.map(\.id), [first.id, second.id])
        XCTAssertEqual(MuscleCoverageService.initialExpandedID(ordered, logs: [completed]), first.id)
    }
    func testLastReferenceUsesActualValuesAndMatchingHistoricalUnit() {
        let old = session(offset: -1_000)
        let newerWrongUnit = session(offset: -500)
        let current = session(status: .inProgress, offset: 100)
        let identity = UUID()
        let past = snapshot(old, exerciseID: identity)
        let wrongUnit = snapshot(newerWrongUnit, exerciseID: identity, unit: .bodyweight)
        let active = snapshot(current, exerciseID: identity)
        let actual = log(past)
        actual.completedAt = old.completedAt
        let result = MuscleCoverageService.lastReference(for: active, sessions: [current, newerWrongUnit, old], snapshots: [active, wrongUnit, past], logs: [actual, log(wrongUnit), log(active)])
        XCTAssertEqual(result?.date, old.startedAt)
        XCTAssertTrue(result?.rows.first?.contains("25") == true)
        XCTAssertFalse(result?.rows.first?.contains("99") == true)
    }
    func testTrainingMappingDoesNotUsePainJointRegions() {
        XCTAssertEqual(MuscleCoverageService.group(for: "front-chest"), "胸部")
        XCTAssertEqual(MuscleCoverageService.group(for: "back-left-hamstring"), "腿部")
        XCTAssertNil(MuscleCoverageService.group(for: "front-left-knee"))
        XCTAssertEqual(MuscleCoverageService.groups(in: "lateral deltoid"), ["肩部"])
    }
    func testTrainingDiagramUsesAnatomicalSidesWithoutChangingPainCatalog() throws {
        let front = try XCTUnwrap(BodyRegionCatalog.all.first { $0.id == "front-left-shoulder" })
        let back = try XCTUnwrap(BodyRegionCatalog.all.first { $0.id == "back-left-shoulder" })
        XCTAssertEqual(MuscleCoverageService.horizontalPosition(for: front), 0.67, accuracy: 0.0001)
        XCTAssertEqual(MuscleCoverageService.horizontalPosition(for: back), 0.33, accuracy: 0.0001)
        XCTAssertEqual(front.x, 0.33, accuracy: 0.0001)
        XCTAssertEqual(back.x, 0.33, accuracy: 0.0001)
    }
    func testMeasurementSideTracksPendingSetAndPreservesCompletedSet() {
        let workout = session(status: .inProgress)
        let exercise = snapshot(workout)
        exercise.plannedSets = [
            WorkoutSetPlan(weight: 25, reps: 8, weightSide: .bilateral, repsSide: .bilateral),
            WorkoutSetPlan(weight: 25, reps: 8, weightSide: .bilateral, repsSide: .bilateral)
        ]
        let first = log(exercise)
        let second = log(exercise, completed: false)
        second.setNumber = 2
        let completedAt = first.completedAt

        WorkoutMeasurementSideEditing.apply(.single, to: exercise, logs: [second, first])

        XCTAssertEqual(WorkoutMeasurementSideEditing.selected(in: [second, first]), .single)
        XCTAssertEqual(second.actualWeightSide, .single)
        XCTAssertEqual(second.actualRepsSide, .single)
        XCTAssertEqual(first.actualWeightSide, .bilateral)
        XCTAssertEqual(first.actualRepsSide, .bilateral)
        XCTAssertEqual(first.targetWeightSide, .bilateral)
        XCTAssertEqual(first.actualWeight, 25)
        XCTAssertEqual(first.actualReps, 8)
        XCTAssertEqual(first.completedAt, completedAt)
        XCTAssertTrue(first.isCompleted)
        XCTAssertEqual(exercise.plannedSets[0].weightSide, .bilateral)
        XCTAssertEqual(exercise.plannedSets[1].weightSide, .single)
    }
    func testMeasurementSideCannotChangeAllCompletedRows() {
        let workout = session()
        let exercise = snapshot(workout)
        let first = log(exercise)
        WorkoutMeasurementSideEditing.apply(.single, to: exercise, logs: [first])
        XCTAssertEqual(WorkoutMeasurementSideEditing.selected(in: [first]), .bilateral)
        XCTAssertEqual(first.actualWeightSide, .bilateral)
        XCTAssertEqual(first.actualRepsSide, .bilateral)
    }
}
