import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class AdaptivePlanningTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: NotificationService.workoutEnabledKey)
    }

    func testRecommendationPrioritizesActionOutsideLastMenu() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let bench = Exercise(name: "卧推", muscleGroup: "胸部", equipment: "杠铃")
        let incline = Exercise(name: "上斜推", muscleGroup: "胸部", equipment: "哑铃")
        let cableFly = Exercise(name: "绳索夹胸", muscleGroup: "胸部", equipment: "龙门架")
        let session = WorkoutSession(
            templateName: "上次胸部",
            plannedDate: now.addingDays(-5),
            startedAt: now.addingDays(-5),
            completedAt: now.addingDays(-5).addingTimeInterval(3600),
            status: .completed
        )
        let benchSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: bench.id,
            exerciseName: bench.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 12,
            targetWeight: 40,
            restSeconds: 90,
            muscleGroup: "胸部"
        )
        let inclineSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: incline.id,
            exerciseName: incline.name,
            order: 1,
            targetSets: 1,
            minReps: 8,
            maxReps: 12,
            targetWeight: 16,
            restSeconds: 90,
            muscleGroup: "胸部"
        )
        let logs = [
            completedLog(session: session, snapshot: benchSnapshot, exercise: bench, weight: 40, reps: 10, rir: 2),
            completedLog(session: session, snapshot: inclineSnapshot, exercise: incline, weight: 16, reps: 10, rir: 2)
        ]

        let recommendations = WorkoutRecommendationService.recommendations(
            selectedMuscleGroups: ["胸部"],
            exercises: [bench, incline, cableFly],
            sessions: [session],
            sessionExercises: [benchSnapshot, inclineSnapshot],
            setLogs: logs,
            templateExercises: [],
            now: now
        )

        XCTAssertEqual(recommendations.first?.exerciseID, cableFly.id)
        XCTAssertFalse(recommendations.first?.appearedInLastMenu ?? true)
        XCTAssertTrue(recommendations.last(where: { $0.exerciseID == bench.id })?.appearedInLastMenu == true)
    }

    func testRecommendationShowsLastIntensityAndProgressesWeight() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let bench = Exercise(
            name: "卧推",
            muscleGroup: "胸部",
            equipment: "杠铃",
            notes: "肩胛稳定"
        )
        let session = WorkoutSession(
            templateName: "胸部训练",
            plannedDate: now.addingDays(-8),
            startedAt: now.addingDays(-8),
            completedAt: now.addingDays(-8).addingTimeInterval(3600),
            status: .completed,
            notes: "右肩状态正常"
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: bench.id,
            exerciseName: bench.name,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 12,
            targetWeight: 40,
            restSeconds: 120,
            muscleGroup: "胸部",
            exerciseNotes: "肩胛稳定",
            performanceNotes: "下放慢一点"
        )
        let logs = (1...3).map { setNumber in
            SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: bench.id,
                setNumber: setNumber,
                targetWeight: 40,
                targetReps: 12,
                actualWeight: 40,
                actualReps: 12,
                rir: 2,
                isCompleted: true,
                completedAt: session.startedAt
            )
        }

        let recommendation = WorkoutRecommendationService.recommendations(
            selectedMuscleGroups: ["胸部"],
            exercises: [bench],
            sessions: [session],
            sessionExercises: [snapshot],
            setLogs: logs,
            templateExercises: [],
            now: now
        ).first

        XCTAssertEqual(recommendation?.lastPerformance?.sets.count, 3)
        XCTAssertEqual(recommendation?.lastPerformance?.bestSet?.weight, 40)
        XCTAssertEqual(recommendation?.suggestedWeight, 42.5)
        XCTAssertTrue(recommendation?.attentionText.contains("肩胛稳定") == true)
        XCTAssertTrue(recommendation?.attentionText.contains("下放慢一点") == true)
    }

    func testCuttingRecommendationPreservesSetsAndUsesWorkingWeight() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let row = Exercise(name: "上背划船机", muscleGroup: "背部", equipment: "器械")
        let session = WorkoutSession(
            templateName: "背部训练",
            plannedDate: now.addingDays(-7),
            startedAt: now.addingDays(-7),
            completedAt: now.addingDays(-7).addingTimeInterval(3_600),
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: row.id,
            exerciseName: row.name,
            order: 0,
            targetSets: 4,
            minReps: 12,
            maxReps: 12,
            targetWeight: 55,
            restSeconds: 90,
            muscleGroup: "背部"
        )
        let weights = [40.0, 45.0, 50.0, 55.0]
        let logs = weights.enumerated().map { index, weight in
            SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: row.id,
                setNumber: index + 1,
                targetWeight: weight,
                targetReps: 12,
                actualWeight: weight,
                actualReps: 12,
                rir: nil,
                isCompleted: true,
                completedAt: session.startedAt
            )
        }

        let recommendation = WorkoutRecommendationService.recommendations(
            selectedMuscleGroups: ["背部"],
            exercises: [row],
            sessions: [session],
            sessionExercises: [snapshot],
            setLogs: logs,
            templateExercises: [],
            goalMode: .cuttingVolume,
            now: now
        ).first

        XCTAssertEqual(recommendation?.suggestedSets, 4)
        XCTAssertEqual(recommendation?.minReps, 10)
        XCTAssertEqual(recommendation?.maxReps, 15)
        XCTAssertEqual(recommendation?.suggestedWeight, 47.5)
        XCTAssertEqual(recommendation?.suggestedVolume, 2_280)
        XCTAssertEqual(recommendation?.progressionTitle, "维持重量与组数")
        XCTAssertTrue(recommendation?.progressionDetail.contains("不据此加重") == true)
    }

    func testDailyPlanCreatesOneOffAndSkipsExistingPlan() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date.now.startOfDay
        let exercise = Exercise(name: "绳索夹胸", muscleGroup: "胸部", equipment: "龙门架")
        let regularTemplate = WorkoutTemplate(name: "固定推日", weekday: date.weekdayNumber)
        let regularSchedule = ScheduledWorkout(
            templateID: regularTemplate.id,
            templateName: regularTemplate.name,
            plannedDate: date
        )
        context.insert(exercise)
        context.insert(regularTemplate)
        context.insert(regularSchedule)

        let schedule = try DailyPlanService.create(
            on: date,
            muscleGroups: ["胸部"],
            exercises: [
                DailyPlanExerciseInput(
                    exerciseID: exercise.id,
                    targetSets: 3,
                    minReps: 10,
                    maxReps: 15,
                    targetWeight: 12.5,
                    restSeconds: 60
                )
            ],
            replaceExistingPlans: true,
            in: context
        )

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let items = try context.fetch(FetchDescriptor<TemplateExercise>())
        let oneOff = templates.first { $0.id == schedule.templateID }

        XCTAssertTrue(oneOff?.isOneOff == true)
        XCTAssertEqual(oneOff?.focusMuscleGroups, ["胸部"])
        XCTAssertEqual(items.first(where: { $0.templateID == oneOff?.id })?.targetWeight, 12.5)
        XCTAssertEqual(regularSchedule.status, .skipped)
        XCTAssertEqual(regularSchedule.skipReason, "已用当天自选菜单替代")
    }

    func testHistoricalRecordFeedsCompletedHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "高位下拉",
            muscleGroup: "背部",
            equipment: "器械",
            notes: "不要耸肩"
        )
        context.insert(exercise)
        let start = Date.now.addingDays(-7)

        let session = try HistoricalWorkoutService.record(
            HistoricalWorkoutInput(
                name: "上周拉日",
                startedAt: start,
                durationMinutes: 55,
                notes: "整体状态不错",
                exercises: [
                    HistoricalExerciseInput(
                        exerciseID: exercise.id,
                        sets: [
                            HistoricalSetInput(weight: 35, reps: 12, rir: 2),
                            HistoricalSetInput(weight: 35, reps: 11, rir: 1)
                        ],
                        performanceNotes: "下次保持胸口上提"
                    )
                ]
            ),
            in: context
        )

        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())

        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(snapshots.first?.muscleGroup, "背部")
        XCTAssertEqual(snapshots.first?.performanceNotes, "下次保持胸口上提")
        XCTAssertEqual(logs.filter(\.isCompleted).count, 2)
    }

    func testHistoricalCSVImportIsIdempotentAndCreatesMissingExercise() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let csv = """
        session_id,date,workout,duration_minutes,workout_notes,exercise,muscle_group,equipment,set,weight_kg,reps,rir,exercise_notes
        pull-2026-07-20,2026-07-20 18:30,拉日,55,状态良好,单臂器械划船,背部,器械,1,30,12,2,保持躯干稳定
        pull-2026-07-20,2026-07-20 18:30,拉日,55,状态良好,单臂器械划船,背部,器械,2,30,11,1,保持躯干稳定
        """
        let data = Data(csv.utf8)

        let preview = try HistoricalWorkoutCSVService.preview(data, in: context)
        XCTAssertEqual(preview.sessions, 1)
        XCTAssertEqual(preview.exercises, 1)
        XCTAssertEqual(preview.sets, 2)
        XCTAssertEqual(preview.duplicateSessions, 0)

        let first = try HistoricalWorkoutCSVService.importCSV(data, into: context)
        let second = try HistoricalWorkoutCSVService.importCSV(data, into: context)

        XCTAssertEqual(first.importedSessions, 1)
        XCTAssertEqual(first.createdExercises, 1)
        XCTAssertEqual(first.importedSets, 2)
        XCTAssertEqual(second.importedSessions, 0)
        XCTAssertEqual(second.skippedSessions, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).first?.name, "单臂器械划船")
    }

    func testMuscleGroupAdviceRecommendsRecoveryAfterRecentHighVolume() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let squat = Exercise(name: "深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let session = WorkoutSession(
            templateName: "腿部训练",
            plannedDate: now.addingDays(-1),
            startedAt: now.addingDays(-1),
            completedAt: now.addingDays(-1).addingTimeInterval(3600),
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: squat.id,
            exerciseName: squat.name,
            order: 0,
            targetSets: 16,
            minReps: 5,
            maxReps: 8,
            targetWeight: 80,
            restSeconds: 180,
            muscleGroup: "腿部"
        )
        let logs = (1...16).map { setNumber in
            SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: squat.id,
                setNumber: setNumber,
                targetWeight: 80,
                targetReps: 6,
                actualWeight: 80,
                actualReps: 6,
                rir: 2,
                isCompleted: true,
                completedAt: session.startedAt
            )
        }

        let advice = WorkoutRecommendationService.muscleGroupAdvice(
            selectedMuscleGroups: ["腿部"],
            exercises: [squat],
            sessions: [session],
            sessionExercises: [snapshot],
            setLogs: logs,
            now: now
        ).first

        XCTAssertEqual(advice?.readiness, .recover)
        XCTAssertEqual(advice?.completedSetsLast7Days, 16)
    }

    func testHistoricalCSVSupportsQuotedCommasAndNotes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let csv = #"""
        session_id,date,workout,duration_minutes,workout_notes,exercise,muscle_group,equipment,set,weight_kg,reps,rir,exercise_notes
        quoted-1,2026-07-20 18:30,推日,55,"肩部正常, 睡眠一般",杠铃卧推,胸部,杠铃,1,60,10,2,"下放慢, 不要弹胸"
        """#

        let summary = try HistoricalWorkoutCSVService.importCSV(Data(csv.utf8), into: context)
        let session = try context.fetch(FetchDescriptor<WorkoutSession>()).first
        let snapshot = try context.fetch(FetchDescriptor<SessionExercise>()).first

        XCTAssertEqual(summary.importedSessions, 1)
        XCTAssertEqual(session?.notes, "肩部正常, 睡眠一般")
        XCTAssertEqual(snapshot?.performanceNotes, "下放慢, 不要弹胸")
    }

    func testHistoricalCSVSkipsIncompleteRowsAndExistingSessionUUID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = WorkoutSession(
            templateName: "已有训练",
            plannedDate: Date.now.addingDays(-2),
            startedAt: Date.now.addingDays(-2),
            completedAt: Date.now.addingDays(-2).addingTimeInterval(3600),
            status: .completed
        )
        context.insert(existing)
        try context.save()
        let csv = """
        session_id,date,workout,exercise,set,weight_kg,reps,completed
        \(existing.id.uuidString),2026-07-20 18:30,已有训练,卧推,1,60,10,true
        new-session,2026-07-21 18:30,新训练,卧推,1,60,0,false
        """

        let preview = try HistoricalWorkoutCSVService.preview(Data(csv.utf8), in: context)
        let summary = try HistoricalWorkoutCSVService.importCSV(Data(csv.utf8), into: context)

        XCTAssertEqual(preview.sessions, 1)
        XCTAssertEqual(preview.duplicateSessions, 1)
        XCTAssertEqual(summary.importedSessions, 0)
        XCTAssertEqual(summary.skippedSessions, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
    }

    func testImportedWorkoutNameRemovesNotesSourceLabel() {
        XCTAssertEqual(
            SeedDataService.normalizedImportedWorkoutName("肩胸训练 (Notes)"),
            "肩胸训练"
        )
        XCTAssertEqual(
            SeedDataService.normalizedImportedWorkoutName("背部训练（Notes）"),
            "背部训练"
        )
        XCTAssertEqual(
            SeedDataService.normalizedImportedWorkoutName("普通训练"),
            "普通训练"
        )
    }

    func testAppPreparationCleansImportedNotesLabelWithoutChangingLocalNames() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let imported = WorkoutSession(
            templateName: "肩胸训练 (Notes)",
            plannedDate: .now,
            status: .completed,
            importIdentifier: "notes:shoulder-chest"
        )
        let local = WorkoutSession(
            templateName: "自定义训练 (Notes)",
            plannedDate: .now,
            status: .completed
        )
        context.insert(Exercise(name: "卧推", muscleGroup: "胸部", equipment: "杠铃"))
        context.insert(imported)
        context.insert(local)
        try context.save()

        try SeedDataService.prepareIfNeeded(in: context)

        XCTAssertEqual(imported.templateName, "肩胸训练")
        XCTAssertEqual(local.templateName, "自定义训练 (Notes)")
    }

    func testActiveWorkoutMenuCanAddExerciseAndAdjustIncompleteSets() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            templateName: "今日训练",
            plannedDate: .now,
            status: .inProgress
        )
        let bench = Exercise(name: "卧推", muscleGroup: "胸部", equipment: "杠铃")
        let fly = Exercise(name: "夹胸", muscleGroup: "胸部", equipment: "龙门架")
        let benchSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: bench.id,
            exerciseName: bench.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 12,
            targetWeight: 40,
            restSeconds: 90,
            muscleGroup: "胸部"
        )
        let benchLog = SetLog(
            sessionID: session.id,
            sessionExerciseID: benchSnapshot.id,
            exerciseID: bench.id,
            setNumber: 1,
            targetWeight: 40,
            targetReps: 8,
            actualWeight: 40,
            actualReps: 8
        )
        context.insert(session)
        context.insert(bench)
        context.insert(fly)
        context.insert(benchSnapshot)
        context.insert(benchLog)
        try context.save()

        let flySnapshot = try WorkoutService.addExercise(fly, to: session, in: context)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SetLog>())
                .filter { $0.sessionExerciseID == flySnapshot.id }
                .count,
            3
        )

        try WorkoutService.addSet(to: flySnapshot, in: context)
        XCTAssertEqual(flySnapshot.targetSets, 4)
        try WorkoutService.removeLastIncompleteSet(from: flySnapshot, in: context)
        XCTAssertEqual(flySnapshot.targetSets, 3)

        try WorkoutService.removeExercise(flySnapshot, from: session, in: context)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<SessionExercise>())
                .filter { $0.sessionID == session.id }
                .count,
            1
        )
    }

    func testActiveWorkoutCannotRemoveExerciseAfterASetIsCompleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = WorkoutSession(
            templateName: "今日训练",
            plannedDate: .now,
            status: .inProgress
        )
        let bench = Exercise(name: "卧推", muscleGroup: "胸部", equipment: "杠铃")
        let fly = Exercise(name: "夹胸", muscleGroup: "胸部", equipment: "龙门架")
        context.insert(session)
        context.insert(bench)
        context.insert(fly)
        let benchSnapshot = try WorkoutService.addExercise(bench, to: session, in: context)
        _ = try WorkoutService.addExercise(fly, to: session, in: context)
        let firstLog = try context.fetch(FetchDescriptor<SetLog>())
            .first { $0.sessionExerciseID == benchSnapshot.id }
        firstLog?.isCompleted = true
        try context.save()

        XCTAssertThrowsError(
            try WorkoutService.removeExercise(benchSnapshot, from: session, in: context)
        )
    }

    func testExerciseCatalogCreatesSearchableExerciseAndRestoresArchivedMatch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let archived = Exercise(
            name: "高位绳索弯举",
            muscleGroup: "手臂",
            equipment: "龙门架",
            isBuiltIn: false,
            isArchived: true
        )
        context.insert(archived)

        let result = try ExerciseCatalogService.save(
            exercise: nil,
            name: " 高位绳索弯举 ",
            muscleGroup: "手臂",
            equipment: "龙门架",
            defaultRestSeconds: 60,
            notes: "手肘保持固定",
            referenceURL: "https://example.com/curl",
            allExercises: [archived],
            in: context
        )

        XCTAssertEqual(result.kind, .restored)
        XCTAssertEqual(result.exercise.id, archived.id)
        XCTAssertFalse(archived.isArchived)
        XCTAssertEqual(archived.referenceURL, "https://example.com/curl")
        XCTAssertEqual(
            ExerciseCatalogService.search([archived], query: "手肘").first?.id,
            archived.id
        )
    }

    func testExerciseCatalogRejectsUnsafeReferenceURL() throws {
        let container = try makeContainer()
        XCTAssertThrowsError(
            try ExerciseCatalogService.save(
                exercise: nil,
                name: "测试动作",
                muscleGroup: "其他",
                equipment: "自重",
                defaultRestSeconds: 90,
                notes: "",
                referenceURL: "javascript:alert(1)",
                allExercises: [],
                in: container.mainContext
            )
        ) { error in
            XCTAssertEqual(error as? ExerciseCatalogError, .invalidReferenceURL)
        }
    }

    func testDailyPlanValidationDoesNotReplaceExistingPlanOnMissingExercise() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date.now.startOfDay
        let template = WorkoutTemplate(name: "固定推日", weekday: date.weekdayNumber)
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: date
        )
        context.insert(template)
        context.insert(schedule)
        try context.save()

        XCTAssertThrowsError(
            try DailyPlanService.create(
                on: date,
                muscleGroups: ["胸部"],
                exercises: [
                    DailyPlanExerciseInput(
                        exerciseID: UUID(),
                        targetSets: 3,
                        minReps: 8,
                        maxReps: 12,
                        targetWeight: 0,
                        restSeconds: 90
                    )
                ],
                replaceExistingPlans: true,
                in: context
            )
        )

        XCTAssertEqual(schedule.status, .planned)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 1)
        XCTAssertFalse(try context.fetch(FetchDescriptor<WorkoutTemplate>()).contains(where: \.isOneOff))
    }

    func testDailyPlanRejectsEveryInvalidDraftBeforeMutation() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let active = Exercise(name: "有效动作", muscleGroup: "胸部", equipment: "哑铃")
        let archived = Exercise(
            name: "已归档动作",
            muscleGroup: "胸部",
            equipment: "哑铃",
            isArchived: true
        )
        context.insert(active)
        context.insert(archived)
        try context.save()

        let validInput = DailyPlanExerciseInput(
            exerciseID: active.id,
            targetSets: 3,
            minReps: 8,
            maxReps: 12,
            targetWeight: 10,
            restSeconds: 90
        )
        let archivedInput = DailyPlanExerciseInput(
            exerciseID: archived.id,
            targetSets: 3,
            minReps: 8,
            maxReps: 12,
            targetWeight: 10,
            restSeconds: 90
        )
        let missingInput = DailyPlanExerciseInput(
            exerciseID: UUID(),
            targetSets: 3,
            minReps: 8,
            maxReps: 12,
            targetWeight: 10,
            restSeconds: 90
        )

        XCTAssertDailyPlanError(.emptyMuscleGroups) {
            _ = try DailyPlanService.create(
                on: .now,
                muscleGroups: ["  "],
                exercises: [validInput],
                replaceExistingPlans: true,
                in: context
            )
        }
        XCTAssertDailyPlanError(.emptyExercises) {
            _ = try DailyPlanService.create(
                on: .now,
                muscleGroups: ["胸部"],
                exercises: [],
                replaceExistingPlans: true,
                in: context
            )
        }
        XCTAssertDailyPlanError(.duplicateExercise) {
            _ = try DailyPlanService.create(
                on: .now,
                muscleGroups: ["胸部"],
                exercises: [validInput, validInput],
                replaceExistingPlans: true,
                in: context
            )
        }
        XCTAssertDailyPlanError(.archivedExercise) {
            _ = try DailyPlanService.create(
                on: .now,
                muscleGroups: ["胸部"],
                exercises: [archivedInput],
                replaceExistingPlans: true,
                in: context
            )
        }
        XCTAssertDailyPlanError(.missingExercise) {
            _ = try DailyPlanService.create(
                on: .now,
                muscleGroups: ["胸部"],
                exercises: [missingInput],
                replaceExistingPlans: true,
                in: context
            )
        }

        XCTAssertTrue(try context.fetch(FetchDescriptor<ScheduledWorkout>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TemplateExercise>()).isEmpty)
    }

    func testDailyPlanCannotReplaceStartedOrCompletedOneOff() throws {
        for status in [ScheduleStatus.inProgress, .completed] {
            let container = try makeContainer()
            let context = container.mainContext
            let date = Date.now.startOfDay
            let exercise = Exercise(name: "卧推", muscleGroup: "胸部", equipment: "杠铃")
            let template = WorkoutTemplate(
                name: "胸部 · 当天菜单",
                weekday: date.weekdayNumber,
                isActive: false,
                isOneOff: true,
                plannedForDate: date,
                focusMuscleGroups: ["胸部"]
            )
            let item = TemplateExercise(
                templateID: template.id,
                exerciseID: exercise.id,
                order: 0,
                targetSets: 3,
                minReps: 8,
                maxReps: 8,
                targetWeight: 40,
                restSeconds: 90
            )
            let schedule = ScheduledWorkout(
                templateID: template.id,
                templateName: template.name,
                plannedDate: date,
                status: status,
                isManuallyScheduled: true
            )
            context.insert(exercise)
            context.insert(template)
            context.insert(item)
            context.insert(schedule)
            try context.save()

            XCTAssertDailyPlanError(.immutableExistingPlan) {
                _ = try DailyPlanService.create(
                    on: date,
                    muscleGroups: ["胸部"],
                    exercises: [
                        DailyPlanExerciseInput(
                            exerciseID: exercise.id,
                            targetSets: 4,
                            minReps: 10,
                            maxReps: 10,
                            targetWeight: 30,
                            restSeconds: 60
                        )
                    ],
                    replaceExistingPlans: true,
                    in: context
                )
            }

            XCTAssertEqual(schedule.status, status)
            XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).count, 1)
            XCTAssertEqual(try context.fetch(FetchDescriptor<TemplateExercise>()).count, 1)
        }
    }

    func testRepeatedDailyPlanSaveLeavesOneAuthoritativeOneOff() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date.now.startOfDay
        let exercise = Exercise(name: "卧推", muscleGroup: "胸部", equipment: "杠铃")
        let weekly = WorkoutTemplate(name: "固定推日", weekday: date.weekdayNumber)
        let weeklySchedule = ScheduledWorkout(
            templateID: weekly.id,
            templateName: weekly.name,
            plannedDate: date
        )
        context.insert(exercise)
        context.insert(weekly)
        context.insert(weeklySchedule)
        try context.save()

        for weight in [40.0, 42.5, 45.0] {
            _ = try DailyPlanService.create(
                on: date,
                muscleGroups: ["胸部"],
                exercises: [
                    DailyPlanExerciseInput(
                        exerciseID: exercise.id,
                        targetSets: 3,
                        minReps: 8,
                        maxReps: 8,
                        targetWeight: weight,
                        restSeconds: 90
                    )
                ],
                replaceExistingPlans: true,
                in: context
            )
        }

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        let oneOffs = templates.filter(\.isOneOff)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let oneOffSchedules = schedules.filter { oneOffs.map(\.id).contains($0.templateID) }
        let items = try context.fetch(FetchDescriptor<TemplateExercise>())
            .filter { oneOffs.map(\.id).contains($0.templateID) }

        XCTAssertEqual(oneOffs.count, 1)
        XCTAssertEqual(oneOffSchedules.count, 1)
        XCTAssertEqual(oneOffSchedules.first?.status, .planned)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.targetWeight, 45)
        XCTAssertEqual(weeklySchedule.status, .skipped)
    }

    func testWorkoutStartIsIdempotentAndPreservesPlanSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date.now.startOfDay
        let exercise = Exercise(
            name: "哑铃卧推",
            muscleGroup: "胸部",
            equipment: "哑铃",
            volumeUnit: .kilogram
        )
        context.insert(exercise)
        try context.save()
        let schedule = try DailyPlanService.create(
            on: date,
            muscleGroups: ["胸部"],
            exercises: [
                DailyPlanExerciseInput(
                    exerciseID: exercise.id,
                    plannedSets: [
                        WorkoutSetPlan(weight: 20, reps: 10),
                        WorkoutSetPlan(weight: 22.5, reps: 8)
                    ],
                    planPattern: .pyramidUp,
                    restSeconds: 120
                )
            ],
            replaceExistingPlans: true,
            in: context
        )

        let firstSessionID = try WorkoutService.start(schedule: schedule, in: context)
        let secondSessionID = try WorkoutService.start(schedule: schedule, in: context)
        XCTAssertEqual(firstSessionID, secondSessionID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)

        let snapshot = try XCTUnwrap(
            context.fetch(FetchDescriptor<SessionExercise>()).first
        )
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(snapshot.exerciseName, "哑铃卧推")
        XCTAssertEqual(snapshot.planPattern, .pyramidUp)
        XCTAssertEqual(snapshot.plannedSets.map(\.weight), [20, 22.5])
        XCTAssertEqual(logs.map(\.targetWeight), [20, 22.5])

        exercise.name = "动作库后来改名"
        exercise.volumeUnit = .count
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<TemplateExercise>()).first)
        item.plannedSets = [WorkoutSetPlan(weight: 99, reps: 99)]
        try context.save()

        XCTAssertEqual(snapshot.exerciseName, "哑铃卧推")
        XCTAssertEqual(snapshot.volumeUnit, .kilogram)
        XCTAssertEqual(snapshot.plannedSets.map(\.weight), [20, 22.5])
        XCTAssertEqual(logs.map(\.targetWeight), [20, 22.5])
    }

    func testDailyPlanAndCompletedVolumePersistAcrossContainerRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("XFitHomePersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("HomeFeature.store")
        var expectedScheduleID = UUID()
        var expectedSessionID = UUID()

        do {
            let container = try makePersistentContainer(at: storeURL)
            let context = container.mainContext
            let exercise = Exercise(name: "持久化卧推", muscleGroup: "胸部", equipment: "杠铃")
            context.insert(exercise)
            try context.save()
            let schedule = try DailyPlanService.create(
                on: .now,
                muscleGroups: ["胸部"],
                exercises: [
                    DailyPlanExerciseInput(
                        exerciseID: exercise.id,
                        targetSets: 1,
                        minReps: 10,
                        maxReps: 10,
                        targetWeight: 42,
                        restSeconds: 90
                    )
                ],
                replaceExistingPlans: true,
                in: context
            )
            expectedScheduleID = schedule.id
            expectedSessionID = try WorkoutService.start(schedule: schedule, in: context)
            let log = try XCTUnwrap(context.fetch(FetchDescriptor<SetLog>()).first)
            log.actualWeight = 42
            log.actualReps = 10
            log.isCompleted = true
            let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
            session.status = .completed
            session.completedAt = .now
            schedule.status = .completed
            try context.save()
        }

        do {
            let container = try makePersistentContainer(at: storeURL)
            let context = container.mainContext
            let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
            let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
            let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            let exercises = try context.fetch(FetchDescriptor<Exercise>())
            let logs = try context.fetch(FetchDescriptor<SetLog>())

            XCTAssertEqual(schedules.first?.id, expectedScheduleID)
            XCTAssertEqual(schedules.first?.status, .completed)
            XCTAssertEqual(sessions.first?.id, expectedSessionID)
            XCTAssertEqual(sessions.first?.status, .completed)
            XCTAssertEqual(
                TrainingMetrics.volumeTrends(
                    sessions: sessions,
                    sessionExercises: snapshots,
                    exercises: exercises,
                    setLogs: logs
                ).overall.first?.volume,
                420
            )
        }
    }

    func testWorkoutStartSnapshotsExerciseReferenceURL() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "哑铃古巴推举",
            muscleGroup: "肩部",
            equipment: "哑铃",
            referenceURL: "https://example.com/cuban-press"
        )
        let template = WorkoutTemplate(name: "肩部", weekday: Date.now.weekdayNumber)
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: 3,
            minReps: 10,
            maxReps: 12,
            targetWeight: 5,
            restSeconds: 60
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
        let snapshot = try context.fetch(FetchDescriptor<SessionExercise>())
            .first { $0.sessionID == sessionID }

        XCTAssertEqual(snapshot?.referenceURL, exercise.referenceURL)
        exercise.referenceURL = "https://example.com/changed"
        XCTAssertEqual(snapshot?.referenceURL, "https://example.com/cuban-press")
    }

    private func completedLog(
        session: WorkoutSession,
        snapshot: SessionExercise,
        exercise: Exercise,
        weight: Double,
        reps: Int,
        rir: Int
    ) -> SetLog {
        SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: weight,
            targetReps: reps,
            actualWeight: weight,
            actualReps: reps,
            rir: rir,
            isCompleted: true,
            completedAt: session.startedAt
        )
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
            BodyMeasurement.self
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
            BodyMeasurement.self
        ])
        let configuration = ModelConfiguration(
            "HomeFeaturePersistenceTests",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func XCTAssertDailyPlanError(
        _ expected: DailyPlanServiceError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard let actual = error as? DailyPlanServiceError else {
                return XCTFail("错误类型不正确：\(error)", file: file, line: line)
            }
            XCTAssertEqual(
                actual.errorDescription,
                expected.errorDescription,
                file: file,
                line: line
            )
        }
    }
}
