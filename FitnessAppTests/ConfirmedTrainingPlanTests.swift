import CryptoKit
import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class ConfirmedTrainingPlanTests: XCTestCase {
    private func alternatingInput(start: Date, zone: TimeZone) -> CoachWeekInput {
        let rows: [(String, String, String, ExerciseVolumeUnit)] = [
            ("史密斯卧推", "胸部", "史密斯机", .kilogram), ("上斜哑铃卧推", "胸部", "哑铃", .kilogram),
            ("器械坐姿推胸", "胸部", "器械", .kilogram), ("蝴蝶机夹胸", "胸部", "器械", .kilogram),
            ("器械肩推", "肩部", "器械", .kilogram), ("哑铃侧平举", "肩部", "哑铃", .kilogram),
            ("器械反向飞鸟", "肩部", "器械", .kilogram), ("绳索面拉", "肩部", "龙门架", .kilogram),
            ("高位下拉", "背部", "器械", .kilogram), ("坐姿划船", "背部", "器械", .kilogram),
            ("杠铃划船", "背部", "杠铃", .kilogram), ("直臂下压", "背部", "龙门架", .kilogram),
            ("绳索卷腹", "核心", "龙门架", .kilogram), ("绳索躯干旋转", "核心", "龙门架", .kilogram),
            ("地雷杆转体", "核心", "地雷杆", .kilogram), ("负重仰卧起坐", "核心", "负重片", .kilogram),
            ("深蹲", "腿部", "杠铃", .kilogram), ("罗马尼亚硬拉", "腿部", "杠铃", .kilogram),
            ("腿举", "腿部", "器械", .kilogram), ("腿屈伸", "腿部", "器械", .kilogram),
            ("坐姿腿弯举", "腿部", "器械", .kilogram), ("器械臀推", "臀部", "器械", .kilogram),
            ("保加利亚分腿蹲", "腿部", "哑铃", .kilogram), ("固定单车", "心肺", "单车", .second)
        ]
        let catalog = rows.map { name, muscle, equipment, unit in
            let role = CoachWeekService.roleEvidence(name: name, equipment: equipment, canonicalID: nil,
                                                     ruleMethod: CoachWeekService.alternatingMethodVersion)
            return CoachWeekCatalogItem(id: UUID(), name: name, muscle: muscle, equipment: equipment, unit: unit,
                approvedCanonicalID: nil, approvedName: nil, archived: false, roles: role.roles, roleSource: role.source)
        }
        var preference = TrainingPreferenceSnapshot.confirmed
        preference.splitStyle = .upperLowerAlternating
        preference.strengthDaysPerWeek = 3
        preference.maxFocusAreasPerSession = 3
        preference.jumpRopeSessionsPerWeek = 0
        preference.zone2SessionsPerWeek = 0
        preference.totalCardioSessionsPerWeek = 2
        let days = CoachWeekService.dateKeys(start: start, zone: zone)
        return CoachWeekInput(startDay: days[0], timeZone: zone.identifier, methodVersion: CoachWeekService.alternatingMethodVersion,
            personalRuleVersion: CoachWeekService.personalRuleVersion,
            preferences: days.map { CoachWeekPreference(localDay: $0, revisionID: UUID(), code: "test", snapshot: preference) },
            exception: nil, catalog: catalog, history: [], existing: [], recovery: [], unknowns: [], capturedLocalDay: days[0])
    }

    func testAlternatingWeeksUseNaturalWeekAnchorAndThreePlusTwo() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        for (date, expected) in [("2026-10-26", ["前链", "后链", "腿部综合"]),
                                 ("2026-11-02", ["胸肩", "背腹", "胸背肩综合"]),
                                 ("2026-11-09", ["前链", "后链", "腿部综合"]),
                                 ("2026-11-16", ["胸肩", "背腹", "胸背肩综合"])] {
            let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(date, timeZone: zone)!, zone: zone,
                                                       ruleMethod: CoachWeekService.alternatingMethodVersion)
            XCTAssertEqual(goals.filter { $0.kind == .strength }.map(\.focus), expected)
            XCTAssertEqual(goals.filter { $0.kind == .cardio }.count, 2)
            XCTAssertEqual(Array(goals.suffix(2)).map(\.kind), [.rest, .rest])
        }
    }

    func testAlternatingUpperWeekKeepsRoleQuotasFourSetsAndOneBoundDrop() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let start = TrainingLocalDate.date("2026-11-02", timeZone: zone)!
        let input = alternatingInput(start: start, zone: zone)
        var goals = CoachWeekService.defaultGoals(start: start, zone: zone, ruleMethod: CoachWeekService.alternatingMethodVersion)
        goals[3].focus = "跳绳"
        let draft = try CoachWeekService.generate(input: input, goals: goals)
        XCTAssertTrue(draft.weeklyShortfall?.isEmpty == true, "\(draft.weeklyShortfall ?? [])")
        let strengths = draft.days.filter { $0.kind == .strength }
        XCTAssertEqual(strengths.map { $0.movements.count }, [8, 7, 8])
        XCTAssertTrue(strengths.allSatisfy { $0.blockers.isEmpty }, "\(strengths.map(\.blockers))")
        XCTAssertTrue(strengths.allSatisfy { ($0.estimatedSeconds ?? 99999) <= 5400 })
        for day in strengths {
            XCTAssertEqual(day.movements.filter { $0.plannedDrop != nil }.count, 1)
            for movement in day.movements {
                XCTAssertEqual(movement.exercise.plannedSets.count, 4)
                XCTAssertTrue(movement.exercise.plannedSets.allSatisfy { $0.actualDefaultPolicy == .blank })
                XCTAssertEqual(movement.exercise.plannedSets.map(\.reps), [14, 12, 10, 8])
            }
        }
        var changed = strengths[0]
        let index = try XCTUnwrap(changed.movements.firstIndex { $0.plannedDrop != nil })
        changed.movements[index].exercise.plannedSets[3].id = UUID()
        XCTAssertTrue(CoachWeekService.revalidateWeek([changed], input: input)[0].blockers.contains { $0.contains("递减段") })
    }

    func testAlternatingLowerSpecialMovementNeedsIndividualReview() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let start = TrainingLocalDate.date("2026-11-09", timeZone: zone)!
        let input = alternatingInput(start: start, zone: zone)
        let goals = CoachWeekService.defaultGoals(start: start, zone: zone, ruleMethod: CoachWeekService.alternatingMethodVersion)
        let draft = try CoachWeekService.generate(input: input, goals: goals)
        let special = try XCTUnwrap(draft.days.flatMap(\.movements).first { $0.specialPrescriptionReviewed != nil })
        XCTAssertEqual(special.exercise.plannedSets.count, 4)
        XCTAssertNotEqual(special.exercise.plannedSets.map(\.reps), [14, 12, 10, 8])
        XCTAssertTrue(draft.days.flatMap(\.blockers).contains { $0.contains("特殊动作") })
    }

    func testAlternatingPreferenceAppendsOnceAndPreservesOlderSafetyRules() throws {
        let store = try container()
        let context = ModelContext(store)
        let previous = try TrainingPreferenceService.append(snapshot: .weekdayFocused,
            effectiveAt: FatLossCalendar.date(2026, 9, 8), reason: "测试旧偏好", in: context)
        let oldJSON = previous.snapshotJSON
        let first = try XCTUnwrap(TrainingPreferenceService.ensureAlternatingPreference(in: context))
        XCTAssertEqual(try TrainingPreferenceService.ensureAlternatingPreference(in: context)?.id, first.id)
        XCTAssertEqual(previous.snapshotJSON, oldJSON)
        let snapshot = try XCTUnwrap(first.snapshot)
        XCTAssertEqual(snapshot.splitStyle, .upperLowerAlternating)
        XCTAssertEqual(snapshot.strengthDaysPerWeek, 3)
        XCTAssertEqual(snapshot.totalCardioSessionsPerWeek, 2)
        XCTAssertTrue(snapshot.constraints.contains { $0.contains("早晨只有咖啡") })
        XCTAssertTrue(snapshot.constraints.contains { $0.contains("Notes 重量口径") })
        XCTAssertTrue(snapshot.constraints.contains { $0.contains("肌酐") })
        XCTAssertFalse(snapshot.constraints.contains { $0.contains("胸部单次 14–16") })
        XCTAssertNil(try TrainingPreferenceService.ensureProgramRevision(programID: nil, effectiveDate: .now, in: context))
    }

    func testAlternatingCardioCountsAnyTwoModes() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let start = TrainingLocalDate.date("2026-11-02", timeZone: zone)!
        let input = alternatingInput(start: start, zone: zone)
        var goals = CoachWeekService.defaultGoals(start: start, zone: zone, ruleMethod: CoachWeekService.alternatingMethodVersion)
        goals[1].focus = "Zone 2"
        let draft = try CoachWeekService.generate(input: input, goals: goals)
        XCTAssertEqual(draft.days.filter { $0.zone2 != nil }.count, 2)
        XCTAssertFalse(draft.weeklyShortfall?.contains { $0.contains("有氧") } == true)
    }

    func testAlternatingWeekRequiresConfirmationAndReadsBackWithoutDuplicates() throws {
        let store = try container()
        let context = ModelContext(store)
        _ = try TrainingPreferenceService.append(snapshot: .weekdayFocused, effectiveAt: FatLossCalendar.date(2026, 9, 8),
                                                  reason: "测试旧偏好", in: context)
        _ = try TrainingPreferenceService.ensureAlternatingPreference(in: context)
        let zone = TimeZone.current
        let start = try XCTUnwrap(TrainingLocalDate.date("2026-11-16", timeZone: zone))
        let fixture = alternatingInput(start: start, zone: zone)
        for item in fixture.catalog {
            context.insert(Exercise(name: item.name, muscleGroup: item.muscle, equipment: item.equipment, volumeUnit: item.unit))
        }
        try context.save()
        let input = try CoachWeekService.capture(start: start, exception: nil, ruleMethod: CoachWeekService.alternatingMethodVersion, in: context)
        let goals = CoachWeekService.defaultGoals(start: start, zone: zone, ruleMethod: CoachWeekService.alternatingMethodVersion)
        let draft = try CoachWeekService.generate(input: input, goals: goals)
        XCTAssertTrue(draft.days.allSatisfy { $0.blockers.isEmpty }, "\(draft.days.flatMap(\.blockers))")
        XCTAssertTrue(draft.weeklyShortfall?.isEmpty == true, "\(draft.weeklyShortfall ?? [])")
        try CoachWeekService.save(draft, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
        let request = try CoachWeekService.prepareConfirmation(draft, in: context)
        try CoachWeekService.validateConfirmation(request, rowID: request.id, rootID: draft.rootID)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 5)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 5)
        for member in request.members {
            let readback = try XCTUnwrap(ConfirmedDailyTrainingPlanService.readback(id: member.packet.id, in: ModelContext(store)))
            XCTAssertEqual(try ConfirmedTrainingPlanService.digest(readback.packet), member.packetSHA256)
            XCTAssertTrue(readback.packet.sourceMarkdown == member.packet.sourceMarkdown)
            XCTAssertTrue(readback.packet.exercises == member.packet.exercises)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 0)
    }
    func testWeekRoleEvidenceUsesExactSeedDefinitionsWithoutApprovingIdentity() {
        XCTAssertEqual(CoachWeekService.roleEvidence(name: "深蹲", equipment: "杠铃", canonicalID: nil).roles, ["膝主导"])
        XCTAssertEqual(CoachWeekService.roleEvidence(name: "高位下拉", equipment: "器械", canonicalID: nil).roles, ["垂直拉"])
        XCTAssertTrue(CoachWeekService.roleEvidence(name: "深蹲", equipment: "未知", canonicalID: nil).roles.isEmpty)
        XCTAssertTrue(CoachWeekService.roleEvidence(name: "Hip and glute machine", equipment: "器械", canonicalID: nil).roles.isEmpty)
        XCTAssertEqual(CoachWeekService.roleEvidence(name: "Hip and glute machine", equipment: "器械", canonicalID: nil, exerciseID: UUID(uuidString: "0fcd2a94-feb5-4433-abee-50750a249bb4")).roles, ["髋外展"])
        XCTAssertEqual(CoachWeekService.roleEvidence(name: "Abductor machine", equipment: "器械", canonicalID: nil, exerciseID: UUID(uuidString: "fc230b90-0405-492d-bf30-4c391c803578")).roles, ["髋内收"])
        XCTAssertTrue(CoachWeekService.roleEvidence(name: "Abductor machine", equipment: "器械", canonicalID: nil, exerciseID: UUID()).roles.isEmpty)
        XCTAssertTrue(CoachWeekService.roleEvidence(name: "深蹲", equipment: "杠铃", canonicalID: "barbell_hip_thrust").roles.isEmpty)
    }

    func testDefaultWeekKeepsWeekendRestAndReportsUnresolvedCardioShortfalls() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let start = TrainingLocalDate.date("2026-11-02", timeZone: zone)!
        let goals = CoachWeekService.defaultGoals(start: start, zone: zone)
        XCTAssertEqual(goals.count, 7)
        XCTAssertEqual(goals.filter { $0.kind == .strength }.count, 4)
        XCTAssertEqual(goals.filter { $0.kind == .cardio && $0.focus == "跳绳" }.count, 1)
        XCTAssertFalse(goals.contains { $0.kind == .cardio && $0.focus == "Zone 2" })
        XCTAssertEqual(Array(goals.suffix(2)).map(\.kind), [.rest, .rest])
        for index in 0..<5 {
            XCTAssertFalse(goals[index...index + 2].allSatisfy { $0.kind == .strength })
        }
        let input = CoachWeekInput(startDay: "2026-11-02", timeZone: zone.identifier,
            methodVersion: CoachWeekService.methodVersion, personalRuleVersion: CoachWeekService.personalRuleVersion,
            preferences: goals.map { CoachWeekPreference(localDay: $0.localDay, revisionID: nil, code: "fixture", snapshot: .confirmed) },
            exception: nil, catalog: [], history: [], existing: [], recovery: [], unknowns: ["隔离默认目标测试，不证明动作目录可用"], capturedLocalDay: "2026-11-02")
        let draft = try CoachWeekService.generate(input: input, goals: goals)
        XCTAssertTrue(draft.weeklyShortfall?.contains { $0.contains("跳绳候选缺1次") } == true)
        XCTAssertTrue(draft.weeklyShortfall?.contains { $0.contains("Zone 2候选缺1次") } == true)
        XCTAssertTrue(draft.days.allSatisfy { $0.kind != .strength || ($0.cardio == nil && $0.zone2 == nil) })
    }

    func testDefaultGoalsKeepWeekendRestWhenSelectedRangeStartsThursday() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date("2026-11-05", timeZone: zone)!, zone: zone)
        XCTAssertEqual(goals.map(\.focus), ["腿", "肩", "", "", "胸", "背", "跳绳"])
        XCTAssertEqual(goals.map(\.kind), [.strength, .strength, .rest, .rest, .strength, .strength, .cardio])
    }

    func testWeekInputDetectsPreservedPrescriptionAndRecoveryChanges() throws {
        let container = try container()
        let context = ModelContext(container)
        let start = FatLossCalendar.date(2026, 11, 2)
        let now = FatLossCalendar.date(2026, 10, 28)
        let set = WorkoutSetPlan(weight: 20, reps: 10)
        var exercise = ScheduledWorkoutExerciseSnapshot(exerciseID: UUID(), exerciseName: "腿举", muscleGroup: "腿部",
            equipment: "器械", exerciseNotes: "", referenceURL: "", volumeUnit: .kilogram, order: 0,
            targetSets: 1, minReps: 10, maxReps: 10, targetWeight: 20, restSeconds: 90,
            plannedSets: [set], planPattern: .fixed, patternSource: .exerciseOverride)
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "已有安排", plannedDate: start, planSnapshot: [exercise])
        let checkIn = DailyBodyCheckIn(date: FatLossCalendar.date(2026, 10, 27), conditionScore: 3,
                                       createdAt: now.addingTimeInterval(-3600))
        context.insert(schedule); context.insert(checkIn); try context.save()
        let original = try CoachWeekService.fingerprint(CoachWeekService.capture(start: start, exception: nil, now: now, in: context))
        exercise.plannedSets[0].weight = 25
        schedule.planSnapshot = [exercise]
        try context.save()
        let changedPlan = try CoachWeekService.fingerprint(CoachWeekService.capture(start: start, exception: nil, now: now, in: context))
        XCTAssertNotEqual(original, changedPlan)
        checkIn.conditionScore = 2
        checkIn.updatedAt = now.addingTimeInterval(-1800)
        try context.save()
        let changedRecovery = try CoachWeekService.fingerprint(CoachWeekService.capture(start: start, exception: nil, now: now, in: context))
        XCTAssertNotEqual(changedPlan, changedRecovery)
    }

    func testWeekCaptureIncludesAlreadyCompletedWorkoutWithinSelectedWeek() throws {
        let container = try container()
        let context = ModelContext(container)
        let start = FatLossCalendar.date(2026, 10, 26)
        let now = FatLossCalendar.date(2026, 10, 28).addingTimeInterval(12 * 3600)
        let exerciseID = UUID()
        let session = WorkoutSession(templateName: "已完成", plannedDate: FatLossCalendar.date(2026, 10, 27),
                                     completedAt: FatLossCalendar.date(2026, 10, 27).addingTimeInterval(36000), status: .completed)
        let exercise = SessionExercise(sessionID: session.id, exerciseID: exerciseID, exerciseName: "坐姿腿弯举",
            order: 0, targetSets: 1, minReps: 8, maxReps: 10, targetWeight: 30, restSeconds: 90, equipmentSnapshot: "器械")
        let log = SetLog(sessionID: session.id, sessionExerciseID: exercise.id, exerciseID: exerciseID, setNumber: 1,
                         targetWeight: 30, targetReps: 8, actualWeight: 30, actualReps: 8, rir: nil, isCompleted: true)
        context.insert(session); context.insert(exercise); context.insert(log); try context.save()
        let input = try CoachWeekService.capture(start: start, exception: nil, now: now, in: context)
        XCTAssertTrue(input.history.contains { $0.exerciseID == exerciseID && $0.actual.first?.rir == nil })
        XCTAssertTrue(input.existing.contains { $0.id == session.id && $0.source == "实际训练" })
    }

    func testBackWeekCandidateUsesARealPullRoleAsFourSetPrimary() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let start = TrainingLocalDate.date("2026-11-02", timeZone: zone)!
        let days = CoachWeekService.dateKeys(start: start, zone: zone)
        let definitions = [("高位下拉", "背部", "器械"), ("坐姿划船", "背部", "器械"),
                           ("杠铃划船", "背部", "杠铃"), ("引体向上", "背部", "自重"),
                           ("哑铃弯举", "手臂", "哑铃"), ("绳索下压", "手臂", "龙门架")]
        let catalog = definitions.map { name, muscle, equipment in
            let role = CoachWeekService.roleEvidence(name: name, equipment: equipment, canonicalID: nil)
            return CoachWeekCatalogItem(id: UUID(), name: name, muscle: muscle, equipment: equipment, unit: .kilogram,
                approvedCanonicalID: nil, approvedName: nil, archived: false, roles: role.roles, roleSource: role.source)
        }
        let preferences = days.map { CoachWeekPreference(localDay: $0, revisionID: UUID(), code: "test",
                                                         snapshot: .confirmed) }
        let input = CoachWeekInput(startDay: days[0], timeZone: zone.identifier, methodVersion: CoachWeekService.methodVersion,
            personalRuleVersion: CoachWeekService.personalRuleVersion, preferences: preferences, exception: nil,
            catalog: catalog, history: [], existing: [], recovery: [], unknowns: [], capturedLocalDay: days[0])
        let goal = CoachWeekGoal(localDay: days[0], kind: .strength, focus: "背", reason: "测试")
        let draft = try CoachWeekService.generate(input: input, goals: [goal])
        let day = try XCTUnwrap(draft.days.first)
        let primary = try XCTUnwrap(day.movements.first { $0.exercise.plannedSets.count == 4 })
        XCTAssertTrue(primary.roles.contains("垂直拉") || primary.roles.contains("水平拉"))
        XCTAssertEqual(day.movements.count, 6)
        XCTAssertFalse(day.blockers.contains { $0.contains("主肌群不足") })
    }

    func testPreservedStrengthContributesToThreeConsecutiveDayConflict() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let start = TrainingLocalDate.date("2026-11-02", timeZone: zone)!
        let dates = CoachWeekService.dateKeys(start: start, zone: zone)
        let id = UUID()
        let role = CoachWeekService.roleEvidence(name: "深蹲", equipment: "杠铃", canonicalID: nil)
        let item = CoachWeekCatalogItem(id: id, name: "深蹲", muscle: "腿部", equipment: "杠铃", unit: .kilogram,
            approvedCanonicalID: nil, approvedName: nil, archived: false, roles: role.roles, roleSource: role.source)
        let preferences = dates.map { CoachWeekPreference(localDay: $0, revisionID: UUID(), code: "test", snapshot: .confirmed) }
        let frozen = CoachWeekFrozenExercise(exerciseID: id, name: item.name, muscle: item.muscle,
            equipment: item.equipment, roles: role.roles, plannedSets: [WorkoutSetPlan(weight: 0, reps: 8)])
        let preserved = CoachWeekExisting(id: UUID(), localDay: dates[2], title: "已有力量", status: "planned", source: "日程",
                                          contentDigest: "test", exerciseIDs: [id], frozenExercises: [frozen])
        let input = CoachWeekInput(startDay: dates[0], timeZone: zone.identifier, methodVersion: CoachWeekService.methodVersion,
            personalRuleVersion: CoachWeekService.personalRuleVersion, preferences: preferences, exception: nil,
            catalog: [item], history: [], existing: [preserved], recovery: [], unknowns: [], capturedLocalDay: dates[0])
        let goals = dates.enumerated().map { index, day in
            CoachWeekGoal(localDay: day, kind: index >= 3 && index <= 4 ? .strength : .rest, focus: "腿", reason: "测试")
        }
        let result = try CoachWeekService.generate(input: input, goals: goals)
        XCTAssertEqual(result.days[2].kind, .preserved)
        XCTAssertTrue(result.days[4].blockers.contains { $0.contains("连续三天力量") })
    }

    func testDefaultWeekDefersUnplaceableGoalsWithoutWeekendTrainingOrDuplicateFocus() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let start = TrainingLocalDate.date("2026-11-02", timeZone: zone)!
        let dates = CoachWeekService.dateKeys(start: start, zone: zone)
        let id = UUID()
        let role = CoachWeekService.roleEvidence(name: "深蹲", equipment: "杠铃", canonicalID: nil)
        let item = CoachWeekCatalogItem(id: id, name: "深蹲", muscle: "腿部", equipment: "杠铃", unit: .kilogram,
            approvedCanonicalID: nil, approvedName: nil, archived: false, roles: role.roles, roleSource: role.source)
        let preferences = dates.map { CoachWeekPreference(localDay: $0, revisionID: UUID(), code: "test", snapshot: .confirmed) }
        let frozen = CoachWeekFrozenExercise(exerciseID: id, name: item.name, muscle: item.muscle,
            equipment: item.equipment, roles: role.roles, plannedSets: [WorkoutSetPlan(weight: 0, reps: 8)])
        let preserved = CoachWeekExisting(id: UUID(), localDay: dates[2], title: "已有力量", status: "planned", source: "日程",
                                          contentDigest: "test", exerciseIDs: [id], frozenExercises: [frozen])
        let input = CoachWeekInput(startDay: dates[0], timeZone: zone.identifier, methodVersion: CoachWeekService.methodVersion,
            personalRuleVersion: CoachWeekService.personalRuleVersion, preferences: preferences, exception: nil,
            catalog: [item], history: [], existing: [preserved], recovery: [], unknowns: [], capturedLocalDay: dates[0])
        let result = try CoachWeekService.generate(input: input, goals: CoachWeekService.defaultGoals(start: start, zone: zone))
        XCTAssertEqual(result.days[2].existing, [preserved])
        XCTAssertEqual(result.days.filter { $0.kind == .strength }.count, 2)
        XCTAssertEqual(result.days.filter { $0.cardio != nil }.count, 1)
        XCTAssertFalse(result.days.contains { $0.zone2 != nil })
        XCTAssertEqual(Array(result.days.suffix(2)).map(\.kind), [.rest, .rest])
        XCTAssertTrue(result.weeklyShortfall?.contains { $0.contains("力量候选缺1次") } == true)
        XCTAssertTrue(result.weeklyShortfall?.contains { $0.contains("跳绳候选缺1次") } == true)
        XCTAssertTrue(result.weeklyShortfall?.contains { $0.contains("Zone 2候选缺1次") } == true)
        let newStrengthFocus = result.days.filter { $0.kind == .strength }.map(\.focus)
        XCTAssertFalse(newStrengthFocus.contains("腿"), "周三冻结腿部任务不能再消耗一个腿部默认槽位")
        XCTAssertEqual(Set(newStrengthFocus).count, newStrengthFocus.count)
        XCTAssertFalse(result.days.contains { $0.blockers.contains { $0.contains("连续三天力量") } })
        XCTAssertTrue(CoachWeekService.requiresAnkleAttachment(name: "Cable Glute Kickback", equipment: "龙门架"))
        XCTAssertFalse(CoachWeekService.requiresAnkleAttachment(name: "Hip and glute machine", equipment: "器械"))
    }

    func testCoachWeekAtomicCommitAndRepeatedRequest() throws {
        enum Injected: Error { case failure }
        let container = try container()
        let context = ModelContext(container)
        _ = try FatLossService.createProgram(in: context)
        var preference = try XCTUnwrap(TrainingPreferenceService.current(in: context)?.snapshot)
        preference.revisionCode = "TP-WEEK-ATOMIC"
        _ = try TrainingPreferenceService.append(snapshot: preference, effectiveAt: FatLossCalendar.date(2026, 10, 1),
                                                  reason: "隔离测试", in: context)
        let definitions = [("杠铃卧推", "胸部", "杠铃"), ("上斜哑铃卧推", "胸部", "哑铃"),
                           ("器械坐姿推胸", "胸部", "器械"), ("蝴蝶机夹胸", "胸部", "器械"),
                           ("坐姿推举", "肩部", "哑铃"), ("面拉", "肩部", "龙门架")]
        let exercises = definitions.map { Exercise(name: $0.0, muscleGroup: $0.1, equipment: $0.2) }
        let bike = Exercise(name: "测试单车", muscleGroup: "心肺", equipment: "单车")
        bike.volumeUnit = .second
        exercises.forEach(context.insert); context.insert(bike); try context.save()
        let start = FatLossCalendar.date(2026, 11, 2)
        let baseline = try CoachWeekService.capture(start: start, exception: nil, in: context)
        let dates = baseline.preferences.map(\.localDay)
        let goals = dates.enumerated().map { index, day in
            CoachWeekGoal(localDay: day, kind: index == 0 ? .strength : index == 1 ? .cardio : .rest,
                focus: index == 0 ? "胸" : index == 1 ? "跳绳" : "", reason: "本人完整确认事务测试例外周")
        }
        let exception = CoachWeekException(id: UUID(), startDay: dates[0], endDay: dates[6],
            reason: "本人明确确认首日力量加独立Zone2、次日跳绳、其余五日休息；不是默认同日分课",
            goals: goals, confirmation: "隔离测试本人完整确认七日例外及首日独立Zone2")
        let coreException = CoachWeekCoreException(startDay: dates[0], endDay: dates[6], reason: "隔离测试本人确认腹部例外", confirmation: CoachWeekService.coreExceptionConsent, goals: goals)
        let input = try CoachWeekService.capture(start: start, exception: exception, coreException: coreException, in: context)
        let moves = exercises.enumerated().map { index, row -> CoachWeekMovement in
            let sets = (0..<(index == 0 ? 4 : 3)).map { _ in
                WorkoutSetPlan(weight: 0, reps: 8, weightSide: .unknown, repsSide: .unknown,
                    actualDefaultPolicy: .blank, prescription: WorkoutSetPrescription(label: "工作组", repsLower: 8, repsUpper: 10,
                        rirLower: 2, rirUpper: 3, restLowerSeconds: 90, restUpperSeconds: 120))
            }
            let plan = ConfirmedDailyPlanExercise(catalogExerciseID: row.id, catalogName: row.name, equipment: row.equipment,
                volumeUnit: .kilogram, displayName: row.name, loadGuidance: "热身校准", notes: "测试", plannedSets: sets)
            return CoachWeekMovement(exercise: plan, roles: CoachWeekService.roleEvidence(name: row.name, equipment: row.equipment, canonicalID: nil).roles,
                                     roleSource: "测试", reason: "测试", evidence: [], unknowns: [], unilateral: false)
        }
        var days = dates.map { CoachWeekDay(localDay: $0, kind: .rest, title: "休息", focus: "", movements: [], cardio: nil,
                                             estimatedSeconds: 0, rationale: [], blockers: [], existing: []) }
        days[0] = CoachWeekDay(localDay: dates[0], kind: .strength, title: "测试力量", focus: "胸", movements: moves,
                               cardio: nil, estimatedSeconds: 3600, rationale: ["测试"], blockers: [], existing: [])
        days[1] = CoachWeekDay(localDay: dates[1], kind: .cardio, title: "跳绳", focus: "跳绳", movements: [],
            cardio: JumpRopeMenuPlan(targetCount: nil, activeSeconds: 450, elapsedSeconds: 1800, notes: "测试"),
            estimatedSeconds: 1800, rationale: ["测试"], blockers: [], existing: [])
        days[0].zone2 = CoachZone2Plan(mode: bike.name, durationSeconds: 1800, guidance: "轻松", exerciseID: bike.id)
        let checkedDays = CoachWeekService.revalidateWeek(days, input: input)
        XCTAssertTrue(checkedDays.allSatisfy { $0.blockers.isEmpty }, checkedDays.flatMap(\.blockers).joined(separator: "；"))
        XCTAssertTrue(CoachWeekService.weeklyShortfalls(checkedDays, input: input).isEmpty)
        let draft = CoachWeekDraft(id: UUID(), rootID: UUID(), revision: 1, createdAt: .now,
            sourceFingerprint: try CoachWeekService.fingerprint(input), input: input, days: checkedDays, edits: [], ruleCandidates: [],
            weeklyShortfall: CoachWeekService.weeklyShortfalls(checkedDays, input: input))
        try CoachWeekService.save(draft, in: context)
        let request = try CoachWeekService.prepareConfirmation(draft, in: context)
        let before = try context.fetch(FetchDescriptor<ScheduledWorkout>()).count
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context, commit: { _ in throw Injected.failure }))
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, before)
        XCTAssertFalse(try context.fetch(FetchDescriptor<TrainingCoachRecord>()).contains { $0.id == request.id })
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, before + 3)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).count, before + 3)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        XCTAssertNotNil(schedules.first { $0.id == request.ropes[0].id }?.jumpRopePlan)
        let bikeSchedule = try XCTUnwrap(schedules.first { $0.id == request.members.first(where: { $0.packet.exercises.count == 1 && $0.packet.exercises[0].catalogExerciseID == bike.id })?.packet.id })
        XCTAssertEqual(CardioWorkoutPresentation.plan(bikeSchedule)?.durationSeconds, 1800)
    }

    func testWeekLoadDistinguishesActualRIRFromManualReference() throws {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let start = TrainingLocalDate.date("2026-11-02", timeZone: zone)!
        let dates = CoachWeekService.dateKeys(start: start, zone: zone)
        let id = UUID()
        let role = CoachWeekService.roleEvidence(name: "深蹲", equipment: "杠铃", canonicalID: nil)
        let item = CoachWeekCatalogItem(id: id, name: "深蹲", muscle: "腿部", equipment: "杠铃", unit: .kilogram,
            approvedCanonicalID: nil, approvedName: nil, archived: false, roles: role.roles, roleSource: role.source)
        let preferences = dates.map { CoachWeekPreference(localDay: $0, revisionID: UUID(), code: "test", snapshot: .confirmed) }
        let plans = (0..<4).map { _ in WorkoutSetPlan(weight: 30, reps: 8, weightSide: .single, repsSide: .bilateral) }
        func actual(_ rir: Int?) -> CoachWeekActual {
            let sets = (0..<4).map { index in CoachActualSet(id: UUID(), weight: Double(30 + index * 5), reps: 8, rir: rir,
                weightSide: .single, repsSide: .bilateral, completed: true, warmup: false) }
            return CoachWeekActual(id: UUID(), sessionID: UUID(), localDay: "2026-10-20", exerciseID: id, name: "深蹲",
                equipment: "杠铃", unit: .kilogram, plannedSets: plans, actual: sets, feedback: "",
                loadConvention: "每侧片重", classificationKnown: true)
        }
        func movement(_ source: CoachWeekActual) throws -> CoachWeekMovement {
            let input = CoachWeekInput(startDay: dates[0], timeZone: zone.identifier, methodVersion: CoachWeekService.methodVersion,
                personalRuleVersion: CoachWeekService.personalRuleVersion, preferences: preferences, exception: nil,
                catalog: [item], history: [source], existing: [], recovery: [], unknowns: [], capturedLocalDay: dates[0])
            let goal = CoachWeekGoal(localDay: dates[0], kind: .strength, focus: "腿", reason: "测试")
            return try XCTUnwrap(CoachWeekService.generate(input: input, goals: [goal]).days[0].movements.first)
        }
        let qualified = try movement(actual(3))
        XCTAssertEqual(qualified.exercise.plannedSets.map(\.weight), [30, 35, 40, 45])
        XCTAssertTrue(qualified.exercise.loadGuidance.contains("近42天"))
        let reference = try movement(actual(nil))
        XCTAssertEqual(reference.exercise.plannedSets.map(\.weight), [30, 35, 40, 45])
        XCTAssertTrue(reference.exercise.loadGuidance.contains("人工参考候选"))
        XCTAssertTrue(reference.unknowns.contains { $0.contains("实际RIR") })
        var estimated = actual(nil)
        estimated.supplementaryLastRIR = 3
        let estimatedReference = try movement(estimated)
        XCTAssertTrue(estimatedReference.exercise.loadGuidance.contains("人工参考候选"))
        XCTAssertEqual(estimatedReference.evidence.filter { $0.contains("仅绑定该末条") }.count, 1)
        let mismatch = CoachWeekActual(id: UUID(), sessionID: UUID(), localDay: "2026-10-20", exerciseID: id, name: "深蹲",
            equipment: "另一台", unit: .kilogram, plannedSets: plans, actual: actual(3).actual, feedback: "",
            loadConvention: "每侧片重", classificationKnown: true)
        let unknown = try movement(mismatch)
        XCTAssertTrue(unknown.exercise.plannedSets.allSatisfy { $0.weight == 0 })
    }

    func testCardioSummaryShowsCyclingDurationRangeWithoutInventingRounds() {
        let cycling = ProgramCardioDraft(code: "CUT-RESTORE-20261012-CYCLE", title: "轻松单车/椭圆机",
            weekday: 4, timing: "独立恢复时段", activeSeconds: 1200, elapsedSeconds: nil,
            intervals: "20–30分钟，能轻松说完整句子", guidance: "疲劳明显则休息",
            activeSecondsUpper: 1800)
        XCTAssertEqual(TrainingPlanPresentation.cardioVolumeSummary(cycling), "20–30 分钟")

        let rope = ProgramCardioDraft(code: "CUT-RESTORE-20261012-ROPE1", title: "轻松跳绳1",
            weekday: 2, timing: "独立时段", activeSeconds: 360, elapsedSeconds: 720,
            intervals: "8轮，每轮45秒跳绳／45秒步行休息", guidance: "不适就停",
            activeSecondsUpper: 360)
        XCTAssertEqual(TrainingPlanPresentation.cardioVolumeSummary(rope), "8 轮 / 约 12 分钟")
    }

    private func container() throws -> ModelContainer {
        let schema = Schema([Exercise.self, WorkoutTemplate.self, TemplateExercise.self, ScheduledWorkout.self,
                             WorkoutSession.self, SessionExercise.self, SetLog.self, NutritionTarget.self, MealEntry.self,
                             BodyMeasurement.self, DailyBodyCheckIn.self, HydrationEntry.self, JumpRopeEntry.self, SedentarySession.self,
                             FatLossProgram.self, ProgramTargetRevision.self, RecipeVersion.self, PlannedMeal.self,
                             ProgramDailyLog.self, ProgramHealthRecord.self, ProgramWeeklyReview.self, ProgramWorkoutLink.self,
                             TrainingPreferenceRevision.self, TrainingProgramRevision.self, TrainingCoachRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    private func packet(in context: ModelContext) throws -> ConfirmedTrainingPlanPacket {
        let program = try FatLossService.createProgram(in: context)
        var preference = try XCTUnwrap(TrainingPreferenceService.current(in: context)?.snapshot)
        preference.revisionCode = "TP-IMPORT-TEST"
        preference.strengthDaysPerWeek = 1
        _ = try TrainingPreferenceService.append(snapshot: preference, effectiveAt: FatLossCalendar.date(2026, 10, 1),
                                                  reason: "隔离测试偏好", in: context)
        let exercise = Exercise(name: "测试推胸", muscleGroup: "胸部", equipment: "测试器械")
        context.insert(exercise)
        try context.save()
        let top = WorkoutSetPlan(weight: 0, reps: 8, weightSide: .unknown, actualDefaultPolicy: .blank,
                                 prescription: WorkoutSetPrescription(label: "顶组", repsLower: 8, repsUpper: 10,
                                     rirLower: 3, rirUpper: 3, restLowerSeconds: 180, restUpperSeconds: 180))
        let backoff = WorkoutSetPlan(weight: 0, reps: 10, weightSide: .unknown, actualDefaultPolicy: .blank,
                                     prescription: WorkoutSetPrescription(label: "回退组", repsLower: 10, repsUpper: 12,
                                         rirLower: 2, rirUpper: 3, restLowerSeconds: 150, restUpperSeconds: 180))
        let draft = ProgramExerciseDraft(name: exercise.name, muscleGroup: exercise.muscleGroup, equipment: exercise.equipment,
            sets: 2, repsLower: 8, repsUpper: 12, restSeconds: 180, note: "重量留空；不力竭；疼痛则停止",
            catalogExerciseID: exercise.id, plannedSets: [top, backoff])
        let snapshot = TrainingProgramSnapshot(code: "IMPORT-TEST-R1", title: "已确认一周",
            preferenceRevisionCode: preference.revisionCode,
            strengthWorkouts: [ProgramWorkoutDraft(code: "TEST_A", title: "胸部 A", weekday: 2,
                exercises: [draft], guidance: "热身不计工作组；器械不可用时停止，不猜替代动作")],
            cardioWorkouts: [], progressionRule: "本周不自动续排", lowEnergyRule: "状态不好则减量")
        let source = "# 已确认一周\n顶组 1×8–10 RIR3；回退 1×10–12 RIR2–3；重量留空。"
        return ConfirmedTrainingPlanPacket(version: 1, programID: program.id,
            startLocalDay: "2026-10-12", endLocalDay: "2026-10-18", timeZoneIdentifier: "Asia/Shanghai",
            confirmedAt: FatLossCalendar.date(2026, 10, 10), confirmationReference: "REQ-IMPORT-TEST",
            sourceMarkdown: source, sourceSHA256: SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined(),
            snapshot: snapshot)
    }

    // Build the new wire format through the public decoder. Before support exists,
    // unknown keys are ignored and the unchanged preview rejects all four IDs.
    private func packetWithConfirmedNewCatalog(in context: ModelContext) throws -> ConfirmedTrainingPlanPacket {
        var input = try packet(in: context)
        let original = input.snapshot.strengthWorkouts[0].exercises[0]
        let names = ["MTS器械下斜推胸", "胸托T-Bar划船", "哈克深蹲", "器械臀推"]
        let equipment = ["MTS下斜推胸机", "胸托T-Bar划船机", "哈克深蹲机", "器械臀推机"]
        let muscles = ["胸部", "背部", "腿部", "臀部"]
        var definitions: [[String: Any]] = []
        input.snapshot.strengthWorkouts[0].exercises = names.indices.map { index in
            var draft = original
            let id = UUID()
            draft.name = names[index]
            draft.catalogName = names[index]
            draft.catalogExerciseID = id
            draft.muscleGroup = muscles[index]
            draft.equipment = equipment[index]
            definitions.append(["id": id.uuidString, "name": draft.name, "muscleGroup": draft.muscleGroup,
                                "equipment": draft.equipment, "volumeUnitRaw": "kilogram", "defaultRestSeconds": draft.restSeconds])
            return draft
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(input)) as? [String: Any])
        object["catalogAdditions"] = definitions
        object["catalogConfirmationReference"] = "ISOLATED-OWNER-CONFIRMED: four exact machines and kg"
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConfirmedTrainingPlanPacket.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testExplicitCatalogDefinitionsPreviewThenSaveTogetherAndRetryCreatesNoDuplicates() throws {
        let store = try container(), context = store.mainContext
        let input = try packetWithConfirmedNewCatalog(in: context)
        let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
        XCTAssertTrue(preview.conflicts.isEmpty, "本人确认的精确动作应可显式预览，不借相似UUID")
        XCTAssertEqual(preview.newExerciseCount, 4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1, "预览不创建动作")
        XCTAssertFalse(context.hasChanges)
        let first = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(first.newScheduleCount, 1)
        XCTAssertEqual(first.newExerciseCount, 4)
        let catalog = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(catalog.count, 5)
        for draft in input.snapshot.strengthWorkouts[0].exercises {
            let row = try XCTUnwrap(catalog.first { $0.id == draft.catalogExerciseID })
            XCTAssertEqual(row.name, draft.name)
            XCTAssertEqual(row.equipment, draft.equipment)
            XCTAssertEqual(row.volumeUnit, .kilogram)
            XCTAssertFalse(row.isArchived)
        }
        let stored = try XCTUnwrap(ConfirmedTrainingPlanService.readback(code: input.snapshot.code, in: context))
        XCTAssertEqual(stored, first.readback, "新定义必须能完整来源回读，而不破坏包指纹")
        XCTAssertTrue(stored.schedules.flatMap(\.exercises).flatMap(\.plannedSets).allSatisfy { $0.actualDefaultPolicy == .blank })
        let repeated = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(repeated.newScheduleCount, 0)
        XCTAssertEqual(repeated.newExerciseCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    func testFailedCommitRollsBackNewCatalogAndTheWholeWeek() throws {
        let store = try container(), context = store.mainContext
        let input = try packetWithConfirmedNewCatalog(in: context)
        let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
        var reachedCommit = false
        XCTAssertThrowsError(try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context, commit: { _ in
            reachedCommit = true
            throw CocoaError(.fileWriteNoPermission)
        }))
        XCTAssertTrue(reachedCommit, "应实测保存阶段失败，而不是把身份预检拒绝冒充回滚")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testExplicitNewIdentityDoesNotRestoreOrBorrowConflictingName() throws {
        for archived in [false, true] {
            let store = try container(), context = store.mainContext
            let input = try packetWithConfirmedNewCatalog(in: context)
            let draft = input.snapshot.strengthWorkouts[0].exercises[0]
            let collision = Exercise(name: draft.name, muscleGroup: draft.muscleGroup,
                                     equipment: archived ? draft.equipment : "不同的下斜器械")
            collision.isArchived = archived
            context.insert(collision)
            try context.save()
            let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
            XCTAssertFalse(preview.conflicts.isEmpty)
            XCTAssertThrowsError(try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context))
            XCTAssertEqual(collision.isArchived, archived)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 2)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testNewDefinitionsWithoutEquipmentConfirmationAreRejectedBeforeWrite() throws {
        let store = try container(), context = store.mainContext
        let input = try packetWithConfirmedNewCatalog(in: context)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(input)) as? [String: Any])
        object["catalogConfirmationReference"] = nil
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let unconfirmed = try decoder.decode(ConfirmedTrainingPlanPacket.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try ConfirmedTrainingPlanService.preview(unconfirmed, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
    }

    func testPublicBackupRestoresExplicitCatalogAndBoundWeekWithoutDuplicateCreation() throws {
        let store = try container(), context = store.mainContext
        let input = try packetWithConfirmedNewCatalog(in: context)
        let result = try ConfirmedTrainingPlanService.apply(
            expectedPreview: ConfirmedTrainingPlanService.preview(input, in: context), in: context)
        let backup = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backup) }
        let data = try DataExportService.loadBackupData(from: backup)
        let restoredStore = try container(), restored = restoredStore.mainContext
        _ = try DataExportService.importBackup(data, into: restored)
        XCTAssertEqual(try ConfirmedTrainingPlanService.readback(code: input.snapshot.code, in: restored), result.readback)
        XCTAssertEqual(try restored.fetchCount(FetchDescriptor<Exercise>()), 5)
        XCTAssertEqual(try DataExportService.importBackup(data, into: restored).imported, 0)
        XCTAssertEqual(try ConfirmedTrainingPlanService.apply(
            expectedPreview: ConfirmedTrainingPlanService.preview(input, in: restored), in: restored).newScheduleCount, 0)
    }

    func testPreviewRetainsCompletePerSetTargetsAndDoesNotActivateWeek() throws {
        let store = try container(), context = store.mainContext
        let input = try packet(in: context)
        let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
        XCTAssertTrue(preview.conflicts.isEmpty)
        XCTAssertEqual(preview.newScheduleCount, 1)
        XCTAssertEqual(preview.scheduledDays, ["2026-10-12"])
        XCTAssertEqual(preview.packet.sourceMarkdown, input.sourceMarkdown)
        let plans = try XCTUnwrap(preview.packet.snapshot.strengthWorkouts.first?.exercises.first?.plannedSets)
        XCTAssertEqual(plans.map { $0.prescription?.label }, ["顶组", "回退组"])
        XCTAssertEqual(plans.map { $0.prescription?.repsUpper }, [10, 12])
        XCTAssertEqual(plans.map { $0.prescription?.rirLower }, [3, 2])
        XCTAssertTrue(plans.allSatisfy { $0.actualDefaultPolicy == .blank })
        XCTAssertNil(try ConfirmedTrainingPlanService.readback(code: "IMPORT-TEST-R1", in: context))
        XCTAssertFalse(context.hasChanges, "预览不应制造未保存的写入")
    }

    func testReadbackRejectsChangedConfirmedContentOrMissingIntegritySeal() throws {
        for removesSeal in [false, true] {
            let store = try container(), context = store.mainContext
            let input = try packet(in: context)
            let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
            let applied = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
            let revision = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingProgramRevision>())
                .first { $0.id == applied.readback.revisionID })
            var changed = try XCTUnwrap(revision.snapshot)
            if removesSeal { changed.confirmedImport?.scheduleIntegritySHA256 = nil }
            else { changed.strengthWorkouts[0].guidance = "不再是本人确认的恢复规则" }
            revision.snapshotJSON = String(decoding: try JSONEncoder().encode(changed), as: UTF8.self)
            try context.save()
            XCTAssertThrowsError(try ConfirmedTrainingPlanService.readback(code: input.snapshot.code, in: context))
            XCTAssertThrowsError(try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
        }
    }

    func testStalePreviewCannotImportAfterProgramClosesOrReferencedCatalogSourceChanges() throws {
        for closesProgram in [true, false] {
            let store = try container(), context = store.mainContext
            let input = try packet(in: context)
            let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
            if closesProgram {
                try XCTUnwrap(context.fetch(FetchDescriptor<FatLossProgram>()).first { $0.id == input.programID })
                    .statusRaw = "closed"
            } else {
                try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.id == input.snapshot.strengthWorkouts[0].exercises[0].catalogExerciseID })
                    .referenceURL = "https://example.com/changed-after-preview"
            }
            try context.save()
            XCTAssertThrowsError(try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        }
    }

    func testUnknownIdentityIncompatibleUnitAndChangedOriginalSourceRemainUnwritten() throws {
        for variant in 0..<3 {
            let store = try container(), context = store.mainContext
            var input = try packet(in: context)
            if variant == 0 { input.snapshot.strengthWorkouts[0].exercises[0].catalogExerciseID = UUID() }
            if variant == 1 { input.snapshot.strengthWorkouts[0].exercises[0].volumeUnitRaw = ExerciseVolumeUnit.second.rawValue }
            if variant == 2 { input.sourceMarkdown += "\n未确认变更" }
            if variant == 2 {
                XCTAssertThrowsError(try ConfirmedTrainingPlanService.preview(input, in: context))
            } else {
                let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
                XCTAssertFalse(preview.conflicts.isEmpty)
                XCTAssertThrowsError(try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context))
            }
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testPlanKeepsConfirmedLabelWhileReferencingExactExistingRawCatalogIdentity() throws {
        let store = try container(), context = store.mainContext
        var input = try packet(in: context)
        input.snapshot.strengthWorkouts[0].exercises[0].catalogName = "测试推胸"
        input.snapshot.strengthWorkouts[0].exercises[0].name = "已确认推胸名称"
        let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
        XCTAssertTrue(preview.conflicts.isEmpty)
        let result = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(result.readback.schedules.first?.exercises.first?.exerciseName, "已确认推胸名称")
        XCTAssertEqual(result.readback.schedules.first?.exercises.first?.exerciseID,
            input.snapshot.strengthWorkouts[0].exercises[0].catalogExerciseID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Exercise>()).filter { $0.name == "测试推胸" }.count, 1)
    }

    func testPairedExchangePreviewsAppliesRetriesAndReadsExactCompletePlanThroughApp() throws {
        try checkPairedExchange(withNewCatalog: false)
    }

    func testPairedExchangeKeepsExplicitCatalogDefinitionsThroughPreviewApplyAndReadback() throws {
        try checkPairedExchange(withNewCatalog: true)
    }

    private func checkPairedExchange(withNewCatalog: Bool) throws {
        let store = try container(), context = store.mainContext
        let input = try withNewCatalog ? packetWithConfirmedNewCatalog(in: context) : packet(in: context)
        let documents = URL.documentsDirectory
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var ownedFiles: [URL] = []
        defer { for file in ownedFiles { try? FileManager.default.removeItem(at: file) } }
        func exchange<T: Encodable>(_ operation: MealExchangeOperation, _ value: T) throws -> URL {
            let identity = UUID()
            let prefix = "training-test-\(identity.uuidString.lowercased())"
            let payloadName = prefix + "-payload.json"
            let requestName = prefix + "-request.json"
            let data = try encoder.encode(value)
            let payloadFile = documents.appendingPathComponent(payloadName)
            let requestFile = documents.appendingPathComponent(requestName)
            let output = documents.appendingPathComponent("MealExchange").appendingPathComponent(identity.uuidString.lowercased())
            ownedFiles += [payloadFile, requestFile, output]
            try data.write(to: payloadFile, options: .atomic)
            let request = MealExchangeRequest(version: 1, id: identity, operation: operation,
                startLocalDay: nil, endLocalDay: nil, payloadFileName: payloadName,
                approvedSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            try encoder.encode(request).write(to: requestFile, options: .atomic)
            XCTAssertNotNil(try MealExchangeService.processLaunchRequest(arguments: ["--meal-exchange-request=" + requestName], in: context))
            let receipt = try decoder.decode(MealExchangeReceipt.self, from: Data(contentsOf: output.appendingPathComponent("receipt.json")))
            XCTAssertEqual(receipt.requestID, identity)
            XCTAssertEqual(receipt.status, "completed")
            return output
        }
        let previewOutput = try exchange(.previewTrainingPlan, input)
        let preview = try decoder.decode(ConfirmedTrainingPlanPreview.self,
            from: Data(contentsOf: previewOutput.appendingPathComponent("training-preview.json")))
        XCTAssertEqual(preview.packet, input)
        XCTAssertEqual(preview.newExerciseCount, withNewCatalog ? 4 : 0)
        XCTAssertNil(try ConfirmedTrainingPlanService.readback(code: input.snapshot.code, in: context))
        let appliedOutput = try exchange(.applyTrainingPlan, preview)
        let applied = try decoder.decode(ConfirmedTrainingPlanApplyResult.self,
            from: Data(contentsOf: appliedOutput.appendingPathComponent("training-result.json")))
        XCTAssertEqual(applied.newScheduleCount, 1)
        XCTAssertEqual(applied.newExerciseCount, withNewCatalog ? 4 : 0)
        let repeatedOutput = try exchange(.applyTrainingPlan, preview)
        let repeated = try decoder.decode(ConfirmedTrainingPlanApplyResult.self,
            from: Data(contentsOf: repeatedOutput.appendingPathComponent("training-result.json")))
        XCTAssertEqual(repeated.newScheduleCount, 0)
        XCTAssertEqual(repeated.newExerciseCount, 0)
        XCTAssertEqual(repeated.readback.scheduleIDs, applied.readback.scheduleIDs)
        let readOutput = try exchange(.readTrainingPlan,
            ConfirmedTrainingPlanReadRequest(code: input.snapshot.code, packetSHA256: preview.packetSHA256))
        let readback = try decoder.decode(ConfirmedTrainingPlanReadback.self,
            from: Data(contentsOf: readOutput.appendingPathComponent("training-readback.json")))
        XCTAssertEqual(readback, applied.readback)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    func testUserCanApplyOneCompleteWeekAndRepeatAddsNothing() throws {
        let store = try container(), context = store.mainContext
        let input = try packet(in: context)
        let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
        let first = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(first.newScheduleCount, 1)
        let stored = try XCTUnwrap(ConfirmedTrainingPlanService.readback(code: "IMPORT-TEST-R1", in: context))
        XCTAssertEqual(stored.snapshot.confirmedImport?.sourceMarkdown, input.sourceMarkdown)
        XCTAssertEqual(stored.snapshot.confirmedImport?.sourceSHA256, input.sourceSHA256)
        XCTAssertEqual(stored.schedules.map(\.localDay), ["2026-10-12"])
        XCTAssertEqual(stored.schedules.first?.exercises.first?.plannedSets.map { $0.prescription?.repsUpper }, [10, 12])
        XCTAssertTrue(stored.schedules.first?.exercises.first?.plannedSets.allSatisfy { $0.actualDefaultPolicy == .blank } == true)
        let second = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(second.newScheduleCount, 0)
        XCTAssertEqual(second.readback.revisionID, first.readback.revisionID)
        XCTAssertEqual(second.readback.scheduleIDs, first.readback.scheduleIDs)
    }

    func testStorageFailureLeavesNoPartiallyActivatedWeekAndRetrySucceeds() throws {
        let store = try container(), context = store.mainContext
        let input = try packet(in: context)
        let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
        XCTAssertThrowsError(try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context,
            commit: { _ in throw CocoaError(.fileWriteNoPermission) }))
        XCTAssertNil(try ConfirmedTrainingPlanService.readback(code: "IMPORT-TEST-R1", in: context))
        XCTAssertFalse(context.hasChanges)
        let after = try ConfirmedTrainingPlanService.preview(input, in: context)
        XCTAssertEqual(after, preview, "失败后同一预览仍可使用，不应留下编排、菜单或日程")
        let retry = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(retry.newScheduleCount, 1)
        XCTAssertEqual(retry.readback.schedules.count, 1)
    }

    func testWholeWeekIncludesSeparateTimedCardioWithoutGuessingRepetitionsOrDroppingSameDayTask() throws {
        let store = try container(), context = store.mainContext
        var input = try packet(in: context)
        let cycle = Exercise(name: "轻松单车", muscleGroup: "心肺", equipment: "单车", volumeUnit: .second)
        let rope = Exercise(name: "跳绳", muscleGroup: "心肺", equipment: "跳绳", volumeUnit: .second)
        context.insert(cycle)
        context.insert(rope)
        try context.save()
        input.snapshot.cardioWorkouts = [
            ProgramCardioDraft(code: "CYCLE_A", title: "轻松单车", weekday: 2, timing: "独立时段",
                activeSeconds: 1200, elapsedSeconds: nil, intervals: "稳定20–30分钟", guidance: "能说完整句子；先热身5分钟",
                catalogExerciseID: cycle.id, activeSecondsUpper: 1800),
            ProgramCardioDraft(code: "ROPE_A", title: "跳绳", weekday: 2, timing: "晚间，不紧接力量",
                activeSeconds: 360, elapsedSeconds: 720, intervals: "8轮45秒轻跳/45秒步行休息", guidance: "RPE5–6，不适就停",
                catalogExerciseID: rope.id, activeSecondsUpper: 360)
        ]
        let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
        XCTAssertEqual(preview.newScheduleCount, 3)
        let result = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(result.readback.schedules.count, 3)
        let cyclePlan = try XCTUnwrap(result.readback.schedules.first { $0.code == "CYCLE_A" }?.exercises.first)
        XCTAssertEqual(cyclePlan.volumeUnit, .second)
        XCTAssertEqual(cyclePlan.plannedSets.first?.prescription?.repsLower, 1200)
        XCTAssertEqual(cyclePlan.plannedSets.first?.prescription?.repsUpper, 1800)
        let ropePlan = try XCTUnwrap(result.readback.schedules.first { $0.code == "ROPE_A" }?.exercises.first)
        XCTAssertTrue(ropePlan.exerciseNotes.contains("8轮45秒轻跳/45秒步行休息"))
        XCTAssertTrue(ropePlan.exerciseNotes.contains("含休息720秒"))
        XCTAssertEqual(ropePlan.plannedSets.first?.reps, 360, "计划记录有效跳绳秒数，不把含休息时长或轮数伪装成次数")
        XCTAssertEqual(Set(result.readback.schedules.map(\.localDay)), ["2026-10-12"])
    }

    func testConfirmedRopeRouteUsesExactCatalogIdentityRatherThanCodeOrTitle() throws {
        let store = try container(), context = store.mainContext
        var input = try packet(in: context)
        let rope = Exercise(name: "跳绳", muscleGroup: "心肺", equipment: "跳绳", volumeUnit: .second)
        let cycle = Exercise(name: "单车", muscleGroup: "心肺", equipment: "单车", volumeUnit: .second)
        context.insert(rope)
        context.insert(cycle)
        try context.save()
        let cardio = ProgramCardioDraft(code: "CUT-RESTORE-20261012-ROPE1", title: "轻松跳绳1",
            weekday: 2, timing: "独立时段", activeSeconds: 360, elapsedSeconds: 720,
            intervals: "8轮，每轮45秒跳绳／45秒步行休息", guidance: "不适就停",
            catalogExerciseID: rope.id, activeSecondsUpper: 360)
        input.snapshot.cardioWorkouts = [cardio]
        let applied = try ConfirmedTrainingPlanService.apply(
            expectedPreview: ConfirmedTrainingPlanService.preview(input, in: context), in: context)
        let scheduleID = try XCTUnwrap(applied.readback.schedules.first { $0.code == cardio.code }?.id)
        let routed = try XCTUnwrap(TrainingPlanPresentation.cardioDraft(scheduleID: scheduleID,
            links: context.fetch(FetchDescriptor<ProgramWorkoutLink>()),
            revisions: context.fetch(FetchDescriptor<TrainingProgramRevision>())))
        XCTAssertEqual(routed, cardio)
        XCTAssertTrue(TrainingPlanPresentation.isJumpRope(routed, exercises: [rope, cycle]),
            "已确认R1无需旧ROPE_前缀即可到达跳绳记录入口")

        var misnamedCycle = cardio
        misnamedCycle.code = "ROPE_LEGACY"
        misnamedCycle.catalogExerciseID = cycle.id
        XCTAssertFalse(TrainingPlanPresentation.isJumpRope(misnamedCycle, exercises: [rope, cycle]),
            "明确单车身份优先于名称和旧前缀")
        var unknownIdentity = cardio
        unknownIdentity.code = "ROPE_LEGACY"
        unknownIdentity.catalogExerciseID = UUID()
        XCTAssertFalse(TrainingPlanPresentation.isJumpRope(unknownIdentity, exercises: [rope, cycle]))
        var legacy = cardio
        legacy.code = "ROPE_LEGACY"
        legacy.catalogExerciseID = nil
        XCTAssertTrue(TrainingPlanPresentation.isJumpRope(legacy, exercises: []),
            "无动作身份的旧编排保留原路由")
        XCTAssertNil(TrainingPlanPresentation.cardioDraft(scheduleID: UUID(),
            links: try context.fetch(FetchDescriptor<ProgramWorkoutLink>()),
            revisions: try context.fetch(FetchDescriptor<TrainingProgramRevision>())))
    }

    func testStartUsesCompatibleHistoryWithoutChangingBlankPlanAndPublicBackupRestoresBothGenerations() throws {
        let store = try container(), context = store.mainContext
        let input = try packet(in: context)
        let exerciseID = try XCTUnwrap(input.snapshot.strengthWorkouts.first?.exercises.first?.catalogExerciseID)
        let history = WorkoutSession(templateName: "已完成历史", plannedDate: FatLossCalendar.date(2026, 10, 5),
            startedAt: FatLossCalendar.date(2026, 10, 5), completedAt: FatLossCalendar.date(2026, 10, 5).addingTimeInterval(3600),
            status: .completed)
        context.insert(history)
        let historicalExercise = SessionExercise(sessionID: history.id, exerciseID: exerciseID, exerciseName: "测试推胸",
            order: 0, targetSets: 4, minReps: 8, maxReps: 12, targetWeight: 25, restSeconds: 180,
            muscleGroup: "胸部", equipmentSnapshot: "测试器械")
        context.insert(historicalExercise)
        var historicalSetIDs: [UUID] = []
        for number in 1...4 {
            let log = SetLog(sessionID: history.id, sessionExerciseID: historicalExercise.id,
                exerciseID: exerciseID, setNumber: number, targetWeight: 25, targetReps: 12,
                actualWeight: 25, actualReps: 12, isCompleted: true, completedAt: history.completedAt)
            context.insert(log)
            historicalSetIDs.append(log.id)
        }
        try context.save()
        let imported = try ConfirmedTrainingPlanService.apply(
            expectedPreview: ConfirmedTrainingPlanService.preview(input, in: context), in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first {
            $0.id == imported.readback.scheduleIDs.first
        })
        let originalPlanJSON = schedule.planSnapshotJSON
        let sessionID = try WorkoutService.start(schedule: schedule, in: context)
        XCTAssertEqual(schedule.planSnapshotJSON, originalPlanJSON)
        let snapshot = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first { $0.sessionID == sessionID })
        XCTAssertEqual(snapshot.plannedSets, input.snapshot.strengthWorkouts[0].exercises[0].plannedSets)
        let backupURL = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backupURL) }
        let data = try DataExportService.loadBackupData(from: backupURL)
        let backup = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let logs = try XCTUnwrap(backup["setLogs"] as? [[String: Any]])
        let newLogs = logs.filter { ($0["sessionID"] as? String)?.lowercased() == sessionID.uuidString.lowercased() }
            .sorted { ($0["setNumber"] as? Int ?? 0) < ($1["setNumber"] as? Int ?? 0) }
        XCTAssertEqual(newLogs.count, 2, "历史四组不能扩成本次四组")
        XCTAssertEqual(newLogs.compactMap { $0["targetReps"] as? Int }, [8, 10])
        XCTAssertTrue(newLogs.allSatisfy { ($0["targetWeight"] as? Double) == 0 })
        XCTAssertEqual(newLogs.compactMap { $0["actualReps"] as? Int }, [12, 12])
        XCTAssertTrue(newLogs.allSatisfy { ($0["actualWeightIsBlank"] as? Bool) == false && ($0["actualWeight"] as? Double) == 25 })
        XCTAssertTrue(newLogs.allSatisfy { ($0["actualEntrySourceRaw"] as? String) == "history" })
        XCTAssertEqual(newLogs.compactMap { ($0["sourceHistorySetID"] as? String)?.lowercased() },
            historicalSetIDs.prefix(2).map { $0.uuidString.lowercased() })
        XCTAssertTrue(newLogs.allSatisfy { ($0["isCompleted"] as? Bool) == false && $0["rir"] == nil })
        let oldLogs = logs.filter { ($0["sessionID"] as? String)?.lowercased() == history.id.uuidString.lowercased() }
        XCTAssertEqual(oldLogs.count, 4)
        XCTAssertEqual(Set(oldLogs.compactMap { ($0["id"] as? String)?.lowercased() }),
            Set(historicalSetIDs.map { $0.uuidString.lowercased() }))
        XCTAssertTrue(oldLogs.allSatisfy { ($0["actualWeight"] as? Double) == 25 && ($0["actualReps"] as? Int) == 12
            && ($0["isCompleted"] as? Bool) == true })

        let restoredStore = try container(), restored = restoredStore.mainContext
        _ = try DataExportService.importBackup(data, into: restored)
        let readback = try XCTUnwrap(ConfirmedTrainingPlanService.readback(code: "IMPORT-TEST-R1", in: restored))
        XCTAssertEqual(readback, imported.readback, "新目标、原文、日期/时区和完整关联均应从公开备份恢复")
        let restoredLogs = try restored.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionID == sessionID }
            .sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(restoredLogs.count, 2)
        XCTAssertEqual(restoredLogs.map(\.targetReps), [8, 10])
        XCTAssertTrue(restoredLogs.allSatisfy { $0.targetWeight == 0 && $0.actualWeight == 25 && $0.actualReps == 12
            && $0.actualEntrySource == .history && !$0.isActualWeightBlank && !$0.isCompleted && $0.rir == nil })
        XCTAssertEqual(restoredLogs.compactMap(\.sourceHistorySetID), Array(historicalSetIDs.prefix(2)))
        XCTAssertEqual(try DataExportService.importBackup(data, into: restored).imported, 0)
        XCTAssertEqual(try DataExportService.preview(data).sessions, 2)
    }

    func testPublicRestorePreservesExactScheduledInstantNotOnlyDisplayedDay() throws {
        let store = try container(), context = store.mainContext
        let input = try packet(in: context)
        _ = try ConfirmedTrainingPlanService.apply(expectedPreview: ConfirmedTrainingPlanService.preview(input, in: context), in: context)
        let originalURL = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: originalURL) }
        let originalData = try DataExportService.loadBackupData(from: originalURL)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        let destination = try container()
        _ = try DataExportService.importBackup(originalData, into: destination.mainContext)
        let restoredURL = try DataExportService.createBackup(in: destination.mainContext)
        defer { try? FileManager.default.removeItem(at: restoredURL) }
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: DataExportService.loadBackupData(from: restoredURL)) as? [String: Any])
        let sourceSchedules = try XCTUnwrap(original["schedules"] as? [[String: Any]])
        let restoredSchedules = try XCTUnwrap(restored["schedules"] as? [[String: Any]])
        XCTAssertEqual(sourceSchedules.first?["plannedDate"] as? String, "2026-10-12T04:00:00Z")
        XCTAssertEqual(restoredSchedules.first?["plannedDate"] as? String, "2026-10-12T04:00:00Z", "恢复不是一次新的日期选择，不能重新取当天零点")
        XCTAssertEqual(restoredSchedules.first?["plannedLocalDay"] as? String, "2026-10-12")
        XCTAssertEqual(restoredSchedules.first?["planSnapshotJSON"] as? String, sourceSchedules.first?["planSnapshotJSON"] as? String)
    }
}

