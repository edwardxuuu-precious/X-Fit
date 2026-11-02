import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class TrainingDateMenuTests: XCTestCase {
    private func container() throws -> ModelContainer {
        let schema = Schema([Exercise.self, WorkoutTemplate.self, TemplateExercise.self,
            ScheduledWorkout.self, WorkoutSession.self, SessionExercise.self, SetLog.self,
            TrainingPreferenceRevision.self, TrainingProgramRevision.self, ProgramWorkoutLink.self,
            JumpRopeEntry.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }
    private var day: String { TrainingLocalDate.key(Date.now.startOfDay.addingDays(-1)) }
    private var plan: JumpRopeMenuPlan { .init(targetCount: nil, activeSeconds: 600, elapsedSeconds: 900, notes: "本人填写的间歇") }

    private func cardioSchedule(in context: ModelContext, on localDay: String? = nil) throws -> ScheduledWorkout {
        let exercise = Exercise(name: "固定单车", muscleGroup: "心肺", equipment: "单车", volumeUnit: .second)
        context.insert(exercise)
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "固定单车 · 稳定有氧35分钟 · R1",
            plannedDate: TrainingLocalDate.date(localDay ?? day)!, planSnapshot: [
                .init(exerciseID: exercise.id, exerciseName: exercise.name, muscleGroup: "心肺", equipment: "单车",
                    exerciseNotes: "原处方保留", referenceURL: "", volumeUnit: .second, order: 0,
                    targetSets: 1, minReps: 2_400, maxReps: 2_400, targetWeight: 0, restSeconds: 0,
                    plannedSets: [.init(weight: 0, reps: 2_400, actualDefaultPolicy: .blank)],
                    planPattern: .fixed, patternSource: .exerciseOverride)])
        context.insert(schedule); try context.save()
        return schedule
    }

    func testCardioRecordsReportedDurationAndLevelOnceWithoutInventingClockOrLoad() throws {
        let store = try container(), context = store.mainContext
        let schedule = try cardioSchedule(in: context)
        let planBefore = schedule.planSnapshotJSON
        let id = try CardioWorkoutService.record(schedule: schedule, seconds: 2_100, level: 10, in: context)
        XCTAssertEqual(try CardioWorkoutService.record(schedule: schedule, seconds: 2_100, level: 10, in: context), id)
        let session = try XCTUnwrap(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        let log = try XCTUnwrap(context.fetch(FetchDescriptor<SetLog>()).first)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExercise>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLog>()), 1)
        XCTAssertFalse(session.isStartTimeKnown); XCTAssertNil(session.completedAt)
        XCTAssertNil(log.startedAt); XCTAssertNil(log.completedAt); XCTAssertNil(log.rir)
        XCTAssertEqual(session.cardioResistanceLevel, 10)
        XCTAssertEqual(log.actualReps, 2_100); XCTAssertEqual(log.targetReps, 2_400)
        XCTAssertEqual(log.actualWeight, 0); XCTAssertTrue(log.isActualWeightBlank)
        XCTAssertEqual(schedule.planSnapshotJSON, planBefore)
        XCTAssertEqual(schedule.status, .completed)
        let summary = try XCTUnwrap(CardioWorkoutPresentation.actual(session,
            exercises: context.fetch(FetchDescriptor<SessionExercise>()), logs: context.fetch(FetchDescriptor<SetLog>())))
        XCTAssertEqual(summary.title, "固定单车")
        XCTAssertEqual(summary.label, "35 分钟 · Level 10")
        XCTAssertEqual(summary.symbolName, "figure.indoor.cycle")
    }

    func testCardioEditChangesSameActualAndKeepsSiblingAndTargets() throws {
        let store = try container(), context = store.mainContext
        let schedule = try cardioSchedule(in: context)
        let sibling = ScheduledWorkout(templateID: UUID(), templateName: "保留力量", plannedDate: TrainingLocalDate.date(day)!)
        context.insert(sibling); try context.save()
        let originalPlan = schedule.planSnapshotJSON
        let id = try CardioWorkoutService.record(schedule: schedule, seconds: 2_100, level: 10, in: context)
        XCTAssertThrowsError(try CardioWorkoutService.record(schedule: schedule, seconds: 1_800, level: 8, in: context))
        XCTAssertEqual(try CardioWorkoutService.record(schedule: schedule, seconds: 1_800, level: nil, editingSessionID: id, in: context), id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SetLog>()).first?.actualReps, 1_800)
        XCTAssertNil(try context.fetch(FetchDescriptor<WorkoutSession>()).first?.cardioResistanceLevel)
        XCTAssertEqual(sibling.status, .planned); XCTAssertEqual(schedule.planSnapshotJSON, originalPlan)
    }

    func testCardioRejectsFutureInvalidAndStrengthInputsBeforeWriting() throws {
        let store = try container(), context = store.mainContext
        let schedule = try cardioSchedule(in: context)
        let future = try cardioSchedule(in: context, on: TrainingLocalDate.key(.now.addingDays(1)))
        for (item, seconds, level) in [(schedule, 0, 10.0), (schedule, 2_100, Double.nan), (schedule, 2_100, -1.0), (future, 2_100, 10.0)] {
            XCTAssertThrowsError(try CardioWorkoutService.record(schedule: item, seconds: seconds, level: level, in: context))
        }
        XCTAssertNil(CardioWorkoutPresentation.symbol(name: "平板支撑", muscle: "核心", equipment: "垫子", unit: .second))
        XCTAssertNil(CardioWorkoutPresentation.symbol(name: "跳绳", muscle: "心肺", equipment: "跳绳", unit: .second))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
        XCTAssertEqual(schedule.status, .planned); XCTAssertEqual(future.status, .planned)
    }

    func testPlanningRopePreservesStrengthAndLegacyActualWithoutInventingCompletion() throws {
        let store = try container(), context = store.mainContext
        let strength = ScheduledWorkout(templateID: UUID(), templateName: "力量原计划", plannedDate: TrainingLocalDate.date(day)!)
        let legacy = JumpRopeEntry(count: nil, durationSeconds: 480, date: TrainingLocalDate.date(day)!)
        context.insert(strength); context.insert(legacy); try context.save()
        let rope = try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: day, in: context)
        XCTAssertEqual(TrainingScheduleDate.localDay(rope), day)
        XCTAssertEqual(rope.status, .planned)
        XCTAssertEqual(rope.jumpRopePlan, plan)
        XCTAssertEqual(strength.status, .planned)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JumpRopeEntry>()), 1)
        XCTAssertNil(legacy.scheduledWorkoutID)
        XCTAssertNil(legacy.count)
        XCTAssertNil(legacy.activeDurationSeconds)
        XCTAssertEqual(legacy.durationSeconds, 480)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    }

    func testInvalidPlanLeavesStoreUntouched() throws {
        let store = try container(), context = store.mainContext
        XCTAssertThrowsError(try TrainingDateMenuService.saveJumpRopePlan(
            .init(targetCount: nil, activeSeconds: 900, elapsedSeconds: 600, notes: ""), localDay: day, in: context))
        XCTAssertThrowsError(try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: "invalid", in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutTemplate>()), 0)
    }

    func testNewRopeKeepsScheduledCivilDayAcrossZonesWhileLegacyOwnershipStaysUnknown() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-15T15:30:00Z"))
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "跳绳", plannedDate: instant)
        schedule.plannedLocalDay = "2026-10-15"
        let linked = JumpRopeEntry(count: nil, activeDurationSeconds: 600, date: instant)
        linked.scheduledWorkoutID = schedule.id
        let legacy = JumpRopeEntry(count: nil, durationSeconds: 600, date: instant)
        let zone = try XCTUnwrap(TimeZone(identifier: "Australia/Sydney"))
        XCTAssertEqual(TrainingJumpRopeDate.localDay(linked, schedules: [schedule], timeZone: zone), "2026-10-15")
        XCTAssertEqual(TrainingJumpRopeDate.localDay(legacy, schedules: [schedule], timeZone: zone), "2026-10-16")
        XCTAssertNil(legacy.scheduledWorkoutID)
        XCTAssertEqual(TrainingDaySummary(localDay: "2026-10-15", schedules: [schedule], sessions: [],
            jumpRopeEntries: [linked, legacy], timeZone: zone).jumpRopeEntries.map(\.id), [linked.id])
    }

    func testExcludedScheduleStillOwnsLegacyActualDatesAcrossViewerTimezones() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-15T15:30:00Z"))
        let zone = try XCTUnwrap(TimeZone(identifier: "Australia/Sydney"))
        let schedule = ScheduledWorkout(templateID: UUID(), templateName: "保留旧来源", plannedDate: instant)
        schedule.plannedLocalDay = "2026-10-15"
        schedule.plannedTimeZoneIdentifier = "Asia/Shanghai"
        let actual = WorkoutSession(scheduledWorkoutID: schedule.id, templateName: "历史实际",
            plannedDate: instant, startedAt: instant, isStartTimeKnown: false, status: .completed)
        actual.trainingLocalDay = nil
        actual.trainingTimeZoneIdentifier = nil
        let rope = JumpRopeEntry(count: nil, activeDurationSeconds: 600, date: instant)
        rope.scheduledWorkoutID = schedule.id
        let summary = TrainingDaySummary(localDay: "2026-10-15", schedules: [schedule], sessions: [actual],
            jumpRopeEntries: [rope], excludedScheduleIDs: [schedule.id], timeZone: zone)
        XCTAssertEqual(summary.recordedSessions.map(\.id), [actual.id])
        XCTAssertEqual(summary.jumpRopeEntries.map(\.id), [rope.id])
        XCTAssertTrue(summary.hasActualRecords); XCTAssertEqual(summary.pendingScheduleCount, 0)
        let nextDay = TrainingDaySummary(localDay: "2026-10-16", schedules: [schedule], sessions: [actual],
            jumpRopeEntries: [rope], excludedScheduleIDs: [schedule.id], timeZone: zone)
        XCTAssertFalse(nextDay.hasActualRecords)
        actual.status = .inProgress
        let active = TrainingDaySummary(localDay: "2026-10-15", schedules: [schedule], sessions: [actual],
            excludedScheduleIDs: [schedule.id], timeZone: zone)
        XCTAssertEqual(active.activeSessions.map(\.id), [actual.id])
        XCTAssertEqual(active.feedback.tone, .purple)
        XCTAssertNil(actual.trainingLocalDay); XCTAssertNil(actual.trainingTimeZoneIdentifier)
        XCTAssertEqual(actual.startedAt, instant); XCTAssertEqual(rope.date, instant)
        XCTAssertEqual(schedule.plannedLocalDay, "2026-10-15")
        XCTAssertEqual(schedule.status, .planned)
    }

    func testVoluntarySkippedRopeCanRestoreAndBeSupplementedWithoutLosingItsPlan() throws {
        let store = try container(), context = store.mainContext
        let schedule = try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: day, in: context)
        _ = try ScheduleService.skipManaged(schedule, reason: "今天主动休息", in: context)
        XCTAssertEqual(schedule.status, .skipped)
        XCTAssertTrue(ConfirmedDailyTrainingPlanService.supersededScheduleIDs(in: [schedule]).isEmpty)
        _ = try ScheduleService.restoreManaged(schedule, in: context)
        XCTAssertEqual(schedule.status, .planned); XCTAssertEqual(schedule.jumpRopePlan, plan)
        _ = try ScheduleService.skipManaged(schedule, reason: "保留补录入口", in: context)
        let result = try WellnessToolService.recordJumpRope(count: 800, activeDurationSeconds: nil,
            elapsedDurationSeconds: nil, at: TrainingScheduleDate.displayDate(schedule),
            scheduledWorkoutID: schedule.id, in: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertEqual(entry.id, result.recordID); XCTAssertEqual(entry.scheduledWorkoutID, schedule.id)
        XCTAssertEqual(entry.count, 800); XCTAssertEqual(schedule.status, .completed)
        XCTAssertEqual(schedule.jumpRopePlan, plan)
    }

    func testRecordingCompletesOnlySelectedRopeAndRetainsUnknownCountAndTargets() throws {
        let store = try container(), context = store.mainContext
        let selected = try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: day, in: context)
        let sibling = try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: day, in: context)
        let strength = ScheduledWorkout(templateID: UUID(), templateName: "力量", plannedDate: TrainingLocalDate.date(day)!)
        context.insert(strength); try context.save()
        let id = try TrainingDateMenuService.recordJumpRope(schedule: selected, count: nil, active: 540,
            elapsed: 840, at: TrainingLocalDate.date(day)!, in: context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<JumpRopeEntry>()).first)
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.scheduledWorkoutID, selected.id)
        XCTAssertNil(entry.count)
        XCTAssertEqual(entry.activeDurationSeconds, 540)
        XCTAssertEqual(entry.elapsedDurationSeconds, 840)
        XCTAssertEqual(selected.jumpRopePlan, plan)
        XCTAssertEqual(selected.status, .completed)
        XCTAssertEqual(sibling.status, .planned)
        XCTAssertEqual(strength.status, .planned)
        XCTAssertThrowsError(try TrainingDateMenuService.recordJumpRope(schedule: selected, count: 123,
            active: nil, elapsed: nil, at: TrainingLocalDate.date(day)!, in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JumpRopeEntry>()), 1)
    }

    func testWrongDayWrongProjectAndFutureRecordsAreRejectedBeforeWriting() throws {
        let store = try container(), context = store.mainContext
        let rope = try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: day, in: context)
        let future = TrainingLocalDate.key(Date.now.addingDays(2))
        let futureRope = try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: future, in: context)
        let strength = ScheduledWorkout(templateID: UUID(), templateName: "跳绳名称但不是跳绳处方", plannedDate: TrainingLocalDate.date(day)!)
        context.insert(strength); try context.save()
        for (schedule, date) in [(rope, TrainingLocalDate.date(day)!.addingDays(-1)),
                                  (futureRope, TrainingLocalDate.date(future)!), (strength, TrainingLocalDate.date(day)!)] {
            XCTAssertThrowsError(try TrainingDateMenuService.recordJumpRope(schedule: schedule,
                count: nil, active: 600, elapsed: nil, at: date, in: context))
            XCTAssertEqual(schedule.status, .planned)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JumpRopeEntry>()), 0)
    }

    func testEditingStrengthPreservesPendingAndCompletedRopeProjects() throws {
        let store = try container(), context = store.mainContext
        let pending = try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: day, in: context)
        let done = try TrainingDateMenuService.saveJumpRopePlan(plan, localDay: day, in: context)
        _ = try TrainingDateMenuService.recordJumpRope(schedule: done, count: 800, active: nil,
            elapsed: nil, at: TrainingLocalDate.date(day)!, in: context)
        let exercise = Exercise(name: "测试卧推", muscleGroup: "胸部", equipment: "测试器械")
        context.insert(exercise); try context.save()
        _ = try DailyPlanService.create(on: TrainingLocalDate.date(day)!, muscleGroups: ["胸部"],
            exercises: [.init(exerciseID: exercise.id, plannedSets: [.init(weight: 40, reps: 10)], planPattern: .fixed, restSeconds: 90)],
            replaceExistingPlans: true, in: context)
        XCTAssertEqual(pending.status, .planned)
        XCTAssertEqual(done.status, .completed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledWorkout>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JumpRopeEntry>()), 1)
    }
}
