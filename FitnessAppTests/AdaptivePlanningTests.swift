import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class AdaptivePlanningTests: XCTestCase {
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

    func testConfirmedAliasCatalogIncludesNewlyApprovedSixGroups() {
        let groups = Dictionary(
            uniqueKeysWithValues: ExerciseCatalogService.confirmedAliasGroups.map {
                ($0.canonicalID, ($0.primaryName, Set($0.aliases)))
            }
        )

        XCTAssertEqual(ExerciseCatalogService.confirmedAliasGroups.count, 15)
        XCTAssertEqual(groups["landmine_zercher_squat"]?.0, "地雷杆泽奇蹲")
        XCTAssertEqual(groups["landmine_zercher_squat"]?.1, ["地雷杆泽奇蹲", "地雷杠泽奇蹲"])
        XCTAssertEqual(groups["landmine_rotation"]?.0, "地雷杆转体")
        XCTAssertEqual(groups["landmine_rotation"]?.1, ["地雷杆转体", "地雷杆转向"])
        XCTAssertEqual(groups["barbell_conventional_deadlift"]?.0, "传统硬拉")
        XCTAssertEqual(groups["machine_pec_deck_fly"]?.1, ["坐姿飞鸟", "fly"])
        XCTAssertEqual(
            groups["machine_reverse_fly"]?.1,
            ["器械反向飞鸟", "Reverse Fly", "rear dealt"]
        )
        XCTAssertEqual(
            groups["machine_decline_chest_press"]?.1,
            ["器械下斜卧推", "坐姿下斜推胸机", "declined bench press", "MTS 下斜卧推"]
        )
        XCTAssertEqual(
            groups["machine_shoulder_press"]?.1,
            ["器械肩推", "shoulder press", "side press", "三角肌训练机"]
        )
        XCTAssertEqual(groups["barbell_hip_thrust"]?.0, "杠铃臀推")
        XCTAssertEqual(groups["barbell_thruster"]?.0, "杠铃火箭推")
        XCTAssertEqual(groups["machine_triceps_press"]?.1, ["坐姿器械臂屈伸", "三头下压机", "seated dip"])
        XCTAssertEqual(groups["dumbbell_side_lunge"]?.1, ["哑铃侧弓步", "哑铃侧边蹲"])
    }

    func testConfirmedSecondPassCleanupMergesNonConflictingGroupsRenamesAndArchives() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let inputs = [
            Exercise(name: "declined bench press", muscleGroup: "胸部", equipment: "待审核"),
            Exercise(name: "器械下斜卧推", muscleGroup: "胸部", equipment: "器械"),
            Exercise(name: "MTS 下斜卧推", muscleGroup: "胸部", equipment: "MTS 器械"),
            Exercise(name: "臀推", muscleGroup: "腿部", equipment: "杠铃"),
            Exercise(name: "顶髋", muscleGroup: "臀部", equipment: "杠铃"),
            Exercise(name: "火箭推", muscleGroup: "肩部", equipment: "杠铃"),
            Exercise(name: "半蹲上推", muscleGroup: "其他", equipment: "杠铃"),
            Exercise(name: "seated dip", muscleGroup: "手臂", equipment: "器械"),
            Exercise(name: "三头下压机", muscleGroup: "手臂", equipment: "器械"),
            Exercise(name: "side press", muscleGroup: "肩部", equipment: "器械"),
            Exercise(name: "三角肌训练机", muscleGroup: "肩部", equipment: "器械"),
            Exercise(name: "器械肩推", muscleGroup: "肩部", equipment: "器械"),
            Exercise(name: "器械反向飞鸟", muscleGroup: "肩部", equipment: "器械"),
            Exercise(name: "哑铃侧弓步", muscleGroup: "腿部", equipment: "哑铃"),
            Exercise(name: "哑铃侧边蹲", muscleGroup: "腿部", equipment: "哑铃"),
            Exercise(name: "地雷杠侧边蹲", muscleGroup: "腿部", equipment: "地雷杆"),
            Exercise(name: "壶铃饶颈侧拉", muscleGroup: "核心", equipment: "壶铃"),
            Exercise(name: "真机分享动作 20260823", muscleGroup: "其他", equipment: "自重"),
            Exercise(name: "真机菜单动作 20260823", muscleGroup: "手臂", equipment: "自重"),
            Exercise(name: "真机训练中动作 20260823", muscleGroup: "其他", equipment: "自重")
        ]
        inputs.forEach(context.insert)

        let mts = try XCTUnwrap(inputs.first { $0.name == "MTS 下斜卧推" })
        let completedSession = WorkoutSession(
            templateName: "历史胸部训练",
            plannedDate: .now.addingDays(-7),
            startedAt: .now.addingDays(-7),
            completedAt: .now.addingDays(-7).addingTimeInterval(3_600),
            status: .completed
        )
        let historicalSnapshot = SessionExercise(
            sessionID: completedSession.id,
            exerciseID: mts.id,
            exerciseName: mts.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 12,
            targetWeight: 40,
            restSeconds: 90,
            muscleGroup: "胸部"
        )
        context.insert(completedSession)
        context.insert(historicalSnapshot)
        try context.save()

        try SeedDataService.prepareIfNeeded(in: context, allowInitialSeed: false)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let activeNames = Set(exercises.filter { !$0.isArchived }.map(\.name))
        XCTAssertTrue(activeNames.contains("器械下斜卧推"))
        XCTAssertTrue(activeNames.contains("杠铃臀推"))
        XCTAssertTrue(activeNames.contains("杠铃火箭推"))
        XCTAssertTrue(activeNames.contains("坐姿器械臂屈伸"))
        XCTAssertTrue(activeNames.contains("器械肩推"))
        XCTAssertTrue(activeNames.contains("器械反向飞鸟"))
        XCTAssertTrue(activeNames.contains("哑铃侧弓步"))
        XCTAssertTrue(activeNames.contains("地雷杆侧边蹲"))
        XCTAssertTrue(activeNames.contains("壶铃绕颈侧拉"))
        XCTAssertFalse(activeNames.contains("declined bench press"))
        XCTAssertFalse(activeNames.contains("MTS 下斜卧推"))
        XCTAssertFalse(activeNames.contains("臀推"))
        XCTAssertFalse(activeNames.contains("顶髋"))
        XCTAssertFalse(activeNames.contains("火箭推"))
        XCTAssertFalse(activeNames.contains("半蹲上推"))
        XCTAssertFalse(activeNames.contains("seated dip"))
        XCTAssertFalse(activeNames.contains("side press"))
        XCTAssertFalse(activeNames.contains("三角肌训练机"))
        XCTAssertFalse(activeNames.contains("哑铃侧边蹲"))
        XCTAssertFalse(activeNames.contains("地雷杠侧边蹲"))
        XCTAssertFalse(activeNames.contains("壶铃饶颈侧拉"))
        XCTAssertFalse(activeNames.contains("真机分享动作 20260823"))
        XCTAssertFalse(activeNames.contains("真机菜单动作 20260823"))
        XCTAssertFalse(activeNames.contains("真机训练中动作 20260823"))

        XCTAssertEqual(
            exercises.filter { $0.terminologyCanonicalID == "machine_decline_chest_press" && !$0.isArchived }.count,
            1
        )
        XCTAssertEqual(
            exercises.filter { $0.terminologyCanonicalID == "barbell_hip_thrust" && !$0.isArchived }.count,
            1
        )
        XCTAssertEqual(
            exercises.filter { $0.terminologyCanonicalID == "machine_shoulder_press" && !$0.isArchived }.count,
            1
        )
        XCTAssertEqual(
            exercises.filter { $0.terminologyCanonicalID == "machine_reverse_fly" && !$0.isArchived }.count,
            1
        )
        XCTAssertEqual(historicalSnapshot.exerciseID, mts.id)
        XCTAssertEqual(historicalSnapshot.exerciseName, "MTS 下斜卧推")
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
            preference: .confirmed,
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
            preference: .confirmed,
            now: now
        ).first

        XCTAssertEqual(recommendation?.lastPerformance?.sets.count, 3)
        XCTAssertEqual(recommendation?.lastPerformance?.bestSet?.weight, 40)
        XCTAssertEqual(recommendation?.suggestedWeight, 42.5)
        XCTAssertTrue(recommendation?.attentionText.contains("肩胛稳定") == true)
        XCTAssertTrue(recommendation?.attentionText.contains("下放慢一点") == true)
    }

    func testRecommendationAggregatesArchivedAliasHistoryWithoutChangingSnapshotIdentity() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let primary = Exercise(
            name: "地雷杆泽奇蹲",
            muscleGroup: "腿部",
            equipment: "地雷杆",
            terminologyCanonicalID: "landmine_zercher_squat",
            terminologyDecision: .accepted
        )
        let alias = Exercise(
            name: "地雷杠泽奇蹲",
            muscleGroup: "腿部",
            equipment: "地雷杆",
            isBuiltIn: false,
            isArchived: true,
            terminologyCanonicalID: "landmine_zercher_squat",
            terminologyDecision: .accepted
        )
        let session = WorkoutSession(
            templateName: "下肢训练",
            plannedDate: now.addingDays(-3),
            startedAt: now.addingDays(-3),
            completedAt: now.addingDays(-3).addingTimeInterval(3_600),
            status: .completed
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: alias.id,
            exerciseName: alias.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 20,
            restSeconds: 90,
            muscleGroup: "腿部"
        )
        let log = completedLog(
            session: session,
            snapshot: snapshot,
            exercise: alias,
            weight: 20,
            reps: 10,
            rir: 2
        )

        let recommendations = WorkoutRecommendationService.recommendations(
            selectedMuscleGroups: ["腿部"],
            exercises: [primary, alias],
            sessions: [session],
            sessionExercises: [snapshot],
            setLogs: [log],
            templateExercises: [],
            preference: .confirmed,
            now: now
        )

        XCTAssertEqual(recommendations.count, 1)
        XCTAssertEqual(recommendations.first?.exerciseID, primary.id)
        XCTAssertEqual(recommendations.first?.lastPerformance?.workoutName, "下肢训练")
        XCTAssertEqual(recommendations.first?.lastPerformance?.volume, 200)
        XCTAssertTrue(recommendations.first?.appearedInLastMenu == true)
        XCTAssertEqual(snapshot.exerciseID, alias.id)
        XCTAssertEqual(snapshot.exerciseName, "地雷杠泽奇蹲")
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
            preference: .confirmed,
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
        let candidate = try XCTUnwrap(WorkoutService.reductionCandidate(for: flySnapshot, in: context))
        try WorkoutService.reduceSet(from: flySnapshot, candidateID: candidate.id, confirmingEnteredData: false, in: context)
        XCTAssertEqual(flySnapshot.targetSets, 3)

        XCTAssertThrowsError(try WorkoutService.removeExercise(flySnapshot, from: session, in: context))
        try WorkoutService.restoreReducedSet(for: flySnapshot, in: context)
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

    func testRunningWorkoutMenuRemovesAutoStartedExerciseWithNoCompletedSetsWithoutReplacingHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let bulgarian = Exercise(name: "保加利亚单腿蹲", muscleGroup: "腿部", equipment: "哑铃")
        let legCurl = Exercise(name: "俯卧腿弯举", muscleGroup: "腿部", equipment: "固定器械")
        let historicalDate = Date(timeIntervalSince1970: 1_799_000_000)
        let historicalSession = WorkoutSession(
            templateName: "腿部历史",
            plannedDate: historicalDate,
            startedAt: historicalDate,
            completedAt: historicalDate.addingTimeInterval(1_800),
            status: .completed
        )
        let historicalSnapshot = SessionExercise(
            sessionID: historicalSession.id,
            exerciseID: bulgarian.id,
            exerciseName: bulgarian.name,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 15,
            restSeconds: 90,
            muscleGroup: bulgarian.muscleGroup
        )
        let historicalLog = SetLog(
            sessionID: historicalSession.id,
            sessionExerciseID: historicalSnapshot.id,
            exerciseID: bulgarian.id,
            setNumber: 1,
            targetWeight: 15,
            targetReps: 8,
            actualWeight: 15,
            actualReps: 8,
            isCompleted: true,
            completedAt: historicalDate.addingTimeInterval(600)
        )

        let activeDate = Date(timeIntervalSince1970: 1_800_000_000)
        let activeSession = WorkoutSession(
            templateName: "腿部 · 当天菜单",
            plannedDate: activeDate,
            startedAt: activeDate,
            status: .inProgress
        )
        let removableSnapshot = SessionExercise(
            sessionID: activeSession.id,
            exerciseID: bulgarian.id,
            exerciseName: bulgarian.name,
            order: 0,
            targetSets: 4,
            minReps: 8,
            maxReps: 8,
            targetWeight: 20,
            restSeconds: 90,
            muscleGroup: bulgarian.muscleGroup,
            exerciseStartedAt: activeDate
        )
        let keptSnapshot = SessionExercise(
            sessionID: activeSession.id,
            exerciseID: legCurl.id,
            exerciseName: legCurl.name,
            order: 1,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 30,
            restSeconds: 90,
            muscleGroup: legCurl.muscleGroup
        )
        let removableLogs = (1...4).map { setNumber in
            SetLog(
                sessionID: activeSession.id,
                sessionExerciseID: removableSnapshot.id,
                exerciseID: bulgarian.id,
                setNumber: setNumber,
                targetWeight: 20,
                targetReps: 8,
                actualWeight: 20,
                actualReps: 8
            )
        }
        let keptLog = SetLog(
            sessionID: activeSession.id,
            sessionExerciseID: keptSnapshot.id,
            exerciseID: legCurl.id,
            setNumber: 1,
            targetWeight: 30,
            targetReps: 10,
            actualWeight: 30,
            actualReps: 10,
            isCompleted: true,
            completedAt: activeDate.addingTimeInterval(900)
        )

        [bulgarian, legCurl].forEach(context.insert)
        [historicalSession, activeSession].forEach(context.insert)
        [historicalSnapshot, removableSnapshot, keptSnapshot].forEach(context.insert)
        context.insert(historicalLog)
        removableLogs.forEach(context.insert)
        context.insert(keptLog)
        try context.save()

        try WorkoutService.syncMenu(
            [
                DailyPlanExerciseInput(
                    exerciseID: legCurl.id,
                    plannedSets: [WorkoutSetPlan(weight: 30, reps: 10)],
                    planPattern: .fixed,
                    restSeconds: 90
                )
            ],
            to: activeSession,
            in: context
        )

        let currentSnapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == activeSession.id }
        let currentLogs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionID == activeSession.id }
        XCTAssertEqual(currentSnapshots.map(\.exerciseID), [legCurl.id])
        XCTAssertEqual(currentLogs.map(\.id), [keptLog.id])
        XCTAssertEqual(keptLog.actualWeight, 30, accuracy: 0.0001)
        XCTAssertTrue(keptLog.isCompleted)

        activeSession.status = .completed
        activeSession.completedAt = activeDate.addingTimeInterval(1_800)
        try context.save()
        let recommendations = WorkoutRecommendationService.recommendations(
            selectedMuscleGroups: ["腿部"],
            exercises: [bulgarian, legCurl],
            sessions: [historicalSession, activeSession],
            sessionExercises: try context.fetch(FetchDescriptor<SessionExercise>()),
            setLogs: try context.fetch(FetchDescriptor<SetLog>()),
            templateExercises: [],
            preference: .confirmed,
            now: activeDate.addingTimeInterval(86_400)
        )
        let bulgarianRecommendation = try XCTUnwrap(
            recommendations.first { $0.exerciseID == bulgarian.id }
        )
        XCTAssertFalse(bulgarianRecommendation.appearedInLastMenu)
        XCTAssertEqual(bulgarianRecommendation.lastPerformance?.date, historicalDate)
        XCTAssertEqual(bulgarianRecommendation.lastPerformance?.bestSet?.weight, 15)
    }

    func testRunningWorkoutMenuKeepsExerciseThatHasACompletedSet() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let bench = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        let fly = Exercise(name: "绳索夹胸", muscleGroup: "胸部", equipment: "龙门架")
        let session = WorkoutSession(
            templateName: "胸部 · 当天菜单",
            plannedDate: .now,
            status: .inProgress
        )
        let benchSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: bench.id,
            exerciseName: bench.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 40,
            restSeconds: 90,
            muscleGroup: bench.muscleGroup
        )
        let flySnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: fly.id,
            exerciseName: fly.name,
            order: 1,
            targetSets: 1,
            minReps: 12,
            maxReps: 12,
            targetWeight: 10,
            restSeconds: 60,
            muscleGroup: fly.muscleGroup
        )
        let completedBenchSet = SetLog(
            sessionID: session.id,
            sessionExerciseID: benchSnapshot.id,
            exerciseID: bench.id,
            setNumber: 1,
            targetWeight: 40,
            targetReps: 8,
            actualWeight: 40,
            actualReps: 8,
            isCompleted: true,
            completedAt: .now
        )
        let pendingFlySet = SetLog(
            sessionID: session.id,
            sessionExerciseID: flySnapshot.id,
            exerciseID: fly.id,
            setNumber: 1,
            targetWeight: 10,
            targetReps: 12,
            actualWeight: 10,
            actualReps: 12
        )
        [bench, fly].forEach(context.insert)
        context.insert(session)
        [benchSnapshot, flySnapshot].forEach(context.insert)
        [completedBenchSet, pendingFlySet].forEach(context.insert)
        try context.save()

        XCTAssertThrowsError(
            try WorkoutService.syncMenu(
                [
                    DailyPlanExerciseInput(
                        exerciseID: fly.id,
                        plannedSets: [WorkoutSetPlan(weight: 10, reps: 12)],
                        planPattern: .fixed,
                        restSeconds: 60
                    )
                ],
                to: session,
                in: context
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                WorkoutServiceError.cannotRemoveStartedExercise.localizedDescription
            )
        }
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SessionExercise>()).contains { $0.id == benchSnapshot.id }
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SetLog>()).contains { $0.id == completedBenchSet.id }
        )
    }

    func testRunningWorkoutMenuKeepsAtLeastOneExercise() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "保加利亚单腿蹲", muscleGroup: "腿部", equipment: "哑铃")
        let session = WorkoutSession(
            templateName: "腿部 · 当天菜单",
            plannedDate: .now,
            status: .inProgress
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 20,
            restSeconds: 90,
            muscleGroup: exercise.muscleGroup
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 20,
            targetReps: 8,
            actualWeight: 20,
            actualReps: 8
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        XCTAssertThrowsError(
            try WorkoutService.syncMenu([], to: session, in: context)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                WorkoutServiceError.emptyTemplate.localizedDescription
            )
        }
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SessionExercise>()).contains { $0.id == snapshot.id }
        )
        XCTAssertTrue(
            try context.fetch(FetchDescriptor<SetLog>()).contains { $0.id == log.id }
        )
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
