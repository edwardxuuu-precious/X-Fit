import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class TrainingFeedbackTests: XCTestCase {
    func testScheduleMonthBoundsLeapFebruaryAndYearNavigation() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let leapDays = TrainingScheduleMonth.days("2024-02", timeZone: zone)
        XCTAssertEqual(leapDays.count, 29)
        XCTAssertEqual(leapDays.first, "2024-02-01")
        XCTAssertEqual(leapDays.last, "2024-02-29")
        XCTAssertEqual(TrainingScheduleMonth.days("2026-02", timeZone: zone).count, 28)
        XCTAssertEqual(TrainingScheduleMonth.shifted("2026-12", by: 1, timeZone: zone), "2027-01")
        XCTAssertEqual(TrainingScheduleMonth.shifted("2027-01", by: -1, timeZone: zone), "2026-12")
        XCTAssertTrue(TrainingScheduleMonth.days("2026-13", timeZone: zone).isEmpty)
        XCTAssertNil(TrainingScheduleMonth.shifted("invalid", by: 1, timeZone: zone))

        let plans = ["2026-09-30", "2026-10-01", "2026-10-31", "2026-11-01"].map { day in
            let plan = ScheduledWorkout(templateID: UUID(), templateName: day,
                plannedDate: TrainingLocalDate.date(day, timeZone: zone)!)
            plan.plannedLocalDay = day
            return plan
        }
        let october = TrainingScheduleMonthContent(month: "2026-10", schedules: plans,
            sessions: [], jumpRopeEntries: [], timeZone: zone)
        XCTAssertEqual(october.days.map(\.localDay), ["2026-10-01", "2026-10-31"])
        XCTAssertEqual(october.days.flatMap(\.entries).map(\.id),
            ["schedule:" + plans[1].id.uuidString, "schedule:" + plans[2].id.uuidString])
        XCTAssertTrue(TrainingScheduleMonthContent(month: "2026-08", schedules: plans,
            sessions: [], jumpRopeEntries: [], timeZone: zone).days.isEmpty,
            "空月不能自动插入今天或相邻月份")
    }

    func testScheduleMonthJoinsBeforeFilteringAndKeepsActualCivilMonth() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let planned = TrainingLocalDate.date("2026-09-30", timeZone: zone)!
        let actualDate = TrainingLocalDate.date("2026-10-01", timeZone: zone)!
        let plan = ScheduledWorkout(templateID: UUID(), templateName: "跨月训练",
            plannedDate: planned, status: .completed)
        plan.plannedLocalDay = "2026-09-30"
        let actual = WorkoutSession(scheduledWorkoutID: plan.id, templateName: "跨月训练",
            plannedDate: planned, startedAt: planned, completedAt: actualDate, status: .completed)
        actual.trainingLocalDay = "2026-10-01"

        for displayZone in [zone, TimeZone(identifier: "Australia/Sydney")!] {
            let september = TrainingScheduleMonthContent(month: "2026-09", schedules: [plan],
                sessions: [actual], jumpRopeEntries: [], timeZone: displayZone)
            XCTAssertTrue(september.days.isEmpty, "先裁九月再关联会重复显示已完成计划")
            let october = TrainingScheduleMonthContent(month: "2026-10", schedules: [plan],
                sessions: [actual], jumpRopeEntries: [], timeZone: displayZone)
            XCTAssertEqual(october.days.map(\.localDay), ["2026-10-01"])
            let entries = october.days.flatMap(\.entries)
            XCTAssertEqual(entries.count, 1)
            guard let first = entries.first, case .session(let row, let linked) = first else {
                XCTFail("跨月实际必须作为真实场次显示")
                return
            }
            XCTAssertEqual(row.id, actual.id)
            XCTAssertEqual(linked?.id, plan.id, "原计划在所选月外仍需保留明确关联")
        }
        XCTAssertEqual(plan.plannedLocalDay, "2026-09-30")
        XCTAssertEqual(plan.status, .completed)
        XCTAssertEqual(actual.trainingLocalDay, "2026-10-01")
        XCTAssertEqual(actual.startedAt, planned, "呈现不能改写原始时刻")
    }

    func testScheduleMonthKeepsMultipleActualsAndSameNamedPlansWhileDeduplicating() {
        let day = "2026-10-20", date = TrainingLocalDate.date("2026-10-20")!
        let fulfilled = ScheduledWorkout(templateID: UUID(), templateName: "同名训练",
            plannedDate: date, status: .completed)
        let firstPending = ScheduledWorkout(templateID: UUID(), templateName: "同名训练", plannedDate: date)
        let secondPending = ScheduledWorkout(templateID: UUID(), templateName: "同名训练", plannedDate: date)
        for plan in [fulfilled, firstPending, secondPending] { plan.plannedLocalDay = day }
        let first = WorkoutSession(id: firstPending.id, scheduledWorkoutID: fulfilled.id,
            templateName: "同名训练", plannedDate: date, startedAt: date,
            completedAt: date, status: .completed)
        let second = WorkoutSession(scheduledWorkoutID: fulfilled.id, templateName: "同名训练",
            plannedDate: date, startedAt: date.addingTimeInterval(3_600),
            completedAt: date.addingTimeInterval(4_000), status: .completed)
        for session in [first, second] { session.trainingLocalDay = day }
        let content = TrainingScheduleMonthContent(month: "2026-10",
            schedules: [fulfilled, firstPending, secondPending, fulfilled],
            sessions: [first, second, first], jumpRopeEntries: [])
        let entries = content.days.flatMap(\.entries)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(Set(entries.map(\.id)).count, 4, "不同实体类别使用同UUID时，列表身份仍应唯一")
        var planIDs = Set<UUID>(), actualIDs = Set<UUID>()
        for entry in entries {
            switch entry {
            case .arrangement(let plan): planIDs.insert(plan.id)
            case .session(let session, let linked):
                actualIDs.insert(session.id)
                XCTAssertEqual(linked?.id, fulfilled.id)
            case .jumpRope: XCTFail("未提供跳绳实际")
            }
        }
        XCTAssertEqual(planIDs, Set([firstPending.id, secondPending.id]))
        XCTAssertEqual(actualIDs, Set([first.id, second.id]), "一个计划的多次实际不能只保留最近一次")
        XCTAssertEqual(firstPending.status, .planned)
        XCTAssertEqual(secondPending.status, .planned)
    }

    func testScheduleMonthRetainsOrphansUnknownRopeAndPlanAfterDiscardedActual() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let day = "2026-10-15", date = TrainingLocalDate.date("2026-10-15", timeZone: zone)!
        let orphan = ScheduledWorkout(templateID: UUID(), templateName: "旧完成安排",
            plannedDate: date, status: .completed)
        let oldRopePlan = ScheduledWorkout(templateID: UUID(), templateName: "跳绳",
            plannedDate: date, status: .skipped)
        let pending = ScheduledWorkout(templateID: UUID(), templateName: "待练", plannedDate: date)
        for plan in [orphan, oldRopePlan, pending] { plan.plannedLocalDay = day }
        let discarded = WorkoutSession(scheduledWorkoutID: pending.id, templateName: "已放弃",
            plannedDate: date, status: .discarded)
        let active = WorkoutSession(templateName: "独立进行中", plannedDate: date)
        for session in [discarded, active] { session.trainingLocalDay = day }
        let legacyRope = JumpRopeEntry(count: nil, durationSeconds: 480, date: date)
        let ropeDay = "2026-10-31", ropeDate = TrainingLocalDate.date(ropeDay, timeZone: zone)!
        let ropePlan = ScheduledWorkout(templateID: UUID(), templateName: "跳绳",
            plannedDate: ropeDate, status: .completed)
        ropePlan.plannedLocalDay = ropeDay
        let laterInstant = TrainingLocalDate.date("2026-11-01", timeZone: zone)!
        let linkedRope = JumpRopeEntry(count: nil, activeDurationSeconds: 300, date: laterInstant)
        linkedRope.scheduledWorkoutID = ropePlan.id
        let content = TrainingScheduleMonthContent(month: "2026-10",
            schedules: [orphan, oldRopePlan, pending, ropePlan], sessions: [discarded, active],
            jumpRopeEntries: [legacyRope, legacyRope, linkedRope], timeZone: zone)
        XCTAssertEqual(content.days.map(\.localDay), [day, ropeDay])
        let entries = content.days.flatMap(\.entries)
        XCTAssertEqual(entries.count, 6)
        var planIDs = Set<UUID>(), actualIDs = Set<UUID>(), ropeIDs = Set<UUID>()
        for entry in entries {
            switch entry {
            case .arrangement(let plan): planIDs.insert(plan.id)
            case .session(let session, let linked):
                actualIDs.insert(session.id)
                XCTAssertNil(linked)
            case .jumpRope(let rope, let linked):
                ropeIDs.insert(rope.id)
                XCTAssertEqual(linked?.id, rope.id == linkedRope.id ? ropePlan.id : nil)
            }
        }
        XCTAssertEqual(planIDs, Set([orphan.id, oldRopePlan.id, pending.id]))
        XCTAssertEqual(actualIDs, Set([active.id]))
        XCTAssertEqual(ropeIDs, Set([legacyRope.id, linkedRope.id]))
        XCTAssertEqual(orphan.status, .completed, "孤立完成安排不能被制造成实际")
        XCTAssertEqual(oldRopePlan.status, .skipped)
        XCTAssertEqual(pending.status, .planned, "放弃的实际不能隐藏或完成原计划")
        XCTAssertEqual(active.status, .inProgress)
        XCTAssertNil(legacyRope.count)
        XCTAssertNil(legacyRope.scheduledWorkoutID, "旧跳绳不能按同日同名猜关联")
        XCTAssertEqual(legacyRope.durationSeconds, 480)
        XCTAssertEqual(linkedRope.date, laterInstant, "按关联civil day呈现不能改写原时间")
    }

    func testScheduleProgressFractionKeepsPartialEvidenceAndUnknownTotal() throws {
        let partial = TrainingWorkSetProgress(completed: 17, total: 20)
        XCTAssertEqual(try XCTUnwrap(partial.completionFraction), 0.85, accuracy: 0.000_001)
        XCTAssertEqual(TrainingWorkSetProgress(completed: 0, total: 20).completionFraction, 0)
        XCTAssertEqual(TrainingWorkSetProgress(completed: 25, total: 20).completionFraction, 1)
        XCTAssertEqual(TrainingWorkSetProgress(completed: -3, total: 20).completionFraction, 0)
        XCTAssertNil(TrainingWorkSetProgress(completed: 0, total: 0).completionFraction)
        XCTAssertNil(TrainingWorkSetProgress(completed: 17, total: 0).completionFraction)
        let feedback = TrainingDayFeedback(recordedEvents: [.init(state: .completed, workingSets: partial)])
        XCTAssertTrue(feedback.isPartial)
        XCTAssertEqual(feedback.tone, .amber)
        XCTAssertEqual(feedback.label, "已记录 17/20 组", "列表图形化不能删除详情依赖的精确事实")
    }

    func testScheduleCategoriesKeepIdentityAndActualEvidenceSeparate() {
        let day = "2026-10-20", date = TrainingLocalDate.date("2026-10-20")!
        let template = UUID()
        let first = ScheduledWorkout(templateID: template, templateName: "同名训练", plannedDate: date)
        let second = ScheduledWorkout(templateID: template, templateName: "同名训练", plannedDate: date)
        let skipped = ScheduledWorkout(templateID: template, templateName: "跳过", plannedDate: date, status: .skipped)
        let missing = ScheduledWorkout(templateID: template, templateName: "旧完成安排", plannedDate: date, status: .completed)
        let done = ScheduledWorkout(templateID: template, templateName: "已关联", plannedDate: date, status: .completed)
        let activePlan = ScheduledWorkout(templateID: template, templateName: "继续", plannedDate: date, status: .inProgress)
        let linked = WorkoutSession(scheduledWorkoutID: done.id, templateName: "已关联", plannedDate: date,
            completedAt: date, status: .completed)
        let independent = WorkoutSession(templateName: "独立实际", plannedDate: date, completedAt: date, status: .completed)
        let active = WorkoutSession(scheduledWorkoutID: activePlan.id, templateName: "继续", plannedDate: date)
        let soloActive = WorkoutSession(templateName: "独立进行中", plannedDate: date)
        let discarded = WorkoutSession(templateName: "已放弃", plannedDate: date, status: .discarded)
        let ropePlan = ScheduledWorkout(templateID: template, templateName: "跳绳", plannedDate: date, status: .completed)
        let rope = JumpRopeEntry(count: nil, activeDurationSeconds: 300, date: date)
        rope.scheduledWorkoutID = ropePlan.id
        let plans = [first, second, skipped, missing, done, activePlan, ropePlan]
        let actuals = [linked, independent, active, soloActive, discarded]
        for schedule in plans { schedule.plannedLocalDay = day }
        for session in actuals { session.trainingLocalDay = day }
        let result = TrainingScheduleDayContent(localDay: day, schedules: plans + [first],
            sessions: actuals + [linked], jumpRopeEntries: [rope, rope])
        XCTAssertEqual(Set(result.arrangements.map(\.id)), Set([first.id, second.id, skipped.id, missing.id, activePlan.id]))
        XCTAssertEqual(Set(result.recordedSessions.map(\.id)), Set([linked.id, independent.id]))
        XCTAssertEqual(result.independentActiveSessions.map(\.id), [soloActive.id])
        XCTAssertEqual(result.jumpRopeEntries.map(\.id), [rope.id])
        XCTAssertEqual(missing.status, .completed, "不能制造实际、丢弃旧安排或改写完成状态")
        XCTAssertEqual(first.status, .planned)
        XCTAssertNil(rope.count)
    }

    func testScheduleCategoriesRespectActualCivilDayEvenWhenPlanWasOnAnotherDay() {
        let planned = TrainingLocalDate.date("2026-10-19")!
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "跨日实际", plannedDate: planned, status: .completed)
        schedule.plannedLocalDay = "2026-10-19"
        let session = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: "跨日实际", plannedDate: planned,
            completedAt: planned, status: .completed)
        session.trainingLocalDay = "2026-10-20"
        let planDay = TrainingScheduleDayContent(localDay: "2026-10-19", schedules: [schedule], sessions: [session], jumpRopeEntries: [])
        let actualDay = TrainingScheduleDayContent(localDay: "2026-10-20", schedules: [schedule], sessions: [session], jumpRopeEntries: [])
        XCTAssertFalse(planDay.hasArrangements)
        XCTAssertFalse(planDay.hasRecords)
        XCTAssertEqual(actualDay.recordedSessions.map(\.id), [session.id])
        XCTAssertEqual(schedule.plannedLocalDay, "2026-10-19")
        XCTAssertEqual(session.trainingLocalDay, "2026-10-20")
    }

    func testQATitlesRemoveOnlyKnownMetadataAndKeepUnknownDescriptors() {
        let original = "下肢综合·已确认P5·20组"
        XCTAssertEqual(TrainingWorkoutPresentation.title(original), "下肢综合")
        XCTAssertEqual(original, "下肢综合·已确认P5·20组")
        XCTAssertEqual(TrainingWorkoutPresentation.title("推 · 自定义技术练习 · R4"), "推 · 自定义技术练习")
        XCTAssertEqual(TrainingWorkoutPresentation.title("R练习 · P动作"), "R练习 · P动作")
        XCTAssertEqual(TrainingWorkoutPresentation.title("R4"), "R4", "Do not replace an entire user title with empty text")
    }

    func testQAPromotesOnlyExplicitLocalLoadAndConditionalEvidence() {
        XCTAssertEqual(TrainingWorkoutPresentation.loadGuidance(in: "每侧片重，不含杆\n原始说明"), "每侧片重，不含杆")
        XCTAssertNil(TrainingWorkoutPresentation.loadGuidance(in: "热身5kg×8\n其他动作按每侧片重，不含杆"))
        XCTAssertNil(TrainingWorkoutPresentation.loadGuidance(in: "每侧12次，轻档5kg准备"))
        let notes = "原机配重区显示kg，双侧合计\n条件动作/试重：先核肩肘及三头恢复；仍未知或有不适则省去本动作3组，不补组。"
        XCTAssertNotNil(TrainingWorkoutPresentation.conditionNotice(in: notes))
        XCTAssertNil(TrainingWorkoutPresentation.conditionNotice(in: "一般说明：恢复未知或有不适时跳过其他条件动作"))
        XCTAssertNil(TrainingWorkoutPresentation.conditionNotice(in: "条件动作/试重：先核验机器设置。"))
    }

    func testQARecognizesConfirmedRawLoadWordingWithoutRewritingSource() {
        let explicitLines = [
            "每侧杠铃片kg，不含史密斯杆重",
            "单侧kg，不含未知器械初始阻力",
            "每侧配重栈显示8.75，沿用原机刻度；不跨滑轮换算实际阻力",
            "双手同一绳把，记录单个配重栈显示17.5",
            "kg per side； reps/RIR unknown Oct19",
            "kg/side； reps-side and RIR unknown"
        ]
        for line in explicitLines {
            XCTAssertEqual(TrainingWorkoutPresentation.loadGuidance(in: line + "\n后续原始说明"), line)
        }
        XCTAssertNil(TrainingWorkoutPresentation.loadGuidance(in: "热身：每侧杠铃片kg递增准备"))
        XCTAssertNil(TrainingWorkoutPresentation.loadGuidance(in: "口径未知\n其他动作单侧kg"))
    }

    func testQACompactTargetKeepsUnknownRIRUnknownAndRestSeparate() {
        let original = WorkoutSetPrescription(label: "顶组", repsLower: 8, repsUpper: 10,
            restLowerSeconds: 150, restUpperSeconds: 180, effortCue: "原始技术说明")
        XCTAssertEqual(TrainingWorkoutPresentation.compactTarget(original), "8–10次")
        XCTAssertEqual(TrainingWorkoutPresentation.rest(original), "休息150–180秒")
        XCTAssertNil(original.rirLower)
        XCTAssertTrue(original.summary.contains("原始技术说明"))
        XCTAssertTrue(original.summary.contains("顶组"))
    }

    func testUpcomingPresentationSplitsCardioDurationWithoutChangingSourceNames() {
        let source = "固定单车 · 稳定有氧35分钟 · R1"
        let presentation = TrainingWorkoutPresentation.upcoming(source)
        XCTAssertEqual(presentation.title, "固定单车")
        XCTAssertEqual(presentation.detail, "稳定有氧 · 35 分钟")
        XCTAssertEqual(presentation.symbolName, "figure.indoor.cycle")
        XCTAssertEqual(source, "固定单车 · 稳定有氧35分钟 · R1")
        XCTAssertEqual(TrainingWorkoutPresentation.upcoming("椭圆机 · 稳定有氧40分钟 · R1").detail, "稳定有氧 · 40 分钟")
    }

    func testUpcomingPresentationRetainsUsefulDescriptorsAndDoesNotInventDuration() {
        let strength = TrainingWorkoutPresentation.upcoming("背部＋二头 · R2建议预填 · 22组")
        XCTAssertEqual(strength.title, "背部＋二头")
        XCTAssertNil(strength.detail)
        XCTAssertEqual(strength.symbolName, "dumbbell")
        let custom = TrainingWorkoutPresentation.upcoming("推 · 胸肩三头 · 技术练习 · R1")
        XCTAssertEqual(custom.title, "推")
        XCTAssertEqual(custom.detail, "胸肩三头 · 技术练习")
        XCTAssertNil(TrainingWorkoutPresentation.upcoming("固定单车 · R1").detail)
    }

    func testIndependentActualWorkoutDoesNotLookUntrainedWhenOldPlanIsPending() {
        let date = TrainingLocalDate.date("2026-10-15")!
        let oldPlan = ScheduledWorkout(templateID: UUID(), templateName: "旧恢复周", plannedDate: date)
        let actual = WorkoutSession(templateName: "实际后侧", plannedDate: date,
            startedAt: date, completedAt: date.addingTimeInterval(3_600), status: .completed)
        actual.trainingLocalDay = "2026-10-15"
        let summary = TrainingDaySummary(localDay: "2026-10-15", schedules: [oldPlan], sessions: [actual],
            progress: [actual.id: TrainingWorkSetProgress(completed: 27, total: 27)])
        let feedback = summary.feedback
        XCTAssertEqual(feedback.tone, .green, "当天已有独立实际，不能只显示旧计划的小时钟")
        XCTAssertEqual(feedback.label, "已记录训练")
        XCTAssertEqual(summary.pendingPlansLabel, "另有 1 项安排待完成")
        XCTAssertEqual(TrainingDayFeedback(schedules: [oldPlan], sessions: [actual]).symbolName, "clock",
            "单条旧计划的状态不能被当天其他实际替代")
        XCTAssertEqual(oldPlan.status, .planned)
        XCTAssertNil(actual.scheduledWorkoutID)
    }

    func testDaySummaryIncludesActualWithoutAnyScheduleAndDeduplicatesStableIdentities() {
        let day = "2026-10-15"
        let date = TrainingLocalDate.date(day)!
        let actual = WorkoutSession(templateName: "独立实际", plannedDate: date, startedAt: date,
            completedAt: date, status: .completed)
        actual.trainingLocalDay = day
        let old = ScheduledWorkout(templateID: UUID(), templateName: "旧安排", plannedDate: date)
        let solo = TrainingDaySummary(localDay: day, schedules: [], sessions: [actual])
        XCTAssertEqual(solo.feedback.label, "已记录训练")
        XCTAssertNil(solo.pendingPlansLabel)
        let repeated = TrainingDaySummary(localDay: day, schedules: [old, old], sessions: [actual, actual])
        XCTAssertEqual(repeated.recordedSessions.map(\.id), [actual.id])
        XCTAssertEqual(repeated.pendingScheduleCount, 1)
        XCTAssertEqual(repeated.feedback.total, 1)
    }

    func testDaySummaryKeepsSeventeenOfTwentyPartialEvenWithAnotherPendingPlan() {
        let date = TrainingLocalDate.date("2026-10-17")!
        let done = ScheduledWorkout(templateID: UUID(), templateName: "P5", plannedDate: date, status: .completed)
        let old = ScheduledWorkout(templateID: UUID(), templateName: "旧安排", plannedDate: date)
        let actual = WorkoutSession(scheduledWorkoutID: done.id, templateName: "P5", plannedDate: date,
            completedAt: date, status: .completed)
        actual.trainingLocalDay = "2026-10-17"
        let progress = [actual.id: TrainingWorkSetProgress(completed: 17, total: 20)]
        for linked in [true, false] {
            actual.scheduledWorkoutID = linked ? done.id : nil
            let result = TrainingDaySummary(localDay: "2026-10-17", schedules: [done, old],
                sessions: [actual], progress: progress)
            XCTAssertEqual(result.feedback.label, "已记录 17/20 组")
            XCTAssertEqual(result.feedback.symbolName, "circle.lefthalf.filled")
            XCTAssertEqual(result.feedback.tone, .amber)
            XCTAssertEqual(result.feedback.completed, 0)
            XCTAssertEqual(result.pendingScheduleCount, 1)
            XCTAssertEqual(done.status, .completed)
            XCTAssertEqual(old.status, .planned)
        }
    }

    func testDaySummaryKeepsProgressAndSkipsSeparateFromRecordedFacts() {
        let date = TrainingLocalDate.date("2026-10-15")!
        let old = ScheduledWorkout(templateID: UUID(), templateName: "旧安排", plannedDate: date)
        let actual = WorkoutSession(templateName: "进行中", plannedDate: date, startedAt: date)
        actual.trainingLocalDay = "2026-10-15"
        XCTAssertEqual(TrainingDaySummary(localDay: "2026-10-15", schedules: [old], sessions: [actual]).feedback.tone, .purple)
        actual.status = .discarded
        let discarded = TrainingDaySummary(localDay: "2026-10-15", schedules: [old], sessions: [actual])
        XCTAssertEqual(discarded.feedback.symbolName, "clock")
        XCTAssertTrue(discarded.recordedSessions.isEmpty)
        old.status = .skipped
        XCTAssertEqual(TrainingDaySummary(localDay: "2026-10-15", schedules: [old], sessions: []).feedback.tone, .gray)
        actual.status = .completed
        XCTAssertEqual(TrainingDaySummary(localDay: "2026-10-15", schedules: [old], sessions: [actual]).feedback.tone, .green)
        XCTAssertEqual(old.status, .skipped)
    }

    func testDaySummaryUsesFrozenCivilDayAndDoesNotBorrowOtherDaysActuals() {
        let instant = ISO8601DateFormatter().date(from: "2026-10-15T15:30:00Z")!
        let actual = WorkoutSession(templateName: "跨时区实际", plannedDate: instant,
            startedAt: instant, completedAt: instant, status: .completed)
        actual.plannedDate = instant // Legacy raw timestamps must survive presentation unchanged.
        actual.trainingLocalDay = "2026-10-15"
        actual.trainingTimeZoneIdentifier = "Asia/Shanghai"
        for zone in [TimeZone(identifier: "Asia/Shanghai")!, TimeZone(identifier: "Australia/Sydney")!] {
            XCTAssertEqual(TrainingDaySummary(localDay: "2026-10-15", schedules: [], sessions: [actual], timeZone: zone).feedback.tone, .green)
            XCTAssertEqual(TrainingDaySummary(localDay: "2026-10-16", schedules: [], sessions: [actual], timeZone: zone).feedback.tone, .none)
        }
        XCTAssertEqual(actual.startedAt, instant)
        XCTAssertEqual(actual.plannedDate, instant)
        XCTAssertEqual(actual.trainingTimeZoneIdentifier, "Asia/Shanghai")
        XCTAssertNil(actual.scheduledWorkoutID)
    }

    func testDaySummaryIncludesStandaloneRopeAndKeepsItsUnknownCountUnknown() {
        let date = TrainingLocalDate.date("2026-10-13")!
        let rope = JumpRopeEntry(count: nil, activeDurationSeconds: 300, date: date)
        let old = ScheduledWorkout(templateID: UUID(), templateName: "旧跳绳", plannedDate: date)
        let result = TrainingDaySummary(localDay: "2026-10-13", schedules: [old], sessions: [],
            jumpRopeEntries: [rope, rope])
        XCTAssertEqual(result.feedback.label, "已记录训练")
        XCTAssertEqual(result.jumpRopeEntries.map(\.id), [rope.id])
        XCTAssertEqual(result.pendingScheduleCount, 1)
        XCTAssertNil(rope.count)
        XCTAssertEqual(old.status, .planned)
        XCTAssertFalse(TrainingDaySummary(localDay: "2026-10-14", schedules: [], sessions: [], jumpRopeEntries: [rope]).hasActualRecords)
    }

    func testActualProgressLoaderIncludesOnlyRequestedCivilDaysWithoutSavingOrChangingAnyHistory() throws {
        let container = try scheduleContainer()
        let context = container.mainContext
        let date = TrainingLocalDate.date("2026-10-15")!
        let actual = WorkoutSession(templateName: "独立实际", plannedDate: date, startedAt: date,
            completedAt: date, status: .completed, notes: "保留原备注")
        actual.trainingLocalDay = "2026-10-15"
        let old = ScheduledWorkout(templateID: UUID(), templateName: "旧安排", plannedDate: date)
        old.skipReason = "保留旧字段"
        let other = WorkoutSession(templateName: "其他日期", plannedDate: date.addingDays(1),
            completedAt: date.addingDays(1), status: .completed)
        other.trainingLocalDay = "2026-10-16"
        let logs = [row(actual.id, completed: true), row(actual.id, completed: false),
            row(actual.id, completed: true, warmup: true), row(other.id, completed: true)]
        context.insert(actual); context.insert(old); context.insert(other)
        for log in logs { context.insert(log) }
        try context.save()
        let ids = logs.map(\.id)
        let originalPlannedDate = actual.plannedDate // New-session construction normalizes this date.
        let before = logs.map { "\($0.actualWeight)|\($0.actualReps)|\($0.isCompleted)|\($0.isWarmup)|\(String(describing: $0.rir))" }
        XCTAssertTrue(try TrainingWorkingSetProgressLoader.load(schedules: [old], sessions: [actual, other], in: context).isEmpty,
            "原单日程消费者不能将无关实际当成计划已完成")
        let progress = try TrainingWorkingSetProgressLoader.load(schedules: [old], sessions: [actual, other],
            includingLocalDays: ["2026-10-15"], in: context)
        XCTAssertEqual(progress[actual.id], TrainingWorkSetProgress(completed: 1, total: 2))
        XCTAssertNil(progress[other.id])
        _ = TrainingDaySummary(localDay: "2026-10-15", schedules: [old], sessions: [actual, other], progress: progress)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(logs.map(\.id), ids)
        XCTAssertEqual(logs.map { "\($0.actualWeight)|\($0.actualReps)|\($0.isCompleted)|\($0.isWarmup)|\(String(describing: $0.rir))" }, before)
        XCTAssertEqual(actual.notes, "保留原备注")
        XCTAssertEqual(actual.plannedDate, originalPlannedDate)
        XCTAssertNil(actual.scheduledWorkoutID)
        XCTAssertEqual(old.status, .planned)
        XCTAssertEqual(old.skipReason, "保留旧字段")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 4)
    }

    func testHistoryCivilDayPrefersSessionThenLinkedScheduleWithoutMovingAbsoluteTimes() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        let sydney = TimeZone(identifier: "Australia/Sydney")!
        let instant = ISO8601DateFormatter().date(from: "2026-09-26T15:30:00Z")!
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "周六", plannedDate: instant)
        schedule.plannedLocalDay = "2026-09-26"
        schedule.plannedTimeZoneIdentifier = shanghai.identifier
        let session = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: "历史", plannedDate: instant, startedAt: instant)
        let rawPlan = session.plannedDate
        XCTAssertNil(TrainingHistoryDate.knownLocalDay(session))
        XCTAssertEqual(TrainingHistoryDate.localDay(session, timeZone: shanghai), "2026-09-26")
        XCTAssertEqual(TrainingHistoryDate.localDay(session, timeZone: sydney), "2026-09-27")
        for zone in [shanghai, sydney] {
            XCTAssertEqual(TrainingHistoryDate.localDay(session, schedule: schedule, timeZone: zone), "2026-09-26")
        }
        TrainingHistoryDate.capture(session, date: instant, timeZone: sydney)
        for zone in [shanghai, sydney] {
            XCTAssertEqual(TrainingHistoryDate.localDay(session, schedule: schedule, timeZone: zone), "2026-09-27")
            XCTAssertEqual(TrainingLocalDate.key(TrainingHistoryDate.displayDate(session, schedule: schedule, timeZone: zone), timeZone: zone), "2026-09-27")
        }
        XCTAssertEqual(session.trainingTimeZoneIdentifier, sydney.identifier)
        XCTAssertEqual(session.startedAt, instant)
        XCTAssertEqual(session.plannedDate, rawPlan)
    }

    func testHistoryDateEditPreservesCivilOwnershipUntilExplicitCrossDayChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let start = ISO8601DateFormatter().date(from: "2026-09-26T15:30:00Z")!
        let session = WorkoutSession(templateName: "编辑", plannedDate: start, startedAt: start)
        session.trainingLocalDay = "2026-09-26"
        session.trainingTimeZoneIdentifier = "Asia/Shanghai"
        let original = session.plannedDate
        for time in [start, start.addingTimeInterval(3_600)] {
            TrainingHistoricalDateEditing.apply(to: session, originalStartedAt: start, editedStartedAt: time, calendar: calendar)
            XCTAssertEqual(session.trainingLocalDay, "2026-09-26")
            XCTAssertEqual(session.trainingTimeZoneIdentifier, "Asia/Shanghai")
            XCTAssertEqual(session.plannedDate, original)
        }
        let nextDay = start.addingTimeInterval(86_400)
        TrainingHistoricalDateEditing.apply(to: session, originalStartedAt: start, editedStartedAt: nextDay, calendar: calendar)
        XCTAssertEqual(session.trainingLocalDay, "2026-09-28")
        XCTAssertEqual(session.trainingTimeZoneIdentifier, "Australia/Sydney")
        XCTAssertEqual(session.plannedDate, calendar.startOfDay(for: nextDay))
        XCTAssertEqual(session.startedAt, start, "Date ownership helper must not reinterpret the actual start instant")
    }

    func testLiveStartAndScheduledBackfillFreezeKnownScheduleCivilOwnership() throws {
        let schema = Schema([Exercise.self, WorkoutTemplate.self, TemplateExercise.self, ScheduledWorkout.self,
            WorkoutSession.self, SessionExercise.self, SetLog.self, BodyMeasurement.self])
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let exercise = Exercise(name: "归属日期测试", muscleGroup: "胸部", equipment: "哑铃")
        let template = WorkoutTemplate(name: "跨时区安排", weekday: 1)
        let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name, plannedDate: .now)
        schedule.plannedLocalDay = "2026-09-26"
        schedule.plannedTimeZoneIdentifier = "Asia/Shanghai"
        store.mainContext.insert(exercise)
        store.mainContext.insert(template)
        store.mainContext.insert(schedule)
        store.mainContext.insert(TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: 0, targetSets: 1, minReps: 8, maxReps: 12, targetWeight: 10, restSeconds: 90))
        try store.mainContext.save()
        let id = try WorkoutService.start(schedule: schedule, in: store.mainContext)
        let session = try XCTUnwrap(store.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == id })
        XCTAssertEqual(session.trainingLocalDay, "2026-09-26")
        XCTAssertEqual(session.trainingTimeZoneIdentifier, "Asia/Shanghai")
        let startInstant = session.startedAt
        XCTAssertEqual(try WorkoutService.start(schedule: schedule, in: store.mainContext), id)
        XCTAssertEqual(session.startedAt, startInstant)
        session.status = .discarded
        schedule.status = .planned
        let chosenStart = ISO8601DateFormatter().date(from: "2026-09-26T15:30:00Z")!
        let backfill = try HistoricalWorkoutService.recordScheduledBackfill(.init(scheduleID: schedule.id,
            existingSessionID: session.id, name: schedule.templateName,
            date: TrainingLocalDate.date("2026-09-26")!, startedAt: chosenStart, durationMinutes: 20, notes: "补录",
            exercises: [.init(existingSnapshotID: nil, exerciseID: exercise.id,
                sets: [.init(existingLogID: nil, weight: 10, reps: 8, rir: nil)], performanceNotes: "", feeling: nil, isWarmup: false)]), in: store.mainContext)
        XCTAssertEqual(backfill.id, id)
        XCTAssertEqual(backfill.trainingLocalDay, "2026-09-26")
        XCTAssertEqual(backfill.trainingTimeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(backfill.startedAt, chosenStart)
    }

    func testNewManualHistoryFreezesChosenCivilDayButGenericAndImportedSessionsRemainUnknown() throws {
        let schema = Schema([Exercise.self, ScheduledWorkout.self, WorkoutSession.self,
            SessionExercise.self, SetLog.self, BodyMeasurement.self])
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let exercise = Exercise(name: "手工补录动作", muscleGroup: "胸部", equipment: "哑铃")
        store.mainContext.insert(exercise)
        try store.mainContext.save()
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 0, minute: 30))!
        var input = HistoricalWorkoutInput(name: "手工补录", startedAt: start, durationMinutes: 20, notes: "",
            exercises: [.init(exerciseID: exercise.id, sets: [.init(weight: 10, reps: 8, rir: nil)], performanceNotes: "")])
        let manual = try HistoricalWorkoutService.record(input, in: store.mainContext)
        XCTAssertEqual(manual.trainingLocalDay, "2026-09-27")
        XCTAssertEqual(manual.trainingTimeZoneIdentifier, TimeZone.current.identifier)
        XCTAssertEqual(manual.startedAt, start)
        input.importIdentifier = "legacy-import-without-source-timezone"
        let imported = try HistoricalWorkoutService.record(input, in: store.mainContext)
        XCTAssertNil(imported.trainingLocalDay)
        XCTAssertNil(imported.trainingTimeZoneIdentifier)
        let generic = WorkoutSession(templateName: "来源未知", plannedDate: start, startedAt: start)
        XCTAssertNil(generic.trainingLocalDay)
        XCTAssertNil(generic.trainingTimeZoneIdentifier)
    }

    func testHistoricalNotesSetsAndTimeOnlyEditsPreserveOriginalPlannedDate() {
        let originalPlan = ISO8601DateFormatter().date(from: "2026-09-25T14:00:00Z")!
        let originalStart = TrainingLocalDate.date("2026-09-27")!
        XCTAssertEqual(TrainingHistoricalDateEditing.plannedDate(original: originalPlan,
            originalStartedAt: originalStart, editedStartedAt: originalStart), originalPlan)
        XCTAssertEqual(TrainingHistoricalDateEditing.plannedDate(original: originalPlan,
            originalStartedAt: originalStart, editedStartedAt: originalStart.addingTimeInterval(3_600)), originalPlan)
        let changedDay = TrainingLocalDate.date("2026-09-28")!
        XCTAssertEqual(TrainingHistoricalDateEditing.plannedDate(original: originalPlan,
            originalStartedAt: originalStart, editedStartedAt: changedDay), changedDay.startOfDay)
    }

    func testScheduledBackfillPreparationUsesStableCivilDayWithoutChangingKnownStartOrRawSchedule() throws {
        let container = try scheduleContainer()
        let template = WorkoutTemplate(name: "跨时区补录", weekday: 1)
        let schedule = foreignSchedule(template)
        container.mainContext.insert(template)
        container.mainContext.insert(schedule)
        try container.mainContext.save()
        let original = schedule.plannedDate
        let first = try HistoricalWorkoutService.prepareScheduledBackfill(scheduleID: schedule.id, in: container.mainContext)
        XCTAssertEqual(TrainingLocalDate.key(first.date), "2026-09-27")
        let knownStart = original.addingTimeInterval(30 * 60)
        let session = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: template.name,
            plannedDate: original, startedAt: knownStart, completedAt: knownStart.addingTimeInterval(600), status: .completed)
        container.mainContext.insert(session)
        try container.mainContext.save()
        let second = try HistoricalWorkoutService.prepareScheduledBackfill(scheduleID: schedule.id, in: container.mainContext)
        XCTAssertEqual(TrainingLocalDate.key(second.date), "2026-09-27")
        XCTAssertEqual(second.startedAt, knownStart)
        XCTAssertEqual(schedule.plannedDate, original)
        XCTAssertEqual(session.startedAt, knownStart)
    }

    func testManualScheduleRejectsDuplicateCivilDayAfterTimeZoneChange() throws {
        let container = try scheduleContainer()
        let template = WorkoutTemplate(name: "跨时区", weekday: 1)
        let existing = foreignSchedule(template)
        container.mainContext.insert(template)
        container.mainContext.insert(existing)
        try container.mainContext.save()
        let original = existing.plannedDate
        XCTAssertThrowsError(try ScheduleService.addManual(template: template,
            on: TrainingLocalDate.date("2026-09-27")!, in: container.mainContext)) { error in
            XCTAssertEqual(error as? ScheduleServiceError, .duplicateSchedule)
        }
        XCTAssertEqual(existing.plannedDate, original)
        XCTAssertEqual(existing.plannedLocalDay, "2026-09-27")
    }

    func testRescheduleRejectsOccupiedCivilDayAfterTimeZoneChange() throws {
        let container = try scheduleContainer()
        let template = WorkoutTemplate(name: "跨时区", weekday: 1)
        let existing = foreignSchedule(template)
        let moving = ScheduledWorkout(templateID: template.id, templateName: template.name,
            plannedDate: TrainingLocalDate.date("2026-09-28")!)
        container.mainContext.insert(template)
        container.mainContext.insert(existing)
        container.mainContext.insert(moving)
        try container.mainContext.save()
        let original = moving.plannedDate
        XCTAssertThrowsError(try ScheduleService.reschedule(moving,
            to: TrainingLocalDate.date("2026-09-27")!, in: container.mainContext)) { error in
            XCTAssertEqual(error as? ScheduleServiceError, .duplicateSchedule)
        }
        XCTAssertEqual(moving.plannedDate, original)
        XCTAssertEqual(moving.plannedLocalDay, "2026-09-28")
    }

    func testExplicitRescheduleUpdatesCivilDateAndPreservesOriginalInstant() throws {
        let schema = Schema([ScheduledWorkout.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let source = TrainingLocalDate.date("2026-09-21")!
        let target = TrainingLocalDate.date("2026-09-28")!
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "改期", plannedDate: source)
        schedule.plannedLocalDay = "2026-09-21"
        let original = schedule.plannedDate
        container.mainContext.insert(schedule)
        try container.mainContext.save()
        try ScheduleService.reschedule(schedule, to: target, in: container.mainContext)
        XCTAssertEqual(schedule.plannedLocalDay, "2026-09-28")
        XCTAssertEqual(schedule.plannedTimeZoneIdentifier, TimeZone.current.identifier)
        XCTAssertEqual(schedule.originalPlannedDate, original)
    }

    func testDayFeedbackDistinguishesPartialCompletionAndAllSkippedWithoutInventingEvents() {
        XCTAssertEqual(TrainingDayFeedback(states: []).tone, .none)
        XCTAssertEqual(TrainingDayFeedback(states: [.planned]).tone, .amber)
        XCTAssertEqual(TrainingDayFeedback(states: [.completed, .planned]).label, "部分完成 1/2")
        XCTAssertEqual(TrainingDayFeedback(states: [.completed, .inProgress]).tone, .purple)
        XCTAssertEqual(TrainingDayFeedback(states: [.completed, .completed]).tone, .green)
        XCTAssertEqual(TrainingDayFeedback(states: [.skipped, .skipped]).tone, .gray)
        XCTAssertEqual(TrainingDayFeedback(states: [.completed, .skipped]).label, "部分完成 1/2")
        XCTAssertEqual(TrainingDayFeedback(states: [.completed]).symbolName, "checkmark.circle.fill")
        XCTAssertEqual(TrainingDayFeedback(states: [.inProgress]).symbolName, "arrow.triangle.2.circlepath")
        XCTAssertEqual(TrainingDayFeedback(states: [.skipped]).symbolName, "forward.end")
        XCTAssertEqual(TrainingDayFeedback(states: []).symbolName, "")
    }

    func testPartlyRecordedWorkoutNeverMakesCalendarFullyCompleteOrChangesStoredStatus() {
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "提前结束", plannedDate: .now, status: .completed)
        let session = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: "提前结束", plannedDate: .now,
            completedAt: .now, status: .completed)
        let progress = [session.id: TrainingWorkSetProgress(completed: 1, total: 12)]
        let partial = TrainingDayFeedback(schedules: [schedule], sessions: [session], progress: progress)
        XCTAssertEqual(partial.tone, .amber)
        XCTAssertEqual(partial.completed, 0)
        XCTAssertEqual(partial.label, "已记录 1/12 组")
        XCTAssertEqual(partial.symbolName, "circle.lefthalf.filled")
        XCTAssertEqual(schedule.status, .completed)
        let cardio = ScheduledWorkout(templateID: UUID(), templateName: "单车", plannedDate: .now, status: .completed)
        XCTAssertEqual(TrainingDayFeedback(schedules: [cardio]).tone, .green)
        XCTAssertEqual(TrainingDayFeedback(schedules: [schedule, cardio], sessions: [session], progress: progress).label, "部分完成 1/2")
    }

    func testCompletionUsesOnlyThisSessionsCompletedWorkingSetsAndActualElapsedTimeOnce() {
        let now = Date.now
        let session = WorkoutSession(templateName: "胸肩", plannedDate: now, startedAt: now.addingTimeInterval(-93),
            completedAt: now, status: .completed)
        let rows = [row(session.id, completed: true), row(session.id, completed: true),
                    row(session.id, completed: false), row(session.id, completed: true, warmup: true), row(UUID(), completed: true)]
        let feedback = WorkoutCompletionFeedback()
        let summary = feedback.receiveSavedCompletion(session: session, logs: rows, allDaySchedulesCompleted: true, now: now)
        XCTAssertEqual(summary?.completedWorkSets, 2)
        XCTAssertEqual(summary?.durationSeconds, 93)
        XCTAssertEqual(summary?.title, "本次训练已记录")
        XCTAssertNil(feedback.receiveSavedCompletion(session: session, logs: rows, now: now))
    }

    func testCompletionDoesNotTriggerForIncompleteImportedOrHistoricalRecords() {
        let now = Date.now
        let feedback = WorkoutCompletionFeedback()
        let session = WorkoutSession(templateName: "历史", plannedDate: now)
        XCTAssertNil(feedback.receiveSavedCompletion(session: session, logs: [], now: now))
        session.status = .completed
        session.completedAt = now
        session.importIdentifier = "notes:source"
        XCTAssertNil(feedback.receiveSavedCompletion(session: session, logs: [], now: now))
        session.importIdentifier = ""
        session.completedAt = now.addingTimeInterval(-86_400)
        XCTAssertNil(feedback.receiveSavedCompletion(session: session, logs: [], now: now))
    }

    func testCompletionRemainsSinglePresentationAcrossFeedbackRelaunchAndKeepsUnknownDurationUnknown() {
        let suite = "TrainingFeedbackTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date.now
        let session = WorkoutSession(templateName: "未知时长", plannedDate: now, startedAt: now,
            isStartTimeKnown: false, completedAt: now, status: .completed)
        let first = WorkoutCompletionFeedback(defaults: defaults).receiveSavedCompletion(session: session, logs: [], now: now)
        XCTAssertNotNil(first)
        XCTAssertNil(first?.durationSeconds)
        XCTAssertEqual(first?.durationLabel, "时长未记录")
        XCTAssertNil(WorkoutCompletionFeedback(defaults: defaults).receiveSavedCompletion(session: session, logs: [], now: now))
    }

    func testDailyCompletionTitleRequiresAllWorkingSetsAndAllSchedulesOtherwiseOnlyRecordsSession() {
        let now = Date.now
        let session = WorkoutSession(templateName: "背腹", plannedDate: now, startedAt: now.addingTimeInterval(-60),
            completedAt: now, status: .completed)
        let rows = [row(session.id, completed: true)]
        XCTAssertEqual(WorkoutCompletionFeedback().receiveSavedCompletion(session: session, logs: rows,
            allDaySchedulesCompleted: true, now: now)?.title, "今日训练完成")
        XCTAssertEqual(WorkoutCompletionFeedback().receiveSavedCompletion(session: session, logs: rows,
            allDaySchedulesCompleted: false, now: now)?.title, "本次训练已记录")
        XCTAssertEqual(WorkoutCompletionFeedback().receiveSavedCompletion(session: session, logs: rows,
            now: now)?.title, "本次训练已记录")
    }

    func testScheduleCivilDaySurvivesChinaAustraliaDisplayChangeWithoutChangingStoredDate() {
        let raw = ISO8601DateFormatter().date(from: "2026-09-26T14:00:00Z")!
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "当地训练", plannedDate: raw)
        schedule.plannedDate = raw
        schedule.plannedLocalDay = "2026-09-27"
        schedule.plannedTimeZoneIdentifier = "Australia/Sydney"
        XCTAssertEqual(TrainingScheduleDate.localDay(schedule, timeZone: TimeZone(identifier: "Asia/Shanghai")!), "2026-09-27")
        XCTAssertEqual(TrainingScheduleDate.localDay(schedule, timeZone: TimeZone(identifier: "Australia/Sydney")!), "2026-09-27")
        XCTAssertEqual(schedule.plannedDate, raw)
        XCTAssertEqual(schedule.plannedTimeZoneIdentifier, "Australia/Sydney")
    }

    private func row(_ sessionID: UUID, completed: Bool, warmup: Bool = false) -> SetLog {
        SetLog(sessionID: sessionID, sessionExerciseID: UUID(), exerciseID: UUID(), setNumber: 1,
            targetWeight: 25, targetReps: 12, actualWeight: 25, actualReps: 12,
            isWarmup: warmup, isCompleted: completed)
    }

    private func scheduleContainer() throws -> ModelContainer {
        let schema = Schema([ScheduledWorkout.self, WorkoutTemplate.self, TemplateExercise.self, Exercise.self,
            WorkoutSession.self, SessionExercise.self, SetLog.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema,
            isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    private func foreignSchedule(_ template: WorkoutTemplate) -> ScheduledWorkout {
        // A real civil midnight on the other side of the date boundary, without changing global timezone.
        let offset = TimeZone.current.secondsFromGMT() == 14 * 3_600 ? -12 * 3_600 : 14 * 3_600
        let sourceZone = TimeZone(secondsFromGMT: offset)!
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceZone
        let instant = sourceCalendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        XCTAssertNotEqual(TrainingLocalDate.key(instant), "2026-09-27", "夹具必须真实跨越当地日期边界")
        let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name, plannedDate: instant)
        schedule.plannedDate = instant
        schedule.plannedLocalDay = "2026-09-27"
        schedule.plannedTimeZoneIdentifier = sourceZone.identifier
        return schedule
    }
}
