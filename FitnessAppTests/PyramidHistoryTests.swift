import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class PyramidHistoryTests: XCTestCase {
    private let now = FatLossCalendar.date(2026, 10, 21).addingTimeInterval(12 * 3600)

    func testLegacyPreferenceWithoutPatternKeepsFixedDefaults() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            TrainingPreferenceSnapshot.postTravelRestoration)) as? [String: Any])
        json.removeValue(forKey: "preferredSetPlanPattern")
        let decoded = try JSONDecoder().decode(TrainingPreferenceSnapshot.self,
            from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.preferredSetPlanPattern)
        XCTAssertEqual(decoded.defaultPattern(for: Exercise(name: "普通推胸", muscleGroup: "胸部", equipment: "器械")), .fixed)
        XCTAssertEqual(decoded.revisionCode, "TP-20260928-05")
    }

    func testPyramidPreferenceAppendsOnceAndLeavesOriginalPreferenceAndWorkoutUntouched() throws {
        let container = try makeContainer(), context = container.mainContext
        let old = try seedPreference(in: context)
        let historical = WorkoutSession(templateName: "历史处方", plannedDate: FatLossCalendar.date(2026, 10, 19),
            completedAt: FatLossCalendar.date(2026, 10, 19), status: .completed, notes: "原始备注", defaultPlanPattern: .fixed)
        context.insert(historical); try context.save()
        let oldJSON = old.snapshotJSON, oldID = old.id
        XCTAssertNil(try TrainingPreferenceService.ensurePyramidPreference(in: context, on: FatLossCalendar.date(2026, 10, 20)))
        let first = try XCTUnwrap(TrainingPreferenceService.ensurePyramidPreference(in: context, on: now))
        let again = try XCTUnwrap(TrainingPreferenceService.ensurePyramidPreference(in: context, on: now))
        XCTAssertEqual(first.id, again.id)
        XCTAssertEqual(first.snapshot?.preferredSetPlanPattern, .pyramidUp)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingPreferenceRevision>()), 2)
        XCTAssertEqual(old.id, oldID); XCTAssertEqual(old.snapshotJSON, oldJSON)
        XCTAssertEqual(historical.defaultPlanPattern, .fixed)
        XCTAssertEqual(historical.notes, "原始备注"); XCTAssertEqual(historical.status, .completed)
        XCTAssertEqual(first.snapshot?.strengthDaysPerWeek, old.snapshot?.strengthDaysPerWeek)
        XCTAssertEqual(first.snapshot?.sessionMinutesLower, old.snapshot?.sessionMinutesLower)
        XCTAssertTrue(first.snapshot?.constraints.contains(where: { $0.contains("递增工作组计入") }) == true)
        XCTAssertFalse(first.snapshot?.constraints.contains(where: { $0.contains("热身和递增组不计入") }) == true)
    }

    func testPyramidDefaultExcludesTechnicalBodyweightTimeAndDistanceExercises() {
        var preference = TrainingPreferenceSnapshot.postTravelRestoration
        preference.preferredSetPlanPattern = .pyramidUp
        let normal = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        XCTAssertEqual(preference.defaultPattern(for: normal), .pyramidUp)
        for name in ["高翻", "悬垂高翻", "Power Clean", "抓举"] {
            XCTAssertEqual(preference.defaultPattern(for: Exercise(name: name, muscleGroup: "腿部", equipment: "杠铃")), .fixed)
        }
        for unit in [ExerciseVolumeUnit.bodyweight, .second, .meter, .count] {
            let exercise = Exercise(name: "专用计量动作", muscleGroup: "核心", equipment: "自重")
            exercise.volumeUnit = unit
            XCTAssertEqual(preference.defaultPattern(for: exercise), .fixed)
        }
    }

    func testDisplayHistoryRetainsOldUnknownEffortUnverifiedEquipmentAndNotesRowsWithoutQualifyingThem() {
        for scenario in 0..<4 {
            let fixture = historyFixture(daysAgo: scenario == 0 ? 60 : 1,
                equipment: scenario == 2 ? nil : "同一器械", rir: scenario == 1 ? nil : 3,
                importedNotes: scenario == 3)
            let history = resolve(fixture)
            XCTAssertEqual(history.rows.map(\.id), fixture.logs.prefix(2).map(\.id), "Scenario \(scenario) remains visible")
            XCTAssertEqual(history.sourceSessionID, fixture.session.id)
            XCTAssertTrue(history.eligibleSetIDs.isEmpty, "Display access must not grant automatic load eligibility")
            XCTAssertEqual(history.equipmentVerified, scenario != 2)
            XCTAssertEqual(history.classificationUnknown, scenario == 3)
        }
    }

    func testGenericMachineNamesDoNotGrantComparabilityOrAutomaticLoad() {
        let fixture = historyFixture()
        fixture.exercise.equipment = "器械"
        fixture.snapshot.equipmentSnapshot = "器械"
        let history = resolve(fixture)
        XCTAssertEqual(history.rows.count, 2)
        XCTAssertFalse(history.equipmentVerified)
        XCTAssertTrue(history.eligibleSetIDs.isEmpty)
        XCTAssertFalse(history.volumeComparison(plans: [WorkoutSetPlan(weight: 20, reps: 12)], unit: .kilogram).contains("%"))
    }

    func testWarmupsAndIncompleteRowsAreExcludedWhileIncreasingWorkSetsRemain() {
        let fixture = historyFixture()
        let history = resolve(fixture)
        XCTAssertEqual(history.rows.map(\.weight), [20, 25])
        XCTAssertEqual(history.rows.map(\.reps), [12, 10])
        XCTAssertEqual(history.eligibleSetIDs, Set(fixture.logs.prefix(2).map(\.id)))
        XCTAssertFalse(history.rows.contains { $0.id == fixture.logs[2].id || $0.id == fixture.logs[3].id })
    }

    func testVolumeComparisonRequiresMatchingKnownConventionsAndNeverPadsMissingRows() {
        let fixture = historyFixture()
        var history = resolve(fixture)
        let plans = [WorkoutSetPlan(weight: 20, reps: 10)]
        let summary = history.volumeComparison(plans: plans, unit: .kilogram)
        XCTAssertTrue(summary.contains("490")); XCTAssertTrue(summary.contains("200")); XCTAssertTrue(summary.contains("%"))
        XCTAssertEqual(history.rows.count, 2); XCTAssertEqual(plans.count, 1)
        let added = plans + [WorkoutSetPlan(weight: 25, reps: 10), WorkoutSetPlan(weight: 30, reps: 8)]
        XCTAssertTrue(history.volumeComparison(plans: added, unit: .kilogram).contains("690"))
        XCTAssertEqual(history.rows.count, 2); XCTAssertEqual(added.count, 3)
        for unit in [ExerciseVolumeUnit.bodyweight, .second, .meter, .count] {
            XCTAssertFalse(history.volumeComparison(plans: plans, unit: unit).contains("%"))
        }
        let differentSide = [WorkoutSetPlan(weight: 20, reps: 10, weightSide: .single)]
        XCTAssertFalse(history.volumeComparison(plans: differentSide, unit: .kilogram).contains("%"))
        history.rows[0].repsSide = .unknown
        XCTAssertFalse(history.volumeComparison(plans: plans, unit: .kilogram).contains("%"))
        history = resolve(fixture); history.equipmentVerified = false
        XCTAssertFalse(history.volumeComparison(plans: plans, unit: .kilogram).contains("%"))
        history.equipmentVerified = true; history.classificationUnknown = true
        XCTAssertFalse(history.volumeComparison(plans: plans, unit: .kilogram).contains("%"))
    }

    func testInitialPlansUseOnlyQualifiedObservedStaircaseAndNeverInventMachineIncrements() {
        let fixture = historyFixture()
        var history = resolve(fixture)
        let qualified = history.initialPlans(pattern: .pyramidUp, count: 2, weight: 7, reps: 15)
        XCTAssertEqual(qualified.map(\.weight), [20, 25]); XCTAssertEqual(qualified.map(\.reps), [12, 10])
        let insufficient = history.initialPlans(pattern: .pyramidUp, count: 4, weight: 20, reps: 12)
        XCTAssertEqual(insufficient.map(\.weight), [20, 20, 20, 20])
        XCTAssertEqual(insufficient.map(\.reps), [12, 12, 12, 12])
        history.eligibleSetIDs = []
        XCTAssertEqual(history.initialPlans(pattern: .pyramidUp, count: 2, weight: 20, reps: 12).map(\.weight), [20, 20])
        history = resolve(fixture); history.rows.reverse()
        XCTAssertEqual(history.initialPlans(pattern: .pyramidUp, count: 2, weight: 20, reps: 12).map(\.weight), [20, 20])
        XCTAssertEqual(history.initialPlans(pattern: .fixed, count: 2, weight: 20, reps: 12).map(\.weight), [20, 20])
        XCTAssertEqual(history.rows.map(\.weight), [25, 20], "Building a candidate must not sort or edit actual history")
    }

    func testVolumeDoesNotTreatBlankOrMissingRepetitionsAsZeroCapacity() {
        let fixture = historyFixture()
        let plans = [WorkoutSetPlan(weight: 20, reps: 12), WorkoutSetPlan(weight: 25, reps: 10)]
        var history = resolve(fixture)
        history.rows[0].weight = nil
        XCTAssertFalse(history.volumeComparison(plans: plans, unit: .kilogram).contains("%"))
        history = resolve(fixture); history.rows[0].reps = 0
        XCTAssertFalse(history.volumeComparison(plans: plans, unit: .kilogram).contains("%"),
            "A completed row with missing repetitions cannot silently contribute zero capacity")
        history = resolve(fixture); history.rows[0].reps = -1
        XCTAssertFalse(history.volumeComparison(plans: plans, unit: .kilogram).contains("%"))
    }

    func testLegacyDailyPacketDecodesWithoutPatternAndRetainsOriginalCanonicalDigest() throws {
        let container = try makeContainer()
        let packet = try dailyPacket(in: container.mainContext, pattern: nil)
        let legacy = LegacyPacket(packet)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(legacy)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ConfirmedDailyTrainingPlanPacket.self, from: original)
        XCTAssertNil(decoded.exercises[0].planPattern)
        XCTAssertEqual(try ConfirmedTrainingPlanService.digest(decoded), try ConfirmedTrainingPlanService.digest(legacy))
        let reencoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(decoded)) as? [String: Any])
        let exercises = try XCTUnwrap(reencoded["exercises"] as? [[String: Any]])
        XCTAssertNil(exercises[0]["planPattern"], "A nil optional must stay absent, not introduce a null key")
    }

    func testNewDailyPatternPersistsThroughConfirmationReadbackAndSessionStart() throws {
        let container = try makeContainer(), context = container.mainContext
        let packet = try dailyPacket(in: context, pattern: .pyramidUp)
        let preview = try ConfirmedDailyTrainingPlanService.preview(packet, in: context)
        XCTAssertTrue(preview.conflicts.isEmpty)
        let applied = try ConfirmedDailyTrainingPlanService.apply(expectedPreview: preview, in: context)
        XCTAssertEqual(applied.readback.packet.exercises[0].planPattern, .pyramidUp)
        XCTAssertEqual(applied.readback.schedule.exercises[0].planPattern, .pyramidUp)
        let reread = try XCTUnwrap(ConfirmedDailyTrainingPlanService.readback(id: packet.id, in: ModelContext(container)))
        XCTAssertEqual(reread, applied.readback)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TemplateExercise>()).first?.planPattern, .pyramidUp)
        let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledWorkout>()).first { $0.id == packet.id })
        let sessionID = try WorkoutService.start(schedule: schedule, in: context)
        let snapshot = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExercise>()).first { $0.sessionID == sessionID })
        XCTAssertEqual(snapshot.planPattern, .pyramidUp)
        XCTAssertEqual(snapshot.plannedSets, packet.exercises[0].plannedSets)
        let actuals = try context.fetch(FetchDescriptor<SetLog>())
        XCTAssertEqual(actuals.count, 2)
        XCTAssertTrue(actuals.allSatisfy { !$0.isCompleted && $0.rir == nil && $0.isActualWeightBlank })
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Exercise.self, WorkoutTemplate.self, TemplateExercise.self, ScheduledWorkout.self,
            WorkoutSession.self, SessionExercise.self, SetLog.self, BodyMeasurement.self, TrainingPreferenceRevision.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
        container.mainContext.autosaveEnabled = false
        return container
    }

    @discardableResult
    private func seedPreference(in context: ModelContext) throws -> TrainingPreferenceRevision {
        try TrainingPreferenceService.append(snapshot: .postTravelRestoration,
            effectiveAt: FatLossCalendar.date(2026, 9, 28), reason: "隔离历史偏好", in: context)
    }

    private struct HistoryFixture {
        let exercise: Exercise
        let session: WorkoutSession
        let snapshot: SessionExercise
        let logs: [SetLog]
    }

    private func historyFixture(daysAgo: Int = 1, equipment: String? = "同一器械", rir: Int? = 3,
                                importedNotes: Bool = false) -> HistoryFixture {
        let date = now.addingTimeInterval(-Double(daysAgo) * 86400)
        let exercise = Exercise(name: "历史推胸", muscleGroup: "胸部", equipment: "同一器械")
        let session = WorkoutSession(templateName: "真实已完成", plannedDate: date, startedAt: date,
            completedAt: date.addingTimeInterval(1800), status: .completed,
            importIdentifier: importedNotes ? "notes-test-source" : "")
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: exercise.id, exerciseName: exercise.name,
            order: 0, targetSets: 4, minReps: 8, maxReps: 12, targetWeight: 20, restSeconds: 90,
            equipmentSnapshot: equipment)
        let values: [(Double, Int, Bool, Bool)] = [(20, 12, false, true), (25, 10, false, true),
            (5, 20, true, true), (30, 8, false, false)]
        let logs = values.enumerated().map { index, value in
            SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
                setNumber: index + 1, targetWeight: value.0, targetReps: value.1, actualWeight: value.0,
                actualReps: value.1, rir: rir, isWarmup: value.2, isCompleted: value.3)
        }
        return HistoryFixture(exercise: exercise, session: session, snapshot: snapshot, logs: logs)
    }

    private func resolve(_ fixture: HistoryFixture) -> TrainingPlanHistory {
        TrainingPlanHistory.resolve(exercise: fixture.exercise, before: now,
            sessions: [fixture.session], snapshots: [fixture.snapshot], logs: fixture.logs, schedules: [])
    }

    private func dailyPacket(in context: ModelContext, pattern: SetPlanPattern?) throws -> ConfirmedDailyTrainingPlanPacket {
        let preference = try seedPreference(in: context)
        let exercise = Exercise(name: "单日推胸", muscleGroup: "胸部", equipment: "本人同一器械")
        context.insert(exercise); try context.save()
        let plans = [(20.0, 12), (25.0, 10)].map { weight, reps in
            WorkoutSetPlan(weight: weight, reps: reps, actualDefaultPolicy: .blank,
                prescription: WorkoutSetPrescription(label: "工作组", repsLower: reps, repsUpper: reps + 2,
                    rirLower: 2, rirUpper: 3, restLowerSeconds: 90, restUpperSeconds: 120))
        }
        let source = "# 隔离确认包\n逐组计划与实际分开，热身另计。"
        return ConfirmedDailyTrainingPlanPacket(version: 1, id: UUID(), localDay: "2026-10-23",
            timeZoneIdentifier: "Asia/Shanghai", title: "单日递增计划", preferenceRevisionCode: preference.revisionCode,
            confirmedAt: FatLossCalendar.date(2026, 10, 20), confirmationReference: "ISOLATED-OWNER-CONFIRMATION",
            sourceMarkdown: source, sourceSHA256: ConfirmedTrainingPlanService.digest(Data(source.utf8)),
            guidance: "热身另计，原处方保留",
            exercises: [ConfirmedDailyPlanExercise(catalogExerciseID: exercise.id, catalogName: exercise.name,
                equipment: exercise.equipment, volumeUnit: .kilogram, displayName: exercise.name,
                loadGuidance: "同机显示kg，双侧合计", notes: "热身另计", plannedSets: plans, planPattern: pattern)])
    }

    /// The pre-change wire shape is independent of the new optional property.
    private struct LegacyExercise: Encodable {
        let catalogExerciseID: UUID, catalogName: String, equipment: String, volumeUnit: ExerciseVolumeUnit
        let displayName: String, loadGuidance: String, notes: String
        let plannedSets: [WorkoutSetPlan]
        init(_ row: ConfirmedDailyPlanExercise) {
            catalogExerciseID = row.catalogExerciseID; catalogName = row.catalogName; equipment = row.equipment
            volumeUnit = row.volumeUnit; displayName = row.displayName; loadGuidance = row.loadGuidance
            notes = row.notes; plannedSets = row.plannedSets
        }
    }

    private struct LegacyPacket: Encodable {
        let version: Int, id: UUID, localDay: String, timeZoneIdentifier: String, title: String
        let preferenceRevisionCode: String, confirmedAt: Date, confirmationReference: String
        let sourceMarkdown: String, sourceSHA256: String, guidance: String
        let exercises: [LegacyExercise]
        let actualPrefillConfirmationReference: String?, replacement: ConfirmedDailyTrainingPlanReplacement?
        init(_ row: ConfirmedDailyTrainingPlanPacket) {
            version = row.version; id = row.id; localDay = row.localDay; timeZoneIdentifier = row.timeZoneIdentifier
            title = row.title; preferenceRevisionCode = row.preferenceRevisionCode; confirmedAt = row.confirmedAt
            confirmationReference = row.confirmationReference; sourceMarkdown = row.sourceMarkdown
            sourceSHA256 = row.sourceSHA256; guidance = row.guidance; exercises = row.exercises.map(LegacyExercise.init)
            actualPrefillConfirmationReference = row.actualPrefillConfirmationReference; replacement = row.replacement
        }
    }
}