extension ConfirmedTrainingPlanTests {
    private func prefilledRevision(_ original: ConfirmedDailyTrainingPlanPacket) throws -> ConfirmedDailyTrainingPlanPacket {
        var revision = original
        revision.id = UUID()
        revision.title = "明确确认的建议预填修订"
        revision.actualPrefillConfirmationReference = "OWNER-CONFIRMED-PREFILL"
        revision.replacement = ConfirmedDailyTrainingPlanReplacement(scheduleID: original.id,
            packetSHA256: try ConfirmedTrainingPlanService.digest(original))
        revision.exercises = Array(original.exercises.prefix(2))
        for e in revision.exercises.indices {
            revision.exercises[e].loadGuidance = "每侧片重kg，不含空载阻力"
            for s in revision.exercises[e].plannedSets.indices {
                revision.exercises[e].plannedSets[s].id = UUID()
                revision.exercises[e].plannedSets[s].weight = s == 0 ? 25 : 20
                revision.exercises[e].plannedSets[s].actualDefaultPolicyRaw = "plan"
            }
        }
        return revision
    }

    func testExplicitDailyPrefillStartsAsEditableIncompleteDraftAndResumesWithoutReset() throws {
        let store = try container(), context = store.mainContext
        let original = try dailyPacket(in: context)
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(original, in: context), in: context)
        let revision = try prefilledRevision(original)
        let preview = try ConfirmedDailyTrainingPlanService.preview(revision, in: context)
        XCTAssertTrue(preview.conflicts.isEmpty)
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == revision.id })
        let sessionID = try WorkoutService.start(schedule: schedule, in: context)
        let logs = try context.fetch(FetchDescriptor<SetLog>())
        XCTAssertEqual(logs.count, 8)
        XCTAssertTrue(logs.allSatisfy { !$0.isCompleted && $0.completedAt == nil && $0.rir == nil &&
            $0.actualEntrySource == .plan && !$0.isActualWeightBlank && $0.sourceHistorySetID == nil &&
            $0.actualWeight == $0.targetWeight && $0.actualReps == $0.targetReps })
        let edited = try XCTUnwrap(logs.first)
        edited.actualWeight = 22.5
        edited.actualReps = 11
        edited.markActualEntryEdited()
        try context.save()
        XCTAssertEqual(try WorkoutService.start(schedule: schedule, in: context), sessionID)
        XCTAssertEqual(edited.actualWeight, 22.5)
        XCTAssertEqual(edited.actualReps, 11)
        XCTAssertFalse(edited.isCompleted)
        let exercise = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first { $0.id == edited.sessionExerciseID })
        try WorkoutService.restorePlanDefaults(for: exercise, in: context)
        XCTAssertEqual(edited.actualWeight, edited.targetWeight)
        XCTAssertEqual(edited.actualReps, edited.targetReps)
        XCTAssertTrue(logs.allSatisfy { !$0.isCompleted && $0.rir == nil })
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 0,
                       "A repeat after starting must remain a no-op, never replace the active revision")
    }

    func testConfirmedDailyPrefillCanUseRangeUpperBoundWithoutCompletingOrChangingTargets() throws {
        let store = try container(), context = store.mainContext
        var original = try dailyPacket(in: context)
        var range = try XCTUnwrap(original.exercises[0].plannedSets[0].prescription)
        range.repsLower = 12; range.repsUpper = 15; range.rirLower = 2; range.rirUpper = 2
        original.exercises[0].plannedSets[0].prescription = range
        original.exercises[0].plannedSets[0].reps = 12
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(original, in: context), in: context)
        var revision = try prefilledRevision(original)
        for e in revision.exercises.indices {
            for s in revision.exercises[e].plannedSets.indices {
                let target = try XCTUnwrap(revision.exercises[e].plannedSets[s].prescription)
                revision.exercises[e].plannedSets[s].reps = target.repsUpper
            }
        }
        let preview = try ConfirmedDailyTrainingPlanService.preview(revision, in: context)
        XCTAssertTrue(preview.conflicts.isEmpty)
        let applied = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(applied.readback.packet, revision)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == revision.id })
        let sessionID = try WorkoutService.start(schedule: schedule, in: context)
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>()).filter { $0.sessionID == sessionID }
        let logs = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionID == sessionID }
        XCTAssertEqual(logs.count, revision.exercises.reduce(0) { $0 + $1.plannedSets.count })
        for exercise in snapshots {
            for log in logs where log.sessionExerciseID == exercise.id {
                let plan = exercise.plannedSets[log.setNumber - 1]
                XCTAssertEqual(log.actualReps, plan.prescription?.repsUpper)
                XCTAssertEqual(log.targetReps, plan.reps)
                XCTAssertFalse(log.isCompleted)
                XCTAssertNil(log.rir)
                XCTAssertNil(log.completedAt)
            }
        }
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 0)
    }

    func testRangePrefillStillRejectsOutOfRangeRepsAndDoesNotChangeLegacyBlankContract() throws {
        let store = try container(), context = store.mainContext
        var original = try dailyPacket(in: context)
        var range = try XCTUnwrap(original.exercises[0].plannedSets[0].prescription)
        range.repsLower = 12; range.repsUpper = 15
        original.exercises[0].plannedSets[0].prescription = range
        original.exercises[0].plannedSets[0].reps = 12
        let target = try XCTUnwrap(original.exercises[0].plannedSets[0].prescription)
        XCTAssertGreaterThan(target.repsUpper, target.repsLower)
        var legacy = original
        legacy.exercises[0].plannedSets[0].reps = target.repsUpper
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.preview(legacy, in: context))
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(original, in: context), in: context)
        let revision = try prefilledRevision(original)
        for reps in [target.repsLower - 1, target.repsUpper + 1] {
            var invalid = revision
            invalid.exercises[0].plannedSets[0].reps = reps
            XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.preview(invalid, in: context))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    func testDailyRevisionPreservesLegacySourceBackupAndChainedIdempotence() throws {
        let store = try container(), context = store.mainContext
        let original = try dailyPacket(in: context)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        XCTAssertNil(legacyJSON["replacement"])
        XCTAssertNil(legacyJSON["actualPrefillConfirmationReference"])
        let first = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(original, in: context), in: context)
        let predecessor = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        let frozen = predecessor.planSnapshotJSON, source = predecessor.confirmedDailyImportJSON
        let revision = try prefilledRevision(original)
        let preview = try ConfirmedDailyTrainingPlanService.preview(revision, in: context)
        let applied = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(predecessor.status, .skipped)
        XCTAssertTrue(predecessor.skipReason.contains(revision.id.uuidString))
        XCTAssertEqual(predecessor.planSnapshotJSON, frozen)
        XCTAssertEqual(predecessor.confirmedDailyImportJSON, source)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: original.id, in: context), first.readback)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 0)
        // A later, explicitly confirmed revision can follow the same protected chain.
        var next = try prefilledRevision(revision)
        next.exercises[0].plannedSets[0].weight = 27.5
        let nextPreview = try ConfirmedDailyTrainingPlanService.preview(next, in: context)
        XCTAssertTrue(nextPreview.conflicts.isEmpty)
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: nextPreview, in: context)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: nextPreview, in: context).newScheduleCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ScheduledWorkout>()).filter { $0.status == .planned }.count, 1)
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.supersededScheduleIDs(in:
            try context.fetch(FetchDescriptor<ScheduledWorkout>())), [original.id, revision.id])
        let backup = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: backup), into: restored.mainContext)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: revision.id, in: restored.mainContext), applied.readback)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: original.id, in: restored.mainContext), first.readback)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    private func revisedDailyPlan(exerciseName: String = "修订测试推胸", equipment: String = "测试推胸机",
                                  volumeUnit: ExerciseVolumeUnit = .kilogram,
                                  in context: ModelContext) throws -> (old: ScheduledWorkout, current: ScheduledWorkout) {
        var original = try dailyPacket(in: context)
        let exercise = Exercise(name: exerciseName, muscleGroup: volumeUnit == .second ? "心肺" : "胸部",
            equipment: equipment, volumeUnit: volumeUnit)
        context.insert(exercise)
        let reps = volumeUnit == .second ? 600 : 8
        let target = WorkoutSetPrescription(label: "隔离测试目标", repsLower: reps, repsUpper: reps,
            rirLower: nil, rirUpper: nil, restLowerSeconds: 60, restUpperSeconds: 60)
        original.title = "旧修订 · " + exerciseName
        original.exercises = [.init(catalogExerciseID: exercise.id, catalogName: exercise.name,
            equipment: equipment, volumeUnit: volumeUnit, displayName: exercise.name,
            loadGuidance: volumeUnit == .second ? "只记录秒数" : "同机显示kg，实际留空",
            notes: "隔离测试", plannedSets: [.init(weight: volumeUnit == .second ? 0 : 20,
                reps: reps, actualDefaultPolicy: .blank, prescription: target)])]
        try context.save()
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(original, in: context), in: context)
        var revision = original
        revision.id = UUID()
        revision.title = "当前修订 · " + exerciseName
        revision.replacement = .init(scheduleID: original.id, packetSHA256: try ConfirmedTrainingPlanService.digest(original))
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(revision, in: context), in: context)
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        return (try XCTUnwrap(schedules.first { $0.id == original.id }),
                try XCTUnwrap(schedules.first { $0.id == revision.id }))
    }

    func testSupersededProjectionUsesConfirmedReplacementAndKeepsVoluntarySkipSeparate() throws {
        let store = try container(), context = store.mainContext
        let pair = try revisedDailyPlan(in: context)
        let voluntary = ScheduledWorkout(templateID: UUID(), templateName: "本人主动跳过", plannedDate: pair.old.plannedDate,
            status: .skipped)
        voluntary.skipReason = "已由确认修订 只是本人填写的说明"
        pair.old.skipReason = "来源绑定仍然存在"
        context.insert(voluntary); try context.save()
        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        let retired = ConfirmedDailyTrainingPlanService.supersededScheduleIDs(in: schedules)
        XCTAssertEqual(retired, [pair.old.id])
        XCTAssertTrue(try ConfirmedDailyTrainingPlanService.isSuperseded(pair.old.id, in: context))
        XCTAssertFalse(try ConfirmedDailyTrainingPlanService.isSuperseded(pair.current.id, in: context))
        XCTAssertFalse(try ConfirmedDailyTrainingPlanService.isSuperseded(voluntary.id, in: context))
        let day = TrainingScheduleDate.localDay(pair.old)
        let summary = TrainingDaySummary(localDay: day, schedules: schedules, sessions: [], excludedScheduleIDs: retired)
        XCTAssertEqual(summary.pendingScheduleCount, 1)
        XCTAssertEqual(summary.feedback, TrainingDayFeedback(schedules: [pair.current, voluntary]))
        XCTAssertEqual(TrainingDaySummary(localDay: day, schedules: [pair.old], sessions: [],
            excludedScheduleIDs: retired).feedback.tone, .none)
        XCTAssertEqual(TrainingDaySummary(localDay: day, schedules: [voluntary], sessions: [],
            excludedScheduleIDs: retired).feedback.tone, .gray)
        XCTAssertFalse(context.hasChanges)
    }

    func testSupersededRopeIsRejectedByLowestSaveBoundaryWithoutChangingEitherRevision() throws {
        let store = try container(), context = store.mainContext
        let pair = try revisedDailyPlan(exerciseName: "隔离跳绳", equipment: "跳绳", volumeUnit: .second, in: context)
        let original = (pair.old.statusRaw, pair.old.skipReason, pair.old.updatedAt,
                        pair.old.planSnapshotJSON, pair.old.confirmedDailyImportJSON)
        XCTAssertThrowsError(try WellnessToolService.recordJumpRope(count: nil, activeDurationSeconds: 540,
            elapsedDurationSeconds: 720, at: TrainingScheduleDate.displayDate(pair.old),
            scheduledWorkoutID: pair.old.id, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JumpRopeEntry>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(pair.old.statusRaw, original.0); XCTAssertEqual(pair.old.skipReason, original.1)
        XCTAssertEqual(pair.old.updatedAt, original.2); XCTAssertEqual(pair.old.planSnapshotJSON, original.3)
        XCTAssertEqual(pair.old.confirmedDailyImportJSON, original.4)
        XCTAssertEqual(pair.current.status, .planned); XCTAssertFalse(context.hasChanges)
        let result = try WellnessToolService.recordJumpRope(count: nil, activeDurationSeconds: 540,
            elapsedDurationSeconds: 720, at: TrainingScheduleDate.displayDate(pair.current),
            scheduledWorkoutID: pair.current.id, in: context)
        let actual = try XCTUnwrap(context.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertEqual(actual.id, result.recordID); XCTAssertEqual(actual.scheduledWorkoutID, pair.current.id)
        XCTAssertEqual(pair.current.status, .completed); XCTAssertEqual(pair.old.status, .skipped)
    }

    func testSupersededStrengthCannotCreateActualEvenIfItsStatusStillSaysPlanned() throws {
        let store = try container(), context = store.mainContext
        let pair = try revisedDailyPlan(in: context)
        pair.old.status = .planned; try context.save()
        let source = pair.old.confirmedDailyImportJSON, plan = pair.old.planSnapshotJSON, update = pair.old.updatedAt
        XCTAssertThrowsError(try WorkoutService.start(schedule: pair.old, in: context)) { error in
            guard case WorkoutServiceError.scheduleNotReady = error else { return XCTFail("应拒绝旧修订的新实际：\(error)") }
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 0)
        XCTAssertEqual(pair.old.status, .planned); XCTAssertEqual(pair.old.updatedAt, update)
        XCTAssertEqual(pair.old.confirmedDailyImportJSON, source); XCTAssertEqual(pair.old.planSnapshotJSON, plan)
        XCTAssertFalse(context.hasChanges)
        let currentID = try WorkoutService.start(schedule: pair.current, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.id, currentID)
        XCTAssertEqual(pair.current.status, .inProgress)
    }

    func testSupersededStrengthStillResumesItsExistingActualWithoutResettingIt() throws {
        let store = try container(), context = store.mainContext
        let pair = try revisedDailyPlan(in: context)
        let actual = WorkoutSession(scheduledWorkoutID: pair.old.id, templateID: pair.old.templateID,
            templateName: pair.old.templateName, plannedDate: pair.old.plannedDate)
        actual.notes = "已有实际，不覆盖"
        context.insert(actual); try context.save()
        let update = pair.old.updatedAt
        XCTAssertEqual(try WorkoutService.start(schedule: pair.old, in: context), actual.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(actual.notes, "已有实际，不覆盖"); XCTAssertEqual(pair.old.updatedAt, update)
        XCTAssertEqual(pair.old.status, .skipped); XCTAssertFalse(context.hasChanges)
    }

    func testSupersededCardioRejectsNewActualAndRetainsExistingIdempotenceAndEdit() throws {
        let store = try container(), context = store.mainContext
        let pair = try revisedDailyPlan(exerciseName: "固定单车", equipment: "单车", volumeUnit: .second, in: context)
        pair.old.status = .planned; try context.save()
        let source = pair.old.confirmedDailyImportJSON, planJSON = pair.old.planSnapshotJSON, update = pair.old.updatedAt
        XCTAssertThrowsError(try CardioWorkoutService.record(schedule: pair.old, seconds: 540, level: 8, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 0)
        XCTAssertEqual(pair.old.updatedAt, update); XCTAssertEqual(pair.old.status, .planned)
        XCTAssertFalse(context.hasChanges)
        let plan = try XCTUnwrap(pair.old.planSnapshot.first)
        let actual = WorkoutSession(scheduledWorkoutID: pair.old.id, templateID: pair.old.templateID,
            templateName: pair.old.templateName, plannedDate: pair.old.plannedDate,
            startedAt: pair.old.plannedDate, isStartTimeKnown: false, status: .completed)
        TrainingHistoryDate.capture(actual, date: pair.old.plannedDate, schedule: pair.old)
        actual.cardioResistanceLevel = 8
        let snapshot = SessionExercise(sessionID: actual.id, exerciseID: plan.exerciseID, exerciseName: plan.exerciseName,
            order: 0, targetSets: 1, minReps: 600, maxReps: 600, targetWeight: 0, restSeconds: 60,
            muscleGroup: "心肺", volumeUnit: .second, plannedSets: plan.plannedSets, equipmentSnapshot: "单车")
        let log = SetLog(sessionID: actual.id, sessionExerciseID: snapshot.id, exerciseID: plan.exerciseID,
            setNumber: 1, targetWeight: 0, targetReps: 600, actualWeight: 0, actualReps: 540,
            isCompleted: true, actualEntrySource: .manual, actualWeightIsBlank: true)
        context.insert(actual); context.insert(snapshot); context.insert(log)
        pair.old.status = .completed; try context.save()
        XCTAssertEqual(try CardioWorkoutService.record(schedule: pair.old, seconds: 540, level: 8, in: context), actual.id)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try CardioWorkoutService.record(schedule: pair.old, seconds: 480, level: 7,
            editingSessionID: actual.id, in: context), actual.id)
        XCTAssertEqual(log.actualReps, 480); XCTAssertEqual(actual.cardioResistanceLevel, 7)
        XCTAssertEqual(pair.old.confirmedDailyImportJSON, source); XCTAssertEqual(pair.old.planSnapshotJSON, planJSON)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        _ = try CardioWorkoutService.record(schedule: pair.current, seconds: 600, level: nil, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 2)
        XCTAssertEqual(pair.current.status, .completed)
    }

    func testSupersededHistoricalNewActualIsRejectedAcrossBothSavePaths() throws {
        let store = try container(), context = store.mainContext
        let pair = try revisedDailyPlan(in: context)
        let plan = try XCTUnwrap(pair.old.planSnapshot.first)
        func input(for schedule: ScheduledWorkout) -> ScheduledWorkoutBackfillInput {
            .init(scheduleID: schedule.id, existingSessionID: nil, name: "本人补录", date: schedule.plannedDate,
                startedAt: nil, durationMinutes: nil, notes: "保留真实补录", exercises: [
                    .init(existingSnapshotID: nil, exerciseID: plan.exerciseID,
                        sets: [.init(existingLogID: nil, weight: 20, reps: 8, rir: 3)],
                        performanceNotes: "", feeling: nil, isWarmup: false)])
        }
        let original = (pair.old.statusRaw, pair.old.skipReason, pair.old.updatedAt,
                        pair.old.planSnapshotJSON, pair.old.confirmedDailyImportJSON)
        XCTAssertThrowsError(try HistoricalWorkoutService.prepareScheduledBackfill(scheduleID: pair.old.id, in: context))
        XCTAssertThrowsError(try HistoricalWorkoutService.recordScheduledBackfill(input(for: pair.old), in: context))
        let direct = HistoricalWorkoutInput(name: "直接补录", startedAt: pair.old.plannedDate, durationMinutes: nil,
            notes: "", exercises: [.init(exerciseID: plan.exerciseID,
                sets: [.init(weight: 20, reps: 8, rir: 3)], performanceNotes: "")], scheduledWorkoutID: pair.old.id)
        XCTAssertThrowsError(try HistoricalWorkoutService.record(direct, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 0)
        XCTAssertEqual(pair.old.statusRaw, original.0); XCTAssertEqual(pair.old.skipReason, original.1)
        XCTAssertEqual(pair.old.updatedAt, original.2); XCTAssertEqual(pair.old.planSnapshotJSON, original.3)
        XCTAssertEqual(pair.old.confirmedDailyImportJSON, original.4); XCTAssertFalse(context.hasChanges)
        _ = try ScheduleService.skipManaged(pair.current, reason: "本人主动跳过，之后补录", in: context)
        let actual = try HistoricalWorkoutService.recordScheduledBackfill(input(for: pair.current), in: context)
        XCTAssertEqual(actual.scheduledWorkoutID, pair.current.id)
        XCTAssertEqual(pair.current.status, .completed); XCTAssertEqual(pair.old.status, .skipped)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    }

    func testSupersededHistoricalExistingActualKeepsItsExplicitEditingPath() throws {
        let store = try container(), context = store.mainContext
        let pair = try revisedDailyPlan(in: context)
        let actual = WorkoutSession(scheduledWorkoutID: pair.old.id, templateID: pair.old.templateID,
            templateName: pair.old.templateName, plannedDate: pair.old.plannedDate,
            isStartTimeKnown: false, status: .completed)
        context.insert(actual); try context.save()
        let preparation = try HistoricalWorkoutService.prepareScheduledBackfill(scheduleID: pair.old.id, in: context)
        XCTAssertEqual(preparation.existingSessionID, actual.id)
        let source = pair.old.confirmedDailyImportJSON, planJSON = pair.old.planSnapshotJSON
        let plan = try XCTUnwrap(pair.old.planSnapshot.first)
        let input = ScheduledWorkoutBackfillInput(scheduleID: pair.old.id, existingSessionID: actual.id,
            name: "修正原实际", date: pair.old.plannedDate, startedAt: nil, durationMinutes: nil,
            notes: "明确修改原记录", exercises: [.init(existingSnapshotID: nil, exerciseID: plan.exerciseID,
                sets: [.init(existingLogID: nil, weight: 22.5, reps: 9, rir: 2)],
                performanceNotes: "本人修正", feeling: nil, isWarmup: false)])
        XCTAssertEqual(try HistoricalWorkoutService.recordScheduledBackfill(input, in: context).id, actual.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).first?.actualWeight, 22.5)
        XCTAssertEqual(actual.notes, "明确修改原记录")
        XCTAssertEqual(pair.old.confirmedDailyImportJSON, source); XCTAssertEqual(pair.old.planSnapshotJSON, planJSON)
    }

    func testConfirmedWeekWindowUsesSourceDaysAndTimezoneAtBothBoundaries() throws {
        let store = try container(), context = store.mainContext
        let input = try packet(in: context)
        var snapshot = input.snapshot
        snapshot.confirmedImport = .init(packetSHA256: "test", startLocalDay: "2026-10-12", endLocalDay: "2026-10-18",
            timeZoneIdentifier: "America/Los_Angeles", confirmedAt: input.confirmedAt,
            confirmationReference: input.confirmationReference, sourceMarkdown: input.sourceMarkdown,
            sourceSHA256: input.sourceSHA256)
        let preference = try XCTUnwrap(TrainingPreferenceService.current(in: context))
        let revision = try TrainingProgramRevision(programID: input.programID, preferenceRevision: preference,
            snapshot: snapshot, revision: 2, effectiveDate: FatLossCalendar.date(2026, 10, 1), reason: "来源日期优先测试")
        let window = TrainingPlanPresentation.window(for: revision)
        XCTAssertEqual(window.label, "2026-10-12 至 2026-10-18")
        XCTAssertEqual(window.timeZone.identifier, "America/Los_Angeles")
        for (instant, expected) in [("2026-10-12T06:59:59Z", "待生效编排"),
                                    ("2026-10-12T07:00:00Z", "当前编排"),
                                    ("2026-10-19T06:59:59Z", "当前编排"),
                                    ("2026-10-19T07:00:00Z", "历史编排")] {
            XCTAssertEqual(window.status(on: try XCTUnwrap(ISO8601DateFormatter().date(from: instant))), expected)
        }
        XCTAssertEqual(revision.effectiveDate, FatLossCalendar.date(2026, 10, 1))
        XCTAssertEqual(revision.snapshot, snapshot)
    }

    func testNativeWeekWindowStaysOnItsOriginalWeekAfterExpiry() throws {
        let store = try container(), context = store.mainContext
        let input = try packet(in: context)
        let preference = try XCTUnwrap(TrainingPreferenceService.current(in: context))
        let revision = try TrainingProgramRevision(programID: input.programID, preferenceRevision: preference,
            snapshot: input.snapshot, revision: 1, effectiveDate: FatLossCalendar.date(2026, 10, 12), reason: "原生周窗口测试")
        let window = TrainingPlanPresentation.window(for: revision)
        XCTAssertEqual(window.label, "2026-10-12 至 2026-10-18")
        XCTAssertEqual(window.timeZone.identifier, "Asia/Shanghai")
        XCTAssertEqual(window.status(on: FatLossCalendar.date(2026, 10, 11)), "待生效编排")
        XCTAssertEqual(window.status(on: FatLossCalendar.date(2026, 10, 12)), "当前编排")
        XCTAssertEqual(window.status(on: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-18T15:59:59Z"))), "当前编排")
        XCTAssertEqual(window.status(on: FatLossCalendar.date(2026, 10, 19)), "历史编排")
        XCTAssertEqual(window.startLocalDay, "2026-10-12")
        XCTAssertEqual(window.endLocalDay, "2026-10-18")
        XCTAssertEqual(revision.snapshot, input.snapshot)
    }

    func testDailyRevisionCommitFailureRestoresPredecessorAndAllCounts() throws {
        let store = try container(), context = store.mainContext
        let original = try dailyPacket(in: context)
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(original, in: context), in: context)
        let predecessor = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        let updated = predecessor.updatedAt
        let revision = try prefilledRevision(original)
        let preview = try ConfirmedDailyTrainingPlanService.preview(revision, in: context)
        let templates = try context.fetchCount(FetchDescriptor<WorkoutTemplate>())
        let items = try context.fetchCount(FetchDescriptor<TemplateExercise>())
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context, commit: { _ in
            throw CocoaError(.fileWriteNoPermission)
        }))
        XCTAssertEqual(predecessor.status, .planned)
        XCTAssertEqual(predecessor.skipReason, "")
        XCTAssertEqual(predecessor.updatedAt, updated)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()), templates)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TemplateExercise>()), items)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 1,
                       "The exact preview must remain usable after a fully rolled-back failed save")
    }

    func testDailyRevisionRejectsStartedActualChangedBindingAndUnrelatedSchedules() throws {
        for variant in 0..<7 {
            let store = try container(), context = store.mainContext
            let original = try dailyPacket(in: context)
            _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
                ConfirmedDailyTrainingPlanService.preview(original, in: context), in: context)
            let predecessor = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
            var revision = try prefilledRevision(original)
            let preview = try ConfirmedDailyTrainingPlanService.preview(revision, in: context)
            if variant == 0 { predecessor.status = .inProgress }
            if variant == 1 { predecessor.status = .completed }
            if variant == 2 {
                context.insert(WorkoutSession(scheduledWorkoutID: predecessor.id, templateName: "已开始后丢弃",
                    plannedDate: predecessor.plannedDate, startedAt: .now, status: .discarded))
            }
            if variant == 3 { revision.replacement?.packetSHA256 = String(repeating: "a", count: 64) }
            if variant == 4 { predecessor.skipReason = "预览后人工编辑" }
            if variant == 5 {
                context.insert(ScheduledWorkout(templateID: UUID(), templateName: "无关的已跳过安排",
                    plannedDate: predecessor.plannedDate, status: .skipped))
            }
            if variant == 6 { revision.timeZoneIdentifier = "Asia/Tokyo" }
            try context.save()
            if variant == 3 || variant == 6 {
                XCTAssertFalse(try ConfirmedDailyTrainingPlanService.preview(revision, in: context).conflicts.isEmpty)
            } else {
                XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context), "variant=\(variant)")
            }
            XCTAssertFalse(try context.fetch(FetchDescriptor<ScheduledWorkout>()).contains { $0.id == revision.id })
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testDailyPrefillRequiresExplicitConfirmationNumericLoadAndClearInstructions() throws {
        let store = try container(), context = store.mainContext
        let original = try dailyPacket(in: context)
        for variant in 0..<6 {
            var revision = try prefilledRevision(original)
            revision.replacement = nil
            if variant == 0 { revision.actualPrefillConfirmationReference = nil }
            if variant == 1 { revision.actualPrefillConfirmationReference = " " }
            if variant == 2 { revision.exercises[0].plannedSets[0].weight = 0 }
            if variant == 3 { revision.exercises[0].plannedSets[0].weightSide = .unknown }
            if variant == 4 { revision.exercises[0].notes = "重量留空" }
            if variant == 5 { revision.exercises[0].plannedSets[0].actualDefaultPolicyRaw = "history" }
            XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.preview(revision, in: context), "variant=\(variant)")
            XCTAssertFalse(context.hasChanges)
        }
    }

    private func dailyPacket(in context: ModelContext) throws -> ConfirmedDailyTrainingPlanPacket {
        let week = try packet(in: context)
        let names = ["隔离高翻", "隔离腿举", "隔离箭步蹲", "隔离腿弯举", "隔离腿屈伸", "隔离死虫"]
        let counts = [4, 4, 3, 3, 3, 3]
        let lower = [3, 8, 8, 10, 12, 6], upper = [3, 10, 10, 15, 15, 10]
        var drafts: [ConfirmedDailyPlanExercise] = []
        for index in names.indices {
            let exercise = Exercise(name: names[index], muscleGroup: index == 5 ? "核心" : "腿部", equipment: index == 5 ? "自重" : "隔离器械")
            if index == 5 { exercise.volumeUnit = .count }
            context.insert(exercise)
            let load = ["每侧片重15kg，不含杆", "每侧片重90/80/80/80kg，空载未知", "一只15kg哑铃，另一手扶架", "同机显示20起，20–25校准，单位未确认", "同机显示35起，35–40校准，单位未确认", "自重，每侧"][index]
            let sets = (0..<counts[index]).map { setIndex in
                let reps = index == 1 && setIndex > 0 ? 10 : lower[index]
                return WorkoutSetPlan(weight: index == 0 || index == 2 ? 15 : index == 1 ? (setIndex == 0 ? 90 : 80) : 0,
                    reps: reps, weightSide: index <= 2 ? .single : .unknown,
                    repsSide: index == 2 || index == 5 ? .single : .bilateral, actualDefaultPolicy: .blank,
                    prescription: WorkoutSetPrescription(label: load, repsLower: reps,
                        repsUpper: index == 1 && setIndex > 0 ? 12 : upper[index],
                        rirLower: index == 0 || index == 5 ? nil : 2,
                        rirUpper: index == 0 || index == 5 ? nil : 3,
                        restLowerSeconds: index < 2 ? 120 : 60, restUpperSeconds: index < 2 ? 180 : 90,
                        effortCue: index == 0 ? "快拉稳接，速度下降或失稳则结束" : "保持动作幅度与稳定"))
            }
            drafts.append(ConfirmedDailyPlanExercise(catalogExerciseID: exercise.id, catalogName: exercise.name,
                equipment: exercise.equipment, volumeUnit: exercise.volumeUnit, displayName: exercise.name + "确认变式",
                loadGuidance: load, notes: "准备组另计；不猜其他机器重量", plannedSets: sets))
        }
        try context.save()
        let source = "# 隔离单日确认\n6动作20组；机器显示口径保留；每组目标与实际分开。"
        return ConfirmedDailyTrainingPlanPacket(version: 1, id: UUID(), localDay: "2026-10-17",
            timeZoneIdentifier: "Asia/Shanghai", title: "隔离周六单日计划", preferenceRevisionCode: week.snapshot.preferenceRevisionCode,
            confirmedAt: week.confirmedAt, confirmationReference: "ISOLATED-DAILY-CONFIRMATION",
            sourceMarkdown: source, sourceSHA256: ConfirmedTrainingPlanService.digest(Data(source.utf8)),
            guidance: "75–90分钟；热身另计；质量下降下调或停止；不续排", exercises: drafts)
    }

    private func ropeWeekRequest(in context: ModelContext, includeRope: Bool = true, startDay: String = "2026-11-02", reviewExistingID: UUID? = nil, reviewFocus: String = "背") throws -> CoachWeekConfirmation {
        if try context.fetchCount(FetchDescriptor<TrainingPreferenceRevision>()) == 0 { _ = try packet(in: context) }
        let start = TrainingLocalDate.date(startDay)!
        let zone = TimeZone.current
        let keys = CoachWeekService.dateKeys(start: start, zone: zone)
        let retainedDay = try CoachWeekService.capture(start: start, exception: nil, in: context).existing.first { $0.id == reviewExistingID }?.localDay
        let goals = keys.enumerated().map { index, key in
            CoachWeekGoal(localDay: key, kind: key == retainedDay ? .strength : includeRope && index == 0 ? .cardio : .rest,
                focus: key == retainedDay ? reviewFocus : includeRope && index == 0 ? "跳绳" : "", reason: "本人明确恢复周及保留安排")
        }
        let exception = CoachWeekException(id: UUID(), startDay: keys[0], endDay: keys[6], reason: "恢复周",
            goals: goals, confirmation: "测试本人完整确认恢复周")
        let coreException = CoachWeekCoreException(startDay: keys[0], endDay: keys[6], reason: "测试本人确认恢复周腹部例外", confirmation: CoachWeekService.coreExceptionConsent, goals: goals)
        let input = try CoachWeekService.capture(start: start, exception: exception, coreException: coreException, in: context)
        let plan = JumpRopeMenuPlan(targetCount: 300, activeSeconds: 180, elapsedSeconds: 360, notes: "按实际完成记录")
        let days = goals.enumerated().map { index, goal in
            CoachWeekDay(localDay: goal.localDay,
                kind: input.existing.contains(where: { $0.localDay == goal.localDay }) ? .preserved : goal.kind,
                title: goal.kind == .rest ? "休息" : "跳绳", focus: goal.focus,
                movements: [], cardio: includeRope && index == 0 ? plan : nil,
                estimatedSeconds: goal.kind == .rest ? 0 : 360, rationale: [goal.reason], blockers: [],
                existing: input.existing.filter { $0.localDay == goal.localDay })
        }
        let checkedDays = CoachWeekService.revalidateWeek(days, input: input)
        var draft = CoachWeekDraft(id: UUID(), rootID: UUID(), revision: 1, createdAt: .now,
            sourceFingerprint: try CoachWeekService.fingerprint(input), input: input, days: checkedDays,
            edits: [], ruleCandidates: [], weeklyShortfall: CoachWeekService.weeklyShortfalls(checkedDays, input: input))
        try CoachWeekService.save(draft, in: context)
        if let reviewExistingID {
            draft = try CoachWeekService.reviewPreservedArrangement(draft, existingID: reviewExistingID,
                kind: .strength, focus: reviewFocus, reason: "本人核对该具体保留安排为\(reviewFocus)部任务；不补写原实际或恢复", in: context)
        }
        return try CoachWeekService.prepareConfirmation(draft, in: context)
    }

    func testCoachStrengthAndZone2AreIndependentSameDaySchedules() throws {
        let store = try container(), context = store.mainContext
        _ = try packet(in: context)
        let definitions = [("高位下拉", "背部", "器械"), ("坐姿划船", "背部", "器械"),
            ("杠铃划船", "背部", "杠铃"), ("引体向上", "背部", "自重"),
            ("哑铃弯举", "手臂", "哑铃"), ("绳索下压", "手臂", "龙门架")]
        for (name, muscle, equipment) in definitions { context.insert(Exercise(name: name, muscleGroup: muscle, equipment: equipment)) }
        let cycle = Exercise(name: "动感单车", muscleGroup: "心肺", equipment: "单车")
        cycle.volumeUnit = .second
        context.insert(cycle); try context.save()
        let start = TrainingLocalDate.date("2026-11-02")!, zone = TimeZone.current
        let keys = CoachWeekService.dateKeys(start: start, zone: zone)
        let goals = keys.enumerated().map { index, key in
            CoachWeekGoal(localDay: key, kind: index == 0 ? .strength : .rest, focus: index == 0 ? "背" : "", reason: "本人确认同日独立力量与Zone2")
        }
        let exception = CoachWeekException(id: UUID(), startDay: keys[0], endDay: keys[6], reason: "本人完整确认例外周", goals: goals, confirmation: "测试确认")
        let coreException = CoachWeekCoreException(startDay: keys[0], endDay: keys[6], reason: "测试本人确认腹部例外", confirmation: CoachWeekService.coreExceptionConsent, goals: goals)
        let input = try CoachWeekService.capture(start: start, exception: exception, coreException: coreException, in: context)
        let generated = try CoachWeekService.generate(input: input, goals: goals)
        var days = generated.days
        days[0].zone2 = CoachZone2Plan(mode: cycle.name, durationSeconds: 1800, guidance: "独立时段轻松交谈强度", exerciseID: cycle.id)
        XCTAssertTrue(days[0].blockers.isEmpty, days[0].blockers.joined(separator: "；"))
        let draft = CoachWeekDraft(id: generated.id, rootID: generated.rootID, revision: 1, createdAt: generated.createdAt,
            sourceFingerprint: generated.sourceFingerprint, input: input, days: days, edits: [], ruleCandidates: [], weeklyShortfall: [])
        try CoachWeekService.save(draft, in: context)
        let request = try CoachWeekService.prepareConfirmation(draft, in: context)
        XCTAssertEqual(request.members.count, 2)
        XCTAssertEqual(Set(request.members.map { $0.packet.localDay }).count, 1)
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyWeek(expectedPreviews: request.members, in: context))
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        let schedules = try ModelContext(store).fetch(FetchDescriptor<ScheduledWorkout>())
        XCTAssertEqual(schedules.count, 2)
        XCTAssertEqual(schedules.filter { CardioWorkoutPresentation.plan($0) != nil }.count, 1)
    }

    func testCoachRopeOnlyWeekPersistsAdjustsMovesAndRestoresOriginalConfirmation() throws {
        let store = try container(), context = store.mainContext
        let request = try ropeWeekRequest(in: context)
        XCTAssertTrue(request.members.isEmpty)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == request.ropes[0].id })
        let originalDate = schedule.plannedDate
        let expectedCivilDate = try XCTUnwrap(MealLocalDay.date(request.ropes[0].localDay,
            timeZone: try XCTUnwrap(TimeZone(identifier: request.draft.input.timeZone))))
        XCTAssertEqual(originalDate, expectedCivilDate)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutTemplate>()).first { $0.id == schedule.templateID }?.plannedForDate, expectedCivilDate)
        let changed = JumpRopeMenuPlan(targetCount: 400, activeSeconds: 240, elapsedSeconds: 480, notes: "本人调整")
        _ = try TrainingDateMenuService.saveJumpRopePlan(changed, localDay: TrainingScheduleDate.localDay(schedule), editing: schedule, in: context)
        let undo = try ScheduleService.rescheduleManaged(schedule, to: originalDate.addingDays(8), in: context)
        XCTAssertEqual(undo.originalDate, originalDate)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.verifiedRopeSchedule(schedule, in: context)?.plannedDate, schedule.plannedDate)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
        let backup = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: backup), into: restored.mainContext)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: restored.mainContext)
        let recovered = try XCTUnwrap(restored.mainContext.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == schedule.id })
        XCTAssertEqual(recovered.jumpRopePlan, changed)
        XCTAssertEqual(recovered.plannedDate, schedule.plannedDate)
        schedule.plannedDate = schedule.plannedDate.addingDays(1)
        schedule.plannedLocalDay = TrainingLocalDate.key(schedule.plannedDate)
        try context.save()
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context))
    }

    func testCoachRopeWeekRollsBackAllStagedRecordsAndReportsSaveThenThrow() throws {
        let store = try container(), context = store.mainContext
        let request = try ropeWeekRequest(in: context)
        let count = try context.fetchCount(FetchDescriptor<TrainingCoachRecord>())
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context, commit: { _ in
            throw CocoaError(.fileWriteNoPermission)
        }))
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingCoachRecord>()), count)
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context, commit: {
            try $0.save()
            throw CocoaError(.fileWriteNoPermission)
        })) { error in XCTAssertTrue(error.localizedDescription.contains("已提交")) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
    }

    func testCoachWeekReportsCommittedWhenConcurrentScheduleAppearsAfterPrecommitCheck() throws {
        let store = try container(), context = store.mainContext
        let request = try ropeWeekRequest(in: context, includeRope: false)
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context, commit: { staging in
            let other = ModelContext(store)
            let date = TrainingLocalDate.date(request.draft.days[3].localDay)!
            other.insert(ScheduledWorkout(templateID: UUID(), templateName: "并发新增安排", plannedDate: date))
            try other.save()
            try staging.save()
        })) { error in XCTAssertTrue(error.localizedDescription.contains("已提交")) }
        let verification = ModelContext(store)
        XCTAssertTrue(try verification.fetch(FetchDescriptor<TrainingCoachRecord>()).contains { $0.id == request.id })
    }

    func testCoachRopeWeekRejectsUnrecordedTargetMutation() throws {
        let store = try container(), context = store.mainContext
        let request = try ropeWeekRequest(in: context)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        schedule.jumpRopePlan = JumpRopeMenuPlan(targetCount: 999, activeSeconds: nil, elapsedSeconds: nil, notes: "未确认")
        try context.save()
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context))
    }

    func testCoachPreservedDailyScheduleKeepsOriginalPacketIdentityThroughLegalMove() throws {
        let store = try container(), context = store.mainContext
        var packet = try dailyPacket(in: context)
        packet.localDay = "2026-11-02"
        let preview = try ConfirmedDailyTrainingPlanService.preview(packet, in: context)
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        let request = try ropeWeekRequest(in: context, includeRope: false, reviewExistingID: packet.id, reviewFocus: "腿")
        XCTAssertEqual(request.draft.input.existing.first { $0.id == packet.id }?.confirmedPacketDigest, preview.packetSHA256)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == packet.id })
        _ = try ScheduleService.rescheduleManaged(schedule, to: schedule.plannedDate.addingDays(8), in: context)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
        var changed = schedule.planSnapshot
        changed[0].plannedSets[0].weight += 1
        schedule.planSnapshot = changed
        try context.save()
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context))
    }

    func testCoachInProgressBaselineAllowsAppendAndCompletionButProtectsCompletedActuals() throws {
        let store = try container(), context = store.mainContext
        let date = Date.now.startOfDay
        let session = WorkoutSession(templateName: "进行中训练", plannedDate: date)
        session.trainingLocalDay = TrainingLocalDate.key(date)
        session.trainingTimeZoneIdentifier = TimeZone.current.identifier
        let exerciseID = UUID()
        let item = SessionExercise(sessionID: session.id, exerciseID: exerciseID, exerciseName: "测试动作", order: 0,
            targetSets: 2, minReps: 8, maxReps: 10, targetWeight: 10, restSeconds: 90, equipmentSnapshot: "哑铃")
        let completed = SetLog(sessionID: session.id, sessionExerciseID: item.id, exerciseID: exerciseID,
            setNumber: 1, targetWeight: 10, targetReps: 8, actualWeight: 10, actualReps: 8, isCompleted: true)
        let unfinished = SetLog(sessionID: session.id, sessionExerciseID: item.id, exerciseID: exerciseID,
            setNumber: 2, targetWeight: 10, targetReps: 8, actualWeight: 0, actualReps: 0, isCompleted: false)
        context.insert(session); context.insert(item); context.insert(completed); context.insert(unfinished); try context.save()
        let request = try ropeWeekRequest(in: context, includeRope: false, startDay: TrainingLocalDate.key(date), reviewExistingID: session.id)
        XCTAssertNotNil(request.draft.input.existing.first { $0.id == session.id }?.actualBaselineJSON)
        XCTAssertTrue(request.draft.input.retainedReviews?.contains { $0.existingID == session.id } == true)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        unfinished.actualWeight = 10; unfinished.actualReps = 9; unfinished.isCompleted = true
        let additional = SetLog(sessionID: session.id, sessionExerciseID: item.id, exerciseID: exerciseID,
            setNumber: 3, targetWeight: 10, targetReps: 8, actualWeight: 10, actualReps: 8, isCompleted: true)
        context.insert(additional)
        session.status = .completed; session.completedAt = .now
        try context.save()
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        completed.actualReps += 1; try context.save()
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context))
    }

    func testCoachBackupRestoresValidActivationAndRollbackChain() throws {
        let store = try container(), context = store.mainContext
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let definitions = [("双滑轮高位下拉", "背部", "双滑轮器械"), ("双滑轮低位划船", "背部", "双滑轮器械"),
            ("胸托T-Bar划船", "背部", "胸托T-Bar划船机"), ("直臂下压", "背部", "龙门架"),
            ("哑铃弯举", "手臂", "哑铃"), ("锤式弯举", "手臂", "哑铃"), ("高位下拉", "背部", "器械")]
        let catalog = definitions.map { name, muscle, equipment in
            let role = CoachWeekService.roleEvidence(name: name, equipment: equipment, canonicalID: nil, ruleMethod: CoachWeekService.legacyMethodVersion)
            return CoachWeekCatalogItem(id: UUID(), name: name, muscle: muscle, equipment: equipment, unit: .kilogram,
                approvedCanonicalID: nil, approvedName: nil, archived: false, roles: role.roles, roleSource: role.source)
        }
        let dates = CoachWeekService.dateKeys(start: TrainingLocalDate.date("2026-10-26", timeZone: zone)!, zone: zone)
        let goals = dates.map { CoachWeekGoal(localDay: $0, kind: $0 == "2026-10-28" ? .strength : .rest,
            focus: $0 == "2026-10-28" ? "背" : "", reason: "隔离回放目标") }
        let exception = CoachWeekException(id: UUID(), startDay: dates[0], endDay: dates[6], reason: "隔离目标", goals: goals, confirmation: "测试")
        let repeated = catalog[0]
        let actual = CoachWeekActual(id: UUID(), sessionID: UUID(), localDay: "2026-10-25", exerciseID: repeated.id,
            name: repeated.name, equipment: repeated.equipment, unit: .kilogram, plannedSets: [],
            actual: [CoachActualSet(id: UUID(), weight: 20, reps: 10, rir: nil, weightSide: .unknown, repsSide: .unknown, completed: true, warmup: false)],
            feedback: "合成暴露", classificationKnown: false)
        func source(_ version: String) -> CoachWeekInput {
            CoachWeekInput(startDay: dates[0], timeZone: zone.identifier, methodVersion: CoachWeekService.legacyMethodVersion,
                personalRuleVersion: version, preferences: dates.map { CoachWeekPreference(localDay: $0, revisionID: nil, code: "fixture", snapshot: .confirmed) },
                exception: exception, catalog: catalog, history: [actual], existing: [], recovery: [], unknowns: ["合成测试输入"])
        }
        let original = try CoachWeekService.generate(input: source(CoachWeekService.personalRuleVersion), goals: goals)
        let variant = try CoachWeekService.generate(input: source(CoachWeekService.overlapRuleVersion), goals: goals)
        try CoachWeekService.save(original, in: context)
        var revised = original.days
        revised[2] = variant.days[2]
        let edit = CoachWeekEdit(id: UUID(), day: dates[2], field: "动作", before: repeated.name, after: "替换近期重复", reason: "同角色减少同UUID近期重复")
        let candidate = try CoachWeekService.ruleCandidate(original: original, revisedDays: revised, edits: [edit])
        XCTAssertEqual(candidate.executableVersion, CoachWeekService.overlapRuleVersion, candidate.replayResult)
        let saved = try CoachWeekService.revise(original, days: revised, edits: [edit], candidates: [candidate], in: context)
        _ = try CoachWeekService.activateRuleCandidate(candidate, draft: saved, in: context)
        let file = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: file) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: file), into: restored.mainContext)
        XCTAssertEqual(try CoachWeekService.activeRuleVersion(in: restored.mainContext), CoachWeekService.overlapRuleVersion)
        XCTAssertEqual(try CoachWeekService.rollbackRule(in: restored.mainContext), CoachWeekService.personalRuleVersion)
        let rollbackFile = try DataExportService.createBackup(in: restored.mainContext)
        defer { try? FileManager.default.removeItem(at: rollbackFile) }
        let second = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: rollbackFile), into: second.mainContext)
        XCTAssertEqual(try CoachWeekService.activeRuleVersion(in: second.mainContext), CoachWeekService.personalRuleVersion)
    }

    func testLegacyCompletedActualReadbackIgnoresNewRoleInferenceButDetectsChangedSets() throws {
        let store = try container(), context = store.mainContext
        _ = try packet(in: context)
        let now = Date.now, zone = TimeZone.current
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = zone
        let start = try XCTUnwrap(calendar.dateInterval(of: .weekOfYear, for: now)?.start)
        let session = WorkoutSession(templateName: "合成旧版已完成", plannedDate: now, completedAt: now, status: .completed)
        session.trainingLocalDay = TrainingLocalDate.key(now, timeZone: zone)
        session.trainingTimeZoneIdentifier = zone.identifier
        let exerciseID = UUID()
        let exercise = SessionExercise(sessionID: session.id, exerciseID: exerciseID, exerciseName: "绳索卷腹", order: 0,
            targetSets: 1, minReps: 8, maxReps: 10, targetWeight: 10, restSeconds: 90, muscleGroup: "核心", equipmentSnapshot: "龙门架")
        let set = SetLog(sessionID: session.id, sessionExerciseID: exercise.id, exerciseID: exerciseID,
            setNumber: 1, targetWeight: 10, targetReps: 8, actualWeight: 10, actualReps: 8, isCompleted: true)
        context.insert(session); context.insert(exercise); context.insert(set); try context.save()
        let current = try CoachWeekService.capture(start: start, exception: nil, in: context)
        let currentActual = try XCTUnwrap(current.existing.first { $0.id == session.id })
        XCTAssertTrue(currentActual.frozenExercises?.first?.roles.contains("腹部") == true)
        let legacyFrozen = (currentActual.frozenExercises ?? []).map {
            CoachWeekFrozenExercise(exerciseID: $0.exerciseID, name: $0.name, muscle: $0.muscle, equipment: $0.equipment, roles: [], plannedSets: $0.plannedSets)
        }
        let legacyActual = CoachWeekExisting(id: currentActual.id, localDay: currentActual.localDay, title: currentActual.title,
            status: currentActual.status, source: currentActual.source, contentDigest: currentActual.contentDigest,
            confirmedPacketDigest: currentActual.confirmedPacketDigest, actualBaselineJSON: currentActual.actualBaselineJSON,
            exerciseIDs: currentActual.exerciseIDs, knownCardio: currentActual.knownCardio, cardioMode: currentActual.cardioMode,
            frozenExercises: legacyFrozen)
        let review = CoachWeekRetainedReview(id: UUID(), existingID: session.id, localDay: legacyActual.localDay,
            sourceDigest: try ConfirmedTrainingPlanService.digest(legacyActual), kind: .strength, focus: "背", reason: "合成测试本人核对", confirmedAt: now)
        let dates = current.preferences.map(\.localDay)
        let goals = dates.map { CoachWeekGoal(localDay: $0, kind: $0 == legacyActual.localDay ? .strength : .rest,
            focus: $0 == legacyActual.localDay ? "背" : "", reason: "旧版合成例外") }
        let exception = CoachWeekException(id: UUID(), startDay: dates[0], endDay: dates[6], reason: "旧版合成例外", goals: goals, confirmation: "测试确认")
        let input = CoachWeekInput(startDay: current.startDay, timeZone: current.timeZone, methodVersion: CoachWeekService.legacyMethodVersion,
            personalRuleVersion: CoachWeekService.personalRuleVersion, preferences: current.preferences, exception: exception,
            catalog: current.catalog, history: current.history, existing: [legacyActual], recovery: current.recovery,
            unknowns: current.unknowns, retainedReviews: [review])
        let draft = try CoachWeekService.generate(input: input, goals: goals, now: now)
        XCTAssertTrue((draft.weeklyShortfall ?? []).isEmpty)
        let members: [ConfirmedDailyTrainingPlanPreview] = [], ropes: [CoachWeekRopeMember] = []
        let dayDigests = try Dictionary(uniqueKeysWithValues: draft.days.map { ($0.localDay, try ConfirmedTrainingPlanService.digest($0)) })
        let requestID = UUID()
        let digest = try ConfirmedTrainingPlanService.digest([try ConfirmedTrainingPlanService.digest(draft),
            try ConfirmedTrainingPlanService.digest(members), try ConfirmedTrainingPlanService.digest(ropes),
            try ConfirmedTrainingPlanService.digest(dayDigests), requestID.uuidString])
        let request = CoachWeekConfirmation(id: requestID, draft: draft, confirmedAt: now, members: members, ropes: ropes, dayDigests: dayDigests, requestDigest: digest)
        try TrainingCoachService.append(request, kind: "week_confirmation", sessionID: draft.rootID, id: request.id, in: context)
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .committed)
        exercise.muscleGroup = "胸部"; try context.save()
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .unknown)
        exercise.muscleGroup = "核心"; try context.save()
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .committed)
        set.actualReps += 1; try context.save()
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .unknown)
    }

    func testCoachBackupRejectsOrphanRuleActivationBeforeSaving() throws {
        for digest in ["x", String(repeating: "a", count: 64)] {
            let source = try container(), context = source.mainContext
            let activation = CoachWeekRuleActivation(id: UUID(), version: CoachWeekService.overlapRuleVersion,
                previousVersion: CoachWeekService.personalRuleVersion, candidateID: nil, sourceDraftID: UUID(),
                replayFingerprint: digest, createdAt: .now)
            context.insert(TrainingCoachRecord(id: activation.id,
                sessionID: UUID(uuidString: "78283952-B6AC-4B03-B215-76864BE804D1")!, kind: "week_rule_activation",
                payloadJSON: try TrainingCoachService.encode(activation), sequence: 1))
            try context.save()
            let file = try DataExportService.createBackup(in: context)
            defer { try? FileManager.default.removeItem(at: file) }
            let destination = try container()
            XCTAssertThrowsError(try DataExportService.importBackup(Data(contentsOf: file), into: destination.mainContext))
            XCTAssertEqual(try ModelContext(destination).fetchCount(FetchDescriptor<TrainingCoachRecord>()), 0)
        }
    }

    func testCoachRequestAuditRequiresIndependentAbsenceAndRejectsPartialArtifacts() throws {
        let store = try container(), context = store.mainContext
        let request = try ropeWeekRequest(in: context)
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .safelyAbsent)
        let partial = ScheduledWorkout(id: request.ropes[0].id, templateID: UUID(), templateName: "部分", plannedDate: .now)
        context.insert(partial)
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .unknown)
        try context.save()
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .unknown)
        context.delete(partial); try context.save()
        var other = request
        other.id = UUID()
        let intersecting = TrainingCoachRecord(id: other.id, sessionID: other.draft.rootID, kind: "week_confirmation",
            payloadJSON: try TrainingCoachService.encode(other))
        context.insert(intersecting); try context.save()
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .unknown)
        context.delete(intersecting); try context.save()
        let malformed = TrainingCoachRecord(sessionID: request.draft.rootID, kind: "week_rope_origin", payloadJSON: "broken")
        context.insert(malformed); try context.save()
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .unknown)
        context.delete(malformed); try context.save()
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .safelyAbsent)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        XCTAssertEqual(ConfirmedDailyTrainingPlanService.auditCoachWeekRequest(request, in: context), .committed)
    }

    func testCoachNoNewSchedulesPersistsConfirmationAndFailedCommitRollsBack() throws {
        let store = try container(), context = store.mainContext
        let request = try ropeWeekRequest(in: context, includeRope: false)
        XCTAssertTrue(request.members.isEmpty && request.ropes.isEmpty)
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context, commit: { _ in }))
        XCTAssertFalse(context.hasChanges)
        XCTAssertFalse(try context.fetch(FetchDescriptor<TrainingCoachRecord>()).contains { $0.id == request.id })
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        try ConfirmedDailyTrainingPlanService.applyCoachWeek(request, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingCoachRecord>()).filter { $0.id == request.id }.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
    }

    func testAtomicDailyPacketsPreserveExactPlansAndRepeat() throws {
        let store = try container(), context = store.mainContext
        let first = try dailyPacket(in: context)
        var second = first
        second.id = UUID(); second.localDay = "2026-10-18"
        second.exercises[0].planPattern = .pyramidUp
        let previews = try [first, second].map { try ConfirmedDailyTrainingPlanService.preview($0, in: context) }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
        let result = try ConfirmedDailyTrainingPlanService.applyWeek(expectedPreviews: previews, in: context)
        XCTAssertEqual(result.map(\.packet), [first, second])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 2)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.applyWeek(expectedPreviews: previews, in: context), result)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 2)
    }

    func testAtomicDailyPacketsRejectStaleOrPartialDestination() throws {
        let store = try container(), context = store.mainContext
        let first = try dailyPacket(in: context)
        var second = first
        second.id = UUID(); second.localDay = "2026-10-18"
        let previews = try [first, second].map { try ConfirmedDailyTrainingPlanService.preview($0, in: context) }
        let conflicting = ScheduledWorkout(templateID: UUID(), templateName: "保留", plannedDate: FatLossCalendar.date(2026, 10, 18))
        context.insert(conflicting); try context.save()
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyWeek(expectedPreviews: previews, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
        context.delete(conflicting); try context.save()
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: previews[0], in: context)
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyWeek(expectedPreviews: previews, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
    }

    func testAtomicDailyPacketsRollBackWhenCommitDoesNotSave() throws {
        let store = try container(), context = store.mainContext
        let first = try dailyPacket(in: context)
        var second = first
        second.id = UUID(); second.localDay = "2026-10-18"
        let previews = try [first, second].map { try ConfirmedDailyTrainingPlanService.preview($0, in: context) }
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyWeek(expectedPreviews: previews, in: context, commit: { _ in }))
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
    }

    func testAtomicDailyPacketsRollBackWholeBatchOnCommitFailure() throws {
        let store = try container(), context = store.mainContext
        let first = try dailyPacket(in: context)
        var second = first
        second.id = UUID(); second.localDay = "2026-10-18"
        let previews = try [first, second].map { try ConfirmedDailyTrainingPlanService.preview($0, in: context) }
        var reachedCommit = false
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.applyWeek(expectedPreviews: previews, in: context, commit: { _ in
            reachedCommit = true
            throw CocoaError(.fileWriteNoPermission)
        }))
        XCTAssertTrue(reachedCommit)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TemplateExercise>()), 0)
        XCTAssertFalse(context.hasChanges)
    }

    func testSingleDayPreservesTwentySetPrescriptionsOtherDatesAndBlankActuals() throws {
        let store = try container(), context = store.mainContext
        let input = try dailyPacket(in: context)
        let other = ScheduledWorkout(templateID: UUID(), templateName: "其他日保留", plannedDate: FatLossCalendar.date(2026, 10, 18))
        context.insert(other)
        try context.save()
        let preferences = try context.fetchCount(FetchDescriptor<TrainingPreferenceRevision>())
        let revisions = try context.fetchCount(FetchDescriptor<TrainingProgramRevision>())
        let preview = try ConfirmedDailyTrainingPlanService.preview(input, in: context)
        XCTAssertEqual(preview.newScheduleCount, 1)
        XCTAssertTrue(preview.conflicts.isEmpty)
        XCTAssertFalse(context.hasChanges)
        let result = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(result.newScheduleCount, 1)
        XCTAssertEqual(result.readback.packet, input)
        XCTAssertEqual(result.readback.schedule.localDay, "2026-10-17")
        XCTAssertEqual(result.readback.schedule.timeZoneIdentifier, "Asia/Shanghai")
        let snapshots = result.readback.schedule.exercises
        XCTAssertEqual(snapshots.map(\.targetSets), [4, 4, 3, 3, 3, 3])
        for (snapshot, draft) in zip(snapshots, input.exercises) {
            XCTAssertEqual(snapshot.plannedSets, draft.plannedSets)
            XCTAssertEqual(snapshot.exerciseID, draft.catalogExerciseID)
            XCTAssertEqual(snapshot.exerciseName, draft.displayName)
            XCTAssertTrue(snapshot.exerciseNotes.contains(draft.loadGuidance))
            XCTAssertTrue(snapshot.exerciseNotes.contains(input.guidance))
        }
        XCTAssertTrue(snapshots[3].plannedSets.allSatisfy { $0.weight == 0 && $0.prescription!.summary.contains("20–25") })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingPreferenceRevision>()), preferences)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingProgramRevision>()), revisions)
        let repeated = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(repeated.newScheduleCount, 0)
        XCTAssertEqual(repeated.readback, result.readback)
        XCTAssertEqual(other.templateName, "其他日保留")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 2)
        // Exercise the real start path only in this isolated in-memory store.
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == input.id })
        _ = try WorkoutService.start(schedule: schedule, in: context)
        let logs = try context.fetch(FetchDescriptor<SetLog>())
        XCTAssertEqual(logs.count, 20)
        XCTAssertTrue(logs.allSatisfy { !$0.isCompleted && $0.actualEntrySource == .blank && $0.isActualWeightBlank && $0.actualReps == 0 && $0.rir == nil })
        XCTAssertEqual(logs.filter { $0.targetWeight == 15 }.count, 7)
        let activeExercise = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first)
        try WorkoutService.restorePlanDefaults(for: activeExercise, in: context)
        XCTAssertTrue(logs.allSatisfy { $0.actualReps == 0 && !$0.isCompleted && $0.actualEntrySource == .blank })
    }

    func testSingleDayConflictsAndChangedPreviewDoNotOverwrite() throws {
        for change in 0..<5 {
            let store = try container(), context = store.mainContext
            let input = try dailyPacket(in: context)
            let preview = try ConfirmedDailyTrainingPlanService.preview(input, in: context)
            if change == 0 {
                context.insert(ScheduledWorkout(templateID: UUID(), templateName: "他人新安排", plannedDate: FatLossCalendar.date(2026, 10, 17)))
            } else if change == 1 {
                let session = WorkoutSession(templateName: "当日实际", plannedDate: FatLossCalendar.date(2026, 10, 17),
                    startedAt: FatLossCalendar.date(2026, 10, 17))
                session.trainingLocalDay = "2026-10-17"
                session.trainingTimeZoneIdentifier = "Asia/Shanghai"
                context.insert(session)
            } else if change == 2 {
                let row = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.id == input.exercises[0].catalogExerciseID })
                row.equipment = "不同器械"
            } else if change == 3 {
                let row = try XCTUnwrap(context.fetch(FetchDescriptor<Exercise>()).first { $0.id == input.exercises[0].catalogExerciseID })
                row.referenceURL = "https://example.invalid/changed-after-preview"
            } else {
                var pref = try XCTUnwrap(TrainingPreferenceService.current(in: context)?.snapshot)
                pref.revisionCode = "TP-NEW-AFTER-PREVIEW"
                _ = try TrainingPreferenceService.append(snapshot: pref, effectiveAt: FatLossCalendar.date(2026, 10, 16), reason: "隔离变更", in: context)
            }
            try context.save()
            XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context), "change=\(change)")
            XCTAssertFalse(try context.fetch(FetchDescriptor<ScheduledWorkout>()).contains { $0.id == input.id }, "change=\(change)")
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testSingleDayCommitFailureRollsBackAndModifiedSnapshotFailsReadback() throws {
        let store = try container(), context = store.mainContext
        let input = try dailyPacket(in: context)
        let preview = try ConfirmedDailyTrainingPlanService.preview(input, in: context)
        let templateCount = try context.fetchCount(FetchDescriptor<WorkoutTemplate>())
        var reachedCommit = false
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context, commit: { _ in
            reachedCommit = true
            throw CocoaError(.fileWriteNoPermission)
        }))
        XCTAssertTrue(reachedCommit)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TemplateExercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()), templateCount)
        XCTAssertFalse(context.hasChanges)
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        var changed = input
        changed.exercises[0].plannedSets[0].weight = 25
        XCTAssertFalse(try ConfirmedDailyTrainingPlanService.preview(changed, in: context).conflicts.isEmpty)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        var snapshots = schedule.planSnapshot
        snapshots[0].plannedSets[0].weight += 1
        schedule.planSnapshot = snapshots
        try context.save()
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.readback(id: input.id, in: context))
    }

    func testSingleDayRejectsIncompleteTargetsUnconfirmedActualsAndChangedSource() throws {
        let store = try container(), context = store.mainContext
        let input = try dailyPacket(in: context)
        for variant in 0..<4 {
            var changed = input
            if variant == 0 { changed.sourceMarkdown += "未确认变更" }
            if variant == 1 { changed.exercises[0].plannedSets[0].prescription = nil }
            if variant == 2 { changed.exercises[0].plannedSets[0].actualDefaultPolicyRaw = "plan" }
            if variant == 3 { changed.exercises[0].plannedSets[0].prescription?.repsUpper = 0 }
            XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.preview(changed, in: context))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testManagedSingleDayRescheduleKeepsOriginalSealRetryAndBackupButRejectsUnrecordedDrift() throws {
        let store = try container(), context = store.mainContext
        let input = try dailyPacket(in: context)
        let preview = try ConfirmedDailyTrainingPlanService.preview(input, in: context)
        let first = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == input.id })
        let originalSource = try XCTUnwrap(schedule.confirmedDailyImportJSON)
        let originalObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(originalSource.utf8)) as? [String: Any])
        let frozen = schedule.planSnapshotJSON
        let token = try ScheduleService.rescheduleManaged(schedule, to: schedule.plannedDate.addingDays(1), in: context)
        XCTAssertEqual(token.scheduleID, input.id)
        XCTAssertEqual(token.originalDate, first.readback.schedule.plannedDate)
        let moved = try XCTUnwrap(ConfirmedDailyTrainingPlanService.readback(id: input.id, in: context))
        XCTAssertEqual(moved.packet, first.readback.packet)
        XCTAssertEqual(moved.packetSHA256, first.readback.packetSHA256)
        XCTAssertEqual(moved.schedule.plannedDate, token.newDate)
        XCTAssertEqual(schedule.plannedDate, MealLocalDay.date(try XCTUnwrap(schedule.plannedLocalDay),
            timeZone: try XCTUnwrap(TimeZone(identifier: try XCTUnwrap(schedule.plannedTimeZoneIdentifier)))))
        XCTAssertEqual(schedule.planSnapshotJSON, frozen)
        let changedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(schedule.confirmedDailyImportJSON).utf8)) as? [String: Any])
        XCTAssertEqual(changedObject["scheduleIntegritySHA256"] as? String, originalObject["scheduleIntegritySHA256"] as? String)
        XCTAssertEqual(changedObject["packetSHA256"] as? String, originalObject["packetSHA256"] as? String)
        XCTAssertNotNil(changedObject["scheduleAdjustmentsJSON"])
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
        let backup = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: backup), into: restored.mainContext)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: input.id, in: restored.mainContext), moved)
        schedule.plannedDate = schedule.plannedDate.addingDays(1)
        schedule.plannedLocalDay = TrainingLocalDate.key(schedule.plannedDate)
        try context.save()
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.readback(id: input.id, in: context))
    }

    func testLegacyWeeklyRescheduleKeepsOriginalSealRetryAndBackupButRejectsUnrecordedDrift() throws {
        let store = try container(), context = store.mainContext
        let input = try packet(in: context)
        let preview = try ConfirmedTrainingPlanService.preview(input, in: context)
        let first = try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context)
        let id = try XCTUnwrap(first.readback.scheduleIDs.first)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == id })
        let originalSeal = first.readback.snapshot.confirmedImport?.scheduleIntegritySHA256
        // Exercise the existing calendar entry too, not only the new management API.
        try ScheduleService.reschedule(schedule, to: schedule.plannedDate.addingDays(8), in: context)
        let moved = try XCTUnwrap(ConfirmedTrainingPlanService.readback(code: input.snapshot.code, in: context))
        XCTAssertEqual(moved.snapshot.confirmedImport?.scheduleIntegritySHA256, originalSeal)
        XCTAssertEqual(moved.snapshot.confirmedImport?.packetSHA256, first.readback.snapshot.confirmedImport?.packetSHA256)
        XCTAssertEqual(moved.schedules.first?.plannedDate, schedule.plannedDate)
        XCTAssertEqual(schedule.plannedDate, MealLocalDay.date(try XCTUnwrap(schedule.plannedLocalDay), timeZone: .current))
        XCTAssertEqual(try ConfirmedTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 0)
        let backup = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: backup), into: restored.mainContext)
        XCTAssertEqual(try ConfirmedTrainingPlanService.readback(code: input.snapshot.code, in: restored.mainContext), moved)
        var changed = schedule.planSnapshot
        changed[0].plannedSets[0].weight += 1
        schedule.planSnapshot = changed
        try context.save()
        XCTAssertThrowsError(try ConfirmedTrainingPlanService.readback(code: input.snapshot.code, in: context))
    }

    func testConfirmedRescheduleUsesSelectedCivilDayAndZoneAcrossDSTAndUndo() throws {
        for zoneID in ["America/Los_Angeles", "Pacific/Kiritimati"] {
            let store = try container(), context = store.mainContext
            let input = try dailyPacket(in: context)
            let preview = try ConfirmedDailyTrainingPlanService.preview(input, in: context)
            let first = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
            let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == input.id })
            let before = ScheduleManagementState(schedule)
            let zone = try XCTUnwrap(TimeZone(identifier: zoneID))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            // Los Angeles changes offset later this day; Kiritimati's selected date is
            // a different UTC day. Neither case may inherit the host's calendar zone.
            let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0, minute: 30)))
            let targetDay = "2026-11-01"
            let blocker = ScheduledWorkout(templateID: UUID(), templateName: "目标日另一力量", plannedDate: selected)
            blocker.plannedLocalDay = targetDay
            blocker.plannedTimeZoneIdentifier = zoneID
            context.insert(blocker); try context.save()
            XCTAssertThrowsError(try ScheduleService.validateManagedReschedule(schedule, to: selected, timeZone: zone, in: context)) {
                XCTAssertEqual($0 as? ScheduleServiceError, .occupiedDay)
            }
            blocker.status = .skipped; try context.save()
            try ScheduleService.validateManagedReschedule(schedule, to: selected, timeZone: zone, in: context)
            XCTAssertEqual(ScheduleManagementState(schedule), before, "Preview must not write source or dates")
            XCTAssertFalse(context.hasChanges)
            let token = try ScheduleService.rescheduleManaged(schedule, to: selected, timeZone: zone, in: context)
            let expectedDate = try XCTUnwrap(MealLocalDay.date(targetDay, timeZone: zone))
            XCTAssertEqual(schedule.plannedDate, expectedDate)
            XCTAssertEqual(schedule.plannedLocalDay, targetDay)
            XCTAssertEqual(schedule.plannedTimeZoneIdentifier, zoneID)
            XCTAssertEqual(schedule.originalPlannedDate, before.plannedDate)
            let moved = try XCTUnwrap(ConfirmedDailyTrainingPlanService.readback(id: input.id, in: context))
            XCTAssertEqual(moved.packet, first.readback.packet)
            XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 0)
            // The strict action check still rejects a same-day instant that is not the
            // canonical date anchor; fixing the writer must not weaken this assertion.
            var invalid = moved.schedule
            invalid.plannedDate = expectedDate.addingTimeInterval(60)
            XCTAssertThrowsError(try ConfirmedTrainingPlanService.addingAdjustment(kind: "reschedule",
                before: moved.schedule, after: invalid, to: nil))
            try ScheduleService.undoManaged(token, in: context)
            XCTAssertEqual(schedule.plannedDate, before.plannedDate)
            XCTAssertEqual(schedule.plannedLocalDay, before.plannedLocalDay)
            XCTAssertEqual(schedule.plannedTimeZoneIdentifier, before.plannedTimeZoneIdentifier)
            XCTAssertEqual(schedule.originalPlannedDate, before.originalPlannedDate)
            XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: input.id, in: context)?.packet, first.readback.packet)
            XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 0)
        }
    }

    func testManagementRejectsMissingLinkedRevisionOrUndecodableSourceSnapshot() throws {
        for missingRevision in [true, false] {
            let store = try container(), context = store.mainContext
            let input = try packet(in: context)
            let result = try ConfirmedTrainingPlanService.apply(
                expectedPreview: ConfirmedTrainingPlanService.preview(input, in: context), in: context)
            let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == result.readback.scheduleIDs.first })
            let revision = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingProgramRevision>()).first { $0.id == result.readback.revisionID })
            if missingRevision { context.delete(revision) }
            else { revision.snapshotJSON = "{}" }
            try context.save()
            let before = ScheduleManagementState(schedule)
            XCTAssertThrowsError(try ConfirmedTrainingPlanService.captureScheduleAdjustment(schedule, in: context))
            XCTAssertThrowsError(try ScheduleService.validateManagedReschedule(schedule, to: schedule.plannedDate.addingDays(8), in: context))
            XCTAssertThrowsError(try ScheduleService.rescheduleManaged(schedule, to: schedule.plannedDate.addingDays(8), in: context))
            XCTAssertThrowsError(try ScheduleService.skipManaged(schedule, reason: "临时有事", in: context))
            XCTAssertEqual(ScheduleManagementState(schedule), before)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testExplicitSingleDayEditCopiesTemplateAndPreservesSiblingActualAndConfirmedOriginal() throws {
        let store = try container(), context = store.mainContext
        let input = try dailyPacket(in: context)
        let preview = try ConfirmedDailyTrainingPlanService.preview(input, in: context)
        let first = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == input.id })
        let oldTemplateID = schedule.templateID
        let oldTemplate = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutTemplate>()).first { $0.id == oldTemplateID })
        let oldItems = try context.fetch(FetchDescriptor<TemplateExercise>()).filter { $0.templateID == oldTemplateID }
        let oldItemIDs = Set(oldItems.map(\.id))
        let oldSets = oldItems.map(\.plannedSets)
        let sibling = ScheduledWorkout(templateID: oldTemplateID, templateName: "同日另一力量安排",
            plannedDate: schedule.plannedDate, isManuallyScheduled: true, planSnapshot: schedule.planSnapshot)
        let actual = WorkoutSession(scheduledWorkoutID: sibling.id, templateName: sibling.templateName, plannedDate: sibling.plannedDate)
        context.insert(sibling); context.insert(actual); try context.save()
        let siblingBefore = ScheduleManagementState(sibling)
        let actualID = actual.id, templateName = oldTemplate.name
        let inputs = schedule.planSnapshot.enumerated().map { index, row in
            var plans = row.plannedSets
            if index == 0 { plans[0].weight += 1 }
            return DailyPlanExerciseInput(exerciseID: row.exerciseID, plannedSets: plans,
                planPattern: row.planPattern, patternSource: row.patternSource, restSeconds: row.restSeconds)
        }
        let updated = try DailyPlanService.update(scheduleID: schedule.id, muscleGroups: ["腿部", "核心"],
            defaultPlanPattern: .pyramidUp, exercises: inputs, in: context)
        XCTAssertEqual(updated.id, input.id)
        XCTAssertNotEqual(updated.templateID, oldTemplateID)
        XCTAssertEqual(ScheduleManagementState(sibling), siblingBefore)
        XCTAssertEqual(oldTemplate.name, templateName)
        let retainedItems = try context.fetch(FetchDescriptor<TemplateExercise>()).filter { $0.templateID == oldTemplateID }
        XCTAssertEqual(Set(retainedItems.map(\.id)), oldItemIDs)
        XCTAssertEqual(oldItems.map(\.plannedSets), oldSets)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.id), [actualID])
        let readback = try XCTUnwrap(ConfirmedDailyTrainingPlanService.readback(id: input.id, in: context))
        XCTAssertEqual(readback.packet, first.readback.packet)
        XCTAssertEqual(readback.schedule.exercises[0].plannedSets[0].weight, first.readback.schedule.exercises[0].plannedSets[0].weight + 1)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 0,
            "A repeat cannot delete the edited occurrence or recreate its original date, even with another same-day plan")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 2)
        let backup = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: backup), into: restored.mainContext)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: input.id, in: restored.mainContext), readback)
    }

    func testSkipAllowsDiscardedEmptyDraftWithoutChangingItsRecordsOrConfirmedSource() throws {
        for managed in [false, true] {
            let store = try container(), context = store.mainContext
            let input = try dailyPacket(in: context)
            _ = try ConfirmedDailyTrainingPlanService.apply(
                expectedPreview: ConfirmedDailyTrainingPlanService.preview(input, in: context), in: context)
            let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == input.id })
            let sessionID = try WorkoutService.start(schedule: schedule, in: context)
            let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == sessionID })
            try WorkoutService.discard(session: session, schedules: [schedule], in: context)
            let logs = try context.fetch(FetchDescriptor<SetLog>()).sorted { $0.id.uuidString < $1.id.uuidString }
            XCTAssertFalse(logs.isEmpty)
            XCTAssertTrue(logs.allSatisfy { !$0.isCompleted })
            let ids = logs.map(\.id), weights = logs.map(\.actualWeight), reps = logs.map(\.actualReps)
            let source = schedule.confirmedDailyImportJSON, plan = schedule.planSnapshotJSON
            let discardedAt = session.completedAt
            if managed { _ = try ScheduleService.skipManaged(schedule, reason: "Notes实际替代，原处方保留", in: context) }
            else { try ScheduleService.skip(schedule, reason: "Notes实际替代，原处方保留", in: context) }
            XCTAssertEqual(schedule.status, .skipped)
            XCTAssertEqual(schedule.skipReason, "Notes实际替代，原处方保留")
            XCTAssertEqual(schedule.confirmedDailyImportJSON, source)
            XCTAssertEqual(schedule.planSnapshotJSON, plan)
            XCTAssertEqual(session.status, .discarded)
            XCTAssertEqual(session.completedAt, discardedAt)
            let after = try context.fetch(FetchDescriptor<SetLog>()).sorted { $0.id.uuidString < $1.id.uuidString }
            XCTAssertEqual(after.map(\.id), ids); XCTAssertEqual(after.map(\.actualWeight), weights)
            XCTAssertEqual(after.map(\.actualReps), reps); XCTAssertTrue(after.allSatisfy { !$0.isCompleted })
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
            XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: input.id, in: context)?.packet, input)
            XCTAssertFalse(ScheduleService.canManage(schedule, in: context), "改期资格不因允许跳过而放开")
            XCTAssertThrowsError(try ScheduleService.rescheduleManaged(schedule, to: schedule.plannedDate.addingDays(1), in: context))
            XCTAssertThrowsError(try ScheduleService.restoreManaged(schedule, in: context))
        }
    }

    func testSkipRejectsActiveCompletedOrDiscardedWithAnyCompletedSet() throws {
        for scenario in 0..<5 {
            let store = try container(), context = store.mainContext
            let schedule = ScheduledWorkout(templateID: UUID(), templateName: "原处方", plannedDate: .now)
            let session = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: "原处方", plannedDate: .now,
                status: scenario == 0 ? .inProgress : scenario == 1 ? .completed : .discarded)
            let exerciseID = UUID(), snapshotID = UUID()
            let log = SetLog(sessionID: session.id, sessionExerciseID: snapshotID, exerciseID: exerciseID,
                setNumber: 1, targetWeight: 20, targetReps: 10, actualWeight: 20, actualReps: 10,
                isWarmup: scenario == 3, isCompleted: scenario == 2 || scenario == 3)
            context.insert(schedule); context.insert(session); context.insert(log)
            if scenario == 4 {
                context.insert(WorkoutSession(scheduledWorkoutID: schedule.id, templateName: "另一活动草稿", plannedDate: .now))
            }
            try context.save()
            let before = ScheduleManagementState(schedule)
            XCTAssertThrowsError(try ScheduleService.skip(schedule, reason: "不应保存", in: context))
            XCTAssertThrowsError(try ScheduleService.skipManaged(schedule, reason: "不应保存", in: context))
            XCTAssertEqual(ScheduleManagementState(schedule), before)
            XCTAssertFalse(context.hasChanges)
        }
    }

    func testSkipDiscardedEmptyDraftStillRejectsLinkedJumpRopeActual() throws {
        let store = try container(), context = store.mainContext
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "原处方", plannedDate: .now)
        let session = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: "原处方", plannedDate: .now, status: .discarded)
        let rope = JumpRopeEntry(count: 50, durationSeconds: 60, date: .now)
        rope.scheduledWorkoutID = schedule.id
        context.insert(schedule); context.insert(session); context.insert(rope); try context.save()
        let before = ScheduleManagementState(schedule)
        XCTAssertThrowsError(try ScheduleService.skipManaged(schedule, reason: "不应保存", in: context))
        XCTAssertEqual(ScheduleManagementState(schedule), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JumpRopeEntry>()), 1)
    }

    func testSkipDiscardedEmptyDraftRollsBackSaveFailure() throws {
        let store = try container(), context = store.mainContext
        let input = try dailyPacket(in: context)
        _ = try ConfirmedDailyTrainingPlanService.apply(
            expectedPreview: ConfirmedDailyTrainingPlanService.preview(input, in: context), in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == input.id })
        let draft = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: schedule.templateName,
            plannedDate: schedule.plannedDate, status: .discarded)
        context.insert(draft); try context.save()
        let before = ScheduleManagementState(schedule)
        var attemptedCommit = false
        XCTAssertThrowsError(try ScheduleService.skipManaged(schedule, reason: "不应保存", in: context,
            commit: { _ in attemptedCommit = true; throw CocoaError(.fileWriteNoPermission) }))
        XCTAssertTrue(attemptedCommit)
        XCTAssertEqual(ScheduleManagementState(schedule), before)
        XCTAssertEqual(draft.status, .discarded)
        XCTAssertFalse(context.hasChanges)
    }

    func testManagedActionsRollbackFailuresAndRejectUndoAfterDraftOrLaterMutation() throws {
        let store = try container(), context = store.mainContext
        let input = try dailyPacket(in: context)
        _ = try ConfirmedDailyTrainingPlanService.apply(
            expectedPreview: ConfirmedDailyTrainingPlanService.preview(input, in: context), in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == input.id })
        let original = ScheduleManagementState(schedule)
        XCTAssertThrowsError(try ScheduleService.rescheduleManaged(schedule, to: schedule.plannedDate.addingDays(1), in: context,
            commit: { _ in throw CocoaError(.fileWriteNoPermission) }))
        XCTAssertEqual(ScheduleManagementState(schedule), original)
        XCTAssertFalse(context.hasChanges)
        let token = try ScheduleService.rescheduleManaged(schedule, to: schedule.plannedDate.addingDays(1), in: context)
        let moved = ScheduleManagementState(schedule)
        XCTAssertThrowsError(try ScheduleService.undoManaged(token, in: context,
            commit: { _ in throw CocoaError(.fileWriteNoPermission) }))
        XCTAssertEqual(ScheduleManagementState(schedule), moved)
        XCTAssertFalse(context.hasChanges)
        let draft = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: schedule.templateName,
            plannedDate: schedule.plannedDate)
        draft.status = .discarded
        context.insert(draft); try context.save()
        XCTAssertFalse(ScheduleService.canManage(schedule, in: context))
        XCTAssertThrowsError(try ScheduleService.undoManaged(token, in: context))
        _ = try ScheduleService.skipManaged(schedule, reason: "丢弃空白草稿后跳过", in: context)
        XCTAssertEqual(schedule.status, .skipped)
        let skipped = ScheduleManagementState(schedule)
        XCTAssertThrowsError(try ScheduleService.rescheduleManaged(schedule, to: schedule.plannedDate.addingDays(1), in: context))
        XCTAssertEqual(ScheduleManagementState(schedule), skipped)
        XCTAssertEqual(draft.status, .discarded)
        XCTAssertFalse(context.hasChanges)
    }

    func testManagedRestoreAndUndoRejectNewOccupiedDayAndOldUndoCannotOverwriteLaterEdit() throws {
        let store = try container(), context = store.mainContext
        let template = WorkoutTemplate(name: "测试力量", weekday: Date.now.weekdayNumber, isActive: false, isOneOff: true)
        let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name, plannedDate: .now, isManuallyScheduled: true)
        context.insert(template); context.insert(schedule); try context.save()
        let skip = try ScheduleService.skipManaged(schedule, reason: "临时有事", in: context)
        let other = ScheduledWorkout(templateID: UUID(), templateName: "同日另一力量", plannedDate: schedule.plannedDate, isManuallyScheduled: true)
        context.insert(other); try context.save()
        XCTAssertThrowsError(try ScheduleService.restoreManaged(schedule, in: context))
        XCTAssertThrowsError(try ScheduleService.undoManaged(skip, in: context))
        XCTAssertEqual(schedule.status, .skipped)
        other.status = .skipped; try context.save()
        let restore = try ScheduleService.restoreManaged(schedule, in: context)
        schedule.skipReason = "另一次明确修改"; schedule.updatedAt = .now; try context.save()
        XCTAssertThrowsError(try ScheduleService.undoManaged(restore, in: context))
        XCTAssertEqual(schedule.skipReason, "另一次明确修改")
        XCTAssertFalse(context.hasChanges)
    }

    func testScopedEditFailureRestoresFrozenPlanTemplateAndSource() throws {
        let store = try container(), context = store.mainContext
        let input = try packet(in: context)
        let first = try ConfirmedTrainingPlanService.apply(
            expectedPreview: ConfirmedTrainingPlanService.preview(input, in: context), in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == first.readback.scheduleIDs.first })
        let before = ScheduleManagementState(schedule)
        let templateCount = try context.fetchCount(FetchDescriptor<WorkoutTemplate>())
        let itemCount = try context.fetchCount(FetchDescriptor<TemplateExercise>())
        let inputs = schedule.planSnapshot.map { row in
            DailyPlanExerciseInput(exerciseID: row.exerciseID, plannedSets: row.plannedSets,
                planPattern: row.planPattern, patternSource: row.patternSource, restSeconds: row.restSeconds)
        }
        XCTAssertThrowsError(try DailyPlanService.update(scheduleID: schedule.id, muscleGroups: ["胸部"],
            exercises: inputs, in: context, commit: { _ in throw CocoaError(.fileWriteNoPermission) }))
        XCTAssertEqual(ScheduleManagementState(schedule), before)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()), templateCount)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TemplateExercise>()), itemCount)
        XCTAssertEqual(try ConfirmedTrainingPlanService.readback(code: input.snapshot.code, in: context), first.readback)
        XCTAssertFalse(context.hasChanges)
    }

    func testManagedIndependentCardioCanShareDayWithStrengthButCannotUseStrengthEditor() throws {
        for movingCardio in [true, false] {
            let store = try container(), context = store.mainContext
            let day = Date.now.startOfDay
            let cardioTemplate = WorkoutTemplate(name: "单车", weekday: day.weekdayNumber, isActive: false, isOneOff: true)
            let strengthTemplate = WorkoutTemplate(name: "胸部", weekday: day.weekdayNumber, isActive: false, isOneOff: true)
            let exercise = Exercise(name: "单车", muscleGroup: "心肺", equipment: "单车")
            exercise.volumeUnit = .second
            let plans = [WorkoutSetPlan(weight: 0, reps: 600)]
            let frozen = ScheduledWorkoutExerciseSnapshot(exerciseID: exercise.id, exerciseName: exercise.name,
                muscleGroup: exercise.muscleGroup, equipment: exercise.equipment, exerciseNotes: "", referenceURL: "",
                volumeUnit: .second, order: 0, targetSets: 1, minReps: 600, maxReps: 600, targetWeight: 0,
                restSeconds: 0, plannedSets: plans, planPattern: .fixed, patternSource: .exerciseOverride)
            let cardio = ScheduledWorkout(templateID: cardioTemplate.id, templateName: "单车",
                plannedDate: movingCardio ? day : day.addingDays(1), isManuallyScheduled: true, planSnapshot: [frozen])
            let strength = ScheduledWorkout(templateID: strengthTemplate.id, templateName: "胸部",
                plannedDate: movingCardio ? day.addingDays(1) : day, isManuallyScheduled: true)
            context.insert(cardioTemplate); context.insert(strengthTemplate); context.insert(exercise)
            context.insert(cardio); context.insert(strength); try context.save()
            _ = try ScheduleService.rescheduleManaged(movingCardio ? cardio : strength, to: day.addingDays(1), in: context)
            XCTAssertEqual(TrainingScheduleDate.localDay(cardio), TrainingScheduleDate.localDay(strength))
            XCTAssertThrowsError(try DailyPlanService.update(scheduleID: cardio.id, muscleGroups: ["心肺"],
                exercises: [DailyPlanExerciseInput(exerciseID: exercise.id, plannedSets: plans, planPattern: .fixed, restSeconds: 0)],
                in: context))
            if !movingCardio {
                let actual = WorkoutSession(templateName: "独立力量实际", plannedDate: day.addingDays(2),
                    startedAt: day.addingDays(2).addingTimeInterval(3600))
                context.insert(actual); try context.save()
                XCTAssertThrowsError(try ScheduleService.validateManagedReschedule(strength, to: day.addingDays(2), in: context))
            }
        }
    }

    func testSingleDayBackupRoundTripAndPairedExchangePreserveSource() throws {
        let store = try container(), context = store.mainContext
        let input = try dailyPacket(in: context)
        let documents = URL.documentsDirectory
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var owned: [URL] = []
        defer { for url in owned { try? FileManager.default.removeItem(at: url) } }
        func exchange<T: Encodable>(_ operation: MealExchangeOperation, _ value: T, file: String) throws -> Data {
            let id = UUID(), data = try encoder.encode(value)
            let payload = "daily-test-\(id.uuidString).json", requestName = "daily-request-\(id.uuidString).json"
            let output = documents.appendingPathComponent("MealExchange/\(id.uuidString.lowercased())")
            owned += [documents.appendingPathComponent(payload), documents.appendingPathComponent(requestName), output]
            try data.write(to: documents.appendingPathComponent(payload))
            let request = MealExchangeRequest(version: 1, id: id, operation: operation,
                startLocalDay: nil, endLocalDay: nil, payloadFileName: payload,
                approvedSHA256: ConfirmedTrainingPlanService.digest(data))
            try encoder.encode(request).write(to: documents.appendingPathComponent(requestName))
            _ = try MealExchangeService.processLaunchRequest(arguments: ["--meal-exchange-request=" + requestName], in: context)
            let receipt = try decoder.decode(MealExchangeReceipt.self, from: Data(contentsOf: output.appendingPathComponent("receipt.json")))
            XCTAssertEqual(receipt.status, "completed")
            XCTAssertEqual(receipt.requestID, id)
            return try Data(contentsOf: output.appendingPathComponent(file))
        }
        let preview = try decoder.decode(ConfirmedDailyTrainingPlanPreview.self,
            from: exchange(.previewDailyTrainingPlan, input, file: "daily-training-preview.json"))
        let first = try decoder.decode(ConfirmedDailyTrainingPlanApplyResult.self,
            from: exchange(.applyDailyTrainingPlan, preview, file: "daily-training-result.json"))
        let repeated = try decoder.decode(ConfirmedDailyTrainingPlanApplyResult.self,
            from: exchange(.applyDailyTrainingPlan, preview, file: "daily-training-result.json"))
        XCTAssertEqual(first.newScheduleCount, 1)
        XCTAssertEqual(repeated.newScheduleCount, 0)
        let readback = try decoder.decode(ConfirmedDailyTrainingPlanReadback.self,
            from: exchange(.readDailyTrainingPlan, ConfirmedDailyTrainingPlanReadRequest(id: input.id, packetSHA256: preview.packetSHA256),
                           file: "daily-training-readback.json"))
        XCTAssertEqual(readback, first.readback)
        let backup = try DataExportService.createBackup(in: context)
        owned.append(backup)
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: backup), into: restored.mainContext)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: input.id, in: restored.mainContext), first.readback)
    }
}

