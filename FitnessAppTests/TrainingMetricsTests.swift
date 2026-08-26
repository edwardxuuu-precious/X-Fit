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

    func testVolumeCountsOnlyCompletedWorkingSetsAndClampsInvalidValues() {
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
        let warmup = SetLog(
            sessionID: completed.sessionID,
            sessionExerciseID: completed.sessionExerciseID,
            exerciseID: completed.exerciseID,
            setNumber: 3,
            targetWeight: 20,
            targetReps: 10,
            actualWeight: 20,
            actualReps: 10,
            isWarmup: true,
            isCompleted: true
        )
        let invalid = SetLog(
            sessionID: completed.sessionID,
            sessionExerciseID: completed.sessionExerciseID,
            exerciseID: completed.exerciseID,
            setNumber: 4,
            targetWeight: 0,
            targetReps: 10,
            actualWeight: -20,
            actualReps: 10,
            isCompleted: true
        )

        XCTAssertEqual(TrainingMetrics.volume(for: [completed, incomplete, warmup, invalid]), 400)
    }

    func testVolumeUnitsUseTheirOwnMeasurementRules() {
        XCTAssertEqual(ExerciseVolumeUnit.count.volume(weight: 99, reps: 40), 40)
        XCTAssertEqual(ExerciseVolumeUnit.meter.volume(weight: 500, reps: 2), 1_000)
        XCTAssertEqual(ExerciseVolumeUnit.kilogram.volume(weight: 20, reps: 5), 100)

        XCTAssertEqual(ExerciseVolumeUnit.count.volume(weight: -99, reps: -40), 0)
        XCTAssertEqual(ExerciseVolumeUnit.meter.volume(weight: -500, reps: 2), 0)
        XCTAssertEqual(ExerciseVolumeUnit.kilogram.volume(weight: 20, reps: -5), 0)
    }

    func testInvalidOrMissingStoredVolumeUnitFallsBackToKilogram() {
        let exercise = Exercise(name: "旧动作", muscleGroup: "背部", equipment: "器械")
        exercise.volumeUnitRaw = nil
        XCTAssertEqual(exercise.volumeUnit, .kilogram)

        exercise.volumeUnitRaw = "unsupported-unit"
        XCTAssertEqual(exercise.volumeUnit, .kilogram)

        let snapshot = SessionExercise(
            sessionID: UUID(),
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 20,
            restSeconds: 60
        )
        snapshot.volumeUnitRaw = nil
        XCTAssertEqual(snapshot.volumeUnit, .kilogram)
    }

    func testMixedUnitTrendsKeepUnitsSeparateAndOverallIncludesOnlyKilograms() {
        let strength = Exercise(
            name: "深蹲",
            muscleGroup: "腿部",
            equipment: "杠铃",
            volumeUnit: .kilogram
        )
        let run = Exercise(
            name: "折返跑",
            muscleGroup: "有氧",
            equipment: "无",
            volumeUnit: .meter
        )
        let jump = Exercise(
            name: "开合跳",
            muscleGroup: "有氧",
            equipment: "无",
            volumeUnit: .count
        )
        let session = WorkoutSession(
            templateName: "混合训练",
            plannedDate: date(2026, 8, 5),
            startedAt: date(2026, 8, 5),
            completedAt: date(2026, 8, 5, hour: 13),
            status: .completed
        )
        let strengthSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: strength.id,
            exerciseName: strength.name,
            order: 0,
            targetSets: 1,
            minReps: 5,
            maxReps: 5,
            targetWeight: 20,
            restSeconds: 90,
            volumeUnit: .kilogram
        )
        let runSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: run.id,
            exerciseName: run.name,
            order: 1,
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
            order: 2,
            targetSets: 1,
            minReps: 40,
            maxReps: 40,
            targetWeight: 0,
            restSeconds: 30,
            volumeUnit: .count
        )
        let logs = [
            SetLog(
                sessionID: session.id,
                sessionExerciseID: strengthSnapshot.id,
                exerciseID: strength.id,
                setNumber: 1,
                targetWeight: 20,
                targetReps: 5,
                actualWeight: 20,
                actualReps: 5,
                isCompleted: true
            ),
            SetLog(
                sessionID: session.id,
                sessionExerciseID: runSnapshot.id,
                exerciseID: run.id,
                setNumber: 1,
                targetWeight: 500,
                targetReps: 2,
                actualWeight: 500,
                actualReps: 2,
                isCompleted: true
            ),
            SetLog(
                sessionID: session.id,
                sessionExerciseID: jumpSnapshot.id,
                exerciseID: jump.id,
                setNumber: 1,
                targetWeight: 0,
                targetReps: 40,
                actualWeight: 0,
                actualReps: 40,
                isCompleted: true
            )
        ]

        let trends = TrainingMetrics.volumeTrends(
            calendar: calendar,
            sessions: [session],
            sessionExercises: [strengthSnapshot, runSnapshot, jumpSnapshot],
            exercises: [strength, run, jump],
            setLogs: logs
        )

        XCTAssertEqual(trends.overall.map(\.volume), [100])
        XCTAssertEqual(trends.exercises.first(where: { $0.unit == .kilogram })?.totalVolume, 100)
        XCTAssertEqual(trends.exercises.first(where: { $0.unit == .meter })?.totalVolume, 1_000)
        XCTAssertEqual(trends.exercises.first(where: { $0.unit == .count })?.totalVolume, 40)
    }

    func testVolumeTotalsUseSnapshotUnitsAndIgnoreWarmupIncompleteAndOrphanLogs() {
        let session = WorkoutSession(
            templateName: "混合训练",
            plannedDate: date(2026, 8, 8),
            startedAt: date(2026, 8, 8),
            completedAt: date(2026, 8, 8, hour: 13),
            status: .completed
        )
        let strength = SessionExercise(
            sessionID: session.id,
            exerciseID: UUID(),
            exerciseName: "深蹲",
            order: 0,
            targetSets: 1,
            minReps: 5,
            maxReps: 5,
            targetWeight: 20,
            restSeconds: 90,
            volumeUnit: .kilogram
        )
        let run = SessionExercise(
            sessionID: session.id,
            exerciseID: UUID(),
            exerciseName: "跑步",
            order: 1,
            targetSets: 1,
            minReps: 2,
            maxReps: 2,
            targetWeight: 500,
            restSeconds: 60,
            volumeUnit: .meter
        )
        let jump = SessionExercise(
            sessionID: session.id,
            exerciseID: UUID(),
            exerciseName: "开合跳",
            order: 2,
            targetSets: 1,
            minReps: 40,
            maxReps: 40,
            targetWeight: 0,
            restSeconds: 30,
            volumeUnit: .count
        )
        let logs = [
            SetLog(
                sessionID: session.id, sessionExerciseID: strength.id, exerciseID: strength.exerciseID,
                setNumber: 1, targetWeight: 20, targetReps: 5, actualWeight: 20, actualReps: 5,
                isCompleted: true
            ),
            SetLog(
                sessionID: session.id, sessionExerciseID: run.id, exerciseID: run.exerciseID,
                setNumber: 1, targetWeight: 500, targetReps: 2, actualWeight: 500, actualReps: 2,
                isCompleted: true
            ),
            SetLog(
                sessionID: session.id, sessionExerciseID: jump.id, exerciseID: jump.exerciseID,
                setNumber: 1, targetWeight: 0, targetReps: 40, actualWeight: 0, actualReps: 40,
                isCompleted: true
            ),
            SetLog(
                sessionID: session.id, sessionExerciseID: run.id, exerciseID: run.exerciseID,
                setNumber: 2, targetWeight: 500, targetReps: 2, actualWeight: 500, actualReps: 2,
                isWarmup: true, isCompleted: true
            ),
            SetLog(
                sessionID: session.id, sessionExerciseID: jump.id, exerciseID: jump.exerciseID,
                setNumber: 2, targetWeight: 0, targetReps: 30, actualWeight: 0, actualReps: 30,
                isCompleted: false
            ),
            SetLog(
                sessionID: session.id, sessionExerciseID: UUID(), exerciseID: UUID(),
                setNumber: 1, targetWeight: 999, targetReps: 999, actualWeight: 999, actualReps: 999,
                isCompleted: true
            )
        ]

        let totals = TrainingMetrics.volumeTotals(
            for: logs,
            sessionExercises: [strength, run, jump]
        )

        XCTAssertEqual(totals[.kilogram], 100)
        XCTAssertEqual(totals[.meter], 1_000)
        XCTAssertEqual(totals[.count], 40)
    }

    func testTrendKeepsHistoricalSnapshotUnitAfterCatalogUnitChanges() {
        let exercise = Exercise(
            name: "折返跑",
            muscleGroup: "有氧",
            equipment: "无",
            volumeUnit: .count
        )
        let session = WorkoutSession(
            templateName: "有氧",
            plannedDate: date(2026, 8, 9),
            startedAt: date(2026, 8, 9),
            completedAt: date(2026, 8, 9, hour: 13),
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 2,
            maxReps: 2,
            targetWeight: 500,
            restSeconds: 60,
            volumeUnit: .meter
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 500,
            targetReps: 2,
            actualWeight: 500,
            actualReps: 2,
            isCompleted: true
        )

        let trends = TrainingMetrics.volumeTrends(
            calendar: calendar,
            sessions: [session],
            sessionExercises: [snapshot],
            exercises: [exercise],
            setLogs: [log]
        )

        XCTAssertTrue(trends.overall.isEmpty)
        XCTAssertEqual(trends.exercises.count, 1)
        XCTAssertEqual(trends.exercises.first?.unit, .meter)
        XCTAssertEqual(trends.exercises.first?.totalVolume, 1_000)
    }

    func testEstimatedOneRepMaxUsesEpleyFormula() {
        XCTAssertEqual(
            TrainingMetrics.estimatedOneRepMax(weight: 100, reps: 6),
            120,
            accuracy: 0.001
        )
    }

    func testVolumeTrendsUseExerciseSnapshotWhenSyncedExerciseIdentifierChanged() {
        let sourceExerciseID = UUID()
        let currentExercise = Exercise(
            name: "MTS 下斜卧推",
            muscleGroup: "胸部",
            equipment: "MTS 器械"
        )
        let session = WorkoutSession(
            templateName: "胸部训练",
            plannedDate: date(2026, 7, 1),
            startedAt: date(2026, 7, 1),
            completedAt: date(2026, 7, 1, hour: 13),
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: sourceExerciseID,
            exerciseName: "MTS 下斜卧推",
            order: 0,
            targetSets: 2,
            minReps: 10,
            maxReps: 15,
            targetWeight: 25,
            restSeconds: 90,
            muscleGroup: "胸部"
        )
        let logs = [
            SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: sourceExerciseID,
                setNumber: 1,
                targetWeight: 25,
                targetReps: 15,
                actualWeight: 25,
                actualReps: 15,
                isCompleted: true
            ),
            SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: sourceExerciseID,
                setNumber: 2,
                targetWeight: 20,
                targetReps: 15,
                actualWeight: 20,
                actualReps: 15,
                isCompleted: true
            )
        ]

        let trends = TrainingMetrics.volumeTrends(
            calendar: calendar,
            sessions: [session],
            sessionExercises: [snapshot],
            exercises: [currentExercise],
            setLogs: logs
        )

        XCTAssertEqual(trends.overall.count, 1)
        XCTAssertEqual(trends.overall.first?.volume, 675)
        XCTAssertEqual(trends.overall.first?.completedSets, 2)
        XCTAssertEqual(trends.exercises.count, 1)
        XCTAssertEqual(trends.exercises.first?.name, "MTS 下斜卧推")
        XCTAssertEqual(trends.exercises.first?.points.count, 1)
        XCTAssertEqual(trends.exercises.first?.totalVolume, 675)
        XCTAssertEqual(trends.exercises.first?.sessionCount, 1)
    }

    func testVolumeTrendsExcludeIncompleteSessionsAndSets() {
        let exercise = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        let completedSession = WorkoutSession(
            templateName: "完成训练",
            plannedDate: date(2026, 7, 2),
            startedAt: date(2026, 7, 2),
            completedAt: date(2026, 7, 2, hour: 13),
            status: .completed
        )
        let activeSession = WorkoutSession(
            templateName: "进行中训练",
            plannedDate: date(2026, 7, 3),
            startedAt: date(2026, 7, 3),
            status: .inProgress
        )
        let snapshot = SessionExercise(
            sessionID: completedSession.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 2,
            minReps: 8,
            maxReps: 12,
            targetWeight: 50,
            restSeconds: 90,
            muscleGroup: exercise.muscleGroup
        )
        let completed = SetLog(
            sessionID: completedSession.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 50,
            targetReps: 10,
            actualWeight: 50,
            actualReps: 10,
            isCompleted: true
        )
        let unchecked = SetLog(
            sessionID: completedSession.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 2,
            targetWeight: 50,
            targetReps: 10,
            actualWeight: 50,
            actualReps: 10,
            isCompleted: false
        )
        let activeLog = SetLog(
            sessionID: activeSession.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 100,
            targetReps: 10,
            actualWeight: 100,
            actualReps: 10,
            isCompleted: true
        )
        let warmupLog = SetLog(
            sessionID: completedSession.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 3,
            targetWeight: 25,
            targetReps: 10,
            actualWeight: 25,
            actualReps: 10,
            isWarmup: true,
            isCompleted: true
        )

        let trends = TrainingMetrics.volumeTrends(
            calendar: calendar,
            sessions: [completedSession, activeSession],
            sessionExercises: [snapshot],
            exercises: [exercise],
            setLogs: [completed, unchecked, activeLog, warmupLog]
        )

        XCTAssertEqual(trends.overall.map(\.volume), [500])
        XCTAssertEqual(trends.overall.map(\.completedSets), [1])
        XCTAssertEqual(trends.exercises.first?.totalVolume, 500)
    }

    func testVolumeRejectsNonFiniteAndOverflowingInputs() {
        XCTAssertEqual(ExerciseVolumeUnit.kilogram.volume(weight: .infinity, reps: 10), 0)
        XCTAssertEqual(ExerciseVolumeUnit.meter.volume(weight: .nan, reps: 10), 0)
        XCTAssertEqual(
            ExerciseVolumeUnit.kilogram.volume(
                weight: Double.greatestFiniteMagnitude,
                reps: 2
            ),
            0
        )

        let invalidLog = SetLog(
            sessionID: UUID(),
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 1,
            targetWeight: 0,
            targetReps: 10,
            actualWeight: .infinity,
            actualReps: 10,
            isCompleted: true
        )
        XCTAssertEqual(TrainingMetrics.volume(for: [invalidLog]), 0)

        let largeFiniteLog = SetLog(
            sessionID: UUID(),
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 2,
            targetWeight: 0,
            targetReps: 1,
            actualWeight: Double.greatestFiniteMagnitude * 0.75,
            actualReps: 1,
            isCompleted: true
        )
        let saturatedTotal = TrainingMetrics.volume(for: [largeFiniteLog, largeFiniteLog])
        XCTAssertTrue(saturatedTotal.isFinite)
        XCTAssertEqual(saturatedTotal, largeFiniteLog.actualWeight)
    }

    func testVolumeTrendsAggregateMultipleSessionsOnTheSameCalendarDay() {
        let exercise = Exercise(name: "杠铃深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let firstSession = WorkoutSession(
            templateName: "上午腿部",
            plannedDate: date(2026, 8, 6, hour: 9),
            startedAt: date(2026, 8, 6, hour: 9),
            completedAt: date(2026, 8, 6, hour: 10),
            status: .completed
        )
        let secondSession = WorkoutSession(
            templateName: "晚上腿部",
            plannedDate: date(2026, 8, 6, hour: 20),
            startedAt: date(2026, 8, 6, hour: 20),
            completedAt: date(2026, 8, 6, hour: 21),
            status: .completed
        )
        let firstSnapshot = SessionExercise(
            sessionID: firstSession.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 5,
            maxReps: 5,
            targetWeight: 20,
            restSeconds: 90
        )
        let secondSnapshot = SessionExercise(
            sessionID: secondSession.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 4,
            maxReps: 4,
            targetWeight: 30,
            restSeconds: 90
        )
        let logs = [
            SetLog(
                sessionID: firstSession.id,
                sessionExerciseID: firstSnapshot.id,
                exerciseID: exercise.id,
                setNumber: 1,
                targetWeight: 20,
                targetReps: 5,
                actualWeight: 20,
                actualReps: 5,
                isCompleted: true
            ),
            SetLog(
                sessionID: secondSession.id,
                sessionExerciseID: secondSnapshot.id,
                exerciseID: exercise.id,
                setNumber: 1,
                targetWeight: 30,
                targetReps: 4,
                actualWeight: 30,
                actualReps: 4,
                isCompleted: true
            )
        ]

        let trends = TrainingMetrics.volumeTrends(
            calendar: calendar,
            sessions: [firstSession, secondSession],
            sessionExercises: [firstSnapshot, secondSnapshot],
            exercises: [exercise],
            setLogs: logs
        )

        XCTAssertEqual(trends.overall.count, 1)
        XCTAssertEqual(trends.overall.first?.date, date(2026, 8, 6, hour: 0))
        XCTAssertEqual(trends.overall.first?.volume, 220)
        XCTAssertEqual(trends.overall.first?.completedSets, 2)
        XCTAssertEqual(trends.overall.first?.sessionCount, 2)
    }

    func testRecentOverallVolumeUsesLatestSixActualDaysAndExcludesFuture() {
        let exercise = Exercise(name: "测试深蹲", muscleGroup: "腿部", equipment: "杠铃")
        var sessions: [WorkoutSession] = []
        var snapshots: [SessionExercise] = []
        var logs: [SetLog] = []

        for day in 1...9 {
            let session = WorkoutSession(
                templateName: "第 \(day) 日",
                plannedDate: date(2026, 8, day),
                startedAt: date(2026, 8, day),
                completedAt: date(2026, 8, day, hour: 13),
                status: .completed
            )
            let snapshot = SessionExercise(
                sessionID: session.id,
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                order: 0,
                targetSets: 1,
                minReps: 10,
                maxReps: 10,
                targetWeight: Double(day * 10),
                restSeconds: 90
            )
            let log = SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: exercise.id,
                setNumber: 1,
                targetWeight: Double(day * 10),
                targetReps: 10,
                actualWeight: Double(day * 10),
                actualReps: 10,
                isCompleted: true
            )
            sessions.append(session)
            snapshots.append(snapshot)
            logs.append(log)
        }

        let points = TrainingMetrics.recentOverallVolumePoints(
            through: date(2026, 8, 8, hour: 23),
            limit: 6,
            calendar: calendar,
            sessions: sessions,
            sessionExercises: snapshots,
            exercises: [exercise],
            setLogs: logs
        )

        XCTAssertEqual(points.map(\.date), (3...8).map { date(2026, 8, $0, hour: 0) })
        XCTAssertEqual(points.map(\.volume), [300, 400, 500, 600, 700, 800])
        XCTAssertTrue(
            TrainingMetrics.recentOverallVolumePoints(
                through: date(2026, 8, 8),
                limit: 0,
                calendar: calendar,
                sessions: sessions,
                sessionExercises: snapshots,
                exercises: [exercise],
                setLogs: logs
            ).isEmpty
        )
    }

    func testVolumeTrendDayBucketsRespectInjectedDSTCalendar() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        let beforeMidnight = try XCTUnwrap(formatter.date(from: "2026-03-08T07:30:00Z"))
        let afterMidnight = try XCTUnwrap(formatter.date(from: "2026-03-08T08:30:00Z"))
        let exercise = Exercise(name: "深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let sessions = [beforeMidnight, afterMidnight].enumerated().map { index, startedAt in
            WorkoutSession(
                templateName: "跨日 \(index)",
                plannedDate: startedAt,
                startedAt: startedAt,
                completedAt: startedAt.addingTimeInterval(1_800),
                status: .completed
            )
        }
        let snapshots = sessions.map { session in
            SessionExercise(
                sessionID: session.id,
                exerciseID: exercise.id,
                exerciseName: exercise.name,
                order: 0,
                targetSets: 1,
                minReps: 10,
                maxReps: 10,
                targetWeight: 10,
                restSeconds: 90
            )
        }
        let logs = zip(sessions, snapshots).map { pair in
            let (session, snapshot) = pair
            return SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: exercise.id,
                setNumber: 1,
                targetWeight: 10,
                targetReps: 10,
                actualWeight: 10,
                actualReps: 10,
                isCompleted: true
            )
        }

        let points = TrainingMetrics.volumeTrends(
            calendar: losAngeles,
            sessions: sessions,
            sessionExercises: snapshots,
            exercises: [exercise],
            setLogs: logs
        ).overall

        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].date, losAngeles.startOfDay(for: beforeMidnight))
        XCTAssertEqual(points[1].date, losAngeles.startOfDay(for: afterMidnight))
    }

    func testCompactDayMonthLabelUsesDayThenEnglishMonth() {
        XCTAssertEqual(date(2026, 8, 2).compactDayMonthLabel, "2/Aug")
        XCTAssertEqual(date(2026, 12, 31).compactDayMonthLabel, "31/Dec")
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

    func testExerciseGlyphsCoverCurrentLibraryAndUseSpecificMovementFamilies() {
        let library: [(name: String, group: String, equipment: String)] = [
            ("站姿提踵", "小腿", "器械"),
            ("三头下压", "手臂", "龙门架"),
            ("三头下压机", "手臂", "器械"),
            ("哑铃弯举", "手臂", "哑铃"),
            ("绳索下压", "手臂", "龙门架"),
            ("举腿", "核心", "自重"),
            ("绳索卷腹", "核心", "龙门架"),
            ("绳索躯干旋转", "核心", "龙门架"),
            ("三角肌训练机", "肩部", "器械"),
            ("史密斯肩推", "肩部", "史密斯机"),
            ("哑铃侧平举", "肩部", "哑铃"),
            ("器械肩推", "肩部", "器械"),
            ("坐姿哑铃侧平举", "肩部", "哑铃"),
            ("坐姿推举", "肩部", "哑铃"),
            ("坐姿肩推", "肩部", "哑铃"),
            ("火箭推", "肩部", "杠铃"),
            ("站姿哑铃肩推", "肩部", "哑铃"),
            ("绳索侧平举", "肩部", "龙门架"),
            ("绳索反向飞鸟", "肩部", "龙门架"),
            ("面拉", "肩部", "龙门架"),
            ("MTS 划船", "背部", "MTS 器械"),
            ("上背下拉机", "背部", "器械"),
            ("上背划船机", "背部", "器械"),
            ("坐姿划船", "背部", "器械"),
            ("引体向上", "背部", "自重"),
            ("杠铃划船", "背部", "杠铃"),
            ("窄握下拉", "背部", "器械"),
            ("颈后下拉", "背部", "器械"),
            ("高位下拉", "背部", "器械"),
            ("MTS 下斜卧推", "胸部", "MTS 器械"),
            ("上斜卧推", "胸部", "杠铃"),
            ("上斜哑铃卧推", "胸部", "哑铃"),
            ("史密斯上斜卧推", "胸部", "史密斯机"),
            ("史密斯卧推", "胸部", "史密斯机"),
            ("器械上斜卧推", "胸部", "器械"),
            ("器械下斜卧推", "胸部", "器械"),
            ("坐姿上斜推胸机", "胸部", "器械"),
            ("坐姿下斜推胸机", "胸部", "器械"),
            ("坐姿推胸机", "胸部", "器械"),
            ("坐姿飞鸟", "胸部", "器械"),
            ("杠铃卧推", "胸部", "杠铃"),
            ("站姿绳索夹胸", "胸部", "龙门架"),
            ("绳索夹胸", "胸部", "龙门架"),
            ("V 型深蹲", "腿部", "器械"),
            ("严格深蹲", "腿部", "杠铃"),
            ("单腿钟摆推举", "腿部", "器械"),
            ("哑铃行走弓步", "腿部", "哑铃"),
            ("深蹲", "腿部", "杠铃"),
            ("站姿髋推", "腿部", "器械"),
            ("罗马尼亚硬拉", "腿部", "杠铃"),
            ("腿举", "腿部", "器械"),
            ("腿弯举", "腿部", "器械"),
            ("臀推", "腿部", "杠铃"),
            ("钟摆深蹲", "腿部", "器械"),
            ("高翻", "腿部", "杠铃")
        ]

        let resolved = library.map {
            ExerciseGlyphKind.resolve(name: $0.name, muscleGroup: $0.group, equipment: $0.equipment)
        }
        XCTAssertEqual(resolved.count, 55)
        XCTAssertFalse(resolved.contains(.general))

        let categories = library.map {
            ExerciseMuscleTaxonomy.category(name: $0.name, muscleGroup: $0.group)
        }
        let majorCounts = Dictionary(grouping: categories, by: \.majorGroup).mapValues(\.count)
        XCTAssertEqual(majorCounts["胸部"], 14)
        XCTAssertEqual(majorCounts["背部"], 9)
        XCTAssertEqual(majorCounts["肩部"], 12)
        XCTAssertEqual(majorCounts["手臂"], 4)
        XCTAssertEqual(majorCounts["腿部"], 13)
        XCTAssertEqual(majorCounts["核心"], 3)

        let backMinorCounts = Dictionary(
            grouping: categories.filter { $0.majorGroup == "背部" },
            by: \.minorGroup
        ).mapValues(\.count)
        XCTAssertEqual(backMinorCounts["上背"], 2)
        XCTAssertEqual(backMinorCounts["中背"], 3)
        XCTAssertEqual(backMinorCounts["背阔肌"], 4)

        let chestMinorCounts = Dictionary(
            grouping: categories.filter { $0.majorGroup == "胸部" },
            by: \.minorGroup
        ).mapValues(\.count)
        XCTAssertEqual(chestMinorCounts["上胸"], 5)
        XCTAssertEqual(chestMinorCounts["中胸"], 6)
        XCTAssertEqual(chestMinorCounts["下胸"], 3)

        XCTAssertEqual(
            ExerciseGlyphKind.resolve(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃"),
            .chestPress
        )
        XCTAssertEqual(
            ExerciseGlyphKind.resolve(name: "坐姿飞鸟", muscleGroup: "胸部", equipment: "器械"),
            .chestFly
        )
        XCTAssertEqual(
            ExerciseGlyphKind.resolve(name: "高位下拉", muscleGroup: "背部", equipment: "器械"),
            .verticalPull
        )
        XCTAssertEqual(
            ExerciseGlyphKind.resolve(name: "坐姿划船", muscleGroup: "背部", equipment: "器械"),
            .row
        )
        XCTAssertEqual(
            ExerciseGlyphKind.resolve(name: "罗马尼亚硬拉", muscleGroup: "腿部", equipment: "杠铃"),
            .hinge
        )
        XCTAssertEqual(
            ExerciseGlyphKind.resolve(name: "腿弯举", muscleGroup: "腿部", equipment: "器械"),
            .legCurl
        )
        XCTAssertEqual(
            ExerciseGlyphKind.resolve(name: "高翻", muscleGroup: "腿部", equipment: "杠铃"),
            .olympicLift
        )
        XCTAssertEqual(
            ExerciseGlyphKind.resolve(name: "绳索躯干旋转", muscleGroup: "核心", equipment: "龙门架"),
            .rotation
        )
    }

    func testExerciseMuscleTaxonomyBuildsLinkedMajorAndMinorGroups() {
        let samples: [(String, String, ExerciseMuscleCategory)] = [
            ("上斜哑铃卧推", "胸部", .init(majorGroup: "胸部", minorGroup: "上胸")),
            ("杠铃卧推", "胸部", .init(majorGroup: "胸部", minorGroup: "中胸")),
            ("MTS 下斜卧推", "胸部", .init(majorGroup: "胸部", minorGroup: "下胸")),
            ("上背划船机", "背部", .init(majorGroup: "背部", minorGroup: "上背")),
            ("坐姿划船", "背部", .init(majorGroup: "背部", minorGroup: "中背")),
            ("高位下拉", "背部", .init(majorGroup: "背部", minorGroup: "背阔肌")),
            ("引体向上", "背部", .init(majorGroup: "背部", minorGroup: "背阔肌")),
            ("史密斯肩推", "肩部", .init(majorGroup: "肩部", minorGroup: "前束")),
            ("哑铃侧平举", "肩部", .init(majorGroup: "肩部", minorGroup: "中束")),
            ("面拉", "肩部", .init(majorGroup: "肩部", minorGroup: "后束")),
            ("哑铃弯举", "手臂", .init(majorGroup: "手臂", minorGroup: "肱二头肌")),
            ("三头下压", "手臂", .init(majorGroup: "手臂", minorGroup: "肱三头肌")),
            ("深蹲", "腿部", .init(majorGroup: "腿部", minorGroup: "股四头肌")),
            ("罗马尼亚硬拉", "腿部", .init(majorGroup: "腿部", minorGroup: "腘绳肌")),
            ("臀推", "腿部", .init(majorGroup: "腿部", minorGroup: "臀肌")),
            ("站姿提踵", "小腿", .init(majorGroup: "腿部", minorGroup: "小腿")),
            ("绳索卷腹", "核心", .init(majorGroup: "核心", minorGroup: "腹直肌")),
            ("绳索躯干旋转", "核心", .init(majorGroup: "核心", minorGroup: "腹斜肌"))
        ]

        for (name, group, expected) in samples {
            XCTAssertEqual(
                ExerciseMuscleTaxonomy.category(name: name, muscleGroup: group),
                expected,
                name
            )
        }

        let categories = samples.map {
            ExerciseMuscleTaxonomy.category(name: $0.0, muscleGroup: $0.1)
        }
        XCTAssertEqual(
            ExerciseMuscleTaxonomy.orderedMajorGroups(in: categories),
            ["胸部", "背部", "肩部", "手臂", "腿部", "核心"]
        )
        XCTAssertEqual(
            ExerciseMuscleTaxonomy.orderedMinorGroups(for: "胸部", in: categories),
            ["上胸", "中胸", "下胸"]
        )
        XCTAssertEqual(
            ExerciseMuscleTaxonomy.orderedMinorGroups(for: "腿部", in: categories),
            ["股四头肌", "腘绳肌", "臀肌", "小腿"]
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