@MainActor
final class WorkoutRecordingDefaultsTests: XCTestCase {
    private struct Fixture {
        let container: ModelContainer
        let exercise: Exercise
        let schedule: ScheduledWorkout
        let originalPlans: [WorkoutSetPlan]
        let history: [SetLog]
        @MainActor var context: ModelContext { container.mainContext }
    }

    private func fixture(unit: ExerciseVolumeUnit = .kilogram, policy: WorkoutActualDefaultPolicy = .plan,
                         notes: String = "", historyEquipment: String? = "器械A",
                         side: MeasurementSide = .single, historyCount: Int = 2,
                         historyWeight: Double = 25, withHistory: Bool = true) throws -> Fixture {
        let schema = Schema([Exercise.self, WorkoutTemplate.self, TemplateExercise.self, ScheduledWorkout.self,
            WorkoutSession.self, SessionExercise.self, SetLog.self, BodyMeasurement.self, TrainingPreferenceRevision.self])
        let container = try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let context = container.mainContext
        context.autosaveEnabled = false
        let exercise = Exercise(name: "本次测试动作", muscleGroup: "胸部", equipment: "器械A", notes: notes)
        exercise.volumeUnit = unit
        let template = WorkoutTemplate(name: "本次计划", weekday: 2)
        let plans = (0..<3).map { WorkoutSetPlan(weight: 40 + Double($0), reps: 8,
            actualDefaultPolicy: policy) }
        let item = TemplateExercise(templateID: template.id, exerciseID: exercise.id, order: 0,
            targetSets: 3, minReps: 8, maxReps: 8, targetWeight: 40, restSeconds: 90, plannedSets: plans)
        let schedule = ScheduledWorkout(templateID: template.id, templateName: template.name, plannedDate: .now)
        context.insert(exercise); context.insert(template); context.insert(item); context.insert(schedule)
        var history: [SetLog] = []
        if withHistory {
            let date = Date.now.addingTimeInterval(-86400)
            let previous = WorkoutSession(templateName: "上次已完成", plannedDate: date, startedAt: date,
                completedAt: date.addingTimeInterval(3600), status: .completed)
            let snapshot = SessionExercise(sessionID: previous.id, exerciseID: exercise.id, exerciseName: exercise.name,
                order: 0, targetSets: historyCount, minReps: 10, maxReps: 12, targetWeight: 25,
                restSeconds: 120, volumeUnit: unit, equipmentSnapshot: historyEquipment)
            context.insert(previous); context.insert(snapshot)
            history = (0..<historyCount).map { index in
                SetLog(sessionID: previous.id, sessionExerciseID: snapshot.id, exerciseID: exercise.id,
                    setNumber: index + 1, targetWeight: 20, targetReps: 8,
                    actualWeight: historyWeight + Double(index), actualReps: 12 - index,
                    isCompleted: true, actualWeightSide: side, actualRepsSide: side)
            }
            for row in history { context.insert(row) }
        }
        try context.save()
        return Fixture(container: container, exercise: exercise, schedule: schedule, originalPlans: plans, history: history)
    }

