import SwiftData
import XCTest
@testable import FitnessApp

@MainActor
final class ScheduleAndDataTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: NotificationService.workoutEnabledKey)
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
            isBuiltIn: false
        ))
        sourceContext.insert(MealEntry(
            mealType: .lunch,
            name: "鸡胸饭",
            calories: 520,
            proteinGrams: 42,
            carbsGrams: 58,
            fatGrams: 12
        ))
        try sourceContext.save()

        let backupURL = try DataExportService.createBackup(in: sourceContext)
        let data = try Data(contentsOf: backupURL)
        let preview = try DataExportService.preview(data)
        XCTAssertEqual(preview.exercises, 1)
        XCTAssertEqual(preview.meals, 1)

        let destination = try makeContainer()
        let summary = try DataExportService.importBackup(data, into: destination.mainContext)
        XCTAssertEqual(summary.imported, 2)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<Exercise>()).count, 1)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<MealEntry>()).count, 1)
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
            BodyMeasurement.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
