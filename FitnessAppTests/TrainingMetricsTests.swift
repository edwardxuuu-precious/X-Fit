import XCTest
@testable import FitnessApp

final class TrainingMetricsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

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

    func testWeeklyProgressUsesCalendarWeekAndCompletedWorkingSets() {
        let first = WorkoutSession(
            templateName: "胸部",
            plannedDate: date(2026, 7, 14),
            startedAt: date(2026, 7, 14, hour: 9),
            completedAt: date(2026, 7, 14, hour: 9, minute: 45),
            status: .completed
        )
        let second = WorkoutSession(
            templateName: "背部",
            plannedDate: date(2026, 7, 15),
            startedAt: date(2026, 7, 15, hour: 10),
            completedAt: date(2026, 7, 15, hour: 10, minute: 30),
            status: .completed
        )
        let previous = WorkoutSession(
            templateName: "上周训练",
            plannedDate: date(2026, 7, 7),
            startedAt: date(2026, 7, 7, hour: 9),
            completedAt: date(2026, 7, 7, hour: 10),
            status: .completed
        )
        let workingSet = SetLog(
            sessionID: first.id,
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 1,
            targetWeight: 50,
            targetReps: 10,
            actualWeight: 50,
            actualReps: 10,
            isCompleted: true
        )
        let secondWorkingSet = SetLog(
            sessionID: second.id,
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 1,
            targetWeight: 40,
            targetReps: 10,
            actualWeight: 40,
            actualReps: 10,
            isCompleted: true
        )
        let warmup = SetLog(
            sessionID: first.id,
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 0,
            targetWeight: 20,
            targetReps: 10,
            actualWeight: 20,
            actualReps: 10,
            isWarmup: true,
            isCompleted: true
        )
        let previousSet = SetLog(
            sessionID: previous.id,
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 1,
            targetWeight: 100,
            targetReps: 10,
            actualWeight: 100,
            actualReps: 10,
            isCompleted: true
        )
        let schedules = [
            ScheduledWorkout(
                templateID: UUID(),
                templateName: "胸部",
                plannedDate: date(2026, 7, 14),
                status: .completed
            ),
            ScheduledWorkout(
                templateID: UUID(),
                templateName: "腿部",
                plannedDate: date(2026, 7, 17),
                status: .planned
            ),
            ScheduledWorkout(
                templateID: UUID(),
                templateName: "休息",
                plannedDate: date(2026, 7, 16),
                status: .skipped
            )
        ]

        let summary = TrainingMetrics.progressSummary(
            period: .week,
            now: date(2026, 7, 15, hour: 18),
            calendar: calendar,
            schedules: schedules,
            sessions: [first, second, previous],
            setLogs: [workingSet, secondWorkingSet, warmup, previousSet]
        )

        XCTAssertEqual(summary.interval.start, date(2026, 7, 13, hour: 0))
        XCTAssertEqual(summary.completedSessions, 2)
        XCTAssertEqual(summary.plannedWorkouts, 2)
        XCTAssertEqual(summary.targetWorkouts, 2)
        XCTAssertEqual(summary.completionProgress, 1)
        XCTAssertEqual(summary.workingSets, 2)
        XCTAssertEqual(summary.volume, 900)
        XCTAssertEqual(summary.activeMinutes, 75)
        XCTAssertEqual(summary.previousVolume, 1_000)
        XCTAssertEqual(summary.volumeChangePercent ?? 0, -10, accuracy: 0.001)
        XCTAssertEqual(summary.buckets.map(\.label), ["一", "二", "三", "四", "五", "六", "日"])
        XCTAssertEqual(summary.buckets[1].volume, 500)
        XCTAssertEqual(summary.buckets[2].volume, 400)
    }

    func testMonthlyProgressUsesNaturalWeekBucketsAndExcludesAdjacentMonths() {
        let julyFirst = WorkoutSession(
            templateName: "月初",
            plannedDate: date(2026, 7, 1),
            startedAt: date(2026, 7, 1),
            completedAt: date(2026, 7, 1, hour: 13),
            status: .completed
        )
        let julyLast = WorkoutSession(
            templateName: "月末",
            plannedDate: date(2026, 7, 30),
            startedAt: date(2026, 7, 30),
            completedAt: date(2026, 7, 30, hour: 13),
            status: .completed
        )
        let june = WorkoutSession(
            templateName: "六月",
            plannedDate: date(2026, 6, 30),
            startedAt: date(2026, 6, 30),
            completedAt: date(2026, 6, 30, hour: 13),
            status: .completed
        )
        let august = WorkoutSession(
            templateName: "八月",
            plannedDate: date(2026, 8, 1),
            startedAt: date(2026, 8, 1),
            completedAt: date(2026, 8, 1, hour: 13),
            status: .completed
        )
        let logs = [
            completedSet(for: julyFirst, weight: 50),
            completedSet(for: julyLast, weight: 60),
            completedSet(for: june, weight: 100),
            completedSet(for: august, weight: 200)
        ]

        let summary = TrainingMetrics.progressSummary(
            period: .month,
            now: date(2026, 7, 31, hour: 18),
            calendar: calendar,
            schedules: [],
            sessions: [julyFirst, julyLast, june, august],
            setLogs: logs
        )

        XCTAssertEqual(summary.completedSessions, 2)
        XCTAssertEqual(summary.targetWorkouts, 0)
        XCTAssertEqual(summary.completionProgress, 0)
        XCTAssertEqual(summary.volume, 1_100)
        XCTAssertEqual(summary.previousVolume, 1_000)
        XCTAssertEqual(summary.volumeChangePercent ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(summary.buckets.map(\.label), ["6/29", "7/6", "7/13", "7/20", "7/27"])
        XCTAssertEqual(summary.buckets.first?.volume, 500)
        XCTAssertEqual(summary.buckets.last?.volume, 600)
    }

    func testWorkoutHeroMatchesTrainingGoalAndUsesFullBodyForTies() {
        XCTAssertEqual(
            WorkoutHeroKind.resolve(
                workoutName: "推 · 胸肩三头",
                muscleGroups: ["胸部", "胸部", "肩部", "手臂"]
            ),
            .push
        )
        XCTAssertEqual(
            WorkoutHeroKind.resolve(workoutName: "拉 · 背部二头", muscleGroups: ["背部", "手臂"]),
            .pull
        )
        XCTAssertEqual(
            WorkoutHeroKind.resolve(workoutName: "腿 · 下肢力量", muscleGroups: ["腿部", "小腿"]),
            .legs
        )
        XCTAssertEqual(
            WorkoutHeroKind.resolve(workoutName: "核心稳定", muscleGroups: ["核心"]),
            .core
        )
        XCTAssertEqual(
            WorkoutHeroKind.resolve(workoutName: "背部与核心", muscleGroups: ["背部", "核心"]),
            .full
        )
    }

    private func completedSet(for session: WorkoutSession, weight: Double) -> SetLog {
        SetLog(
            sessionID: session.id,
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 1,
            targetWeight: weight,
            targetReps: 10,
            actualWeight: weight,
            actualReps: 10,
            isCompleted: true
        )
    }
}
