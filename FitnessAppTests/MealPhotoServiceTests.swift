import XCTest
import SwiftData
import UIKit
@testable import FitnessApp

@MainActor
final class MealPhotoServiceTests: XCTestCase {
    func testAssessmentISOExchangeRemainsIdempotentAfterStructuredFirstApply() throws {
        let container = try makeContainer()
        let meal = textMeal("含小数秒的评估")
        meal.date = meal.date.addingTimeInterval(0.654321)
        container.mainContext.insert(meal)
        try container.mainContext.save()
        let review = MealReviewService()
        let package = try review.exportWeek(meals: [meal], startLocalDay: "2026-09-21", endLocalDay: "2026-09-27")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let packageWire = try decoder.decode(MealWeekPackage.self, from: encoder.encode(package))
        let fingerprint = try XCTUnwrap(packageWire.meals.first?.sourceFingerprint)
        let assessment = MealAssessment(mealID: meal.id, sourceFingerprint: fingerprint,
            reviewedAt: Date(timeIntervalSince1970: 1_789_954_321.789123), calories: .init(lower: 450, upper: 650), summary: "保留估算区间")
        let batch = MealReviewBatch(assessments: [assessment])
        _ = try review.apply(batch, confirmed: true, context: container.mainContext)
        let wire = try decoder.decode(MealReviewBatch.self, from: encoder.encode(batch))
        let repeated = try review.apply(wire, confirmed: true, context: container.mainContext)
        XCTAssertEqual(repeated.appliedCount, 0)
        XCTAssertEqual(repeated.duplicateCount, 1)
        XCTAssertEqual(meal.mealAssessments.count, 1)
        XCTAssertEqual(meal.latestApplicableAssessment?.calories?.upper, 650)
        XCTAssertFalse(meal.isCalorieKnown)
        XCTAssertEqual(meal.displayCalorieRange?.lower, 450)
    }

