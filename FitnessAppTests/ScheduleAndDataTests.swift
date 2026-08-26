import SwiftData
import UserNotifications
import XCTest
@testable import FitnessApp

private actor RecordingRestNotificationCenter: RestNotificationCenter {
    private var pending: [String: UNNotificationRequest] = [:]
    private var delivered: Set<String> = []

    func add(_ request: UNNotificationRequest) async throws {
        pending[request.identifier] = request
    }

    func removePending(withIdentifiers identifiers: [String]) async {
        identifiers.forEach { pending[$0] = nil }
    }

    func removeDelivered(withIdentifiers identifiers: [String]) async {
        delivered.subtract(identifiers)
    }

    func summary(for identifier: String) -> (count: Int, title: String?, repeats: Bool?) {
        let request = pending[identifier]
        return (request == nil ? 0 : 1, request?.content.title, request?.trigger?.repeats)
    }
}

@MainActor
final class ScheduleAndDataTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: NotificationService.workoutEnabledKey)
    }

    func testUITestingDisablesExternalSideEffectsByDefault() {
        let arguments = ["FitnessApp", "--ui-testing", "--ui-testing-persistent"]

        XCTAssertFalse(CloudSyncRuntime.shouldSyncWorkoutReminders(arguments: arguments))
        XCTAssertFalse(CloudSyncRuntime.shouldReadShareDraft(arguments: arguments))
    }

    func testDedicatedUITestsMustExplicitlyEnableExternalSideEffects() {
        XCTAssertTrue(CloudSyncRuntime.shouldSyncWorkoutReminders(arguments: [
            "FitnessApp", "--ui-testing", "--ui-testing-workout-reminders"
        ]))
        XCTAssertTrue(CloudSyncRuntime.shouldReadShareDraft(arguments: [
            "FitnessApp", "--ui-testing", "--ui-testing-share-draft"
        ]))
        XCTAssertTrue(CloudSyncRuntime.shouldSyncWorkoutReminders(arguments: ["FitnessApp"]))
        XCTAssertTrue(CloudSyncRuntime.shouldReadShareDraft(arguments: ["FitnessApp"]))
    }

    func testReschedulePreservesOriginalDateAndPreventsRegeneration() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalDate = Date.now.startOfDay
        let template = WorkoutTemplate(
            name: "测试训练",
            weekday: originalDate.weekdayNumber
        )
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: originalDate
        )
        context.insert(template)
        context.insert(schedule)
        try context.save()

        let newDate = originalDate.addingDays(1)
        try ScheduleService.reschedule(schedule, to: newDate, in: context)
        try ScheduleService.refreshUpcoming(in: context, days: 3)

        let schedules = try context.fetch(FetchDescriptor<ScheduledWorkout>())
        XCTAssertEqual(schedules.count, 1)
        XCTAssertTrue(schedule.plannedDate.isSameDay(as: newDate))
        XCTAssertTrue(schedule.originalPlannedDate?.isSameDay(as: originalDate) == true)
    }

    func testSkipAndRestoreSchedule() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "推", weekday: Date.now.weekdayNumber)
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: .now
        )
        context.insert(template)
        context.insert(schedule)

        try ScheduleService.skip(schedule, reason: "出差", in: context)
        XCTAssertEqual(schedule.status, .skipped)
        XCTAssertEqual(schedule.skipReason, "出差")

        try ScheduleService.restore(schedule, in: context)
        XCTAssertEqual(schedule.status, .planned)
        XCTAssertTrue(schedule.skipReason.isEmpty)
    }

    func testManualScheduleRejectsDuplicate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "腿", weekday: Date.now.weekdayNumber)
        context.insert(template)

        _ = try ScheduleService.addManual(template: template, on: .now, in: context)
        XCTAssertThrowsError(try ScheduleService.addManual(template: template, on: .now, in: context)) { error in
            XCTAssertEqual(error as? ScheduleServiceError, .duplicateSchedule)
        }
    }

    func testJSONBackupImportsIntoEmptyDatabase() throws {
        let source = try makeContainer()
        let sourceContext = source.mainContext
        sourceContext.insert(Exercise(
            name: "自定义划船",
            muscleGroup: "背部",
            equipment: "弹力带",
            isBuiltIn: false,
            volumeUnit: .meter
        ))
        sourceContext.insert(MealEntry(
            mealType: .lunch,
            name: "鸡胸饭",
            calories: 520,
            proteinGrams: 42,
            carbsGrams: 58,
            fatGrams: 12
        ))
        sourceContext.insert(DailyBodyCheckIn(
            date: .now,
            conditionScore: 4,
            discomfortNotes: "右肩前侧发紧",
            bodyMarkers: [
                BodyMapMarker(regionID: "front-right-shoulder", kind: .area),
                BodyMapMarker(regionID: "front-right-knee", kind: .jointFascia)
            ]
        ))
        try sourceContext.save()

        let backupURL = try DataExportService.createBackup(in: sourceContext)
        let data = try Data(contentsOf: backupURL)
        let preview = try DataExportService.preview(data)
        XCTAssertEqual(preview.exercises, 1)
        XCTAssertEqual(preview.meals, 1)
        XCTAssertEqual(preview.bodyCheckIns, 1)

        let destination = try makeContainer()
        let summary = try DataExportService.importBackup(data, into: destination.mainContext)
        XCTAssertEqual(summary.imported, 3)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<Exercise>()).count, 1)
        XCTAssertEqual(
            try destination.mainContext.fetch(FetchDescriptor<Exercise>()).first?.volumeUnit,
            .meter
        )
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<MealEntry>()).count, 1)
        let importedCheckIn = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<DailyBodyCheckIn>()).first
        )
        XCTAssertEqual(importedCheckIn.conditionScore, 4)
        XCTAssertEqual(importedCheckIn.discomfortNotes, "右肩前侧发紧")
        XCTAssertEqual(importedCheckIn.bodyMarkers.count, 2)
    }

    func testBackupAndCSVPreserveExerciseAndSessionVolumeUnits() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let run = Exercise(
            name: "测试折返跑",
            muscleGroup: "有氧",
            equipment: "无",
            volumeUnit: .meter
        )
        let jump = Exercise(
            name: "测试开合跳",
            muscleGroup: "有氧",
            equipment: "无",
            volumeUnit: .count
        )
        let session = WorkoutSession(
            templateName: "有氧测试",
            plannedDate: .now,
            status: .completed
        )
        let runSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: run.id,
            exerciseName: run.name,
            order: 0,
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
            order: 1,
            targetSets: 1,
            minReps: 40,
            maxReps: 40,
            targetWeight: 0,
            restSeconds: 30,
            volumeUnit: .count
        )
        let logs = [
            SetLog(
                sessionID: session.id, sessionExerciseID: runSnapshot.id, exerciseID: run.id,
                setNumber: 1, targetWeight: 500, targetReps: 2, actualWeight: 500, actualReps: 2,
                isCompleted: true
            ),
            SetLog(
                sessionID: session.id, sessionExerciseID: jumpSnapshot.id, exerciseID: jump.id,
                setNumber: 1, targetWeight: 0, targetReps: 40, actualWeight: 0, actualReps: 40,
                isCompleted: true
            )
        ]
        context.insert(run)
        context.insert(jump)
        context.insert(session)
        context.insert(runSnapshot)
        context.insert(jumpSnapshot)
        logs.forEach(context.insert)
        try context.save()

        let backup = try Data(contentsOf: DataExportService.createBackup(in: context))
        let csv = try String(contentsOf: DataExportService.createCSV(in: context), encoding: .utf8)
        XCTAssertTrue(csv.contains("volume_unit"))
        XCTAssertTrue(csv.contains(",meter,"))
        XCTAssertTrue(csv.contains(",count,"))

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(backup, into: destination.mainContext)
        let importedExercises = try destination.mainContext.fetch(FetchDescriptor<Exercise>())
        let importedSnapshots = try destination.mainContext.fetch(FetchDescriptor<SessionExercise>())

        XCTAssertEqual(importedExercises.first(where: { $0.name == run.name })?.volumeUnit, .meter)
        XCTAssertEqual(importedExercises.first(where: { $0.name == jump.name })?.volumeUnit, .count)
        XCTAssertEqual(importedSnapshots.first(where: { $0.exerciseName == run.name })?.volumeUnit, .meter)
        XCTAssertEqual(importedSnapshots.first(where: { $0.exerciseName == jump.name })?.volumeUnit, .count)
    }

    func testLegacyBackupWithoutVolumeUnitDefaultsToKilogram() throws {
        let source = try makeContainer()
        let exercise = Exercise(
            name: "旧版动作",
            muscleGroup: "背部",
            equipment: "器械",
            volumeUnit: .meter
        )
        source.mainContext.insert(exercise)
        try source.mainContext.save()

        let currentData = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))
        let currentJSON = try XCTUnwrap(String(data: currentData, encoding: .utf8))
        let legacyJSON = currentJSON.replacingOccurrences(
            of: "volumeUnitRaw",
            with: "legacyVolumeUnitRaw"
        )
        XCTAssertFalse(legacyJSON.contains("\"volumeUnitRaw\""))

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(Data(legacyJSON.utf8), into: destination.mainContext)
        let restored = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<Exercise>()).first
        )
        XCTAssertEqual(restored.volumeUnit, .kilogram)
    }

    func testWorkoutFeelingHasFiveOrderedEmojiAndSurvivesBackup() throws {
        XCTAssertEqual(WorkoutFeeling.allCases.count, 5)
        XCTAssertEqual(WorkoutFeeling.allCases.map(\.emoji), ["😣", "😥", "😮", "🙂", "😄"])

        let source = try makeContainer()
        let exercise = Exercise(name: "测试推举", muscleGroup: "肩部", equipment: "哑铃")
        let session = WorkoutSession(templateName: "测试", plannedDate: .now)
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 10,
            targetWeight: 10,
            restSeconds: 60,
            feeling: .painful
        )
        source.mainContext.insert(exercise)
        source.mainContext.insert(session)
        source.mainContext.insert(snapshot)
        try source.mainContext.save()

        let data = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)
        let imported = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first
        )
        XCTAssertEqual(imported.feeling, .painful)
    }

    func testDailyBodyCheckInNormalizesScoreAndMarkers() {
        let checkIn = DailyBodyCheckIn(
            conditionScore: 9,
            bodyMarkers: [
                BodyMapMarker(regionID: "front-left-knee", kind: .jointFascia),
                BodyMapMarker(regionID: "front-left-knee", kind: .jointFascia)
            ]
        )

        XCTAssertEqual(checkIn.conditionScore, 5)
        XCTAssertEqual(checkIn.bodyMarkers, [
            BodyMapMarker(regionID: "front-left-knee", kind: .jointFascia)
        ])
    }

    func testDailyBodyCheckInClampsBothBoundsAndNormalizesDate() {
        let rawDate = Date(timeIntervalSince1970: 1_800_123_456)
        let low = DailyBodyCheckIn(date: rawDate, conditionScore: Int.min)
        let high = DailyBodyCheckIn(date: rawDate, conditionScore: Int.max)

        XCTAssertEqual(low.conditionScore, 1)
        XCTAssertEqual(high.conditionScore, 5)
        XCTAssertEqual(low.date, rawDate.startOfDay)
        XCTAssertEqual(high.date, rawDate.startOfDay)
    }

    func testDailyBodyCheckInInvalidMarkerJSONFailsClosed() {
        let checkIn = DailyBodyCheckIn(conditionScore: 3)
        checkIn.bodyMarkersJSON = "{not-json"

        XCTAssertEqual(checkIn.bodyMarkers, [])
    }

    func testDailyBodyCheckInSupportsAreaAndJointMarkerOnSameRegion() {
        let checkIn = DailyBodyCheckIn(
            conditionScore: 3,
            bodyMarkers: [
                BodyMapMarker(regionID: "front-right-shoulder", kind: .area),
                BodyMapMarker(regionID: "front-right-shoulder", kind: .jointFascia)
            ]
        )

        XCTAssertEqual(Set(checkIn.bodyMarkers.map(\.id)), [
            "front-right-shoulder:area",
            "front-right-shoulder:jointFascia"
        ])
    }

    func testDailyBodyCheckInServiceUpsertsSameDayAndTrimsNotes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let day = Date(timeIntervalSince1970: 1_800_100_000)
        let preferred = DailyBodyCheckIn(date: day, conditionScore: 2, discomfortNotes: "旧备注")
        let duplicate = DailyBodyCheckIn(date: day.addingTimeInterval(3_600), conditionScore: 5)
        let tomorrow = DailyBodyCheckIn(date: day.addingDays(1), conditionScore: 4)
        context.insert(preferred)
        context.insert(duplicate)
        context.insert(tomorrow)
        try context.save()

        try DailyBodyCheckInService.save(
            existing: preferred,
            date: day,
            conditionScore: 6,
            discomfortNotes: "  右肩前侧发紧  \n",
            bodyMarkers: [
                BodyMapMarker(regionID: "front-right-shoulder", kind: .area),
                BodyMapMarker(regionID: "front-right-shoulder", kind: .jointFascia)
            ],
            in: context
        )

        let records = try context.fetch(FetchDescriptor<DailyBodyCheckIn>())
        XCTAssertEqual(records.filter { $0.date.isSameDay(as: day) }.count, 1)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(preferred.conditionScore, 5)
        XCTAssertEqual(preferred.discomfortNotes, "右肩前侧发紧")
        XCTAssertEqual(preferred.bodyMarkers.count, 2)
    }

    func testBodyRegionCatalogIsCompleteUniqueAndWithinBounds() {
        let regions = BodyRegionCatalog.all
        XCTAssertEqual(regions.count, 34)
        XCTAssertEqual(Set(regions.map(\.id)).count, 34)
        XCTAssertEqual(regions.filter { $0.side == .front }.count, 17)
        XCTAssertEqual(regions.filter { $0.side == .back }.count, 17)

        for region in regions {
            XCTAssertTrue((0...1).contains(region.x), region.id)
            XCTAssertTrue((0...1).contains(region.y), region.id)
            XCTAssertTrue((0...1).contains(region.width), region.id)
            XCTAssertTrue((0...1).contains(region.height), region.id)
        }

        for left in regions where left.id.contains("left") {
            let rightID = left.id.replacingOccurrences(of: "left", with: "right")
            guard let right = regions.first(where: { $0.id == rightID }) else {
                return XCTFail("缺少对称区域：\(left.id)")
            }
            XCTAssertEqual(left.x + right.x, 1, accuracy: 0.001, left.id)
            XCTAssertEqual(left.y, right.y, accuracy: 0.001, left.id)
        }
    }

    func testBodyRegionImageLayoutMapsFrontAndBackOntoSharedAnatomyAsset() throws {
        let front = try XCTUnwrap(BodyRegionCatalog.definition(for: "front-right-shoulder"))
        let back = try XCTUnwrap(BodyRegionCatalog.definition(for: "back-left-glute"))

        let frontPlacement = BodyRegionImageLayout.placement(for: front)
        XCTAssertEqual(frontPlacement.x, 0.3684, accuracy: 0.0001)
        XCTAssertEqual(frontPlacement.y, 0.2516, accuracy: 0.0001)
        XCTAssertEqual(frontPlacement.width, 0.0884, accuracy: 0.0001)
        XCTAssertEqual(frontPlacement.height, 0.0690, accuracy: 0.0001)

        let backPlacement = BodyRegionImageLayout.placement(for: back)
        XCTAssertEqual(backPlacement.x, 0.6855, accuracy: 0.0001)
        XCTAssertEqual(backPlacement.y, 0.5828, accuracy: 0.0001)
        XCTAssertEqual(backPlacement.width, 0.0935, accuracy: 0.0001)
        XCTAssertEqual(backPlacement.height, 0.1104, accuracy: 0.0001)

        for region in BodyRegionCatalog.all {
            let placement = BodyRegionImageLayout.placement(for: region)
            XCTAssertTrue((0...1).contains(placement.x), region.id)
            XCTAssertTrue((0...1).contains(placement.y), region.id)
            XCTAssertGreaterThan(placement.width, 0, region.id)
            XCTAssertGreaterThan(placement.height, 0, region.id)
        }
    }

    func testBodyMarkerInferenceDisambiguatesFrontBackAndIgnoresNegation() {
        let result = BodyRegionCatalog.inferMarkers(
            in: "右肩前侧抬手疼，但左膝不疼",
            kind: .area
        )

        XCTAssertEqual(result.markers, [
            BodyMapMarker(regionID: "front-right-shoulder", kind: .area)
        ])
        XCTAssertFalse(result.requiresConfirmation)
        XCTAssertEqual(result.ignoredNegatedTerms, ["左膝不疼"])
    }

    func testBodyMarkerInferenceRequiresConfirmationForAmbiguousRegion() {
        let result = BodyRegionCatalog.inferMarkers(in: "右肩疼", kind: .jointFascia)

        XCTAssertTrue(result.markers.isEmpty)
        XCTAssertEqual(result.unresolvedTerms, ["肩部"])
        XCTAssertTrue(result.requiresConfirmation)
    }

    func testBodyMarkerInferenceSupportsBilateralAndMultipleSpecificRegions() {
        let result = BodyRegionCatalog.inferMarkers(
            in: "双侧肩前侧酸，左膝后侧紧",
            kind: .area
        )

        XCTAssertEqual(Set(result.markers.map(\.regionID)), [
            "front-left-shoulder",
            "front-right-shoulder",
            "back-left-knee"
        ])
        XCTAssertFalse(result.requiresConfirmation)
    }

    func testBackupImportKeepsOneBodyCheckInPerDay() throws {
        let source = try makeContainer()
        let day = Date(timeIntervalSince1970: 1_800_100_000)
        source.mainContext.insert(DailyBodyCheckIn(date: day, conditionScore: 2))
        source.mainContext.insert(DailyBodyCheckIn(date: day.addingTimeInterval(7_200), conditionScore: 4))
        try source.mainContext.save()
        let data = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))

        let destination = try makeContainer()
        let summary = try DataExportService.importBackup(data, into: destination.mainContext)
        let imported = try destination.mainContext.fetch(FetchDescriptor<DailyBodyCheckIn>())

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(summary.imported, 1)
        XCTAssertEqual(summary.skipped, 1)
    }

    func testUnknownWorkoutFeelingDoesNotBlockBackupImport() throws {
        let source = try makeContainer()
        let exercise = Exercise(name: "未知体验测试", muscleGroup: "背部", equipment: "器械")
        let session = WorkoutSession(templateName: "未知体验", plannedDate: .now)
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 8,
            targetWeight: 20,
            restSeconds: 60,
            feeling: .painful
        )
        source.mainContext.insert(exercise)
        source.mainContext.insert(session)
        source.mainContext.insert(snapshot)
        try source.mainContext.save()

        let original = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var snapshots = try XCTUnwrap(object["sessionExercises"] as? [[String: Any]])
        snapshots[0]["feelingRaw"] = "future-feeling"
        object["sessionExercises"] = snapshots
        let modified = try JSONSerialization.data(withJSONObject: object)

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(modified, into: destination.mainContext)
        let imported = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first
        )
        XCTAssertNil(imported.feeling)
        XCTAssertEqual(imported.exerciseName, "未知体验测试")
    }

    func testJSONImportKeepsExistingNutritionTargetSingleton() throws {
        let source = try makeContainer()
        source.mainContext.insert(NutritionTarget(
            calories: 2_600,
            proteinGrams: 180,
            carbsGrams: 300,
            fatGrams: 75
        ))
        try source.mainContext.save()
        let data = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))

        let destination = try makeContainer()
        let currentTarget = NutritionTarget(
            calories: 2_100,
            proteinGrams: 150,
            carbsGrams: 220,
            fatGrams: 65
        )
        destination.mainContext.insert(currentTarget)
        try destination.mainContext.save()

        let summary = try DataExportService.importBackup(data, into: destination.mainContext)
        let targets = try destination.mainContext.fetch(FetchDescriptor<NutritionTarget>())

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.id, currentTarget.id)
        XCTAssertEqual(targets.first?.calories, 2_100)
        XCTAssertEqual(summary.imported, 0)
        XCTAssertEqual(summary.skipped, 1)
    }

    func testShareDraftInboxOnlyClearsMatchingDraft() throws {
        let suiteName = "xfit-share-inbox-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let draft = ExerciseShareDraft(
            sharedText: "单臂绳索下拉\n保持肩胛下沉",
            sourceURL: URL(string: "https://example.com/pulldown")
        )
        defaults.set(
            try JSONEncoder().encode(draft),
            forKey: ExerciseShareDraftStorage.pendingDraftKey
        )
        let inbox = ExerciseShareDraftInbox(defaults: defaults)

        XCTAssertEqual(inbox.pendingDraft(), draft)
        XCTAssertEqual(inbox.pendingDraft()?.suggestedExerciseName, "单臂绳索下拉")
        inbox.clearPendingDraft(matching: UUID())
        XCTAssertNotNil(inbox.pendingDraft())
        inbox.clearPendingDraft(matching: draft.id)
        XCTAssertNil(inbox.pendingDraft())
    }

    func testDiscardRestoresScheduleWithoutCompletedHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let template = WorkoutTemplate(name: "测试", weekday: Date.now.weekdayNumber)
        let schedule = ScheduledWorkout(
            templateID: template.id,
            templateName: template.name,
            plannedDate: .now,
            status: .inProgress
        )
        let session = WorkoutSession(
            scheduledWorkoutID: schedule.id,
            templateID: template.id,
            templateName: template.name,
            plannedDate: .now
        )
        context.insert(template)
        context.insert(schedule)
        context.insert(session)

        try WorkoutService.discard(session: session, schedules: [schedule], in: context)

        XCTAssertEqual(session.status, .discarded)
        XCTAssertEqual(schedule.status, .planned)
        XCTAssertNotNil(session.completedAt)
    }

    func testFreestyleRestRecordsBoundaryWhenNextSetStarts() {
        let base = Date(timeIntervalSince1970: 1_800_100_000)
        let session = WorkoutSession(
            templateName: "自由训练",
            plannedDate: base,
            restMode: .freestyle
        )
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let second = makeSet(sessionID: session.id, setNumber: 2)
        let logs = [first, second]

        WorkoutRestTracking.startSet(first, session: session, logs: logs, at: base)
        first.isCompleted = true
        first.completedAt = base.addingTimeInterval(40)
        WorkoutRestTracking.begin(
            after: first,
            session: session,
            logs: logs,
            plannedRestSeconds: 120,
            at: base.addingTimeInterval(40)
        )

        XCTAssertNil(session.restEndDate)
        XCTAssertEqual(WorkoutRestTracking.activeLog(in: logs)?.id, first.id)

        let recorded = WorkoutRestTracking.startSet(
            second,
            session: session,
            logs: logs,
            at: base.addingTimeInterval(125)
        )

        XCTAssertEqual(recorded, 85)
        XCTAssertEqual(first.restDurationSeconds, 85)
        XCTAssertEqual(first.restEndedAt, base.addingTimeInterval(125))
        XCTAssertEqual(second.startedAt, base.addingTimeInterval(125))
        XCTAssertNil(WorkoutRestTracking.activeLog(in: logs))
    }

    func testCountdownRestRecordsAdjustedActualDuration() {
        let base = Date(timeIntervalSince1970: 1_800_200_000)
        let session = WorkoutSession(
            templateName: "固定倒计时",
            plannedDate: base,
            restMode: .countdown
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)

        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: 120,
            at: base
        )
        XCTAssertEqual(session.restEndDate, base.addingTimeInterval(120))

        let recorded = WorkoutRestTracking.finish(
            session: session,
            logs: [log],
            at: base.addingTimeInterval(75)
        )

        XCTAssertEqual(recorded, 75)
        XCTAssertEqual(log.restDurationSeconds, 75)
        XCTAssertNil(session.restEndDate)
    }

    func testStartingAnotherRestDoesNotInventDurationForMissedTap() {
        let base = Date(timeIntervalSince1970: 1_800_300_000)
        let session = WorkoutSession(
            templateName: "漏点保护",
            plannedDate: base,
            restMode: .freestyle
        )
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let second = makeSet(sessionID: session.id, setNumber: 2)
        let logs = [first, second]

        WorkoutRestTracking.begin(
            after: first,
            session: session,
            logs: logs,
            plannedRestSeconds: 90,
            at: base
        )
        WorkoutRestTracking.begin(
            after: second,
            session: session,
            logs: logs,
            plannedRestSeconds: 90,
            at: base.addingTimeInterval(180)
        )

        XCTAssertNil(first.restDurationSeconds)
        XCTAssertNil(first.restStartedAt)
        XCTAssertEqual(WorkoutRestTracking.activeLog(in: logs)?.id, second.id)
    }

    func testFreestyleRestFinishIsIdempotent() {
        let base = Date(timeIntervalSince1970: 1_800_350_000)
        let session = WorkoutSession(
            templateName: "幂等结束",
            plannedDate: base,
            restMode: .freestyle
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)

        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: 90,
            at: base
        )
        let firstResult = WorkoutRestTracking.finish(
            session: session,
            logs: [log],
            at: base.addingTimeInterval(42)
        )
        let secondResult = WorkoutRestTracking.finish(
            session: session,
            logs: [log],
            at: base.addingTimeInterval(90)
        )

        XCTAssertEqual(firstResult, 42)
        XCTAssertNil(secondResult)
        XCTAssertEqual(log.restDurationSeconds, 42)
        XCTAssertEqual(log.restEndedAt, base.addingTimeInterval(42))
        XCTAssertNil(session.restEndDate)
    }

    func testAbandonFreestyleRestClearsProvisionalTiming() {
        let base = Date(timeIntervalSince1970: 1_800_360_000)
        let session = WorkoutSession(
            templateName: "稍后补录",
            plannedDate: base,
            restMode: .freestyle
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)

        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: 90,
            at: base
        )
        WorkoutRestTracking.abandon(session: session, logs: [log])

        XCTAssertNil(log.restStartedAt)
        XCTAssertNil(log.restEndedAt)
        XCTAssertNil(log.restDurationSeconds)
        XCTAssertNil(WorkoutRestTracking.activeLog(in: [log]))
        XCTAssertNil(session.restEndDate)
    }

    func testStartingSetWithoutActiveRestDoesNotInventDuration() {
        let base = Date(timeIntervalSince1970: 1_800_370_000)
        let session = WorkoutSession(
            templateName: "无休息直接开组",
            plannedDate: base,
            restMode: .freestyle
        )
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let second = makeSet(sessionID: session.id, setNumber: 2)
        first.startedAt = base.addingTimeInterval(-20)

        let recorded = WorkoutRestTracking.startSet(
            second,
            session: session,
            logs: [first, second],
            at: base
        )

        XCTAssertNil(recorded)
        XCTAssertNil(first.startedAt)
        XCTAssertEqual(second.startedAt, base)
        XCTAssertNil(first.restDurationSeconds)
        XCTAssertNil(second.restDurationSeconds)
    }

    func testCountdownNegativePlannedRestClampsToImmediateBoundary() {
        let base = Date(timeIntervalSince1970: 1_800_380_000)
        let session = WorkoutSession(
            templateName: "非法倒计时保护",
            plannedDate: base,
            restMode: .countdown
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)

        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: -30,
            at: base
        )

        XCTAssertEqual(session.restEndDate, base)
        XCTAssertEqual(log.restStartedAt, base)
        XCTAssertNil(log.restDurationSeconds)
    }

    func testHistoricalBackfillPersistsBoundaryRestValues() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(name: "补录测试动作", muscleGroup: "背部", equipment: "器械")
        context.insert(exercise)

        let input = HistoricalWorkoutInput(
            name: "补录休息测试",
            startedAt: Date(timeIntervalSince1970: 1_800_390_000),
            durationMinutes: 30,
            notes: "",
            exercises: [
                HistoricalExerciseInput(
                    exerciseID: exercise.id,
                    sets: [
                        HistoricalSetInput(weight: 30, reps: 10, rir: 2, restDurationSeconds: 0),
                        HistoricalSetInput(
                            weight: 30,
                            reps: 9,
                            rir: 1,
                            restDurationSeconds: RestDurationInput.maximumSeconds
                        ),
                        HistoricalSetInput(weight: 30, reps: 8, rir: 0, restDurationSeconds: nil)
                    ],
                    performanceNotes: ""
                )
            ]
        )

        let session = try HistoricalWorkoutService.record(input, in: context)
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionID == session.id }
            .sorted { $0.setNumber < $1.setNumber }

        XCTAssertEqual(logs.map(\.restDurationSeconds), [0, RestDurationInput.maximumSeconds, nil])
        XCTAssertTrue(logs.allSatisfy(\.isCompleted))
    }

    func testHistoricalBackfillRejectsOutOfRangeRestValues() throws {
        for invalidValue in [-1, RestDurationInput.maximumSeconds + 1] {
            let container = try makeContainer()
            let context = container.mainContext
            let exercise = Exercise(name: "非法补录 \(invalidValue)", muscleGroup: "背部", equipment: "器械")
            context.insert(exercise)
            let input = HistoricalWorkoutInput(
                name: "非法休息",
                startedAt: Date(timeIntervalSince1970: 1_800_395_000),
                durationMinutes: 30,
                notes: "",
                exercises: [
                    HistoricalExerciseInput(
                        exerciseID: exercise.id,
                        sets: [
                            HistoricalSetInput(
                                weight: 30,
                                reps: 10,
                                rir: 2,
                                restDurationSeconds: invalidValue
                            )
                        ],
                        performanceNotes: ""
                    )
                ]
            )

            XCTAssertThrowsError(try HistoricalWorkoutService.record(input, in: context)) { error in
                guard case HistoricalWorkoutServiceError.invalidRestDuration = error else {
                    return XCTFail("应拒绝超范围休息，实际错误：\(error)")
                }
            }
            XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutSession>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<SetLog>()).isEmpty)
        }
    }

    func testHistoricalCSVRejectsNegativeRestDuration() throws {
        let container = try makeContainer()
        let csv = """
        session_id,date,workout,exercise,set,weight_kg,reps,rest_seconds
        negative-rest,2026-08-20T10:00:00Z,自由训练,深蹲,1,60,8,-1
        """

        XCTAssertThrowsError(
            try HistoricalWorkoutCSVService.preview(Data(csv.utf8), in: container.mainContext)
        ) { error in
            guard case let HistoricalWorkoutCSVError.invalidValue(line, field) = error else {
                return XCTFail("应拒绝负数组间休息，实际错误：\(error)")
            }
            XCTAssertEqual(line, 2)
            XCTAssertEqual(field, "rest_seconds")
        }
    }

    func testRestDurationInputRejectsSilentCharacterRewritingAndOverflow() {
        XCTAssertEqual(RestDurationInput.validate(""), .empty)
        XCTAssertEqual(RestDurationInput.validate(" 95 "), .valid(95))
        XCTAssertEqual(RestDurationInput.validate("0"), .valid(0))
        XCTAssertEqual(
            RestDurationInput.validate(String(RestDurationInput.maximumSeconds)),
            .valid(RestDurationInput.maximumSeconds)
        )

        for invalid in ["-30", "1a2", "１２", "1.5", "86 400", "999999999999999999999999"] {
            guard case .invalid = RestDurationInput.validate(invalid) else {
                return XCTFail("应严格拒绝而不是改写输入：\(invalid)")
            }
        }
        guard case .invalid = RestDurationInput.validate(
            String(RestDurationInput.maximumSeconds + 1)
        ) else {
            return XCTFail("应拒绝超过 24 小时的组间休息")
        }
    }

    func testReconcileMultipleActiveRestsKeepsOnlyNewestAndAbandonClearsAll() {
        let base = Date(timeIntervalSince1970: 1_800_397_000)
        let session = WorkoutSession(
            templateName: "脏状态收敛",
            plannedDate: base,
            restEndDate: base.addingTimeInterval(90),
            restMode: .freestyle
        )
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let second = makeSet(sessionID: session.id, setNumber: 2)
        let newest = makeSet(sessionID: session.id, setNumber: 3)
        first.restStartedAt = base
        second.restStartedAt = base.addingTimeInterval(10)
        newest.restStartedAt = base.addingTimeInterval(20)
        let logs = [first, second, newest]

        XCTAssertTrue(WorkoutRestTracking.reconcile(session: session, logs: logs))
        XCTAssertNil(first.restStartedAt)
        XCTAssertNil(second.restStartedAt)
        XCTAssertEqual(newest.restStartedAt, base.addingTimeInterval(20))
        XCTAssertEqual(WorkoutRestTracking.activeLogs(in: logs).map(\.id), [newest.id])
        XCTAssertNil(session.restEndDate)

        first.restStartedAt = base.addingTimeInterval(30)
        WorkoutRestTracking.abandon(session: session, logs: logs)
        XCTAssertTrue(WorkoutRestTracking.activeLogs(in: logs).isEmpty)
        XCTAssertTrue(logs.allSatisfy { $0.restDurationSeconds == nil })
    }

    func testClockRollbackProducesConsistentZeroLengthInterval() {
        let base = Date(timeIntervalSince1970: 1_800_398_000)
        let session = WorkoutSession(
            templateName: "时间回拨",
            plannedDate: base,
            restMode: .freestyle
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)
        WorkoutRestTracking.begin(
            after: log,
            session: session,
            logs: [log],
            plannedRestSeconds: 90,
            at: base
        )

        let duration = WorkoutRestTracking.finish(
            session: session,
            logs: [log],
            at: base.addingTimeInterval(-300)
        )

        XCTAssertEqual(duration, 0)
        XCTAssertEqual(log.restStartedAt, base)
        XCTAssertEqual(log.restEndedAt, base)
        XCTAssertEqual(log.restDurationSeconds, 0)
    }

    func testLastSetCompletionDoesNotStartOrphanRest() {
        let session = WorkoutSession(templateName: "最后一组", plannedDate: .now)
        let first = makeSet(sessionID: session.id, setNumber: 1)
        let last = makeSet(sessionID: session.id, setNumber: 2)
        first.isCompleted = true
        last.isCompleted = true

        XCTAssertFalse(WorkoutRestTracking.shouldBeginRest(after: last, logs: [first, last]))
        first.isCompleted = false
        XCTAssertTrue(WorkoutRestTracking.shouldBeginRest(after: last, logs: [first, last]))
    }

    func testUndoCompletedSetClearsItsRecordedAndProvisionalRest() {
        let base = Date(timeIntervalSince1970: 1_800_398_500)
        let session = WorkoutSession(
            templateName: "撤销完成组",
            plannedDate: base,
            restMode: .freestyle
        )
        let log = makeSet(sessionID: session.id, setNumber: 1)
        log.isCompleted = true
        log.restStartedAt = base
        log.restEndedAt = base.addingTimeInterval(30)
        log.restDurationSeconds = 30
        log.isCompleted = false
        log.completedAt = nil
        WorkoutRestTracking.clearRest(on: log)

        XCTAssertFalse(log.isCompleted)
        XCTAssertNil(log.completedAt)
        XCTAssertNil(log.restStartedAt)
        XCTAssertNil(log.restEndedAt)
        XCTAssertNil(log.restDurationSeconds)
        XCTAssertTrue(WorkoutRestTracking.activeLogs(in: [log]).isEmpty)
    }

    func testRestStateMachineIsStableAcrossOneHundredBoundaryCycles() {
        let base = Date(timeIntervalSince1970: 1_800_399_000)
        for index in 0..<100 {
            let session = WorkoutSession(
                templateName: "稳定性 \(index)",
                plannedDate: base,
                restMode: index.isMultiple(of: 2) ? .freestyle : .countdown
            )
            let first = makeSet(sessionID: session.id, setNumber: 1)
            let second = makeSet(sessionID: session.id, setNumber: 2)
            let startedAt = base.addingTimeInterval(TimeInterval(index * 10))
            WorkoutRestTracking.begin(
                after: first,
                session: session,
                logs: [first, second],
                plannedRestSeconds: index - 50,
                at: startedAt
            )
            let endedAt = index.isMultiple(of: 7)
                ? startedAt.addingTimeInterval(-1)
                : startedAt.addingTimeInterval(TimeInterval(index))
            let recorded = WorkoutRestTracking.startSet(
                second,
                session: session,
                logs: [first, second],
                at: endedAt
            )
            XCTAssertEqual(recorded, index.isMultiple(of: 7) ? 0 : index)
            XCTAssertEqual(first.restEndedAt, max(startedAt, endedAt))
            XCTAssertEqual(first.restDurationSeconds, recorded)
            XCTAssertEqual(second.startedAt, endedAt)
            XCTAssertTrue(WorkoutRestTracking.activeLogs(in: [first, second]).isEmpty)
        }
    }

    func testPersistentStoreRecoversActiveRestAfterContainerRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "XFit-Rest-Persistence-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "test.store")
        let sessionID = UUID()
        let logID = UUID()
        let base = Date(timeIntervalSince1970: 1_800_399_500)

        var firstContainer: ModelContainer? = try makePersistentContainer(at: storeURL)
        do {
            let context = try XCTUnwrap(firstContainer).mainContext
            let session = WorkoutSession(
                id: sessionID,
                templateName: "强杀恢复",
                plannedDate: base,
                startedAt: base,
                restMode: .freestyle
            )
            let log = SetLog(
                id: logID,
                sessionID: session.id,
                sessionExerciseID: UUID(),
                exerciseID: UUID(),
                setNumber: 1,
                targetWeight: 50,
                targetReps: 10,
                actualWeight: 50,
                actualReps: 10,
                isCompleted: true,
                completedAt: base
            )
            context.insert(session)
            context.insert(log)
            WorkoutRestTracking.begin(
                after: log,
                session: session,
                logs: [log],
                plannedRestSeconds: 90,
                at: base
            )
            try context.save()
        }
        firstContainer = nil

        let reopened = try makePersistentContainer(at: storeURL)
        let context = reopened.mainContext
        let session = try XCTUnwrap(
            context.fetch(FetchDescriptor<WorkoutSession>()).first { $0.id == sessionID }
        )
        let log = try XCTUnwrap(
            context.fetch(FetchDescriptor<SetLog>()).first { $0.id == logID }
        )
        XCTAssertEqual(log.restStartedAt, base)
        XCTAssertNil(log.restEndedAt)
        XCTAssertEqual(
            WorkoutRestTracking.finish(
                session: session,
                logs: [log],
                at: base.addingTimeInterval(45)
            ),
            45
        )
        try context.save()
        XCTAssertEqual(log.restDurationSeconds, 45)
    }

    func testRestNotificationReplacementAndCancellationAreExactlyOnce() async {
        let center = RecordingRestNotificationCenter()
        let sessionID = UUID()
        let identifier = NotificationService.restRequestIdentifier(sessionID: sessionID)

        for offset in [120.0, 150.0, 180.0] {
            let request = NotificationService.makeRestEndRequest(
                sessionID: sessionID,
                at: Date.now.addingTimeInterval(offset)
            )
            try? await NotificationService.replaceRestEndRequest(
                request,
                identifier: identifier,
                using: center
            )
        }
        let scheduled = await center.summary(for: identifier)
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.title, "休息结束")
        XCTAssertEqual(scheduled.repeats, false)

        await NotificationService.cancelRestEndRequest(identifier: identifier, using: center)
        let cancelled = await center.summary(for: identifier)
        XCTAssertEqual(cancelled.count, 0)
    }

    func testCSVExportIncludesAuthoritativeRestAndFreestyleMode() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_800_399_800)
        let exercise = Exercise(name: "导出动作", muscleGroup: "背部", equipment: "器械")
        let session = WorkoutSession(
            templateName: "导出自由训练",
            plannedDate: base,
            startedAt: base,
            completedAt: base.addingTimeInterval(600),
            status: .completed,
            restMode: .freestyle
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 30,
            restSeconds: 90,
            muscleGroup: exercise.muscleGroup
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 30,
            targetReps: 10,
            actualWeight: 30,
            actualReps: 10,
            isCompleted: true,
            completedAt: base,
            restDurationSeconds: 95
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        let csvURL = try DataExportService.createCSV(in: context)
        let rows = try String(contentsOf: csvURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let header = try XCTUnwrap(rows.first?.split(separator: ",").map(String.init))
        let values = try XCTUnwrap(rows.last?.split(separator: ",", omittingEmptySubsequences: false).map(String.init))
        let restIndex = try XCTUnwrap(header.firstIndex(of: "rest_seconds"))
        let modeIndex = try XCTUnwrap(header.firstIndex(of: "rest_mode"))
        XCTAssertEqual(values[restIndex], "95")
        XCTAssertEqual(values[modeIndex], WorkoutRestMode.freestyle.rawValue)
    }

    func testBackupRoundTripPreservesRestModeAndSetTiming() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let base = Date(timeIntervalSince1970: 1_800_400_000)
        let exercise = Exercise(name: "自由卧推", muscleGroup: "胸部", equipment: "杠铃")
        let session = WorkoutSession(
            templateName: "自由训练",
            plannedDate: base,
            startedAt: base,
            completedAt: base.addingTimeInterval(3_600),
            status: .completed,
            restMode: .freestyle
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 1,
            minReps: 8,
            maxReps: 12,
            targetWeight: 60,
            restSeconds: 120,
            muscleGroup: exercise.muscleGroup
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 60,
            targetReps: 10,
            actualWeight: 60,
            actualReps: 10,
            isCompleted: true,
            startedAt: base.addingTimeInterval(300),
            completedAt: base.addingTimeInterval(340),
            restStartedAt: base.addingTimeInterval(340),
            restEndedAt: base.addingTimeInterval(430),
            restDurationSeconds: 90
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        let data = try Data(contentsOf: DataExportService.createBackup(in: context))
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)

        let restoredSession = try destination.mainContext.fetch(FetchDescriptor<WorkoutSession>()).first
        let restoredLog = try destination.mainContext.fetch(FetchDescriptor<SetLog>()).first
        XCTAssertEqual(restoredSession?.restMode, .freestyle)
        XCTAssertEqual(restoredLog?.startedAt, log.startedAt)
        XCTAssertEqual(restoredLog?.restStartedAt, log.restStartedAt)
        XCTAssertEqual(restoredLog?.restEndedAt, log.restEndedAt)
        XCTAssertEqual(restoredLog?.restDurationSeconds, 90)
    }

    func testBackupRoundTripPreservesExerciseReferenceURLs() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let exercise = Exercise(
            name: "参考动作",
            muscleGroup: "核心",
            equipment: "自重",
            isBuiltIn: false,
            referenceURL: "https://example.com/exercise"
        )
        let session = WorkoutSession(
            templateName: "参考训练",
            plannedDate: .now,
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
            targetWeight: 0,
            restSeconds: 60,
            muscleGroup: exercise.muscleGroup,
            referenceURL: exercise.referenceURL
        )
        context.insert(exercise)
        context.insert(session)
        context.insert(snapshot)
        try context.save()

        let data = try Data(contentsOf: DataExportService.createBackup(in: context))
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)

        XCTAssertEqual(
            try destination.mainContext.fetch(FetchDescriptor<Exercise>()).first?.referenceURL,
            exercise.referenceURL
        )
        XCTAssertEqual(
            try destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first?.referenceURL,
            exercise.referenceURL
        )
    }

    func testDeviceHistoryMergePreservesAllSetStatesAndIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_800_000_000.123456)
        let phoneExercise = Exercise(name: "杠铃卧推", muscleGroup: "胸部", equipment: "杠铃")
        let phoneTemplate = WorkoutTemplate(name: "推 · 胸肩三头", weekday: date.weekdayNumber)
        let phoneSchedule = ScheduledWorkout(
            templateID: phoneTemplate.id,
            templateName: phoneTemplate.name,
            plannedDate: date
        )
        context.insert(phoneExercise)
        context.insert(phoneTemplate)
        context.insert(phoneSchedule)
        try context.save()

        let sessionID = UUID()
        let snapshotID = UUID()
        let package = DeviceHistoryMergePackage(
            schemaVersion: 1,
            source: "test-simulator",
            sessions: [
                DeviceHistoryMergeSession(
                    id: sessionID,
                    templateName: phoneTemplate.name,
                    plannedDate: date,
                    startedAt: date.addingTimeInterval(1_800),
                    completedAt: date.addingTimeInterval(2_100),
                    startedAtTimeIntervalSince1970: date.addingTimeInterval(1_800).timeIntervalSince1970,
                    completedAtTimeIntervalSince1970: date.addingTimeInterval(2_100).timeIntervalSince1970,
                    statusRaw: WorkoutSessionStatus.completed.rawValue,
                    notes: "保留原备注",
                    restEndDate: nil,
                    importIdentifier: "",
                    exercises: [
                        DeviceHistoryMergeExercise(
                            id: snapshotID,
                            sourceExerciseID: UUID(),
                            exerciseName: phoneExercise.name,
                            order: 0,
                            targetSets: 2,
                            minReps: 8,
                            maxReps: 12,
                            targetWeight: 20,
                            restSeconds: 120,
                            muscleGroup: phoneExercise.muscleGroup,
                            equipment: phoneExercise.equipment,
                            exerciseNotes: "肩胛稳定",
                            referenceURL: "https://example.com/bench-press",
                            performanceNotes: "第一组完成",
                            sets: [
                                DeviceHistoryMergeSet(
                                    id: UUID(),
                                    setNumber: 1,
                                    targetWeight: 20,
                                    targetReps: 10,
                                    actualWeight: 20,
                                    actualReps: 10,
                                    rir: 2,
                                    isWarmup: false,
                                    isCompleted: true,
                                    completedAt: date.addingTimeInterval(1_900),
                                    completedAtTimeIntervalSince1970: date.addingTimeInterval(1_900).timeIntervalSince1970
                                ),
                                DeviceHistoryMergeSet(
                                    id: UUID(),
                                    setNumber: 2,
                                    targetWeight: 20,
                                    targetReps: 10,
                                    actualWeight: 20,
                                    actualReps: 10,
                                    rir: nil,
                                    isWarmup: false,
                                    isCompleted: false,
                                    completedAt: nil
                                )
                            ]
                        )
                    ]
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(package)

        let first = try DeviceHistoryMergeService.importPackage(data, into: context)
        let second = try DeviceHistoryMergeService.importPackage(data, into: context)
        let importedSession = try context.fetch(FetchDescriptor<WorkoutSession>()).first
        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
        let logs = try context.fetch(FetchDescriptor<SetLog>())

        XCTAssertEqual(first.importedSessions, 1)
        XCTAssertEqual(first.importedSessionExercises, 1)
        XCTAssertEqual(first.importedSetLogs, 2)
        XCTAssertEqual(first.importedCompletedSetLogs, 1)
        XCTAssertEqual(first.updatedSchedules, 1)
        XCTAssertEqual(second.importedSessions, 0)
        XCTAssertEqual(second.skippedSessions, 1)
        XCTAssertEqual(importedSession?.id, sessionID)
        XCTAssertEqual(importedSession?.templateID, phoneTemplate.id)
        XCTAssertEqual(importedSession?.scheduledWorkoutID, phoneSchedule.id)
        XCTAssertNotNil(importedSession)
        XCTAssertEqual(
            importedSession!.startedAt.timeIntervalSince1970,
            date.addingTimeInterval(1_800).timeIntervalSince1970,
            accuracy: 0.000_001
        )
        XCTAssertEqual(snapshots.first?.id, snapshotID)
        XCTAssertEqual(snapshots.first?.exerciseID, phoneExercise.id)
        XCTAssertEqual(snapshots.first?.referenceURL, "https://example.com/bench-press")
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.filter(\.isCompleted).count, 1)
        XCTAssertEqual(phoneSchedule.status, .completed)
    }

    func testCloudRestorePreparationDoesNotSeedAnEmptyStore() throws {
        let container = try makeContainer()
        let context = container.mainContext

        try SeedDataService.prepareIfNeeded(in: context, allowInitialSeed: false)

        XCTAssertTrue(try context.fetch(FetchDescriptor<Exercise>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WorkoutTemplate>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<NutritionTarget>()).isEmpty)
    }

    func testSetPlanPresetsFollowExpectedWeightAndRepDirections() {
        let fixed = WorkoutSetPlan.preset(.fixed, count: 3, baseWeight: 40, baseReps: 10)
        XCTAssertEqual(fixed.map(\.weight), [40, 40, 40])
        XCTAssertEqual(fixed.map(\.reps), [10, 10, 10])

        let ascending = WorkoutSetPlan.preset(.pyramidUp, count: 3, baseWeight: 40, baseReps: 10)
        XCTAssertEqual(ascending.map(\.weight), [40, 42.5, 45])
        XCTAssertEqual(ascending.map(\.reps), [10, 8, 6])

        let descending = WorkoutSetPlan.preset(.pyramidDown, count: 3, baseWeight: 40, baseReps: 10)
        XCTAssertEqual(descending.map(\.weight), [45, 42.5, 40])
        XCTAssertEqual(descending.map(\.reps), [6, 8, 10])
    }

    func testWorkoutStartCopiesPerSetPlanAndSideModesIntoLogs() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let exercise = Exercise(
            name: "哑铃推举",
            muscleGroup: "肩部",
            equipment: "哑铃",
            volumeUnit: .meter
        )
        let template = WorkoutTemplate(name: "肩部", weekday: Date.now.weekdayNumber)
        let plans = [
            WorkoutSetPlan(weight: 10, reps: 12, weightSide: .single, repsSide: .bilateral),
            WorkoutSetPlan(weight: 12.5, reps: 10, weightSide: .single, repsSide: .bilateral),
            WorkoutSetPlan(weight: 15, reps: 8, weightSide: .single, repsSide: .bilateral)
        ]
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: plans.count,
            minReps: 8,
            maxReps: 12,
            targetWeight: 10,
            restSeconds: 90,
            plannedSets: plans,
            planPattern: .pyramidUp
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
        let snapshot = try XCTUnwrap(
            context.fetch(FetchDescriptor<SessionExercise>()).first { $0.sessionID == sessionID }
        )
        let logs = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionID == sessionID }
            .sorted { $0.setNumber < $1.setNumber }

        XCTAssertEqual(snapshot.planPattern, .pyramidUp)
        XCTAssertEqual(snapshot.plannedSets, plans)
        XCTAssertEqual(snapshot.volumeUnit, .meter)
        XCTAssertEqual(logs.map(\.targetWeight), [10, 12.5, 15])
        XCTAssertEqual(logs.map(\.targetReps), [12, 10, 8])
        XCTAssertTrue(logs.allSatisfy { $0.targetWeightSide == .single })
        XCTAssertTrue(logs.allSatisfy { $0.actualWeightSide == .single })

        exercise.volumeUnit = .count
        try context.save()
        XCTAssertEqual(snapshot.volumeUnit, .meter)
    }

    func testConfirmedStrictSquatDuplicateConsolidatesWithoutRenamingHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let squat = Exercise(name: "深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let strictSquat = Exercise(name: "严格深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let template = WorkoutTemplate(name: "腿", weekday: Date.now.weekdayNumber)
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: strictSquat.id,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 50,
            restSeconds: 120
        )
        let snapshot = SessionExercise(
            sessionID: UUID(),
            exerciseID: strictSquat.id,
            exerciseName: "严格深蹲",
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 8,
            targetWeight: 50,
            restSeconds: 120
        )
        context.insert(squat)
        context.insert(strictSquat)
        context.insert(template)
        context.insert(item)
        context.insert(snapshot)
        try context.save()

        try ExerciseCatalogService.consolidateConfirmedSquatDuplicate(in: context)

        XCTAssertEqual(item.exerciseID, squat.id)
        XCTAssertEqual(snapshot.exerciseID, squat.id)
        XCTAssertEqual(snapshot.exerciseName, "严格深蹲")
        XCTAssertTrue(strictSquat.isArchived)
        XCTAssertEqual(
            ExerciseCatalogService.exactNameMatch(named: "严格深蹲", in: [squat, strictSquat])?.id,
            squat.id
        )
    }

    func testSetPlanPresetClampsUnsafeInputsAndPreservesSideModes() {
        let minimum = WorkoutSetPlan.preset(
            .pyramidUp,
            count: -4,
            baseWeight: -20,
            baseReps: -3,
            weightSide: .single,
            repsSide: .single
        )
        XCTAssertEqual(minimum.count, 1)
        XCTAssertEqual(minimum.first?.weight, 0)
        XCTAssertEqual(minimum.first?.reps, 1)
        XCTAssertEqual(minimum.first?.weightSide, .single)
        XCTAssertEqual(minimum.first?.repsSide, .single)

        let maximum = WorkoutSetPlan.preset(
            .pyramidUp,
            count: 99,
            baseWeight: 10,
            baseReps: 5
        )
        XCTAssertEqual(maximum.count, 12)
        XCTAssertTrue(zip(maximum, maximum.dropFirst()).allSatisfy { pair in
            pair.0.weight <= pair.1.weight
        })
        XCTAssertTrue(zip(maximum, maximum.dropFirst()).allSatisfy { pair in
            pair.0.reps >= pair.1.reps
        })
        XCTAssertTrue(maximum.allSatisfy { $0.weight >= 0 && $0.reps >= 1 })
    }

    func testMalformedPlanAndSideStorageFallsBackWithoutCrashing() {
        let templateItem = TemplateExercise(
            templateID: UUID(),
            exerciseID: UUID(),
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 12,
            targetWeight: 40,
            restSeconds: 90
        )
        templateItem.plannedSetsJSON = "{not-json"
        templateItem.planPatternRaw = "unknown-pattern"
        XCTAssertEqual(templateItem.planPattern, .fixed)
        XCTAssertEqual(templateItem.plannedSets.map(\.weight), [40, 40, 40])
        XCTAssertEqual(templateItem.plannedSets.map(\.reps), [8, 8, 8])

        templateItem.plannedSets = []
        XCTAssertEqual(templateItem.targetSets, 1)
        XCTAssertEqual(templateItem.plannedSets.count, 1)

        let log = SetLog(
            sessionID: UUID(),
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: 1,
            targetWeight: 20,
            targetReps: 10,
            actualWeight: 20,
            actualReps: 10,
            targetWeightSide: .single,
            targetRepsSide: .single
        )
        log.targetWeightSideRaw = "invalid"
        log.targetRepsSideRaw = nil
        log.actualWeightSideRaw = nil
        log.actualRepsSideRaw = "invalid"
        XCTAssertEqual(log.targetWeightSide, .bilateral)
        XCTAssertEqual(log.targetRepsSide, .bilateral)
        XCTAssertEqual(log.actualWeightSide, .bilateral)
        XCTAssertEqual(log.actualRepsSide, .bilateral)
    }

    func testDynamicSetAdjustmentCopiesLastValuesAllowsPlanDeltaAndProtectsCompletedSet() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let session = WorkoutSession(templateName: "鲁棒性训练", plannedDate: .now, status: .inProgress)
        let exercise = Exercise(name: "单臂划船", muscleGroup: "背部", equipment: "哑铃")
        let plans = WorkoutSetPlan.preset(
            .pyramidUp,
            count: 3,
            baseWeight: 20,
            baseReps: 12,
            weightSide: .single,
            repsSide: .single
        )
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 3,
            minReps: 8,
            maxReps: 12,
            targetWeight: 20,
            restSeconds: 90,
            plannedSets: plans,
            planPattern: .pyramidUp
        )
        context.insert(session)
        context.insert(exercise)
        context.insert(snapshot)
        for (index, plan) in plans.enumerated() {
            context.insert(SetLog(
                sessionID: session.id,
                sessionExerciseID: snapshot.id,
                exerciseID: exercise.id,
                setNumber: index + 1,
                targetWeight: plan.weight,
                targetReps: plan.reps,
                actualWeight: plan.weight + 1,
                actualReps: plan.reps + 1,
                targetWeightSide: plan.weightSide,
                targetRepsSide: plan.repsSide,
                actualWeightSide: .bilateral,
                actualRepsSide: .bilateral
            ))
        }
        try context.save()

        let extra = try WorkoutService.addSet(to: snapshot, in: context)
        XCTAssertEqual(extra.setNumber, 4)
        XCTAssertEqual(extra.targetWeight, 25)
        XCTAssertEqual(extra.targetReps, 8)
        XCTAssertEqual(extra.actualWeight, 26)
        XCTAssertEqual(extra.actualReps, 9)
        XCTAssertEqual(extra.targetWeightSide, .single)
        XCTAssertEqual(extra.actualWeightSide, .bilateral)
        XCTAssertEqual(snapshot.targetSets, 4)
        XCTAssertEqual(snapshot.plannedSets.count, 3, "加练组不能改写原计划快照")

        try WorkoutService.removeLastIncompleteSet(from: snapshot, in: context)
        try WorkoutService.removeLastIncompleteSet(from: snapshot, in: context)
        XCTAssertEqual(snapshot.targetSets, 2)
        XCTAssertEqual(snapshot.plannedSets.count, 3, "少做一组应保留计划差异")

        let remaining = try context.fetch(FetchDescriptor<SetLog>())
            .filter { $0.sessionExerciseID == snapshot.id }
            .sorted { $0.setNumber < $1.setNumber }
        XCTAssertEqual(remaining.map(\.setNumber), [1, 2])
        remaining[1].isCompleted = true
        try context.save()
        XCTAssertThrowsError(try WorkoutService.removeLastIncompleteSet(from: snapshot, in: context)) { error in
            XCTAssertEqual(error as? WorkoutServiceError, .noIncompleteSet)
        }

        session.status = .completed
        try context.save()
        XCTAssertThrowsError(try WorkoutService.addSet(to: snapshot, in: context)) { error in
            XCTAssertEqual(error as? WorkoutServiceError, .sessionNotInProgress)
        }
    }

    func testBackupRoundTripPreservesPerSetPlansPatternsAndIndependentSideModes() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let exercise = Exercise(name: "保加利亚分腿蹲", muscleGroup: "腿部", equipment: "哑铃")
        let template = WorkoutTemplate(name: "逐组计划", weekday: Date.now.weekdayNumber)
        let plans = [
            WorkoutSetPlan(weight: 12, reps: 12, weightSide: .single, repsSide: .single),
            WorkoutSetPlan(weight: 14, reps: 10, weightSide: .single, repsSide: .bilateral)
        ]
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: 2,
            minReps: 10,
            maxReps: 12,
            targetWeight: 12,
            restSeconds: 90,
            plannedSets: plans,
            planPattern: .pyramidUp
        )
        let session = WorkoutSession(templateName: template.name, plannedDate: .now, status: .completed)
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 2,
            minReps: 10,
            maxReps: 12,
            targetWeight: 12,
            restSeconds: 90,
            plannedSets: plans,
            planPattern: .pyramidUp
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 12,
            targetReps: 12,
            actualWeight: 13,
            actualReps: 11,
            isCompleted: true,
            targetWeightSide: .single,
            targetRepsSide: .single,
            actualWeightSide: .bilateral,
            actualRepsSide: .bilateral
        )
        context.insert(exercise)
        context.insert(template)
        context.insert(item)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        let data = try Data(contentsOf: DataExportService.createBackup(in: context))
        let destination = try makeContainer()
        _ = try DataExportService.importBackup(data, into: destination.mainContext)

        let importedItem = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<TemplateExercise>()).first)
        let importedSnapshot = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first)
        let importedLog = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SetLog>()).first)
        XCTAssertEqual(importedItem.planPattern, .pyramidUp)
        XCTAssertEqual(importedItem.plannedSets, plans)
        XCTAssertEqual(importedSnapshot.planPattern, .pyramidUp)
        XCTAssertEqual(importedSnapshot.plannedSets, plans)
        XCTAssertEqual(importedLog.targetWeightSide, .single)
        XCTAssertEqual(importedLog.targetRepsSide, .single)
        XCTAssertEqual(importedLog.actualWeightSide, .bilateral)
        XCTAssertEqual(importedLog.actualRepsSide, .bilateral)
    }

    func testLegacyBackupWithoutPerSetFieldsUsesFixedBilateralFallbacks() throws {
        let source = try makeContainer()
        let context = source.mainContext
        let exercise = Exercise(name: "旧版卧推", muscleGroup: "胸部", equipment: "杠铃")
        let template = WorkoutTemplate(name: "旧版计划", weekday: Date.now.weekdayNumber)
        let item = TemplateExercise(
            templateID: template.id,
            exerciseID: exercise.id,
            order: 0,
            targetSets: 2,
            minReps: 8,
            maxReps: 10,
            targetWeight: 40,
            restSeconds: 90
        )
        let session = WorkoutSession(templateName: template.name, plannedDate: .now)
        let snapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: exercise.id,
            exerciseName: exercise.name,
            order: 0,
            targetSets: 2,
            minReps: 8,
            maxReps: 10,
            targetWeight: 40,
            restSeconds: 90
        )
        let log = SetLog(
            sessionID: session.id,
            sessionExerciseID: snapshot.id,
            exerciseID: exercise.id,
            setNumber: 1,
            targetWeight: 40,
            targetReps: 8,
            actualWeight: 42.5,
            actualReps: 7
        )
        context.insert(exercise)
        context.insert(template)
        context.insert(item)
        context.insert(session)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        let currentData = try Data(contentsOf: DataExportService.createBackup(in: context))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        var legacy = object
        legacy["schemaVersion"] = 7
        legacy["templateExercises"] = (object["templateExercises"] as? [[String: Any]] ?? []).map { record in
            record.filter { !["plannedSetsJSON", "planPatternRaw"].contains($0.key) }
        }
        legacy["sessionExercises"] = (object["sessionExercises"] as? [[String: Any]] ?? []).map { record in
            record.filter { !["plannedSetsJSON", "planPatternRaw"].contains($0.key) }
        }
        legacy["setLogs"] = (object["setLogs"] as? [[String: Any]] ?? []).map { record in
            record.filter {
                !["targetWeightSideRaw", "targetRepsSideRaw", "actualWeightSideRaw", "actualRepsSideRaw"]
                    .contains($0.key)
            }
        }
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)

        let destination = try makeContainer()
        _ = try DataExportService.importBackup(legacyData, into: destination.mainContext)
        let importedItem = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<TemplateExercise>()).first)
        let importedSnapshot = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SessionExercise>()).first)
        let importedLog = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<SetLog>()).first)
        XCTAssertEqual(importedItem.planPattern, .fixed)
        XCTAssertEqual(importedItem.plannedSets.map(\.weight), [40, 40])
        XCTAssertEqual(importedSnapshot.planPattern, .fixed)
        XCTAssertEqual(importedSnapshot.plannedSets.map(\.reps), [8, 8])
        XCTAssertEqual(importedLog.targetWeightSide, .bilateral)
        XCTAssertEqual(importedLog.targetRepsSide, .bilateral)
        XCTAssertEqual(importedLog.actualWeightSide, .bilateral)
        XCTAssertEqual(importedLog.actualRepsSide, .bilateral)
    }

    func testStrictSquatConsolidationIsIdempotentRemovesPlanCollisionAndRemapsLogs() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let squat = Exercise(name: "深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let strict = Exercise(name: "严格深蹲", muscleGroup: "腿部", equipment: "杠铃")
        let template = WorkoutTemplate(name: "腿", weekday: Date.now.weekdayNumber)
        let primaryItem = TemplateExercise(
            templateID: template.id, exerciseID: squat.id, order: 0,
            targetSets: 3, minReps: 6, maxReps: 8, targetWeight: 60, restSeconds: 120
        )
        let duplicateItem = TemplateExercise(
            templateID: template.id, exerciseID: strict.id, order: 1,
            targetSets: 3, minReps: 6, maxReps: 8, targetWeight: 60, restSeconds: 120
        )
        let snapshot = SessionExercise(
            sessionID: UUID(), exerciseID: strict.id, exerciseName: "严格深蹲", order: 0,
            targetSets: 1, minReps: 6, maxReps: 6, targetWeight: 60, restSeconds: 120
        )
        let log = SetLog(
            sessionID: snapshot.sessionID, sessionExerciseID: snapshot.id, exerciseID: strict.id,
            setNumber: 1, targetWeight: 60, targetReps: 6, actualWeight: 62.5, actualReps: 5
        )
        context.insert(squat)
        context.insert(strict)
        context.insert(template)
        context.insert(primaryItem)
        context.insert(duplicateItem)
        context.insert(snapshot)
        context.insert(log)
        try context.save()

        try ExerciseCatalogService.consolidateConfirmedSquatDuplicate(in: context)
        try ExerciseCatalogService.consolidateConfirmedSquatDuplicate(in: context)
        try context.save()

        let templateItems = try context.fetch(FetchDescriptor<TemplateExercise>())
            .filter { $0.templateID == template.id }
        XCTAssertEqual(templateItems.count, 1)
        XCTAssertEqual(templateItems.first?.exerciseID, squat.id)
        XCTAssertEqual(snapshot.exerciseID, squat.id)
        XCTAssertEqual(snapshot.exerciseName, "严格深蹲")
        XCTAssertEqual(log.exerciseID, squat.id)
        XCTAssertTrue(strict.isArchived)
        XCTAssertEqual(ExerciseCatalogService.search([squat], query: "严格深蹲").map(\.id), [squat.id])
    }

    func testRunningWorkoutMenuSyncUsesBuilderOrderAndPreservesCompletedFacts() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let fly = Exercise(name: "绳索反向飞鸟", muscleGroup: "肩部", equipment: "龙门架")
        let decline = Exercise(name: "MTS 下斜卧推", muscleGroup: "胸部", equipment: "固定器械")
        let session = WorkoutSession(
            templateName: "肩部 + 胸部 · 当天菜单",
            plannedDate: .now,
            status: .inProgress
        )
        let flySnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: fly.id,
            exerciseName: fly.name,
            order: 0,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 5,
            restSeconds: 90
        )
        let declineSnapshot = SessionExercise(
            sessionID: session.id,
            exerciseID: decline.id,
            exerciseName: decline.name,
            order: 1,
            targetSets: 1,
            minReps: 10,
            maxReps: 10,
            targetWeight: 25,
            restSeconds: 90
        )
        let completedFlySet = SetLog(
            sessionID: session.id,
            sessionExerciseID: flySnapshot.id,
            exerciseID: fly.id,
            setNumber: 1,
            targetWeight: 5,
            targetReps: 10,
            actualWeight: 8.875,
            actualReps: 12,
            rir: 3,
            isCompleted: true,
            completedAt: .now
        )
        let pendingDeclineSet = SetLog(
            sessionID: session.id,
            sessionExerciseID: declineSnapshot.id,
            exerciseID: decline.id,
            setNumber: 1,
            targetWeight: 25,
            targetReps: 10,
            actualWeight: 25,
            actualReps: 10
        )
        [fly, decline].forEach(context.insert)
        context.insert(session)
        [flySnapshot, declineSnapshot].forEach(context.insert)
        [completedFlySet, pendingDeclineSet].forEach(context.insert)
        try context.save()

        try WorkoutService.syncMenu(
            [
                DailyPlanExerciseInput(
                    exerciseID: decline.id,
                    plannedSets: [WorkoutSetPlan(weight: 30.125, reps: 8)],
                    planPattern: .fixed,
                    restSeconds: 120
                ),
                DailyPlanExerciseInput(
                    exerciseID: fly.id,
                    plannedSets: [WorkoutSetPlan(weight: 5, reps: 10)],
                    planPattern: .fixed,
                    restSeconds: 90
                )
            ],
            to: session,
            in: context
        )

        let snapshots = try context.fetch(FetchDescriptor<SessionExercise>())
            .filter { $0.sessionID == session.id }
            .sorted { $0.order < $1.order }
        XCTAssertEqual(snapshots.map(\.exerciseID), [decline.id, fly.id])
        XCTAssertEqual(declineSnapshot.restSeconds, 120)
        XCTAssertEqual(pendingDeclineSet.targetWeight, 30.125, accuracy: 0.0001)
        XCTAssertEqual(pendingDeclineSet.actualWeight, 30.125, accuracy: 0.0001)
        XCTAssertEqual(completedFlySet.actualWeight, 8.875, accuracy: 0.0001)
        XCTAssertTrue(completedFlySet.isCompleted)
    }

    func testWeightFormatterShowsUpToThreeDecimalsWithoutPadding() {
        XCTAssertEqual(TrainingFormatters.weight(5), "5")
        XCTAssertTrue(TrainingFormatters.weight(8.875).contains("875"))
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
            "RestPersistenceTests",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeSet(sessionID: UUID, setNumber: Int) -> SetLog {
        SetLog(
            sessionID: sessionID,
            sessionExerciseID: UUID(),
            exerciseID: UUID(),
            setNumber: setNumber,
            targetWeight: 50,
            targetReps: 10,
            actualWeight: 50,
            actualReps: 10
        )
    }
}