extension ConfirmedTrainingPlanTests {
    private func blankDiscardedRevision() throws -> (ModelContainer, ConfirmedDailyTrainingPlanPacket, WorkoutSession) {
        let store = try container(), context = store.mainContext
        let original = try dailyPacket(in: context)
        _ = try ConfirmedDailyTrainingPlanService.apply(expectedPreview:
            ConfirmedDailyTrainingPlanService.preview(original, in: context), in: context)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        let sessionID = try WorkoutService.start(schedule: schedule, in: context)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == sessionID })
        try WorkoutService.discard(session: session, schedules: [schedule], in: context)
        session.startTimeKnownRaw = nil
        session.restModeRaw = nil
        session.defaultPlanPatternRaw = nil
        for item in try context.fetch(FetchDescriptor<SessionExercise>()) where item.sessionID == sessionID {
            item.planPatternRaw = nil
            item.patternSourceRaw = nil
        }
        try context.save()
        var revision = original
        revision.id = UUID()
        revision.title = "已确认的空白草稿后修订"
        revision.replacement = .init(scheduleID: original.id,
            packetSHA256: try ConfirmedTrainingPlanService.digest(original))
        return (store, revision, session)
    }

    private func acknowledgeDiscardedReview(_ preview: ConfirmedDailyTrainingPlanPreview) throws -> ConfirmedDailyTrainingPlanPreview {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(preview)) as? [String: Any])
        wire["discardedDraftConfirmationReference"] = "OWNER-CONFIRMED-EMPTY-DISCARDED-GRAPH"
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConfirmedDailyTrainingPlanPreview.self,
            from: JSONSerialization.data(withJSONObject: wire, options: [.sortedKeys]))
    }

    private func actualHistory(in context: ModelContext) throws -> [String: Data] {
        let url = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: url) }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try Dictionary(uniqueKeysWithValues: ["sessions", "sessionExercises", "setLogs"].map {
            ($0, try JSONSerialization.data(withJSONObject: XCTUnwrap(object[$0]), options: [.sortedKeys]))
        })
    }

    private func assertSupersededDiscardedBackfillRejected(
        explicitSession: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line,
        attempt: (ScheduledWorkoutBackfillInput, ModelContext) throws -> Void
    ) throws {
        let (store, revision, draft) = try blankDiscardedRevision(), context = store.mainContext
        let oldID = try XCTUnwrap(revision.replacement?.scheduleID)
        let preparation = try HistoricalWorkoutService.prepareScheduledBackfill(scheduleID: oldID, in: context)
        let input = ScheduledWorkoutBackfillInput(scheduleID: oldID,
            existingSessionID: explicitSession ? draft.id : nil, name: "过期页面补录", date: preparation.date,
            startedAt: nil, durationMinutes: 45, notes: "不得写入被替代的安排",
            exercises: preparation.exercises.map { item in
                .init(existingSnapshotID: item.existingSnapshotID, exerciseID: item.exerciseID,
                    sets: item.sets.map { set in
                        .init(existingLogID: set.existingLogID, weight: set.weight, reps: set.reps, rir: 2,
                            weightSide: set.weightSide, repsSide: set.repsSide)
                    }, performanceNotes: "过期页面的实际输入", feeling: nil, isWarmup: item.isWarmup)
            })
        let before = try actualHistory(in: context)
        let approved = try acknowledgeDiscardedReview(ConfirmedDailyTrainingPlanService.preview(revision, in: context))
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: approved, in: context).newScheduleCount, 1,
            file: file, line: line)
        let old = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == oldID })
        XCTAssertEqual(try actualHistory(in: context), before, file: file, line: line)
        let identity = [old.id, old.templateID]
        let text: [String?] = [old.templateName, old.statusRaw, old.skipReason, old.planSnapshotJSON,
            old.plannedLocalDay, old.plannedTimeZoneIdentifier, old.confirmedDailyImportJSON, old.jumpRopePlanJSON]
        let dates: [Date?] = [old.plannedDate, old.createdAt, old.originalPlannedDate, old.reminderDate, old.updatedAt]
        let manuallyScheduled = old.isManuallyScheduled
        XCTAssertEqual(draft.status, .discarded, file: file, line: line)
        XCTAssertEqual(old.status, .skipped, file: file, line: line)
        XCTAssertTrue(try ConfirmedDailyTrainingPlanService.isSuperseded(oldID, in: context), file: file, line: line)
        XCTAssertFalse(context.hasChanges, file: file, line: line)

        XCTAssertThrowsError(try attempt(input, context), file: file, line: line) { error in
            guard case HistoricalWorkoutServiceError.supersededSchedule = error else {
                return XCTFail("应拒绝已被替代安排的空白草稿补录：\(error)", file: file, line: line)
            }
        }

        XCTAssertEqual(draft.status, .discarded, file: file, line: line)
        XCTAssertEqual(try actualHistory(in: context), before, file: file, line: line)
        XCTAssertEqual([old.id, old.templateID], identity, file: file, line: line)
        XCTAssertEqual([old.templateName, old.statusRaw, old.skipReason, old.planSnapshotJSON,
            old.plannedLocalDay, old.plannedTimeZoneIdentifier, old.confirmedDailyImportJSON, old.jumpRopePlanJSON], text,
            file: file, line: line)
        XCTAssertEqual([old.plannedDate, old.createdAt, old.originalPlannedDate, old.reminderDate, old.updatedAt], dates,
            file: file, line: line)
        XCTAssertEqual(old.isManuallyScheduled, manuallyScheduled, file: file, line: line)
        XCTAssertFalse(context.hasChanges, file: file, line: line)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: approved, in: context).newScheduleCount, 0,
            file: file, line: line)
        XCTAssertEqual(try actualHistory(in: context), before, file: file, line: line)
        XCTAssertFalse(context.hasChanges, file: file, line: line)
    }

    func testSupersededDiscardedBlankDraftRejectsHistoricalBackfillPreparation() throws {
        try assertSupersededDiscardedBackfillRejected { input, context in
            _ = try HistoricalWorkoutService.prepareScheduledBackfill(scheduleID: input.scheduleID, in: context)
        }
    }

    func testSupersededDiscardedBlankDraftRejectsImplicitHistoricalBackfill() throws {
        try assertSupersededDiscardedBackfillRejected { input, context in
            _ = try HistoricalWorkoutService.recordScheduledBackfill(input, in: context)
        }
    }

    func testSupersededDiscardedBlankDraftRejectsExplicitHistoricalBackfill() throws {
        try assertSupersededDiscardedBackfillRejected(explicitSession: true) { input, context in
            _ = try HistoricalWorkoutService.recordScheduledBackfill(input, in: context)
        }
    }

    func testNonSupersededDiscardedBlankDraftRemainsHistoricallyBackfillable() throws {
        let (store, revision, draft) = try blankDiscardedRevision(), context = store.mainContext
        let oldID = try XCTUnwrap(revision.replacement?.scheduleID)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == oldID })
        let source = schedule.confirmedDailyImportJSON, plan = schedule.planSnapshotJSON
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())
        let preparation = try HistoricalWorkoutService.prepareScheduledBackfill(scheduleID: oldID, in: context)
        XCTAssertEqual(preparation.existingSessionID, draft.id)
        XCTAssertFalse(try ConfirmedDailyTrainingPlanService.isSuperseded(oldID, in: context))
        XCTAssertFalse(context.hasChanges)
        let input = ScheduledWorkoutBackfillInput(scheduleID: oldID, existingSessionID: draft.id,
            name: preparation.name, date: preparation.date, startedAt: nil, durationMinutes: 45,
            notes: "本人补录尚未替代的草稿", exercises: preparation.exercises.map { item in
                .init(existingSnapshotID: item.existingSnapshotID, exerciseID: item.exerciseID,
                    sets: item.sets.map { set in
                        .init(existingLogID: set.existingLogID, weight: set.weight, reps: set.reps, rir: 2,
                            weightSide: set.weightSide, repsSide: set.repsSide)
                    }, performanceNotes: "本人补录", feeling: nil, isWarmup: item.isWarmup)
            })
        let actual = try HistoricalWorkoutService.recordScheduledBackfill(input, in: context)
        XCTAssertEqual(actual.id, draft.id)
        XCTAssertEqual(actual.status, .completed)
        XCTAssertEqual(actual.notes, input.notes)
        XCTAssertEqual(schedule.status, .completed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(Set(try context.fetch(FetchDescriptor<SessionExercise>()).map(\.id)), Set(snapshots.map(\.id)))
        let savedLogs = try context.fetch(FetchDescriptor<SetLog>())
        XCTAssertEqual(Set(savedLogs.map(\.id)), Set(logs.map(\.id)))
        XCTAssertTrue(savedLogs.allSatisfy { $0.isCompleted && $0.actualReps > 0 && $0.rir == 2 })
        XCTAssertEqual(schedule.confirmedDailyImportJSON, source)
        XCTAssertEqual(schedule.planSnapshotJSON, plan)
        XCTAssertFalse(context.hasChanges)
    }

    func testExplicitDiscardedBlankDraftRevisionPreservesOriginalRecordsAndRetries() throws {
        let (store, revision, session) = try blankDiscardedRevision(), context = store.mainContext
        let before = try actualHistory(in: context)
        let preview = try ConfirmedDailyTrainingPlanService.preview(revision, in: context)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(preview)) as? [String: Any])
        XCTAssertNotNil(wire["discardedDraftReview"], "A fully blank discarded graph must produce an App-owned review")
        guard wire["discardedDraftReview"] != nil else { return }
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context))
        let approved = try acknowledgeDiscardedReview(preview)
        let first = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: approved, in: context)
        XCTAssertEqual(first.newScheduleCount, 1)
        XCTAssertEqual(try actualHistory(in: context), before)
        XCTAssertEqual(session.status, .discarded)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: approved, in: context).newScheduleCount, 0)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: revision.id, in: context), first.readback)
        XCTAssertEqual(try actualHistory(in: context), before)
        let backup = try DataExportService.createBackup(in: context)
        defer { try? FileManager.default.removeItem(at: backup) }
        let restored = try container()
        _ = try DataExportService.importBackup(Data(contentsOf: backup), into: restored.mainContext)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.readback(id: revision.id, in: restored.mainContext), first.readback)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: approved, in: restored.mainContext).newScheduleCount, 0)
    }

    func testDiscardedDraftReviewRejectsActualInputAndIncompleteOwnership() throws {
        for variant in 0..<20 {
            let (store, revision, session) = try blankDiscardedRevision(), context = store.mainContext
            let set = try XCTUnwrap(context.fetch(FetchDescriptor<SetLog>()).first)
            let snapshot = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first { $0.id == set.sessionExerciseID })
            switch variant {
            case 0: session.status = .inProgress
            case 1: session.status = .completed
            case 2: set.actualReps = 1
            case 3: set.actualWeight = 1
            case 4: set.rir = 2
            case 5: set.isCompleted = true
            case 6: set.startedAt = .now
            case 7: set.restDurationSeconds = 30
            case 8: set.actualEntrySource = .manual
            case 9: set.actualWeightIsBlank = nil
            case 10: snapshot.performanceNotes = "已练"
            case 11: snapshot.feelingRaw = "normal"
            case 12: snapshot.exerciseCompletedAt = .now
            case 13: session.notes = "手写反馈"
            case 14:
                let rope = JumpRopeEntry(count: 1, durationSeconds: 1, date: .now)
                rope.scheduledWorkoutID = revision.replacement!.scheduleID
                context.insert(rope)
            case 15: context.delete(set)
            case 16: set.sessionID = UUID()
            case 17: set.exerciseID = UUID()
            case 18: snapshot.exerciseName += "changed"
            default: set.sourceHistorySetID = UUID()
            }
            try context.save()
            let before = try actualHistory(in: context)
            let preview = try ConfirmedDailyTrainingPlanService.preview(revision, in: context)
            XCTAssertFalse(preview.conflicts.isEmpty, "variant \(variant)")
            XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.apply(
                expectedPreview: acknowledgeDiscardedReview(preview), in: context), "variant \(variant)")
            XCTAssertEqual(try actualHistory(in: context), before)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 1)
        }
    }

    func testDiscardedReviewDetectsSubsecondMetadataDriftAndSaveRollback() throws {
        let (store, revision, session) = try blankDiscardedRevision(), context = store.mainContext
        let preview = try acknowledgeDiscardedReview(ConfirmedDailyTrainingPlanService.preview(revision, in: context))
        let oldCompletion = try XCTUnwrap(session.completedAt)
        session.completedAt = oldCompletion.addingTimeInterval(0.0001)
        try context.save()
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context))
        session.completedAt = oldCompletion
        try context.save()
        let before = try actualHistory(in: context)
        let old = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first)
        let updated = old.updatedAt
        XCTAssertThrowsError(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context,
            commit: { _ in throw CocoaError(.fileWriteNoPermission) }))
        XCTAssertEqual(old.status, .planned)
        XCTAssertEqual(old.updatedAt, updated)
        XCTAssertEqual(try actualHistory(in: context), before)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context).newScheduleCount, 1)
    }
}