    private func start(_ f: Fixture) throws -> (WorkoutSession, SessionExercise, [SetLog]) {
        let id = try WorkoutService.start(schedule: f.schedule, currentHealthWeightKg: 78, in: f.context)
        let session = try XCTUnwrap(f.context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == id })
        let snapshot = try XCTUnwrap(f.context.fetch(FetchDescriptor<SessionExercise>()).first { $0.sessionID == id })
        return (session, snapshot, try rows(snapshot, in: f.context))
    }

    private func rows(_ snapshot: SessionExercise, in context: ModelContext) throws -> [SetLog] {
        try context.fetch(FetchDescriptor<SetLog>()).filter { $0.sessionExerciseID == snapshot.id }
            .sorted { $0.setNumber < $1.setNumber }
    }

    func testHistoryOverridesPlanBlankAndInstructionDefaultsOnlyForMatchingRows() throws {
        for (policy, notes) in [(WorkoutActualDefaultPolicy.plan, ""), (.blank, ""), (.plan, "重量留空")] {
            let f = try fixture(policy: policy, notes: notes)
            let (_, snapshot, actual) = try start(f)
            XCTAssertEqual(actual.map(\.actualWeight), [25, 26, policy == .blank || !notes.isEmpty ? 0 : 42])
            XCTAssertEqual(actual.map(\.actualReps), [12, 11, 8])
            XCTAssertEqual(actual.prefix(2).map(\.actualEntrySource), [.history, .history])
            XCTAssertEqual(actual.prefix(2).map(\.sourceHistorySetID), f.history.map { Optional($0.id) })
            XCTAssertEqual(actual[0].actualWeightSide, .single)
            XCTAssertFalse(actual[0].isActualWeightBlank)
            XCTAssertEqual(snapshot.plannedSets, f.originalPlans)
            XCTAssertEqual(actual.map(\.targetWeight), [40, 41, 42])
            XCTAssertTrue(actual.allSatisfy { $0.rir == nil && !$0.isCompleted && $0.startedAt == nil && $0.completedAt == nil })
            XCTAssertEqual(f.history.map(\.actualWeight), [25, 26])
            XCTAssertTrue(f.history.allSatisfy(\.isCompleted))
        }
    }

    func testNoCompatibleHistoryPreservesOriginalFallbackAndUnknowns() throws {
        for scenario in 0..<4 {
            let f = try fixture(policy: .blank, historyEquipment: scenario == 0 ? nil : (scenario == 1 ? "其他器械" : "器械A"),
                side: scenario == 2 ? .unknown : .single, withHistory: scenario != 3)
            let (_, _, actual) = try start(f)
            XCTAssertEqual(actual.map(\.actualWeight), [0, 0, 0])
            XCTAssertEqual(actual.map(\.actualReps), [8, 8, 8])
            XCTAssertTrue(actual.allSatisfy { $0.actualEntrySource == .blank && $0.isActualWeightBlank && $0.sourceHistorySetID == nil })
        }
        let f = try fixture(withHistory: false)
        let (_, _, actual) = try start(f)
        XCTAssertEqual(actual.map(\.actualWeight), [40, 41, 42])
        XCTAssertTrue(actual.allSatisfy { $0.actualEntrySource == .plan })
    }

    func testUnknownHistoricalLoadKeepsItsPositionAndExplicitZeroRemainsCopyable() throws {
        for blank in [true, false] {
            let f = try fixture(policy: .blank, historyWeight: 0)
            f.history[0].actualWeightIsBlank = blank
            f.history[1].actualWeight = 15
            try f.context.save()
            let (_, _, actual) = try start(f)
            XCTAssertEqual(actual.map(\.actualWeight), [0, 15, 0])
            XCTAssertEqual(actual[0].actualEntrySource, blank ? .blank : .history)
            XCTAssertEqual(actual[0].isActualWeightBlank, blank)
            XCTAssertEqual(actual[0].sourceHistorySetID, blank ? nil : f.history[0].id)
            XCTAssertEqual(actual[1].actualEntrySource, .history)
            XCTAssertEqual(actual[1].sourceHistorySetID, f.history[1].id)
            XCTAssertEqual(actual[1].actualReps, 11)
            XCTAssertEqual(actual[2].actualEntrySource, .blank)
            XCTAssertEqual(f.history[0].isActualWeightBlank, blank)
            let reference = try XCTUnwrap(WorkoutHistoryResolver.latest(exerciseID: f.exercise.id, unit: .kilogram,
                equipment: f.exercise.equipment, before: .now,
                sessions: try f.context.fetch(FetchDescriptor<WorkoutSession>()),
                snapshots: try f.context.fetch(FetchDescriptor<SessionExercise>()),
                logs: try f.context.fetch(FetchDescriptor<SetLog>())))
            let display = WorkoutHistoryResolver.display(reference, unit: .kilogram)
            XCTAssertEqual(display.rows.count, 2)
            XCTAssertTrue(display.rows[0].hasPrefix(blank ? "重量未记录 × 12" : "0 kg × 12"))
            XCTAssertTrue(display.rows[1].hasPrefix("15 kg × 11"))
        }
    }

    func testBodyweightZeroLoadAndAllSingleAmountUnitsKeepTheirMeaning() throws {
        for unit in [ExerciseVolumeUnit.kilogram, .bodyweight, .second, .meter, .count] {
            let f = try fixture(unit: unit, historyWeight: 0)
            let (_, snapshot, actual) = try start(f)
            XCTAssertEqual(actual[0].actualReps, 12)
            XCTAssertEqual(actual[0].actualEntrySource, .history)
            XCTAssertEqual(actual[0].actualWeight, unit == .bodyweight ? (snapshot.bodyWeightKgSnapshot ?? 0) : (unit.recordsNumericLoad ? 0 : 40))
            XCTAssertFalse(actual[0].isActualWeightBlank)
            XCTAssertNil(actual[0].rir)
        }
    }

    func testReentryLeavesEditedAndCompletedRowsAndHistoryUnchanged() throws {
        let f = try fixture()
        let (session, snapshot, actual) = try start(f)
        actual[0].actualWeight = 33; actual[0].actualReps = 9; actual[0].markActualEntryEdited()
        actual[1].isCompleted = true; actual[1].completedAt = .now; actual[1].rir = 2
        try f.context.save()
        XCTAssertEqual(try WorkoutService.start(schedule: f.schedule, in: f.context), session.id)
        let reread = try rows(snapshot, in: ModelContext(f.container))
        XCTAssertEqual(reread.map(\.actualWeight), [33, 26, 42])
        XCTAssertTrue(reread[1].isCompleted); XCTAssertEqual(reread[1].rir, 2)
        XCTAssertEqual(try f.context.fetchCount(FetchDescriptor<SetLog>()), 5)
        XCTAssertEqual(f.history.map(\.actualReps), [12, 11])
    }

    func testPyramidDraftCopiesPartialHistoryWithoutRIRAndDoesNotQualifyRecommendation() throws {
        let f = try fixture()
        let draft = ExerciseSetupDraft.suggested(for: f.exercise,
            sessions: try f.context.fetch(FetchDescriptor<WorkoutSession>()),
            sessionExercises: try f.context.fetch(FetchDescriptor<SessionExercise>()),
            setLogs: try f.context.fetch(FetchDescriptor<SetLog>()), fallbackSets: 3,
            fallbackReps: 8, fallbackWeight: 40, defaultPattern: .pyramidUp)
        XCTAssertEqual(draft.plannedSets.map(\.weight), [25, 26, 40])
        XCTAssertEqual(draft.plannedSets.map(\.reps), [12, 11, 8])
        XCTAssertEqual(draft.plannedSets[0].weightSide, .single)
        XCTAssertNotNil(draft.previousDate)
        XCTAssertEqual(draft.history?.eligibleSetIDs, [])
        XCTAssertEqual(draft.pattern, .pyramidUp)
    }

    func testConfirmedSetupWinsAndMenuKeepsManualTailSeparateFromNewPlan() throws {
        let f = try fixture()
        let (session, _, _) = try start(f)
        let selected = Exercise(name: "明确新增", muscleGroup: "背部", equipment: "拉力器")
        f.context.insert(selected)
        let configured = [WorkoutSetPlan(weight: 17, reps: 7, weightSide: .single, repsSide: .single),
                          WorkoutSetPlan(weight: 19, reps: 6)]
        let added = try WorkoutService.addExercise(selected, to: session,
            configuration: ExerciseSetupDraft(pattern: .fixed, plannedSets: configured, restSeconds: 90), in: f.context)
        let inputs = [DailyPlanExerciseInput(exerciseID: f.exercise.id, plannedSets: f.originalPlans, planPattern: .fixed, restSeconds: 90),
            DailyPlanExerciseInput(exerciseID: selected.id, plannedSets: [WorkoutSetPlan(weight: 55, reps: 4)], planPattern: .fixed, restSeconds: 90)]
        try WorkoutService.syncMenu(inputs, to: session, in: f.context)
        let actual = try rows(added, in: f.context)
        XCTAssertEqual(actual.map(\.actualWeight), [17, 19])
        XCTAssertEqual(actual.map(\.actualEntrySource), [.manual, .manual])
        XCTAssertTrue(actual.allSatisfy { $0.sourceHistorySetID == nil })
        XCTAssertEqual(actual.map(\.targetWeight), [55, 19])
        XCTAssertEqual(added.targetSets, 1); XCTAssertEqual(added.plannedSets.count, 1)
        XCTAssertEqual(added.plannedSets.map(\.weight), [55])
        XCTAssertThrowsError(try WorkoutService.syncMenu([inputs[0]], to: session, in: f.context))
        XCTAssertEqual(try rows(added, in: f.context).count, 2)
    }

    func testMenuChangesTargetsWithoutReinitializingExistingHistoryAndNewRowsUseHistory() throws {
        let f = try fixture(historyCount: 4)
        let (session, snapshot, _) = try start(f)
        let updated = [WorkoutSetPlan(weight: 60, reps: 5)]
        try WorkoutService.syncMenu([DailyPlanExerciseInput(exerciseID: f.exercise.id, plannedSets: updated, planPattern: .fixed, restSeconds: 90)],
            to: session, in: f.context)
        XCTAssertEqual(try rows(snapshot, in: f.context).map(\.actualWeight), [25])
        XCTAssertEqual(snapshot.targetSets, 1); XCTAssertEqual(snapshot.plannedSets, updated)
        let expanded = f.originalPlans + [WorkoutSetPlan(weight: 70, reps: 4)]
        try WorkoutService.syncMenu([DailyPlanExerciseInput(exerciseID: f.exercise.id, plannedSets: expanded, planPattern: .fixed, restSeconds: 90)],
            to: session, in: f.context)
        let actual = try rows(snapshot, in: f.context)
        XCTAssertEqual(actual.map(\.actualWeight), [25, 26, 27, 28])
        XCTAssertEqual(actual.map(\.targetWeight), [40, 41, 42, 70])
        XCTAssertEqual(actual[3].sourceHistorySetID, f.history[3].id)
        XCTAssertEqual(snapshot.targetSets, 4); XCTAssertEqual(snapshot.plannedSets, expanded)
    }

    private func seedSelectedHistory(in context: ModelContext) throws -> (Exercise, SetLog) {
        let selected = Exercise(name: "替换新动作", muscleGroup: "背部", equipment: "新器械")
        let date = Date.now.addingTimeInterval(-7200)
        let session = WorkoutSession(templateName: "新动作历史", plannedDate: date, startedAt: date,
            completedAt: date.addingTimeInterval(1800), status: .completed)
        let snapshot = SessionExercise(sessionID: session.id, exerciseID: selected.id, exerciseName: selected.name,
            order: 0, targetSets: 1, minReps: 13, maxReps: 13, targetWeight: 9, restSeconds: 90,
            equipmentSnapshot: selected.equipment)
        let log = SetLog(sessionID: session.id, sessionExerciseID: snapshot.id, exerciseID: selected.id,
            setNumber: 1, targetWeight: 9, targetReps: 13, actualWeight: 9, actualReps: 13,
            isCompleted: true, actualWeightSide: .bilateral, actualRepsSide: .bilateral)
        context.insert(selected); context.insert(session); context.insert(snapshot); context.insert(log)
        try context.save()
        return (selected, log)
    }

    func testAutomaticAddAndMenuNewExerciseUseOnlyTheirOwnHistory() throws {
        for viaMenu in [true, false] {
            let f = try fixture()
            let (selected, previous) = try seedSelectedHistory(in: f.context)
            let (session, _, _) = try start(f)
            let added: SessionExercise
            if viaMenu {
                try WorkoutService.syncMenu([
                    DailyPlanExerciseInput(exerciseID: f.exercise.id, plannedSets: f.originalPlans, planPattern: .fixed, restSeconds: 90),
                    DailyPlanExerciseInput(exerciseID: selected.id, plannedSets: [WorkoutSetPlan(weight: 99, reps: 4)],
                        planPattern: .fixed, restSeconds: 90)], to: session, in: f.context)
                added = try XCTUnwrap(f.context.fetch(FetchDescriptor<SessionExercise>()).first {
                    $0.sessionID == session.id && $0.exerciseID == selected.id })
            } else {
                added = try WorkoutService.addExercise(selected, to: session, in: f.context)
            }
            let actual = try XCTUnwrap(rows(added, in: f.context).first)
            XCTAssertEqual(actual.actualWeight, 9); XCTAssertEqual(actual.actualReps, 13)
            XCTAssertEqual(actual.sourceHistorySetID, previous.id)
            XCTAssertEqual(actual.actualEntrySource, .history)
            XCTAssertNil(actual.rir); XCTAssertFalse(actual.isCompleted)
        }
    }

    func testReplacementUsesNewIdentityAndConfirmedValuesWhileKeepingOriginalCompletedSet() throws {
        let f = try fixture()
        let (selected, previous) = try seedSelectedHistory(in: f.context)
        let (session, source, actual) = try start(f)
        actual[0].isCompleted = true; actual[0].completedAt = .now
        try f.context.save()
        let draft = ExerciseSetupDraft.suggested(for: selected,
            sessions: try f.context.fetch(FetchDescriptor<WorkoutSession>()),
            sessionExercises: try f.context.fetch(FetchDescriptor<SessionExercise>()),
            setLogs: try f.context.fetch(FetchDescriptor<SetLog>()))
        XCTAssertEqual(draft.plannedSets.first?.weight, 9)
        var confirmed = draft
        confirmed.plannedSets[0].weight = 11
        let review = try WorkoutService.replacementReview(sessionID: session.id, sourceSessionExerciseID: source.id, in: f.context)
        let replacement = try WorkoutService.replaceRemainingExercise(review: review, with: selected,
            configuration: confirmed, confirmingEnteredData: true, in: f.context)
        let replacementRows = try rows(replacement, in: f.context)
        XCTAssertEqual(replacement.exerciseID, selected.id)
        XCTAssertEqual(replacementRows.first?.actualWeight, 11)
        XCTAssertEqual(replacementRows.first?.actualReps, 13)
        XCTAssertEqual(replacementRows.first?.actualEntrySource, .manual)
        XCTAssertNil(replacementRows.first?.sourceHistorySetID)
        XCTAssertEqual(actual[0].actualWeight, 25); XCTAssertTrue(actual[0].isCompleted)
        XCTAssertEqual(previous.actualWeight, 9); XCTAssertTrue(previous.isCompleted)
        XCTAssertEqual(f.history.map(\.actualWeight), [25, 26])
    }

    func testConfirmedBlankConfigurationWithPositiveNumberKeepsConfirmedNumber() throws {
        let f = try fixture()
        let (session, _, _) = try start(f)
        let selected = Exercise(name: "明确重量", muscleGroup: "胸部", equipment: "器械")
        f.context.insert(selected)
        let draft = ExerciseSetupDraft(pattern: .fixed,
            plannedSets: [WorkoutSetPlan(weight: 17, reps: 9, actualDefaultPolicy: .blank)], restSeconds: 90)
        let added = try WorkoutService.addExercise(selected, to: session, configuration: draft, in: f.context)
        let actual = try XCTUnwrap(rows(added, in: ModelContext(f.container)).first)
        XCTAssertEqual(actual.actualWeight, 17); XCTAssertEqual(actual.actualReps, 9)
        XCTAssertEqual(actual.actualEntrySource, .manual)
        XCTAssertFalse(actual.isActualWeightBlank); XCTAssertNil(actual.sourceHistorySetID)
    }

    func testConfirmedUnfilledBlankStaysUnknownAndExplicitZeroPlanIsKnown() throws {
        for policy in [WorkoutActualDefaultPolicy.blank, .plan] {
            let f = try fixture()
            let (session, _, _) = try start(f)
            let selected = Exercise(name: "零与未知", muscleGroup: "胸部", equipment: "器械")
            f.context.insert(selected)
            let draft = ExerciseSetupDraft(pattern: .fixed,
                plannedSets: [WorkoutSetPlan(weight: 0, reps: 9, actualDefaultPolicy: policy)], restSeconds: 90)
            let added = try WorkoutService.addExercise(selected, to: session, configuration: draft, in: f.context)
            let actual = try XCTUnwrap(rows(added, in: ModelContext(f.container)).first)
            XCTAssertEqual(actual.actualWeight, 0); XCTAssertEqual(actual.actualEntrySource, .manual)
            XCTAssertEqual(actual.isActualWeightBlank, policy == .blank)
            XCTAssertNil(actual.sourceHistorySetID)
        }
    }

    func testRestorePlanDefaultsRemainsExplicitAndNeverCopiesHistory() throws {
        let f = try fixture()
        let (_, snapshot, _) = try start(f)
        try WorkoutService.restorePlanDefaults(for: snapshot, in: f.context)
        let restored = try rows(snapshot, in: f.context)
        XCTAssertEqual(restored.map(\.actualWeight), [40, 41, 42])
        XCTAssertTrue(restored.allSatisfy { $0.actualEntrySource == .plan && $0.sourceHistorySetID == nil && !$0.isCompleted })
        XCTAssertEqual(f.history.map(\.actualWeight), [25, 26])
    }
}