    func testPersistentStoreReopenRetainsPhotosCivilDateAndAssessmentHistory() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let schema = Schema([MealEntry.self])
        let storeURL = root.appendingPathComponent("meals.store")
        let photosURL = root.appendingPathComponent("MealPhotos", isDirectory: true)
        let bytes = jpeg()
        let mealID: UUID
        do {
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)])
            let photos = MealPhotoService(rootURL: photosURL)
            let meal = try photos.createMeal(photoData: [bytes], date: Date(timeIntervalSince1970: 1_789_943_400.875),
                timeZone: try XCTUnwrap(TimeZone(identifier: "Australia/Sydney")), mealType: .dinner,
                note: "晚餐分食", context: container.mainContext)
            meal.recordedLocalDay = "2026-09-21"
            mealID = meal.id
            let review = MealReviewService(photoService: photos)
            let fingerprint = try MealSourceFingerprint.value(for: meal)
            let earlier = MealAssessment(mealID: meal.id, sourceFingerprint: fingerprint,
                reviewedAt: Date(timeIntervalSince1970: 1_900_000_000), calories: .init(lower: 300, upper: 500), summary: "初次评估")
            let correction = MealAssessment(mealID: meal.id, sourceFingerprint: fingerprint,
                reviewedAt: Date(timeIntervalSince1970: 1_800_000_000), calories: .init(lower: 450, upper: 650), summary: "后来确认份量")
            _ = try review.apply(.init(assessments: [earlier]), confirmed: true, context: container.mainContext)
            _ = try review.apply(.init(assessments: [correction]), confirmed: true, context: container.mainContext)
        }
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)])
        let meals = try reopened.mainContext.fetch(FetchDescriptor<MealEntry>())
        let restored = try XCTUnwrap(meals.first(where: { $0.id == mealID }))
        XCTAssertEqual(restored.stableLocalDay, "2026-09-21")
        XCTAssertEqual(restored.captureTimeZoneIdentifier, "Australia/Sydney")
        XCTAssertEqual(try MealPhotoService(rootURL: photosURL).data(for: XCTUnwrap(restored.mealPhotos.first)), bytes)
        XCTAssertEqual(restored.mealAssessments.count, 2)
        XCTAssertEqual(restored.latestApplicableAssessment?.summary, "后来确认份量")
        XCTAssertEqual(restored.displayCalorieRange?.lower, 450)
        XCTAssertFalse(restored.isCalorieKnown)
    }

    func testConfirmedWeekAssessmentPreservesOwnerNutritionAndRejectsChangedSource() throws {
        let schema = Schema([MealEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let meal = MealEntry(date: FatLossCalendar.date(2026, 9, 21), mealType: .lunch, name: "半份饭", calories: 400, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        meal.nutritionKnown = false
        meal.knownNutritionFieldsRaw = "calories"
        meal.estimationMethod = "本人估算"
        container.mainContext.insert(meal)
        try container.mainContext.save()
        let review = MealReviewService()
        let package = try review.exportWeek(meals: [meal], startLocalDay: "2026-09-21", endLocalDay: "2026-09-27")
        let source = try XCTUnwrap(package.meals.first)
        let assessment = MealAssessment(mealID: meal.id, sourceFingerprint: source.sourceFingerprint,
            dishes: [.init(name: "米饭", portionDescription: "半碗，照片估算")],
            calories: .init(lower: 350, upper: 500), summary: "油量未知", limitations: ["不能判断烹调用油"])
        let batch = MealReviewBatch(assessments: [assessment])
        XCTAssertThrowsError(try review.apply(batch, confirmed: false, context: container.mainContext))
        XCTAssertEqual(try review.apply(batch, confirmed: true, context: container.mainContext).appliedCount, 1)
        XCTAssertEqual(meal.calories, 400)
        XCTAssertFalse(meal.isProteinKnown)
        XCTAssertNotNil(meal.latestApplicableAssessment)
        XCTAssertEqual(try review.apply(batch, confirmed: true, context: container.mainContext).duplicateCount, 1)
        meal.name = "全部吃完"
        XCTAssertNil(meal.latestApplicableAssessment)
        XCTAssertThrowsError(try review.apply(batch, confirmed: true, context: container.mainContext))
        XCTAssertEqual(meal.mealAssessments.count, 1)
    }

    func testPhotoOnlyMealPersistsMultiplePhotosWithoutInventingNutrition() throws {
        let schema = Schema([MealEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = MealPhotoService(rootURL: root)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let photo = renderer.jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-23T23:30:00Z"))
        let meal = try service.createMeal(photoData: [photo, photo], date: date, timeZone: try XCTUnwrap(TimeZone(identifier: "Australia/Sydney")), mealType: .breakfast, note: "吃了一半", context: container.mainContext)
        XCTAssertFalse(meal.isNutritionKnown)
        XCTAssertFalse(meal.isCalorieKnown)
        XCTAssertEqual(meal.recordedLocalDay, "2026-09-24")
        XCTAssertEqual(meal.mealPhotos.count, 2)
        let reopenedService = MealPhotoService(rootURL: root)
        XCTAssertEqual(try reopenedService.data(for: meal.mealPhotos[0]), photo)
        XCTAssertEqual(meal.name, "吃了一半")
    }

    func testInvalidAppendLeavesOriginalPhotosAndAssessmentUnchanged() throws {
        let container = try makeContainer()
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = MealPhotoService(rootURL: root)
        let meal = try photos.createMeal(photoData: [jpeg()], date: FatLossCalendar.date(2026, 9, 21),
            timeZone: MealLocalDay.legacyTimeZone, mealType: .lunch, note: "共两人分食", context: container.mainContext)
        let review = MealReviewService(photoService: photos)
        let source = try XCTUnwrap(review.exportWeek(meals: [meal], startLocalDay: "2026-09-21", endLocalDay: "2026-09-27").meals.first)
        let batch = MealReviewBatch(assessments: [.init(mealID: meal.id, sourceFingerprint: source.sourceFingerprint,
            calories: .init(lower: 300, upper: 450), summary: "按半份估算")])
        _ = try review.apply(batch, confirmed: true, context: container.mainContext)
        XCTAssertThrowsError(try photos.appendPhotos([jpeg(), Data()], to: meal, context: container.mainContext))
        XCTAssertEqual(meal.mealPhotos.count, 1)
        XCTAssertNotNil(meal.latestApplicableAssessment)
        XCTAssertEqual(try photos.data(for: meal.mealPhotos[0]), jpeg())
        try photos.appendPhotos([jpeg()], to: meal, context: container.mainContext)
        XCTAssertEqual(meal.mealPhotos.count, 2)
        XCTAssertNil(meal.latestApplicableAssessment)
        XCTAssertEqual(meal.mealAssessments.count, 1)
        XCTAssertThrowsError(try review.apply(batch, confirmed: true, context: container.mainContext))
    }

    func testWeekExportUsesCivilDatesAndExcludesOutsideWeekAndVoidedMeals() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-20T23:30:00Z"))
        let meal = MealEntry(date: date, mealType: .breakfast, name: "早餐", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        meal.nutritionKnown = false
        meal.recordedLocalDay = "2026-09-21"
        meal.captureTimeZoneIdentifier = "Australia/Sydney"
        let outside = MealEntry(date: FatLossCalendar.date(2026, 9, 28), mealType: .lunch, name: "不应导出", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        let voided = MealEntry(date: date, mealType: .snack, name: "已作废", calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        voided.isVoided = true
        let review = MealReviewService()
        let package = try review.exportWeek(meals: [outside, voided, meal], startLocalDay: "2026-09-21", endLocalDay: "2026-09-27")
        XCTAssertEqual(package.meals.map(\.mealID), [meal.id])
        XCTAssertEqual(package.meals.first?.localDay, "2026-09-21")
        XCTAssertNil(package.meals.first?.ownerNutrition.calories)
        XCTAssertThrowsError(try review.exportWeek(meals: [meal], startLocalDay: "2026-09-21", endLocalDay: "2026-09-28"))
        XCTAssertEqual(outside.stableLocalDay, "2026-09-28")
        XCTAssertNil(MealLocalDay.date("2026-02-30"))
    }

    func testInvalidAssessmentInBatchPreventsAnyHistoryInsertion() throws {
        let container = try makeContainer()
        let first = textMeal("第一餐")
        let second = textMeal("第二餐")
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()
        let review = MealReviewService()
        let batch = MealReviewBatch(assessments: [
            .init(mealID: first.id, sourceFingerprint: try MealSourceFingerprint.value(for: first), calories: .init(lower: 100, upper: 200), summary: "估算"),
            .init(mealID: second.id, sourceFingerprint: try MealSourceFingerprint.value(for: second), calories: .init(lower: 500, upper: 100), summary: "无效范围")
        ])
        XCTAssertThrowsError(try review.apply(batch, confirmed: true, context: container.mainContext))
        XCTAssertTrue(first.mealAssessments.isEmpty)
        XCTAssertTrue(second.mealAssessments.isEmpty)
    }

    func testPhotoRestoreRejectsPathTraversalAndCorruptionBeforeWritingAnyFile() throws {
        let container = try makeContainer()
        let root = temporaryRoot()
        let restoredRoot = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: restoredRoot)
        }
        let original = MealPhotoService(rootURL: root)
        let meal = try original.createMeal(photoData: [jpeg(), jpeg()], date: .now, mealType: .dinner, note: "", context: container.mainContext)
        let assets = try original.exportAssets(for: [meal])
        let badPath = MealPhotoAttachment(id: UUID(), relativePath: "../escape.jpg", sha256: assets[1].attachment.sha256,
            byteCount: assets[1].data.count, capturedAt: assets[1].attachment.capturedAt,
            localDay: assets[1].attachment.localDay, timeZoneIdentifier: assets[1].attachment.timeZoneIdentifier)
        let target = MealPhotoService(rootURL: restoredRoot)
        XCTAssertThrowsError(try target.restoreAssets([assets[0], .init(attachment: badPath, data: assets[1].data)]))
        XCTAssertThrowsError(try target.data(for: assets[0].attachment))
        XCTAssertThrowsError(try target.restoreAssets([assets[0], .init(attachment: assets[1].attachment, data: Data("corrupt".utf8))]))
        XCTAssertThrowsError(try target.data(for: assets[0].attachment))
        XCTAssertEqual(try target.restoreAssets(assets).count, 2)
        XCTAssertEqual(try target.restoreAssets(assets).count, 0)
        XCTAssertEqual(try target.data(for: assets[0].attachment), assets[0].data)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MealEntry.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)])
    }

    private func textMeal(_ name: String) -> MealEntry {
        let meal = MealEntry(date: FatLossCalendar.date(2026, 9, 21), mealType: .lunch, name: name, calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0)
        meal.nutritionKnown = false
        return meal
    }

    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}
