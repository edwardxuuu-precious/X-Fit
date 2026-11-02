import SwiftData
import UIKit
import XCTest
@testable import FitnessApp

@MainActor
final class MealPhotoBackupTests: XCTestCase {
    func testLegacyBackupWithoutPhotoFieldsStillRestoresUnknownNutrition() throws {
        let source = try container()
        let destination = try container()
        let meal = MealEntry(date: .now, mealType: .lunch, name: "旧版文字餐",
            calories: 400, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        meal.nutritionKnown = false
        meal.knownNutritionFieldsRaw = "calories"
        source.mainContext.insert(meal)
        try source.mainContext.save()
        let data = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schemaVersion"] = 14
        json.removeValue(forKey: "mealPhotoAssets")
        _ = try DataExportService.importBackup(JSONSerialization.data(withJSONObject: json), into: destination.mainContext)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertEqual(restored.calories, 400)
        XCTAssertTrue(restored.isCalorieKnown)
        XCTAssertFalse(restored.isProteinKnown)
        XCTAssertTrue(restored.mealPhotos.isEmpty)
    }

    func testMissingPhotoAssetsRejectWholeBackupBeforeInsertingAnyRecord() throws {
        let source = try container()
        let destination = try container()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = MealPhotoService(rootURL: root.appendingPathComponent("source"))
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).jpegData(withCompressionQuality: 0.8) { view in
            UIColor.green.setFill(); view.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        _ = try photos.createMeal(photoData: [bytes], date: .now, mealType: .lunch, note: "不完整备份", context: source.mainContext)
        let data = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext, photoService: photos))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["mealPhotoAssets"] = []
        let corrupt = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try DataExportService.importBackup(corrupt, into: destination.mainContext,
            photoService: MealPhotoService(rootURL: root.appendingPathComponent("destination"))))
        XCTAssertTrue(try destination.mainContext.fetch(FetchDescriptor<MealEntry>()).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("destination").path))
    }

    func testSkippedExistingMealDoesNotRestoreUnreferencedOldPhotos() throws {
        let source = try container()
        let destination = try container()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = MealPhotoService(rootURL: root.appendingPathComponent("source"))
        let restoredPhotos = MealPhotoService(rootURL: root.appendingPathComponent("destination"))
        let bytes = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).jpegData(withCompressionQuality: 0.8) { view in
            UIColor.green.setFill(); view.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let meal = try photos.createMeal(photoData: [bytes], date: .now, mealType: .lunch, note: "旧备份", context: source.mainContext)
        let existing = MealEntry(id: meal.id, date: meal.date, mealType: .lunch, name: "保留现在的记录",
            calories: 500, proteinGrams: 20, carbsGrams: 40, fatGrams: 10)
        destination.mainContext.insert(existing)
        try destination.mainContext.save()
        let data = try Data(contentsOf: DataExportService.createBackup(in: source.mainContext, photoService: photos))
        _ = try DataExportService.importBackup(data, into: destination.mainContext, photoService: restoredPhotos)
        XCTAssertEqual(existing.name, "保留现在的记录")
        XCTAssertTrue(existing.mealPhotos.isEmpty)
        XCTAssertThrowsError(try restoredPhotos.data(for: XCTUnwrap(meal.mealPhotos.first)))
    }

    func testBackupRestoresPhotoBytesAndLocalDateWithoutInventingNutrition() throws {
        let source = try container()
        let destination = try container()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = MealPhotoService(rootURL: root.appendingPathComponent("source"))
        let restoredPhotos = MealPhotoService(rootURL: root.appendingPathComponent("destination"))
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let bytes = renderer.jpegData(withCompressionQuality: 0.8) { view in
            UIColor.green.setFill(); view.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-24T01:30:00Z"))
        let meal = try photos.createMeal(photoData: [bytes], date: date,
            timeZone: try XCTUnwrap(TimeZone(identifier: "Australia/Sydney")), mealType: .lunch,
            note: "分食半份", context: source.mainContext)
        let file = try DataExportService.createBackup(in: source.mainContext, photoService: photos)
        let data = try Data(contentsOf: file)
        _ = try DataExportService.importBackup(data, into: destination.mainContext, photoService: restoredPhotos)
        let restored = try XCTUnwrap(destination.mainContext.fetch(FetchDescriptor<MealEntry>()).first)
        XCTAssertEqual(restored.id, meal.id)
        XCTAssertEqual(restored.stableLocalDay, "2026-09-24")
        XCTAssertEqual(restored.captureTimeZoneIdentifier, "Australia/Sydney")
        XCTAssertFalse(restored.isCalorieKnown)
        XCTAssertEqual(try restoredPhotos.data(for: XCTUnwrap(restored.mealPhotos.first)), bytes)
        let repeated = try DataExportService.importBackup(data, into: destination.mainContext, photoService: restoredPhotos)
        XCTAssertEqual(repeated.imported, 0)
    }

    private func container() throws -> ModelContainer {
        let schema = Schema([
            Exercise.self, WorkoutTemplate.self, TemplateExercise.self, ScheduledWorkout.self,
            WorkoutSession.self, SessionExercise.self, SetLog.self, NutritionTarget.self, MealEntry.self,
            DailyBodyCheckIn.self, BodyMeasurement.self, HydrationEntry.self, JumpRopeEntry.self,
            SedentarySession.self, TrainingPreferenceRevision.self, TrainingProgramRevision.self,
            FatLossProgram.self, ProgramTargetRevision.self, RecipeVersion.self, PlannedMeal.self,
            ProgramDailyLog.self, ProgramHealthRecord.self, ProgramWeeklyReview.self, ProgramWorkoutLink.self
        ])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }
}
