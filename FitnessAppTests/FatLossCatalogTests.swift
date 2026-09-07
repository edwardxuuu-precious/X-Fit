import XCTest
@testable import FitnessApp

final class FatLossCatalogTests: XCTestCase {
    func testApprovedFourteenDayCycleRetainsTwoDayMealsAndRestarts() throws {
        for index in 0..<14 {
            let lunch = try XCTUnwrap(FatLossCatalog.recipe(dayIndex: index, mealType: .lunch))
            let dinner = try XCTUnwrap(FatLossCatalog.recipe(dayIndex: index, mealType: .dinner))
            XCTAssertEqual(lunch.key, "lunch-\(index / 2)")
            XCTAssertEqual(dinner.key, "dinner-\(index / 2)")
            XCTAssertEqual(FatLossCatalog.recipe(dayIndex: index, mealType: .breakfast)?.key, "breakfast-\(index % 4)")
            XCTAssertEqual(FatLossCatalog.recipe(dayIndex: index + 14, mealType: .lunch), lunch)
            XCTAssertEqual(FatLossCatalog.recipe(dayIndex: index + 14, mealType: .dinner), dinner)
        }
        XCTAssertEqual(FatLossCatalog.recipe(dayIndex: 0, mealType: .lunch)?.title, "姜葱鸡片＋清炒冬瓜＋米饭")
        XCTAssertEqual(FatLossCatalog.recipe(dayIndex: 13, mealType: .dinner)?.title, "番茄鸡蛋烩饭＋西葫芦")
        XCTAssertNil(FatLossCatalog.recipe(dayIndex: -1, mealType: .lunch))
        XCTAssertNil(FatLossCatalog.recipe(dayIndex: 0, mealType: .snack))
    }

    func testUnknownNutritionAndMedicalPortionsRemainUnknownThroughSnapshot() throws {
        XCTAssertEqual(Set(FatLossCatalog.recipes.map(\.key)).count, 18)
        for recipe in FatLossCatalog.recipes {
            let decoded = try JSONDecoder().decode(RecipeDraft.self, from: JSONEncoder().encode(recipe))
            XCTAssertEqual(decoded, recipe)
            XCTAssertEqual(decoded.portions, 2)
            XCTAssertFalse(decoded.hasCompleteNutrition)
            XCTAssertNil(decoded.calories)
            XCTAssertNil(decoded.proteinGrams)
            XCTAssertNil(decoded.carbsGrams)
            XCTAssertNil(decoded.fatGrams)
            let pending = decoded.ingredients.filter(\.isMedicalPortionPending)
            XCTAssertFalse(pending.isEmpty, "\(decoded.title) must preserve the clinician's portion decision")
            XCTAssertTrue(pending.allSatisfy { $0.referenceGrams == nil && $0.amountText.contains("待医生") })
        }
    }

    func testWorkoutUsesShanghaiDayAcrossUTCDateBoundary() {
        let mondayShanghai = FatLossCalendar.date(2026, 9, 7)
        XCTAssertEqual(FatLossCatalog.workout(on: mondayShanghai)?.code, "A")
        XCTAssertEqual(FatLossCatalog.workout(on: mondayShanghai.addingTimeInterval(23 * 3600))?.code, "A")
        XCTAssertNil(FatLossCatalog.workout(on: mondayShanghai.addingTimeInterval(-1)))
        XCTAssertNil(FatLossCatalog.workout(on: FatLossCalendar.date(2026, 9, 8)))
        XCTAssertEqual(FatLossCatalog.workout(on: FatLossCalendar.date(2026, 9, 9))?.code, "B")
        XCTAssertEqual(FatLossCatalog.workout(on: FatLossCalendar.date(2026, 9, 11))?.code, "C")
    }

    func testUnilateralAndDistanceDraftsCannotBeMistakenForBilateralRepetitions() throws {
        let exercises = FatLossCatalog.workouts.flatMap(\.exercises)
        XCTAssertEqual(exercises.count, 16)
        XCTAssertTrue(exercises.allSatisfy { $0.sets == 2 })
        let deadBug = try XCTUnwrap(exercises.first { $0.name == "死虫" })
        XCTAssertTrue(deadBug.unilateral)
        XCTAssertEqual(deadBug.volumeUnitRaw, ExerciseVolumeUnit.count.rawValue)
        let antiRotation = try XCTUnwrap(exercises.first { $0.name == "抗旋转推" })
        XCTAssertTrue(antiRotation.unilateral)
        XCTAssertEqual(antiRotation.volumeUnitRaw, ExerciseVolumeUnit.kilogram.rawValue)
        let carry = try XCTUnwrap(exercises.first { $0.name == "轻重量农夫走" })
        XCTAssertEqual(carry.volumeUnitRaw, ExerciseVolumeUnit.meter.rawValue)
        XCTAssertEqual(carry.repsLower, 30)
        XCTAssertEqual(carry.repsUpper, 30)
    }
}
