import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class CoachWeekGenerationTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!

    private func item(_ name: String, _ muscle: String, _ equipment: String, id: UUID = UUID(), unit: ExerciseVolumeUnit = .kilogram, method: String? = nil) -> CoachWeekCatalogItem {
        let role = CoachWeekService.roleEvidence(name: name, equipment: equipment, canonicalID: nil, exerciseID: id, ruleMethod: method)
        return CoachWeekCatalogItem(id: id, name: name, muscle: muscle, equipment: equipment, unit: unit,
            approvedCanonicalID: nil, approvedName: nil, archived: false, roles: role.roles, roleSource: role.source)
    }

    private func frozen(_ row: CoachWeekCatalogItem) -> CoachWeekFrozenExercise {
        CoachWeekFrozenExercise(exerciseID: row.id, name: row.name, muscle: row.muscle, equipment: row.equipment, roles: row.roles,
            plannedSets: [WorkoutSetPlan(weight: 0, reps: 8)])
    }

    private func input(_ catalog: [CoachWeekCatalogItem], history: [CoachWeekActual] = [], existing: [CoachWeekExisting] = [],
                       version: String = CoachWeekService.personalRuleVersion, method: String = CoachWeekService.methodVersion, exception: CoachWeekException? = nil, coreException: CoachWeekCoreException? = nil,
                       snapshot: TrainingPreferenceSnapshot = .confirmed, startDay: String = "2026-10-26", recovery: [CoachWeekRecoverySignal] = [], bodyReports: [CoachWeekBodyReport] = [], reviews: [CoachWeekRetainedReview]? = nil) -> CoachWeekInput {
        let dates = CoachWeekService.dateKeys(start: TrainingLocalDate.date(startDay, timeZone: zone)!, zone: zone)
        return CoachWeekInput(startDay: dates[0], timeZone: zone.identifier, methodVersion: method,
            personalRuleVersion: version, preferences: dates.map { CoachWeekPreference(localDay: $0, revisionID: nil, code: "fixture", snapshot: snapshot) },
            exception: exception, catalog: catalog, history: history, existing: existing, recovery: [], unknowns: ["Synthetic test inputs; no real completion evidence."], recoverySignals: recovery, bodyReports: bodyReports, retainedReviews: reviews, coreException: coreException,
            capturedLocalDay: method == CoachWeekService.legacyMethodVersion ? nil : startDay)
    }

    private func day(_ input: CoachWeekInput, focus: String, date: String = "2026-10-28") throws -> CoachWeekDay {
        let goal = CoachWeekGoal(localDay: date, kind: .strength, focus: focus, reason: "隔离规则测试")
        return try XCTUnwrap(CoachWeekService.generate(input: input, goals: [goal]).days.first { $0.localDay == date })
    }

    // Exact identity/equipment fields transcribed from confirmed 2026-10-19 R2.
    // Historical planned weights are deliberately not treated as completed loads.
    private var chestR2: [CoachWeekCatalogItem] {
        [item("史密斯卧推", "胸部", "史密斯机", id: UUID(uuidString: "5e1cec70-a19c-4da8-abf1-75c41e489943")!),
         item("上斜哑铃卧推", "胸部", "哑铃", id: UUID(uuidString: "63b78b46-bec4-4710-8590-66a0e22c963d")!),
         item("MTS器械下斜推胸", "胸部", "MTS下斜推胸机", id: UUID(uuidString: "bd2601d3-a32c-4d29-8c41-cb9152e2533a")!),
         item("站姿绳索夹胸", "胸部", "龙门架", id: UUID(uuidString: "8de3ee03-a5a3-4767-954b-333d4bd17332")!),
         item("绳索下压", "手臂", "龙门架", id: UUID(uuidString: "bd28555c-efc5-49a6-b267-5bf091c103fc")!),
         item("绳索过顶臂屈伸", "手臂", "龙门架", id: UUID(uuidString: "7def3925-cd46-4959-986a-7701342c58f6")!)]
    }

    private var backR5: [CoachWeekCatalogItem] {
        [item("双滑轮高位下拉", "背部", "双滑轮器械", id: UUID(uuidString: "634f2176-1479-4058-b436-3efe90dfed0a")!),
         item("双滑轮低位划船", "背部", "双滑轮器械", id: UUID(uuidString: "e80688b3-3640-4bab-9042-ec439ba9d690")!),
         item("胸托T-Bar划船", "背部", "胸托T-Bar划船机", id: UUID(uuidString: "a6e38c67-e9f6-4b0a-84de-1f9281aa64e7")!),
         item("直臂下压", "背部", "龙门架", id: UUID(uuidString: "2ba64b34-714e-4cfa-bd37-990e75696b4e")!),
         item("哑铃弯举", "手臂", "哑铃", id: UUID(uuidString: "0f843f55-d5d8-417a-b884-13d133d4cd27")!),
         item("锤式弯举", "手臂", "哑铃", id: UUID(uuidString: "7d5ec7dc-2959-4119-938a-15891521fdaf")!)]
    }

    func testConfirmedChestR2AndBackR5PoolsGenerateWithoutCanonicalApprovals() throws {
        for (catalog, focus) in [(chestR2, "胸＋三头"), (backR5, "背")] {
            let result = try day(input(catalog), focus: focus)
            XCTAssertEqual(result.movements.count, 6)
            XCTAssertTrue(result.blockers.isEmpty, result.blockers.joined(separator: "；"))
            XCTAssertEqual(result.movements.filter { $0.exercise.plannedSets.count == 4 }.count, 1)
            XCTAssertLessThanOrEqual(try XCTUnwrap(result.estimatedSeconds), 5400)
            XCTAssertTrue(result.movements.allSatisfy { $0.exercise.plannedSets.allSatisfy { $0.weight == 0 && $0.actualDefaultPolicy == .blank } })
        }
    }

    func testShoulderWithOneCompoundAndIsolationAccessoriesHasDistinctLoadRoles() throws {
        let catalog = [item("器械肩推", "肩部", "器械"),
                       item("哑铃侧平举", "肩部", "哑铃"),
                       item("坐姿哑铃侧平举", "肩部", "哑铃"),
                       item("绳索侧平举", "肩部", "龙门架"),
                       item("器械反向飞鸟", "肩部", "器械"),
                       item("绳索下压", "手臂", "龙门架")]
        let result = try day(input(catalog), focus: "肩")
        XCTAssertEqual(result.movements.count, 6)
        XCTAssertEqual(Set(result.movements.compactMap(\.loadRole)), ["重主项", "中等辅助", "轻负荷正式任务"])
        XCTAssertTrue(result.blockers.isEmpty, result.blockers.joined(separator: "；"))
        XCTAssertEqual(result.movements.filter { $0.exercise.plannedSets.count == 4 }.count, 1)
        XCTAssertTrue(result.movements.allSatisfy { $0.exercise.plannedSets.allSatisfy { $0.weight == 0 && $0.actualDefaultPolicy == .blank } })
    }

    func testNewShoulderRuleRequiresFourMainMovementsAndAllThreeHeads() throws {
        let shoulder = [item("器械肩推", "肩部", "器械"), item("哑铃侧平举", "肩部", "哑铃"),
                        item("器械反向飞鸟", "肩部", "器械"), item("坐姿哑铃侧平举", "肩部", "哑铃")]
        let arms = [item("绳索下压", "手臂", "龙门架"), item("绳索过顶臂屈伸", "手臂", "龙门架"),
                    item("哑铃弯举", "手臂", "哑铃")]
        let method = "METHOD-20261029-12"
        let tooFew = try day(input(Array(shoulder.prefix(3)) + arms, method: method), focus: "肩")
        XCTAssertTrue(tooFew.blockers.contains { $0.contains("主肌群动作不足4个") }, tooFew.blockers.joined(separator: "；"))
        let enough = try day(input(shoulder + arms, method: method), focus: "肩")
        XCTAssertFalse(enough.blockers.contains { $0.contains("主肌群动作不足4个") || $0.contains("肩束") }, enough.blockers.joined(separator: "；"))
        let noRear = [shoulder[0], shoulder[1], shoulder[3], item("绳索侧平举", "肩部", "龙门架")] + arms
        let uncovered = try day(input(noRear, method: method), focus: "肩")
        XCTAssertTrue(uncovered.blockers.contains { $0.contains("肩束") && $0.contains("后") }, uncovered.blockers.joined(separator: "；"))
    }

    func testNewRuleDoesNotCountGenericPressAsBenchOrWarmupsAsFourWorkSets() throws {
        let generic = [item("器械坐姿推胸", "胸部", "器械"), item("MTS器械下斜推胸", "胸部", "MTS下斜推胸机"),
                       item("蝴蝶机夹胸", "胸部", "器械"), item("站姿绳索夹胸", "胸部", "龙门架"),
                       item("绳索下压", "手臂", "龙门架"), item("哑铃弯举", "手臂", "哑铃")]
        let method = "METHOD-20261029-12"
        let missing = try day(input(generic, method: method), focus: "胸")
        XCTAssertTrue(missing.blockers.contains { $0.contains("卧推") }, missing.blockers.joined(separator: "；"))
        let validInput = input(chestR2, method: method)
        var edited = try day(validInput, focus: "胸")
        let index = try XCTUnwrap(edited.movements.firstIndex { $0.exercise.catalogName.contains("卧推") && $0.exercise.plannedSets.count >= 4 })
        edited.movements[index].exercise.plannedSets[0].prescription?.label = "热身"
        let checked = CoachWeekService.revalidateStrength(edited, input: validInput)
        XCTAssertTrue(checked.blockers.contains { $0.contains("卧推") && $0.contains("4") }, checked.blockers.joined(separator: "；"))
    }

    func testNewRuleDoesNotCountPullupOrLegPressAsTheSpecifiedMain() throws {
        let back = [item("引体向上", "背部", "自重", unit: .bodyweight), item("直臂下压", "背部", "龙门架"),
                    item("绳索直臂下压", "背部", "龙门架"), item("哑铃弯举", "手臂", "哑铃"), item("绳索下压", "手臂", "龙门架")]
        let legs = [item("腿举", "腿部", "器械"), item("腿屈伸", "腿部", "器械"), item("坐姿腿弯举", "腿部", "器械"),
                    item("器械臀推", "臀部", "器械臀推机"), item("保加利亚分腿蹲", "腿部", "哑铃"), item("反向箭步蹲", "腿部", "哑铃")]
        let backDay = try day(input(back, method: "METHOD-20261029-12"), focus: "背")
        let legDay = try day(input(legs, method: "METHOD-20261029-12"), focus: "腿")
        XCTAssertTrue(backDay.blockers.contains { $0.contains("划船/下拉") }, backDay.blockers.joined(separator: "；"))
        XCTAssertTrue(legDay.blockers.contains { $0.contains("深蹲/硬拉") }, legDay.blockers.joined(separator: "；"))
    }

    func testNewLegRuleDoesNotCountCalfAsOneOfFourMainExercises() throws {
        let catalog = [item("深蹲", "腿部", "杠铃"), item("腿举", "腿部", "器械"),
                       item("腿屈伸", "腿部", "器械"), item("站姿提踵", "小腿", "器械")]
        let current = try day(input(catalog, method: "METHOD-20261029-12"), focus: "腿")
        XCTAssertTrue(current.blockers.contains { $0.contains("主肌群动作不足4个") }, current.blockers.joined(separator: "；"))
        let legacy = try day(input(catalog, method: "METHOD-20261028-11"), focus: "腿")
        XCTAssertFalse(legacy.blockers.contains { $0.contains("主肌群动作不足4个") })
    }

    func testNewWeekDistributesFourDistinctAbdominalExercises() throws {
        let core = [item("垫高绳索站姿侧屈", "核心", "龙门架"), item("站姿水平伐木", "核心", "龙门架"),
                    item("绳索跪姿卷腹", "核心", "龙门架"), item("负重仰卧起坐", "核心", "负重片")]
        let legs = [item("深蹲", "腿部", "杠铃"), item("罗马尼亚硬拉", "腿部", "杠铃"),
                    item("坐姿腿弯举", "腿部", "器械"), item("腿屈伸", "腿部", "器械")]
        let shoulder = [item("器械肩推", "肩部", "器械"), item("哑铃侧平举", "肩部", "哑铃"),
                        item("器械反向飞鸟", "肩部", "器械"), item("坐姿哑铃侧平举", "肩部", "哑铃")]
        let source = input(chestR2 + backR5 + legs + shoulder + core, method: "METHOD-20261029-12")
        let draft = try CoachWeekService.generate(input: source, goals: CoachWeekService.defaultGoals(start: TrainingLocalDate.date(source.startDay, timeZone: zone)!, zone: zone))
        let coreIDs = Set(core.map(\.id))
        let selected = draft.days.flatMap(\.movements).filter { coreIDs.contains($0.id) }
        XCTAssertEqual(Set(selected.map(\.id)).count, 4)
        XCTAssertTrue(draft.days.filter { $0.kind == .strength }.allSatisfy { $0.movements.count <= 8 })
        XCTAssertFalse((draft.weeklyShortfall ?? []).contains { $0.contains("腹部") }, (draft.weeklyShortfall ?? []).joined(separator: "；"))
    }

    func testNewCoreCoverageDistinguishesPlansCompletedWorkAndUnknown() throws {
        let side = item("垫高绳索站姿侧屈", "核心", "龙门架")
        let chop = item("站姿水平伐木", "核心", "龙门架")
        let crunch = item("绳索跪姿卷腹", "核心", "龙门架")
        let unknown = item("负重仰卧起坐", "核心", "负重片")
        func actual(_ row: CoachWeekCatalogItem, day: String, completed: Bool, warmup: Bool, known: Bool) -> CoachWeekActual {
            CoachWeekActual(id: UUID(), sessionID: UUID(), localDay: day, exerciseID: row.id, name: row.name,
                equipment: row.equipment, unit: .kilogram, plannedSets: [],
                actual: [CoachActualSet(id: UUID(), weight: 10, reps: 10, rir: nil, weightSide: .unknown, repsSide: .unknown, completed: completed, warmup: warmup)],
                feedback: "Synthetic", classificationKnown: known)
        }
        let prescription = WorkoutSetPrescription(label: "轻负荷正式任务", repsLower: 8, repsUpper: 10,
            rirLower: 2, rirUpper: 3, restLowerSeconds: 90, restUpperSeconds: 90, effortCue: "测试")
        let planned = CoachWeekFrozenExercise(exerciseID: chop.id, name: chop.name, muscle: chop.muscle,
            equipment: chop.equipment, roles: chop.roles, plannedSets: [WorkoutSetPlan(weight: 0, reps: 8, prescription: prescription)])
        let future = CoachWeekExisting(id: UUID(), localDay: "2026-10-30", title: "计划", status: "planned", source: "日程", frozenExercises: [planned])
        let stale = CoachWeekExisting(id: UUID(), localDay: "2026-10-26", title: "过去未完成的计划", status: "planned", source: "日程",
            frozenExercises: [CoachWeekFrozenExercise(exerciseID: crunch.id, name: crunch.name, muscle: crunch.muscle, equipment: crunch.equipment, roles: crunch.roles, plannedSets: planned.plannedSets)])
        let observed = [actual(side, day: "2026-10-27", completed: true, warmup: false, known: true),
                        actual(side, day: "2026-10-28", completed: true, warmup: false, known: true),
                        actual(crunch, day: "2026-10-27", completed: true, warmup: true, known: true),
                        actual(unknown, day: "2026-10-28", completed: true, warmup: false, known: false),
                        actual(unknown, day: "2026-10-25", completed: true, warmup: false, known: true)]
        var source = input([side, chop, crunch, unknown], history: observed, existing: [future, stale], method: "METHOD-20261029-12")
        source.capturedLocalDay = "2026-10-29"
        let days = source.preferences.map { CoachWeekDay(localDay: $0.localDay, kind: .rest, title: "休息", focus: "", movements: [], cardio: nil, estimatedSeconds: 0, rationale: [], blockers: [], existing: []) }
        let gaps = CoachWeekService.weeklyShortfalls(days, input: source)
        XCTAssertTrue(gaps.contains { $0.contains("腹部") && $0.contains("当前可核对2个") }, gaps.joined(separator: "；"))
    }

    func testPastUnrecordedDaysAreUnknownAndCannotSatisfyCoreTarget() throws {
        let core = [item("垫高绳索站姿侧屈", "核心", "龙门架"), item("站姿水平伐木", "核心", "龙门架"),
                    item("绳索跪姿卷腹", "核心", "龙门架"), item("负重仰卧起坐", "核心", "负重片")]
        var source = input(chestR2 + backR5 + core)
        let start = TrainingLocalDate.date(source.startDay, timeZone: zone)!
        let goals = CoachWeekService.defaultGoals(start: start, zone: zone)
        let originallyFuture = try CoachWeekService.generate(input: source, goals: goals)
        XCTAssertFalse((originallyFuture.weeklyShortfall ?? []).contains { $0.contains("腹部") })
        source.capturedLocalDay = "2026-10-29"
        let midweek = try CoachWeekService.generate(input: source, goals: goals)
        XCTAssertTrue(midweek.days.prefix(3).allSatisfy { $0.kind == .missing && $0.movements.isEmpty })
        let rechecked = CoachWeekService.revalidateWeek(originallyFuture.days, input: source)
        XCTAssertTrue(rechecked.prefix(3).allSatisfy { $0.blockers.contains { $0.contains("过去日期") } })
        XCTAssertTrue(CoachWeekService.weeklyShortfalls(rechecked, input: source).contains { $0.contains("腹部") })
    }

    func testPastUnrecordedRestRequiresExplicitReviewAndDoesNotCreateHistory() throws {
        var source = input(chestR2 + backR5)
        source.capturedLocalDay = "2026-10-29"
        let start = TrainingLocalDate.date(source.startDay, timeZone: zone)!
        let original = try CoachWeekService.generate(input: source, goals: CoachWeekService.defaultGoals(start: start, zone: zone))
        XCTAssertEqual(original.days[0].kind, .missing)
        let context = ModelContext(try captureContainer())
        try CoachWeekService.save(original, in: context)
        let goal = CoachWeekGoal(localDay: original.days[0].localDay, kind: .rest, focus: "", reason: "本人核对这天没有训练")
        let days = try CoachWeekService.regenerateDay(original, goal: goal)
        XCTAssertEqual(days[0].kind, .rest)
        XCTAssertFalse(days[0].blockers.contains { $0.contains("过去日期") })
        let forged = CoachWeekDraft(id: original.id, rootID: original.rootID, revision: original.revision,
            createdAt: original.createdAt, sourceFingerprint: original.sourceFingerprint, input: original.input,
            days: days, edits: [], ruleCandidates: [])
        XCTAssertThrowsError(try CoachWeekService.validateStored(forged, rowID: forged.id, rootID: forged.rootID))
        let edit = CoachWeekEdit(id: UUID(), day: goal.localDay, field: "日安排", before: "待核", after: "休息", reason: goal.reason)
        let reviewed = try CoachWeekService.revise(original, days: days, edits: [edit], candidates: [], in: context)
        XCTAssertEqual(reviewed.days[0].pastRestReview?.confirmation, CoachWeekService.pastRestConsent)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
        let newlyObserved = CoachWeekExisting(id: UUID(), localDay: goal.localDay, title: "后续发现的安排", status: "planned", source: "日程")
        var changedInput = input(chestR2 + backR5, existing: [newlyObserved]); changedInput.capturedLocalDay = "2026-10-29"
        XCTAssertTrue(CoachWeekService.revalidateWeek(reviewed.days, input: changedInput)[0].blockers.contains { $0.contains("过去日期") })
    }

    func testApprovedCoreAliasesAndFrozenNameDoNotCountTwice() throws {
        func alias(_ name: String) -> CoachWeekCatalogItem {
            CoachWeekCatalogItem(id: UUID(), name: name, muscle: "核心", equipment: "龙门架", unit: .kilogram,
                approvedCanonicalID: "cable_crunch", approvedName: "绳索卷腹", archived: false,
                roles: ["腹部", "躯干屈曲"], roleSource: "测试已批准身份")
        }
        let first = alias("腹部别名甲"), second = alias("腹部别名乙")
        let side = item("垫高绳索站姿侧屈", "核心", "龙门架"), chop = item("站姿水平伐木", "核心", "龙门架")
        let prescription = WorkoutSetPrescription(label: "工作组", repsLower: 8, repsUpper: 10, rirLower: 2, rirUpper: 3, restLowerSeconds: 90, restUpperSeconds: 90)
        let set = WorkoutSetPlan(weight: 0, reps: 8, actualDefaultPolicy: .blank, prescription: prescription)
        func movement(_ row: CoachWeekCatalogItem) -> CoachWeekMovement {
            let exercise = ConfirmedDailyPlanExercise(catalogExerciseID: row.id, catalogName: row.name, equipment: row.equipment,
                volumeUnit: row.unit, displayName: row.name, loadGuidance: "测试", notes: "测试", plannedSets: [set])
            return CoachWeekMovement(exercise: exercise, roles: row.roles, roleSource: row.roleSource, reason: "测试", evidence: [], unknowns: [], unilateral: false)
        }
        let frozen = CoachWeekFrozenExercise(exerciseID: UUID(), name: second.name, muscle: "核心", equipment: second.equipment,
            roles: second.roles, plannedSets: [set])
        let kept = CoachWeekExisting(id: UUID(), localDay: "2026-10-27", title: "保留安排", status: "planned", source: "日程", frozenExercises: [frozen])
        let source = input([first, second, side, chop], existing: [kept])
        let day = CoachWeekDay(localDay: "2026-10-26", kind: .strength, title: "测试", focus: "胸",
            movements: [first, second, side, chop].map(movement), cardio: nil, estimatedSeconds: 0, rationale: [], blockers: [], existing: [])
        let gaps = CoachWeekService.weeklyShortfalls([day], input: source)
        XCTAssertTrue(gaps.contains { $0.contains("腹部") && $0.contains("当前可核对3个") }, gaps.joined(separator: "；"))
    }

    func testNewRuleRechecksAuxiliaryGroupsAfterManualEdit() throws {
        let core = item("垫高绳索站姿侧屈", "核心", "龙门架")
        let source = input(chestR2 + [core], method: "METHOD-20261029-12")
        let oldSource = input(chestR2, method: "METHOD-20261029-12")
        var dayWithArms = try day(oldSource, focus: "胸＋三头")
        let coreDay = try day(source, focus: "胸＋三头")
        let coreMovement = try XCTUnwrap(coreDay.movements.first { $0.id == core.id })
        let armIndices = dayWithArms.movements.indices.filter { index in
            oldSource.catalog.first { $0.id == dayWithArms.movements[index].id }?.muscle == "手臂"
        }
        XCTAssertEqual(armIndices.count, 2)
        dayWithArms.movements[try XCTUnwrap(armIndices.first)] = coreMovement
        let checked = CoachWeekService.revalidateStrength(dayWithArms, input: source)
        XCTAssertTrue(checked.blockers.contains { $0.contains("辅助肌群") }, checked.blockers.joined(separator: "；"))
    }

    func testLegacyMethodRetainsItsRulesAndUnknownMethodIsRejected() throws {
        let generic = [item("器械坐姿推胸", "胸部", "器械"), item("MTS器械下斜推胸", "胸部", "MTS下斜推胸机"),
                       item("蝴蝶机夹胸", "胸部", "器械"), item("站姿绳索夹胸", "胸部", "龙门架"),
                       item("绳索下压", "手臂", "龙门架"), item("哑铃弯举", "手臂", "哑铃")]
        let old = input(generic, method: "METHOD-20261028-11")
        let result = try day(old, focus: "胸")
        XCTAssertFalse(result.blockers.contains { $0.contains("指定主项") }, result.blockers.joined(separator: "；"))
        XCTAssertFalse(CoachWeekService.weeklyShortfalls([result], input: old).contains { $0.contains("腹部") })
        let future = input(generic, method: "METHOD-UNKNOWN")
        let goal = CoachWeekGoal(localDay: "2026-10-28", kind: .strength, focus: "胸", reason: "测试未知方法")
        XCTAssertThrowsError(try CoachWeekService.generate(input: future, goals: [goal]))
    }

    func testLegacySealedRecoveryWeekStillValidatesAfterNewPolicy() throws {
        let dates = input([]).preferences.map(\.localDay)
        let goals = dates.map { CoachWeekGoal(localDay: $0, kind: .rest, focus: "", reason: "旧版确认恢复周") }
        let exception = CoachWeekException(id: UUID(), startDay: dates[0], endDay: dates[6], reason: "旧版恢复周", goals: goals, confirmation: "本人确认")
        let old = input([], method: CoachWeekService.legacyMethodVersion, exception: exception)
        let draft = try CoachWeekService.generate(input: old, goals: goals)
        let members: [ConfirmedDailyTrainingPlanPreview] = []
        let ropes: [CoachWeekRopeMember] = []
        let digests = try Dictionary(uniqueKeysWithValues: draft.days.map { ($0.localDay, try ConfirmedTrainingPlanService.digest($0)) })
        let requestID = UUID()
        let seal = try ConfirmedTrainingPlanService.digest([try ConfirmedTrainingPlanService.digest(draft),
            try ConfirmedTrainingPlanService.digest(members), try ConfirmedTrainingPlanService.digest(ropes),
            try ConfirmedTrainingPlanService.digest(digests), requestID.uuidString])
        let confirmation = CoachWeekConfirmation(id: requestID, draft: draft, confirmedAt: .now,
            members: members, ropes: ropes, dayDigests: digests, requestDigest: seal)
        XCTAssertNoThrow(try CoachWeekService.validateConfirmation(confirmation, rowID: requestID, rootID: draft.rootID))
        let current = input([], method: CoachWeekService.methodVersion, exception: exception)
        let currentDraft = try CoachWeekService.generate(input: current, goals: goals)
        XCTAssertTrue((currentDraft.weeklyShortfall ?? []).contains { $0.contains("腹部") })
    }

    func testCoreShortfallExceptionNeedsExplicitConsentAndExpiresAfterItsWeek() throws {
        let dates = input([]).preferences.map(\.localDay)
        let goals = dates.map { CoachWeekGoal(localDay: $0, kind: .rest, focus: "", reason: "恢复周") }
        let noConsent = CoachWeekException(id: UUID(), startDay: dates[0], endDay: dates[6], reason: "恢复周", goals: goals, confirmation: "确认七日目标")
        let pending = try CoachWeekService.generate(input: input([], exception: noConsent), goals: goals)
        XCTAssertTrue((pending.weeklyShortfall ?? []).contains { $0.contains("腹部") })
        let accepted = CoachWeekCoreException(startDay: dates[0], endDay: dates[6], reason: "恢复周", confirmation: CoachWeekService.coreExceptionConsent, goals: goals)
        let allowed = try CoachWeekService.generate(input: input([], exception: noConsent, coreException: accepted), goals: goals)
        XCTAssertFalse((allowed.weeklyShortfall ?? []).contains { $0.contains("腹部") })
        XCTAssertEqual(allowed.input.coreException?.reason, "恢复周")
        let next = input([], exception: noConsent, coreException: accepted, startDay: "2026-11-02")
        let nextGoals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(next.startDay, timeZone: zone)!, zone: zone)
        let nextDraft = try CoachWeekService.generate(input: next, goals: nextGoals)
        XCTAssertTrue((nextDraft.weeklyShortfall ?? []).contains { $0.contains("腹部") })
        let invalid = CoachWeekCoreException(startDay: dates[0], endDay: dates[6], reason: "恢复周", confirmation: "未明确同意", goals: goals)
        XCTAssertThrowsError(try CoachWeekService.generate(input: input([], coreException: invalid), goals: goals))
        let noReason = CoachWeekCoreException(startDay: dates[0], endDay: dates[6], reason: " ", confirmation: CoachWeekService.coreExceptionConsent, goals: goals)
        XCTAssertThrowsError(try CoachWeekService.generate(input: input([], coreException: noReason), goals: goals))
    }

    func testCoreOnlyConsentKeepsCardioGapsAndExpiresWhenGoalsChange() throws {
        let base = input(chestR2 + backR5)
        let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(base.startDay, timeZone: zone)!, zone: zone)
        let consent = CoachWeekCoreException(startDay: goals[0].localDay, endDay: goals[6].localDay,
            reason: "恢复时只调整腹部", confirmation: CoachWeekService.coreExceptionConsent, goals: goals)
        let source = input(chestR2 + backR5, coreException: consent)
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        let gaps = draft.weeklyShortfall ?? []
        XCTAssertFalse(gaps.contains { $0.contains("腹部") })
        XCTAssertTrue(gaps.contains { $0.contains("跳绳候选缺1次") })
        XCTAssertTrue(gaps.contains { $0.contains("Zone 2候选缺1次") })
        let friday = try XCTUnwrap(draft.days.first { $0.localDay == goals[4].localDay })
        let changed = try CoachWeekService.regenerateDay(draft, goal: CoachWeekGoal(localDay: friday.localDay, kind: .strength, focus: "胸", reason: "本人改为胸"))
        XCTAssertTrue(changed[4].blockers.contains { $0.contains("腹部例外目标已更改") }, changed[4].blockers.joined(separator: "；"))
        XCTAssertTrue(CoachWeekService.weeklyShortfalls(changed, input: source).contains { $0.contains("腹部") })
        let frequency = CoachWeekException(id: UUID(), startDay: goals[0].localDay, endDay: goals[6].localDay,
            reason: "本人确认原七日", goals: goals, confirmation: "明确确认")
        let both = input(chestR2 + backR5, exception: frequency, coreException: consent)
        let frequencyDraft = try CoachWeekService.generate(input: both, goals: goals)
        let frequencyChanged = try CoachWeekService.regenerateDay(frequencyDraft, goal: CoachWeekGoal(localDay: goals[4].localDay, kind: .strength, focus: "胸", reason: "本人改为胸"))
        XCTAssertTrue(frequencyChanged[4].blockers.contains { $0.contains("本周例外目标已更改") })
    }

    func testNewPolicyCanReplayAndActivateRankingWithoutLosingRequiredCore() throws {
        let repeated = backR5[0]
        let catalog = chestR2 + backR5 + [item("高位下拉", "背部", "器械"),
            item("垫高绳索站姿侧屈", "核心", "龙门架"), item("站姿水平伐木", "核心", "龙门架"),
            item("绳索跪姿卷腹", "核心", "龙门架"), item("负重仰卧起坐", "核心", "负重片")]
        let actual = CoachWeekActual(id: UUID(), sessionID: UUID(), localDay: "2026-10-25", exerciseID: repeated.id,
            name: repeated.name, equipment: repeated.equipment, unit: .kilogram, plannedSets: [],
            actual: [CoachActualSet(id: UUID(), weight: 20, reps: 10, rir: nil, weightSide: .unknown,
                                   repsSide: .unknown, completed: true, warmup: false)], feedback: "合成重复", classificationKnown: true)
        let dates = input([]).preferences.map(\.localDay)
        let goals = dates.map { date in
            CoachWeekGoal(localDay: date, kind: ["2026-10-26", "2026-10-28"].contains(date) ? .strength : .rest,
                focus: date == "2026-10-26" ? "胸＋三头" : date == "2026-10-28" ? "背" : "", reason: "隔离新规则回放")
        }
        let exception = CoachWeekException(id: UUID(), startDay: dates[0], endDay: dates[6], reason: "隔离测试", goals: goals, confirmation: "测试")
        let source = input(catalog, history: [actual], method: CoachWeekService.methodVersion, exception: exception)
        let original = try CoachWeekService.generate(input: source, goals: goals)
        let variantInput = input(catalog, history: [actual], version: CoachWeekService.overlapRuleVersion, method: CoachWeekService.methodVersion, exception: exception)
        let variant = try CoachWeekService.generate(input: variantInput, goals: goals)
        let edit = CoachWeekEdit(id: UUID(), day: "2026-10-28", field: "动作", before: repeated.name, after: "替换近期重复", reason: "减少同动作近期重复")
        let candidate = try CoachWeekService.ruleCandidate(original: original, revisedDays: variant.days, edits: [edit])
        XCTAssertTrue(original.days.allSatisfy { $0.blockers.isEmpty }, original.days.flatMap(\.blockers).joined(separator: "；"))
        XCTAssertEqual(candidate.executableVersion, CoachWeekService.overlapRuleVersion, candidate.replayResult)
        XCTAssertFalse((variant.weeklyShortfall ?? []).contains { $0.contains("腹部") })
        let context = ModelContext(try captureContainer())
        try CoachWeekService.save(original, in: context)
        let revised = try CoachWeekService.revise(original, days: variant.days, edits: [edit], candidates: [candidate], in: context)
        XCTAssertEqual(try CoachWeekService.activateRuleCandidate(candidate, draft: revised, in: context), CoachWeekService.overlapRuleVersion)
        XCTAssertEqual(try CoachWeekService.rollbackRule(in: context), CoachWeekService.personalRuleVersion)
    }

    func testPosteriorR3RolesRejectR2ThreeExactRepeatsAndSingleLegOverlap() throws {
        let curl = item("坐姿腿弯举", "腿部", "器械", id: UUID(uuidString: "bed023f2-c4d6-4b0b-82d8-6a163644ab4e")!)
        let abduction = item("Hip and glute machine", "臀部", "器械", id: UUID(uuidString: "0fcd2a94-feb5-4433-abee-50750a249bb4")!)
        let adduction = item("Abductor machine", "腿部", "器械", id: UUID(uuidString: "fc230b90-0405-492d-bf30-4c391c803578")!)
        let split = item("保加利亚分腿蹲", "腿部", "哑铃")
        let reverse = item("扶架单手哑铃反向箭步蹲", "腿部", "哑铃")
        let r3 = [item("罗马尼亚硬拉", "腿部", "杠铃", id: UUID(uuidString: "08f996c2-f996-40fd-b69c-6bdd064ea720")!),
            item("器械臀推", "臀部", "器械臀推机", id: UUID(uuidString: "e00c9518-fc57-4543-b390-10b577b034a5")!), curl,
            item("双手髋铰链壶铃摆动", "臀部", "壶铃", id: UUID(uuidString: "e0234c19-749c-4e15-bbfc-3f0696e62ba9")!),
            item("罗马椅髋伸", "臀部", "罗马椅＋可选负重片", id: UUID(uuidString: "a556e14c-502a-4867-959d-72e9369126ab")!),
            item("臀桥脚跟走步", "腿部", "地垫", id: UUID(uuidString: "74eb322c-65bd-43cd-8dea-29c2af0d1858")!, unit: .count)]
        let frozen = [curl, abduction, adduction, split].map { row in
            CoachWeekFrozenExercise(exerciseID: row.id, name: row.name, muscle: row.muscle, equipment: row.equipment, roles: row.roles,
                plannedSets: (0..<(row.id == curl.id ? 4 : 3)).map { _ in WorkoutSetPlan(weight: 0, reps: 8) })
        }
        let prior = CoachWeekExisting(id: UUID(), localDay: "2026-10-26", title: "前链冻结处方", status: "planned", source: "日程",
            exerciseIDs: frozen.map(\.exerciseID), frozenExercises: frozen)
        let rope = CoachWeekExisting(id: UUID(), localDay: "2026-10-27", title: "已确认跳绳计划", status: "planned", source: "日程", knownCardio: true, cardioMode: "跳绳")
        let result = try day(input(r3 + [abduction, adduction, split, reverse], existing: [prior, rope]), focus: "后链")
        XCTAssertEqual(Set(result.movements.map(\.id)).intersection(Set(frozen.map(\.exerciseID))), [curl.id])
        XCTAssertFalse(result.movements.contains { $0.roles.contains("单腿") || $0.roles.contains("髋外展") || $0.roles.contains("髋内收") })
        XCTAssertTrue(result.blockers.isEmpty, result.blockers.joined(separator: "；"))
        XCTAssertEqual(result.movements.first?.exercise.catalogName, "双手髋铰链壶铃摆动")
        XCTAssertTrue(result.movements.filter { $0.roles.contains("技术") || $0.exercise.volumeUnit == .count }.allSatisfy { $0.exercise.planPattern == .fixed })
        XCTAssertTrue(result.movements.filter { $0.roles.contains("技术") }.allSatisfy { $0.exercise.plannedSets.allSatisfy { $0.prescription?.rirLower == nil } })
        XCTAssertEqual(Set(result.movements.compactMap(\.loadRole)), ["重主项", "中等辅助", "轻负荷正式任务", "技术/速度"])
        XCTAssertEqual([curl, abduction, adduction].reduce(0) { $0 + ( $1.id == curl.id ? 4 : 3 ) }, 10,
            "Historical R2 comparison: three exact repeats correspond to 10 planned sets, not observed completed work.")
    }

    func testAttachmentExclusionDoesNotRejectMachineAbduction() {
        for name in ["绳索后踢", "Cable Glute Kickback", "cable hip abduction"] {
            XCTAssertTrue(CoachWeekService.requiresAnkleAttachment(name: name, equipment: "龙门架"))
        }
        XCTAssertFalse(CoachWeekService.requiresAnkleAttachment(name: "器械髋外展", equipment: "髋外展机"))
        XCTAssertTrue(CoachWeekService.requiresAnkleAttachment(name: "髋外展", equipment: "龙门架"))
        XCTAssertTrue(CoachWeekService.requiresAnkleAttachment(name: "后踢", equipment: "龙门架"))
        XCTAssertFalse(CoachWeekService.requiresAnkleAttachment(name: "绳索肩外展", equipment: "龙门架"))
    }

    func testRevalidationRebuildsRolesAndCountsEverySetSideAndRest() throws {
        let source = input(backR5)
        var edited = try day(source, focus: "背")
        let oldTime = try XCTUnwrap(edited.estimatedSeconds)
        edited.estimatedSeconds = 1
        edited.movements[0].roles = ["髋伸"]
        edited.movements[0].unilateral = false
        for index in edited.movements[0].exercise.plannedSets.indices {
            edited.movements[0].exercise.plannedSets[index].repsSide = .single
        }
        let result = CoachWeekService.revalidateStrength(edited, input: source)
        XCTAssertEqual(result.movements[0].roles, source.catalog.first { $0.id == result.movements[0].id }?.roles)
        XCTAssertTrue(result.movements[0].unilateral)
        XCTAssertGreaterThan(try XCTUnwrap(result.estimatedSeconds), oldTime)
    }

    func testLateSupplementaryRIRNeverUpgradesAutomaticEligibilityOrAnotherSet() throws {
        let squat = item("深蹲", "腿部", "杠铃")
        let plans = (0..<4).map { _ in WorkoutSetPlan(weight: 30, reps: 8, weightSide: .single, repsSide: .bilateral) }
        let logs = (0..<4).map { _ in CoachActualSet(id: UUID(), weight: 30, reps: 8, rir: nil, weightSide: .single, repsSide: .bilateral, completed: true, warmup: false) }
        let actual = CoachWeekActual(id: UUID(), sessionID: UUID(), localDay: "2026-10-26", exerciseID: squat.id, name: squat.name,
            equipment: squat.equipment, unit: .kilogram, plannedSets: plans, actual: logs, feedback: "Synthetic",
            loadConvention: "每侧片重", supplementaryLastRIR: 3, classificationKnown: true, supplementaryLastSetID: logs.last!.id)
        let result = try XCTUnwrap(day(input([squat], history: [actual]), focus: "腿").movements.first)
        XCTAssertTrue(result.exercise.loadGuidance.contains("人工参考"))
        XCTAssertEqual(result.exercise.plannedSets.map(\.weight), [30, 30, 30, 30])
        XCTAssertEqual(result.evidence.filter { $0.contains("仅绑定该末条") }.count, 1)
    }

    func testSameUUIDMachineWithoutSettingsRemainsManualAndGenericEquipmentHasNoLoadTransfer() throws {
        for equipment in ["器械", "坐姿腿弯举机"] {
            let curl = item("坐姿腿弯举", "腿部", equipment)
            let sets = (0..<3).map { _ in CoachActualSet(id: UUID(), weight: 45, reps: 10, rir: 3, weightSide: .bilateral, repsSide: .bilateral, completed: true, warmup: false) }
            let plans = (0..<3).map { _ in WorkoutSetPlan(weight: 45, reps: 10, weightSide: .bilateral, repsSide: .bilateral) }
            let actual = CoachWeekActual(id: UUID(), sessionID: UUID(), localDay: "2026-10-26", exerciseID: curl.id, name: curl.name,
                equipment: equipment, unit: .kilogram, plannedSets: plans, actual: sets, feedback: "Synthetic", loadConvention: "显示kg", classificationKnown: true)
            let result = try XCTUnwrap(day(input([curl], history: [actual]), focus: "后链").movements.first)
            XCTAssertFalse(result.exercise.loadGuidance.contains("近42天"))
            XCTAssertEqual(result.exercise.plannedSets.first?.weight, equipment == "器械" ? 0 : 45)
        }
    }

    func testChangingOneDayPreservesOtherManualPrescriptions() throws {
        let source = input(chestR2 + backR5)
        let goals = source.preferences.map { CoachWeekGoal(localDay: $0.localDay, kind: .rest, focus: "", reason: "测试") }
        var draft = try CoachWeekService.generate(input: source, goals: goals)
        var days = draft.days
        days[4] = try day(source, focus: "背", date: days[4].localDay)
        days[4].movements[0].exercise.plannedSets[0].weight = 37
        days[4] = CoachWeekService.revalidateStrength(days[4], input: source)
        draft = CoachWeekDraft(id: draft.id, rootID: draft.rootID, revision: draft.revision, createdAt: draft.createdAt,
            sourceFingerprint: draft.sourceFingerprint, input: source, days: days, edits: [], ruleCandidates: [])
        let changed = try CoachWeekService.regenerateDay(draft, goal: CoachWeekGoal(localDay: days[0].localDay, kind: .strength, focus: "胸", reason: "测试"))
        XCTAssertEqual(changed[4], days[4])
        XCTAssertEqual(changed[4].movements[0].exercise.plannedSets[0].weight, 37)
    }

    func testExpiredExceptionDoesNotReplaceNextWeekDefault() throws {
        let exception = CoachWeekException(id: UUID(), startDay: "2026-10-19", endDay: "2026-10-25", reason: "过期上肢周", goals: [], confirmation: "历史确认")
        let source = input(chestR2 + backR5, exception: exception)
        let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(source.startDay, timeZone: zone)!, zone: zone)
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        XCTAssertEqual(draft.days.filter { $0.kind == .strength }.count, 4)
        XCTAssertEqual(draft.days.filter { $0.cardio != nil }.count, 1)
        XCTAssertEqual(draft.days.filter { $0.zone2 != nil }.count, 0)
        XCTAssertEqual(draft.days.filter { $0.kind == .rest }.count, 2)
    }

    func testRevalidationRejectsMissingLoadRoleAndExcessTimeAfterEditing() throws {
        let source = input(backR5)
        var edited = try day(source, focus: "背")
        for movementIndex in edited.movements.indices {
            for setIndex in edited.movements[movementIndex].exercise.plannedSets.indices {
                edited.movements[movementIndex].exercise.plannedSets[setIndex].prescription?.label = "中等辅助"
                edited.movements[movementIndex].exercise.plannedSets[setIndex].prescription?.restUpperSeconds = 900
            }
        }
        edited.estimatedSeconds = 10
        let checked = CoachWeekService.revalidateStrength(edited, input: source)
        XCTAssertTrue(checked.blockers.contains { $0.contains("负荷角色") })
        XCTAssertTrue(checked.blockers.contains { $0.contains("估时") })
    }

    func testPreservedZone2ConsumesZone2GoalButUnknownCardioAndSkippedDoNot() throws {
        let zone2 = CoachWeekExisting(id: UUID(), localDay: "2026-10-28", title: "已确认单车", status: "planned", source: "日程", knownCardio: true, cardioMode: "Zone 2")
        let source = input(chestR2 + backR5, existing: [zone2])
        let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(source.startDay, timeZone: zone)!, zone: zone)
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        XCTAssertEqual(draft.days.filter { $0.zone2 != nil }.count, 0)
        XCTAssertEqual(draft.days.filter { $0.cardio != nil }.count, 0)
        XCTAssertTrue(draft.weeklyShortfall?.contains { $0.contains("跳绳候选缺2") } == true)
        let unknown = CoachWeekExisting(id: UUID(), localDay: "2026-10-28", title: "有氧模式未知", status: "planned", source: "日程", knownCardio: true)
        let skipped = CoachWeekExisting(id: UUID(), localDay: "2026-10-28", title: "已跳过跳绳", status: "skipped", source: "日程", knownCardio: true, cardioMode: "跳绳")
        var days = draft.days
        days[2].existing = [unknown, skipped]
        XCTAssertTrue(CoachWeekService.weeklyShortfalls(days, input: source).contains { $0.contains("Zone 2候选缺") })
        days[2].existing = [skipped]
        XCTAssertTrue(CoachWeekService.revalidateWeek(days, input: source)[2].blockers.contains { $0.contains("已有跳过") })
    }

    func testNonDefaultPreferenceAndExpiredExceptionDoNotSilentlyOverrideFrequency() throws {
        var preference = TrainingPreferenceSnapshot.confirmed
        preference.strengthDaysPerWeek = 3
        preference.zone2Minutes = 25
        let expired = CoachWeekException(id: UUID(), startDay: "2026-10-19", endDay: "2026-10-25", reason: "旧周", goals: [], confirmation: "历史确认")
        let source = input(chestR2, exception: expired, snapshot: preference)
        let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(source.startDay, timeZone: zone)!, zone: zone)
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        XCTAssertTrue(draft.days[0].blockers.contains { $0.contains("偏好冲突") })
        let explicit = try CoachWeekService.generate(input: source, goals: [CoachWeekGoal(localDay: "2026-10-28", kind: .cardio, focus: "Zone 2", reason: "本人主动选择")])
        XCTAssertEqual(explicit.days[2].zone2?.durationSeconds, 1500)
    }

    func testKnownBoundaryStrengthCreatesCrossWeekConflictButMissingBoundaryIsUnknown() throws {
        let catalog = chestR2 + backR5
        let prior = CoachWeekExisting(id: UUID(), localDay: "2026-10-25", title: "相邻周力量", status: "planned", source: "临近周边界安排", exerciseIDs: [catalog[0].id], frozenExercises: [frozen(catalog[0])])
        let source = input(catalog, existing: [prior])
        let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(source.startDay, timeZone: zone)!, zone: zone)
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        XCTAssertTrue(draft.days[0].blockers.contains { $0.contains("跨周连续") })
        XCTAssertTrue(draft.days[1].blockers.contains { $0.contains("跨周连续") })
        let noBoundary = try CoachWeekService.generate(input: input(catalog), goals: goals)
        XCTAssertTrue(noBoundary.days[0].rationale.contains { $0.contains("相邻周暴露未知") })
    }

    func testExplicitRecoveryConcernBlocksNormalDoseButUnknownDoesNot() throws {
        let catalog = chestR2
        let time = TrainingLocalDate.date("2026-10-27", timeZone: zone)!
        let adverse = CoachWeekRecoverySignal(id: UUID(), sessionID: UUID(), trainingDay: "2026-10-26", capturedAt: time,
            feedback: CoachFeedback(stage: "morning", pain: "yes", function: "limited", recovery: "poor"))
        let blocked = try day(input(catalog, recovery: [adverse]), focus: "胸")
        XCTAssertTrue(blocked.blockers.contains { $0.contains("恢复待处理") && $0.contains(adverse.sessionID.uuidString) })
        let unknown = CoachWeekRecoverySignal(id: UUID(), sessionID: adverse.sessionID, trainingDay: adverse.trainingDay,
            capturedAt: time, feedback: CoachFeedback(stage: "morning"))
        XCTAssertFalse(try day(input(catalog, recovery: [unknown]), focus: "胸").blockers.contains { $0.contains("恢复待处理") })
        let resolved = CoachWeekRecoverySignal(id: UUID(), sessionID: adverse.sessionID, trainingDay: adverse.trainingDay,
            capturedAt: time.addingTimeInterval(3600), feedback: CoachFeedback(stage: "morning", pain: "none", function: "normal", recovery: "good"))
        XCTAssertFalse(try day(input(catalog, recovery: [adverse, resolved]), focus: "胸").blockers.contains { $0.contains("恢复待处理") })
    }

    private func captureContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, ScheduledWorkout.self, WorkoutSession.self, SessionExercise.self, SetLog.self,
                             TrainingPreferenceRevision.self, TrainingCoachRecord.self, DailyBodyCheckIn.self, JumpRopeEntry.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    func testLegacyMissingPlanJSONFingerprintIsStableAndLateFeedbackDoesNotLeakIntoCapture() throws {
        let container = try captureContainer()
        let context = ModelContext(container)
        let now = TrainingLocalDate.date("2026-10-28", timeZone: zone)!
        let session = WorkoutSession(templateName: "合成旧历史", plannedDate: now.addingTimeInterval(-86400), completedAt: now.addingTimeInterval(-3600), status: .completed)
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: UUID(), exerciseName: "深蹲", order: 0,
            targetSets: 4, minReps: 8, maxReps: 10, targetWeight: 30, restSeconds: 180, equipmentSnapshot: "杠铃")
        snapshot.plannedSetsJSON = nil
        let late = TrainingCoachRecord(sessionID: session.id, kind: "morning", payloadJSON: try TrainingCoachService.encode(CoachFeedback(stage: "morning", pain: "yes")), createdAt: now.addingTimeInterval(3600))
        let check = DailyBodyCheckIn(date: now.addingTimeInterval(-86400), conditionScore: 2)
        check.createdAt = now.addingTimeInterval(3600)
        check.updatedAt = check.createdAt
        context.insert(session); context.insert(snapshot); context.insert(late); context.insert(check)
        try context.save()
        let first = try CoachWeekService.capture(start: now, exception: nil, now: now, in: context)
        let second = try CoachWeekService.capture(start: now, exception: nil, now: now, in: context)
        XCTAssertEqual(try CoachWeekService.fingerprint(first), try CoachWeekService.fingerprint(second))
        XCTAssertEqual(first.history.first?.plannedSets, [])
        XCTAssertNil(first.history.first?.loadConvention)
        XCTAssertEqual(first.recoverySignals, [])
        XCTAssertEqual(first.recovery, [])
        XCTAssertEqual(try CoachWeekService.capture(start: now, exception: nil, now: now.addingTimeInterval(7200), in: context).recoverySignals?.count, 1)
    }

    func testUnrelatedEditAndOutcomeWithoutEditsNeverActivateRankingRule() throws {
        let source = input(chestR2)
        let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(source.startDay, timeZone: zone)!, zone: zone)
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        let edit = CoachWeekEdit(id: UUID(), day: source.startDay, field: "备注", before: "", after: "早晨", reason: "只补备注")
        let candidate = try CoachWeekService.ruleCandidate(original: draft, revisedDays: draft.days, edits: [edit])
        XCTAssertNil(candidate.executableVersion)
        XCTAssertEqual(candidate.status, "仅记录")
        let outcome = CoachWeekOutcome(draftID: UUID(), capturedAt: .now, sessionIDs: [], actual: [], recovery: [], unknowns: ["未产生完成记录"], rootID: draft.rootID, sourceFingerprint: draft.sourceFingerprint)
        let observation = try CoachWeekService.ruleCandidate(original: draft, revisedDays: draft.days, edits: [], outcome: outcome)
        XCTAssertNil(observation.executableVersion)
        XCTAssertEqual(observation.replayEditIDs, [])
        XCTAssertEqual(observation.outcome, outcome)
    }


    func testRelevantRepeatEditReplaysActivatesAndRollsBackAfterEarlierUnrelatedEdit() throws {
        let catalog = (backR5 + [item("高位下拉", "背部", "器械")]).map {
            item($0.name, $0.muscle, $0.equipment, id: $0.id, unit: $0.unit, method: CoachWeekService.legacyMethodVersion)
        }
        let repeated = catalog[0]
        let actual = CoachWeekActual(id: UUID(), sessionID: UUID(), localDay: "2026-10-25", exerciseID: repeated.id,
            name: repeated.name, equipment: repeated.equipment, unit: .kilogram, plannedSets: [],
            actual: [CoachActualSet(id: UUID(), weight: 20, reps: 10, rir: nil, weightSide: .unknown, repsSide: .unknown, completed: true, warmup: false)], feedback: "合成暴露证据", classificationKnown: false)
        let dates = input([]).preferences.map(\.localDay)
        let goals = dates.map { CoachWeekGoal(localDay: $0, kind: $0 == "2026-10-28" ? .strength : .rest, focus: $0 == "2026-10-28" ? "背" : "", reason: "仅本周隔离测试目标") }
        let exception = CoachWeekException(id: UUID(), startDay: dates[0], endDay: dates[6], reason: "隔离测试周目标", goals: goals, confirmation: "测试")
        let source = input(catalog, history: [actual], method: CoachWeekService.legacyMethodVersion, exception: exception)
        let original = try CoachWeekService.generate(input: source, goals: goals)
        let context = ModelContext(try captureContainer())
        try CoachWeekService.save(original, in: context)
        var firstDays = original.days
        firstDays[0].rationale.append("人工备注")
        let firstEdit = CoachWeekEdit(id: UUID(), day: dates[0], field: "备注", before: "", after: "人工备注", reason: "备注补充")
        let first = try CoachWeekService.revise(original, days: firstDays, edits: [firstEdit], candidates: [], in: context)
        let variantInput = input(catalog, history: [actual], version: CoachWeekService.overlapRuleVersion, method: CoachWeekService.legacyMethodVersion, exception: exception)
        let variant = try CoachWeekService.generate(input: variantInput, goals: goals)
        var revised = first.days
        revised[2] = variant.days[2]
        XCTAssertTrue(first.days[2].movements.contains { $0.id == repeated.id })
        XCTAssertFalse(revised[2].movements.contains { $0.id == repeated.id })
        let secondEdit = CoachWeekEdit(id: UUID(), day: dates[2], field: "动作", before: repeated.name, after: "改用另一具体下拉", reason: "近期已做同UUID，希望保留角色并减少重复")
        let candidate = try CoachWeekService.ruleCandidate(original: first, revisedDays: revised, edits: [secondEdit])
        XCTAssertEqual(candidate.executableVersion, CoachWeekService.overlapRuleVersion, candidate.replayResult)
        XCTAssertEqual(candidate.replayEditIDs, [secondEdit.id])
        let saved = try CoachWeekService.revise(first, days: revised, edits: [secondEdit], candidates: [candidate], in: context)
        XCTAssertEqual(saved.edits.count, 2)
        XCTAssertEqual(try CoachWeekService.activateRuleCandidate(candidate, draft: saved, in: context), CoachWeekService.overlapRuleVersion)
        XCTAssertEqual(try CoachWeekService.activeRuleVersion(in: context), CoachWeekService.overlapRuleVersion)
        let captured = try CoachWeekService.capture(start: TrainingLocalDate.date(source.startDay, timeZone: zone)!, exception: exception, in: context)
        XCTAssertEqual(captured.personalRuleVersion, CoachWeekService.overlapRuleVersion)
        XCTAssertEqual(try CoachWeekService.rollbackRule(in: context), CoachWeekService.personalRuleVersion)
        XCTAssertEqual(try CoachWeekService.activeRuleVersion(in: context), CoachWeekService.personalRuleVersion)
    }

    func testConfirmationRecomputesWeekInsteadOfTrustingClearedCache() throws {
        let source = input(chestR2)
        let goals = source.preferences.map { CoachWeekGoal(localDay: $0.localDay, kind: .rest, focus: "", reason: "未经本周例外确认") }
        var draft = try CoachWeekService.generate(input: source, goals: goals)
        draft.weeklyShortfall = []
        let context = ModelContext(try captureContainer())
        XCTAssertThrowsError(try CoachWeekService.prepareConfirmation(draft, in: context)) { error in
            XCTAssertTrue(String(describing: error).contains("整周实际处方"))
        }
    }

    func testOutcomeUsesExactConfirmedScheduleIDsAcrossDatesAndKeepsMissingUnknown() throws {
        let container = try captureContainer()
        let context = ModelContext(container)
        let source = input([])
        let goals = source.preferences.map { CoachWeekGoal(localDay: $0.localDay, kind: .rest, focus: "", reason: "隔离关联测试") }
        let original = try CoachWeekService.generate(input: source, goals: goals)
        try CoachWeekService.save(original, in: context)
        let changed = CoachWeekEdit(id: UUID(), day: source.startDay, field: "备注", before: "", after: "已审阅", reason: "模拟人工审阅")
        let confirmed = try CoachWeekService.revise(original, days: original.days, edits: [changed], candidates: [], in: context)
        let time = TrainingLocalDate.date("2026-10-29", timeZone: zone)!
        let ropeID = UUID(), zoneID = UUID(), missingID = UUID()
        let packet = ConfirmedDailyTrainingPlanPacket(version: 1, id: zoneID, localDay: "2026-10-27", timeZoneIdentifier: zone.identifier,
            title: "合成Zone2关联", preferenceRevisionCode: "fixture", confirmedAt: time.addingTimeInterval(-86400),
            confirmationReference: "Synthetic association fixture only", sourceMarkdown: "", sourceSHA256: "", guidance: "", exercises: [])
        // This fixture tests read association, not transaction acceptance; transactional sealing has its own suite.
        let request = CoachWeekConfirmation(id: UUID(), draft: confirmed, confirmedAt: packet.confirmedAt,
            members: [ConfirmedDailyTrainingPlanPreview(packet: packet, packetSHA256: "fixture", destinationFingerprint: "fixture", conflicts: [], newScheduleCount: 1)],
            ropes: [CoachWeekRopeMember(id: ropeID, localDay: "2026-10-27", plan: JumpRopeMenuPlan(targetCount: nil, activeSeconds: 300, elapsedSeconds: 900, notes: "fixture")),
                    CoachWeekRopeMember(id: missingID, localDay: "2026-10-28", plan: JumpRopeMenuPlan(targetCount: nil, activeSeconds: 300, elapsedSeconds: 900, notes: "fixture"))], dayDigests: [:], requestDigest: "fixture")
        try TrainingCoachService.append(request, kind: "week_confirmation", sessionID: confirmed.rootID, id: request.id, in: context)
        let linkedRope = JumpRopeEntry(count: 500, activeDurationSeconds: 300, elapsedDurationSeconds: 900, date: time.addingTimeInterval(-3600), createdAt: time.addingTimeInterval(-3000))
        linkedRope.scheduledWorkoutID = ropeID
        let unrelatedRope = JumpRopeEntry(count: 999, date: linkedRope.date, createdAt: linkedRope.createdAt)
        let session = WorkoutSession(templateName: "改期后Zone2", plannedDate: time.addingTimeInterval(-3600), completedAt: time.addingTimeInterval(-1000), status: .completed)
        session.scheduledWorkoutID = zoneID
        let exerciseID = UUID()
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: exerciseID, exerciseName: "单车", order: 0, targetSets: 1,
            minReps: 1800, maxReps: 1800, targetWeight: 0, restSeconds: 0, volumeUnit: .second)
        let log = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exerciseID, setNumber: 1,
            targetWeight: 0, targetReps: 1800, actualWeight: 0, actualReps: 1800, rir: nil, isCompleted: true)
        context.insert(linkedRope); context.insert(unrelatedRope); context.insert(session); context.insert(snapshot); context.insert(log)
        try context.save()
        let outcome = try CoachWeekService.evaluateOutcome(confirmed, now: time, in: context)
        XCTAssertEqual(outcome.ropeActual.map(\.id), [linkedRope.id])
        XCTAssertEqual(outcome.sessionIDs, [session.id])
        XCTAssertEqual(outcome.actual.first?.actual.first?.id, log.id)
        XCTAssertTrue(outcome.unknowns.contains { $0.contains(missingID.uuidString) })
        XCTAssertTrue(outcome.unknowns.contains { $0.contains("次晨恢复") })
        let candidate = try CoachWeekService.ruleCandidateFromOutcome(confirmed, now: time, in: context)
        XCTAssertEqual(candidate.replaySourceDraftID, original.id)
        XCTAssertEqual(candidate.outcome?.draftID, confirmed.id)
        let appended = try CoachWeekService.saveOutcomeRuleCandidate(confirmed, candidate: candidate, in: context)
        XCTAssertEqual(appended.days, confirmed.days)
        XCTAssertEqual(appended.edits, confirmed.edits)
        XCTAssertEqual(appended.revision, confirmed.revision + 1)
        var foreign = outcome
        foreign.rootID = UUID()
        XCTAssertThrowsError(try CoachWeekService.ruleCandidate(original: original, revisedDays: confirmed.days, edits: [changed], outcome: foreign))
    }


    func testZone2AlsoRequiresReviewOfExplicitRecoveryConcern() throws {
        let time = TrainingLocalDate.date("2026-10-27", timeZone: zone)!
        let signal = CoachWeekRecoverySignal(id: UUID(), sessionID: UUID(), trainingDay: "2026-10-26", capturedAt: time,
            feedback: CoachFeedback(stage: "morning", recovery: "poor"))
        let source = input([], recovery: [signal])
        let goal = CoachWeekGoal(localDay: "2026-10-28", kind: .cardio, focus: "Zone 2", reason: "隔离测试")
        let draft = try CoachWeekService.generate(input: source, goals: [goal])
        XCTAssertTrue(draft.days[2].blockers.contains { $0.contains("恢复待处理") })
    }

    func testUnstructuredBodyReportRemainsVisibleAfterUnrelatedNormalFeedback() throws {
        let time = TrainingLocalDate.date("2026-10-27", timeZone: zone)!
        let report = CoachWeekBodyReport(id: UUID(), localDay: "2026-10-26", capturedAt: time, note: "本人待核说明", hasBodyMarkers: true)
        let unrelated = CoachWeekRecoverySignal(id: UUID(), sessionID: UUID(), trainingDay: "2026-10-27", capturedAt: time.addingTimeInterval(3600),
            feedback: CoachFeedback(stage: "morning", pain: "none", function: "normal", recovery: "good"))
        let result = try day(input(chestR2, recovery: [unrelated], bodyReports: [report]), focus: "胸")
        XCTAssertTrue(result.rationale.contains { $0.contains(report.id.uuidString) && $0.contains("恢复需本人核对") })
        XCTAssertFalse(result.blockers.contains { $0.contains("已报告疼痛") })
    }

    func testCivilDayBoundaryAcrossDSTDoesNotLosePreviousDayStrength() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        let start = TrainingLocalDate.date("2026-11-01", timeZone: ny)!
        let dates = CoachWeekService.dateKeys(start: start, zone: ny)
        XCTAssertEqual(dates, ["2026-11-01", "2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"])
        let catalog = chestR2 + backR5
        let prior = CoachWeekExisting(id: UUID(), localDay: "2026-10-31", title: "合成边界力量", status: "planned", source: "临近周边界安排", exerciseIDs: [catalog[0].id], frozenExercises: [frozen(catalog[0])])
        let source = CoachWeekInput(startDay: dates[0], timeZone: ny.identifier, methodVersion: CoachWeekService.methodVersion,
            personalRuleVersion: CoachWeekService.personalRuleVersion, preferences: dates.map { CoachWeekPreference(localDay: $0, revisionID: nil, code: "fixture", snapshot: .confirmed) },
            exception: nil, catalog: catalog, history: [], existing: [prior], recovery: [], unknowns: [], capturedLocalDay: dates[0])
        let goals = dates.enumerated().map { index, day in CoachWeekGoal(localDay: day, kind: index < 2 ? .strength : .rest, focus: index == 0 ? "胸" : "背", reason: "隔离DST边界") }
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        XCTAssertTrue(draft.days[0].blockers.contains { $0.contains("跨周连续") })
        XCTAssertTrue(draft.days[1].blockers.contains { $0.contains("跨周连续") })
    }


    func testOrphanActivationAndForgedRollbackCannotChangeActiveRule() throws {
        for rollback in [false, true] {
            let container = try captureContainer()
            let context = ModelContext(container)
            let record = CoachWeekRuleActivation(id: UUID(), version: CoachWeekService.overlapRuleVersion,
                previousVersion: CoachWeekService.personalRuleVersion, candidateID: rollback ? nil : UUID(), sourceDraftID: UUID(),
                replayFingerprint: String(repeating: "a", count: 64), createdAt: .now, rollbackOfActivationID: rollback ? UUID() : nil)
            context.insert(TrainingCoachRecord(id: record.id, sessionID: UUID(uuidString: "78283952-B6AC-4B03-B215-76864BE804D1")!,
                kind: "week_rule_activation", payloadJSON: try TrainingCoachService.encode(record)))
            try context.save()
            XCTAssertThrowsError(try CoachWeekService.validateStoredRuleActivations(in: context))
            XCTAssertThrowsError(try CoachWeekService.activeRuleVersion(in: context))
        }
    }


    func testDefaultWeekLeavesWeekendRestAndUnscheduledCardioAsPending() throws {
        let source = input(chestR2 + backR5)
        let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(source.startDay, timeZone: zone)!, zone: zone)
        XCTAssertEqual(goals.map(\.focus), ["胸", "背", "跳绳", "腿", "肩", "", ""])
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        XCTAssertTrue(draft.days.suffix(2).allSatisfy { $0.kind == .rest })
        XCTAssertTrue(draft.weeklyShortfall?.contains { $0.contains("跳绳候选缺1") } == true)
        XCTAssertTrue(draft.weeklyShortfall?.contains { $0.contains("Zone 2候选缺1") } == true)
        let context = ModelContext(try captureContainer())
        XCTAssertThrowsError(try CoachWeekService.prepareConfirmation(draft, in: context))
        let changed = try CoachWeekService.regenerateDay(draft, goal: CoachWeekGoal(localDay: "2026-10-31", kind: .cardio, focus: "跳绳", reason: "本人主动选择本周六"))
        let shortfalls = CoachWeekService.weeklyShortfalls(changed, input: source)
        XCTAssertFalse(shortfalls.contains { $0.contains("跳绳候选缺") })
        XCTAssertTrue(shortfalls.contains { $0.contains("Zone 2候选缺1") })
        let exceptionGoals = changed.map { CoachWeekGoal(localDay: $0.localDay, kind: $0.kind, focus: $0.focus, reason: "本人明确本周目标") }
        let exception = CoachWeekException(id: UUID(), startDay: "2026-10-26", endDay: "2026-11-01", reason: "本人同意本周不排Zone2", goals: exceptionGoals, confirmation: "隔离确认")
        XCTAssertFalse(CoachWeekService.weeklyShortfalls(changed, input: input(source.catalog, exception: exception)).contains { $0.contains("Zone 2候选缺") })
    }

    func testPreservedBackConsumesBackTargetAndDefersImpossibleWeekdayTaskInsteadOfWeekend() throws {
        let catalog = chestR2 + backR5
        let saved = CoachWeekExisting(id: UUID(), localDay: "2026-10-28", title: "明确背部冻结处方", status: "planned", source: "日程",
            exerciseIDs: backR5.map(\.id), frozenExercises: backR5.map(frozen))
        let source = input(catalog, existing: [saved])
        let goals = CoachWeekService.defaultGoals(start: TrainingLocalDate.date(source.startDay, timeZone: zone)!, zone: zone)
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        XCTAssertEqual(CoachWeekService.preservedFocus(on: saved.localDay, input: source), "背")
        XCTAssertFalse(draft.days.contains { $0.kind == .strength && $0.focus == "背" })
        XCTAssertTrue(draft.days.suffix(2).allSatisfy { $0.kind == .rest })
        XCTAssertFalse(draft.days.contains { $0.blockers.contains { $0.contains("连续三天") } })
        XCTAssertTrue(draft.weeklyShortfall?.contains { $0.contains("力量候选缺1") } == true)
        let unknown = CoachWeekExisting(id: UUID(), localDay: "2026-10-28", title: "原任务未知", status: "planned", source: "日程", exerciseIDs: backR5.map(\.id))
        let missing = try CoachWeekService.generate(input: input(catalog, existing: [unknown]), goals: goals)
        XCTAssertNil(CoachWeekService.preservedFocus(on: unknown.localDay, input: missing.input))
        XCTAssertTrue(missing.days[2].blockers.contains { $0.contains("保留主肌") })
    }

    func testTaskExposureUsesOriginalAndFrozenRolesWithoutCurrentCatalogBackfill() throws {
        let id = UUID()
        let current = item("杠铃卧推", "胸部", "杠铃", id: id)
        let actual = CoachWeekActual(id: UUID(), sessionID: UUID(), localDay: "2026-10-26", exerciseID: id, name: "坐姿腿弯举",
            equipment: "器械", unit: .kilogram, plannedSets: [], actual: [CoachActualSet(id: UUID(), weight: 40, reps: 10, rir: nil, weightSide: .unknown, repsSide: .unknown, completed: true, warmup: false)], feedback: "合成历史快照")
        let frozenRow = CoachWeekFrozenExercise(exerciseID: id, name: "罗马尼亚硬拉", muscle: "腿部", equipment: "杠铃", roles: ["髋铰链"], plannedSets: [])
        let saved = CoachWeekExisting(id: UUID(), localDay: "2026-10-27", title: "冻结旧任务", status: "planned", source: "日程", exerciseIDs: [id], frozenExercises: [frozenRow])
        let evidence = CoachWeekService.taskExposure(on: "2026-10-28", input: input([current], history: [actual], existing: [saved]), priorDays: [])
        XCTAssertEqual(evidence.actualRoles, ["屈膝"])
        XCTAssertEqual(evidence.scheduledRoles, ["髋铰链"])
        XCTAssertFalse(evidence.actualRoles.contains("水平推"))
        let unknownActual = CoachWeekActual(id: UUID(), sessionID: actual.sessionID, localDay: actual.localDay, exerciseID: id, name: "旧记录未识别",
            equipment: nil, unit: .kilogram, plannedSets: [], actual: actual.actual, feedback: "性质未知")
        let unknownSaved = CoachWeekExisting(id: UUID(), localDay: saved.localDay, title: "没有冻结任务", status: "planned", source: "日程", exerciseIDs: [id])
        let unknown = CoachWeekService.taskExposure(on: "2026-10-28", input: input([current], history: [unknownActual], existing: [unknownSaved]), priorDays: [])
        XCTAssertTrue(unknown.actualRoles.isEmpty)
        XCTAssertTrue(unknown.scheduledRoles.isEmpty)
        XCTAssertEqual(unknown.unknowns.count, 2)
    }

    func testPreservedReviewCreatesBoundNewRootAndRejectsConflictOrChangedSource() throws {
        let container = try captureContainer()
        let context = ModelContext(container)
        let start = TrainingLocalDate.date("2026-10-26", timeZone: zone)!
        let now = TrainingLocalDate.date("2026-10-28", timeZone: zone)!
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "旧目录任务待核", plannedDate: start)
        context.insert(schedule); try context.save()
        let source = try CoachWeekService.capture(start: start, exception: nil, now: now, in: context)
        let original = try CoachWeekService.generate(input: source, goals: CoachWeekService.defaultGoals(start: start, zone: zone), now: now)
        try CoachWeekService.save(original, in: context)
        XCTAssertThrowsError(try CoachWeekService.reviewPreservedArrangement(original, existingID: UUID(), kind: .strength, focus: "背", reason: "测试", now: now, in: context))
        let reviewed = try CoachWeekService.reviewPreservedArrangement(original, existingID: schedule.id, kind: .strength, focus: "背", reason: "本人核对这次实际安排为背部", now: now, in: context)
        XCTAssertNotEqual(reviewed.rootID, original.rootID)
        XCTAssertEqual(reviewed.days[0].existing, original.days[0].existing)
        XCTAssertEqual(reviewed.days[1].movements, original.days[1].movements)
        XCTAssertEqual(CoachWeekService.preservedFocus(on: original.days[0].localDay, input: reviewed.input), "背")
        XCTAssertTrue(CoachWeekService.taskExposure(on: "2026-10-28", input: reviewed.input, priorDays: []).unknowns.contains { $0.contains("冻结任务角色未知") })
        schedule.templateName = "来源已改变"
        try context.save()
        XCTAssertThrowsError(try CoachWeekService.capture(start: start, exception: nil, now: now, retainedReviews: reviewed.input.retainedReviews, in: context))

        let session = WorkoutSession(templateName: "已完成但任务未知", plannedDate: start.addingTimeInterval(86400), completedAt: now.addingTimeInterval(-3600), status: .completed)
        context.insert(session); try context.save()
        let changedSource = try CoachWeekService.capture(start: start, exception: nil, now: now, in: context)
        let second = try CoachWeekService.generate(input: changedSource, goals: CoachWeekService.defaultGoals(start: start, zone: zone), now: now)
        try CoachWeekService.save(second, in: context)
        XCTAssertThrowsError(try CoachWeekService.reviewPreservedArrangement(second, existingID: session.id, kind: .rest, focus: "", reason: "错误将已训练当休息", now: now, in: context))
    }


    func testKnownAndReviewedRowsAggregateWithoutInventingTaskRoles() throws {
        let known = CoachWeekExisting(id: UUID(), localDay: "2026-10-28", title: "已知背部", status: "planned", source: "日程", frozenExercises: backR5.map(frozen))
        let unknown = CoachWeekExisting(id: UUID(), localDay: known.localDay, title: "另一条待核", status: "planned", source: "日程")
        let review = CoachWeekRetainedReview(id: UUID(), existingID: unknown.id, localDay: unknown.localDay,
            sourceDigest: try ConfirmedTrainingPlanService.digest(unknown), kind: .strength, focus: "背", reason: "本人核对同为背部安排", confirmedAt: .now)
        let source = input(backR5, existing: [known, unknown], reviews: [review])
        XCTAssertEqual(CoachWeekService.preservedFocus(on: known.localDay, input: source), "背")
        XCTAssertTrue(CoachWeekService.taskExposure(on: "2026-10-29", input: source, priorDays: []).unknowns.contains { $0.contains(unknown.id.uuidString) })
        let forged = CoachWeekRetainedReview(id: UUID(), existingID: known.id, localDay: known.localDay,
            sourceDigest: try ConfirmedTrainingPlanService.digest(known), kind: .strength, focus: "胸", reason: "与已知背部冲突", confirmedAt: .now)
        XCTAssertEqual(CoachWeekService.preservedFocus(on: known.localDay, input: input(backR5, existing: [known], reviews: [forged])), "背")
    }

    func testReviewedRestCanBecomeExplicitFullWeekException() throws {
        let container = try captureContainer()
        let context = ModelContext(container)
        let start = TrainingLocalDate.date("2026-10-26", timeZone: zone)!
        let now = start
        let preference = try TrainingPreferenceRevision(snapshot: .confirmed, revision: 1, effectiveAt: start, reason: "隔离测试")
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "未知旧占位", plannedDate: start)
        context.insert(preference); context.insert(schedule); try context.save()
        let source = try CoachWeekService.capture(start: start, exception: nil, now: now, in: context)
        let goals = source.preferences.map { CoachWeekGoal(localDay: $0.localDay, kind: .rest, focus: "", reason: "本人拟恢复周") }
        let original = try CoachWeekService.generate(input: source, goals: goals, now: now)
        try CoachWeekService.save(original, in: context)
        let reviewed = try CoachWeekService.reviewPreservedArrangement(original, existingID: schedule.id, kind: .rest, focus: "", reason: "本人核对旧占位是休息", now: now, in: context)
        let frequency = try CoachWeekService.confirmWeekException(reviewed, reason: "本人明确本周恢复，七日休息", now: now, in: context)
        XCTAssertTrue((frequency.weeklyShortfall ?? []).contains { $0.contains("腹部") })
        let exception = try CoachWeekService.confirmCoreException(frequency, reason: "本人确认本周恢复时腹部例外", now: now, in: context)
        XCTAssertEqual(exception.input.exception?.goals.count, 7)
        XCTAssertTrue(exception.input.exception?.goals.allSatisfy { $0.kind == .rest } == true)
        XCTAssertEqual(exception.weeklyShortfall, [])
    }

    func testExplicitDayEditOverridesOldExceptionButKeepsOriginalQuotaUntilReconfirmed() throws {
        let dates = input([]).preferences.map(\.localDay)
        let goals = dates.map { CoachWeekGoal(localDay: $0, kind: $0 == "2026-10-28" ? .strength : .rest, focus: $0 == "2026-10-28" ? "胸" : "", reason: "原本人周例外") }
        let exception = CoachWeekException(id: UUID(), startDay: dates[0], endDay: dates[6], reason: "旧确认目标", goals: goals, confirmation: "测试")
        let source = input(chestR2, exception: exception)
        let draft = try CoachWeekService.generate(input: source, goals: goals)
        let changed = try CoachWeekService.regenerateDay(draft, goal: CoachWeekGoal(localDay: "2026-10-28", kind: .rest, focus: "", reason: "本人现在改为休息"))
        XCTAssertEqual(changed[2].kind, .rest)
        XCTAssertTrue(changed[2].movements.isEmpty)
        XCTAssertTrue(CoachWeekService.weeklyShortfalls(changed, input: source).contains { $0.contains("力量候选缺1") })
        XCTAssertEqual(draft.input.exception, exception)
    }

}
