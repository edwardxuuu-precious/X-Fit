import XCTest
@testable import FitnessApp

final class TrainingMetricsTests: XCTestCase {
    func testVolumeCountsOnlyCompletedSets() {
        let completed = SetLog(
            sessionID: UUID(),
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 1,
            targetWeight: 40,
            targetReps: 10,
            actualWeight: 40,
            actualReps: 10,
            isCompleted: true
        )
        let incomplete = SetLog(
            sessionID: completed.sessionID,
            sessionExerciseID: completed.sessionExerciseID,
            exerciseID: completed.exerciseID,
            setNumber: 2,
            targetWeight: 40,
            targetReps: 10,
            actualWeight: 40,
            actualReps: 10,
            isCompleted: false
        )

        XCTAssertEqual(TrainingMetrics.volume(for: [completed, incomplete]), 400)
    }

    func testEstimatedOneRepMaxUsesEpleyFormula() {
        XCTAssertEqual(
            TrainingMetrics.estimatedOneRepMax(weight: 100, reps: 6),
            120,
            accuracy: 0.001
        )
    }

    func testProgressionIncreasesWhenAllSetsReachTopWithReserve() {
        let result = TrainingMetrics.progression(
            completedReps: [12, 12, 12],
            minimumReps: 8,
            maximumReps: 12,
            rirValues: [2, 2, 3]
        )

        XCTAssertEqual(result, .increase(percent: 0.025))
    }

    func testProgressionReducesWhenMinimumIsMissed() {
        let result = TrainingMetrics.progression(
            completedReps: [8, 7, 6],
            minimumReps: 8,
            maximumReps: 12,
            rirValues: [1, 1, 0]
        )

        XCTAssertEqual(result, .reduce)
    }
}
