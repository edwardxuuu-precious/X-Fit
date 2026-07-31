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

    func testProgressionDoesNotIncreaseWhenRIRIsMissing() {
        let result = TrainingMetrics.progression(
            completedReps: [12, 12, 12, 12],
            minimumReps: 10,
            maximumReps: 12,
            rirValues: []
        )

        XCTAssertEqual(result, .maintain)
    }

    func testCuttingAssessmentMaintainsVolumeWithoutCompleteRIR() {
        let assessment = TrainingMetrics.progressionAssessment(
            weights: [40, 45, 50, 55],
            completedReps: [12, 12, 12, 12],
            minimumReps: 10,
            maximumReps: 15,
            rirValues: [nil, nil, nil, nil],
            previousVolume: 2_200,
            goalMode: .cuttingVolume
        )

        XCTAssertEqual(assessment.recommendation, .maintain)
        XCTAssertFalse(assessment.hasCompleteRIR)
        XCTAssertTrue(assessment.detail.contains("不据此加重"))
        XCTAssertEqual(assessment.currentVolume, 2_280)
    }

    func testCuttingAssessmentOnlyAllowsMicroLoadAfterVolumeAndReserveAreConfirmed() {
        let assessment = TrainingMetrics.progressionAssessment(
            weights: [40, 40, 40, 40],
            completedReps: [15, 15, 15, 15],
            minimumReps: 10,
            maximumReps: 15,
            rirValues: [3, 3, 4, 3],
            previousVolume: 2_350,
            goalMode: .cuttingVolume
        )

        XCTAssertEqual(assessment.recommendation, .increase(percent: 0.025))
        XCTAssertTrue(assessment.title.contains("组数不减"))
    }

    func testWorkingWeightUsesRepWeightedAverageInsteadOfHeaviestSet() {
        let result = TrainingMetrics.workingWeight(
            weights: [40, 45, 50, 55],
            reps: [12, 12, 12, 12]
        )

        XCTAssertEqual(result, 47.5)
    }
}
