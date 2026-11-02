import XCTest
@testable import FitnessApp

final class FatLossCatalogTests: XCTestCase {
    func testTravelWeekPreservesApprovedSetsAndRecoveryDaysWithoutFailurePrescriptions() throws {
        var preference = TrainingPreferenceSnapshot.weekdayFocused
        preference.revisionCode = "TP-20260921-04"
        let plan = FatLossCatalog.trainingProgram(preference: preference)
        XCTAssertEqual(plan.code, "CUT-UPPER-TRAVEL-20260921-R1")
        XCTAssertEqual(plan.strengthWorkouts.map(\.weekday), [2, 3, 4, 7])
        XCTAssertEqual(plan.strengthWorkouts.map { $0.exercises.reduce(0) { $0 + $1.sets } }, [15, 16, 12, 16])
        XCTAssertEqual(plan.cardioWorkouts.map(\.weekday), [5, 6])
        XCTAssertTrue(plan.strengthWorkouts.flatMap(\.exercises).allSatisfy { $0.note.contains("RIR 2–3") })
        XCTAssertTrue(plan.lowEnergyRule.contains("疼痛"))
        XCTAssertTrue(plan.isValid)
    }

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
        let preference = TrainingPreferenceSnapshot.confirmed
        XCTAssertNil(FatLossCatalog.workout(on: FatLossCalendar.date(2026, 9, 7), preference: preference))
        XCTAssertEqual(FatLossCatalog.workout(on: FatLossCalendar.date(2026, 9, 8), preference: preference)?.code, "CHEST_TRI")
        XCTAssertEqual(FatLossCatalog.workout(on: FatLossCalendar.date(2026, 9, 10), preference: preference)?.code, "BACK_BI")
        XCTAssertEqual(FatLossCatalog.workout(on: FatLossCalendar.date(2026, 9, 12), preference: preference)?.code, "LEGS_CORE")
        XCTAssertEqual(FatLossCatalog.workout(on: FatLossCalendar.date(2026, 9, 13), preference: preference)?.code, "SHOULDERS_ARMS")
    }

    func testConfirmedSplitKeepsApprovedVolumeAndUnilateralSemantics() throws {
        let plan = FatLossCatalog.trainingProgram(preference: .confirmed)
        let exercises = plan.strengthWorkouts.flatMap(\.exercises)
        XCTAssertEqual(plan.strengthWorkouts.count, 4)
        XCTAssertEqual(exercises.count, 31)
        XCTAssertEqual(exercises.reduce(0) { $0 + $1.sets }, 101)
        XCTAssertEqual(exercises.filter { $0.name == "箱跳" }.reduce(0) { $0 + $1.sets }, 3)
        XCTAssertEqual(exercises.filter { $0.name != "箱跳" }.reduce(0) { $0 + $1.sets }, 98)
        XCTAssertEqual(plan.cardioWorkouts.count, 3)
        XCTAssertEqual(plan.preferenceRevisionCode, TrainingPreferenceSnapshot.confirmed.revisionCode)
        let boxJump = try XCTUnwrap(exercises.first { $0.name == "箱跳" })
        XCTAssertEqual(boxJump.sets, 3)
        XCTAssertEqual(boxJump.volumeUnitRaw, ExerciseVolumeUnit.count.rawValue)
        let antiRotation = try XCTUnwrap(exercises.first { $0.name == "抗旋转推" })
        XCTAssertTrue(antiRotation.unilateral)
        XCTAssertEqual(antiRotation.volumeUnitRaw, ExerciseVolumeUnit.kilogram.rawValue)
        XCTAssertEqual(exercises.first { $0.name == "绳索侧平举" }?.sets, 5)
    }

    func testWeekdayFocusedRevisionUsesConfirmedTransitionWeekAndHighUpperVolume() throws {
        let preference = TrainingPreferenceSnapshot.weekdayFocused
        let plan = FatLossCatalog.trainingProgram(preference: preference)
        XCTAssertEqual(plan.code, "CUT-4D-20260908-R2")
        XCTAssertEqual(plan.preferenceRevisionCode, "TP-20260908-02")
        XCTAssertEqual(plan.strengthWorkouts.map(\.weekday), [3, 4, 6, 1])
        XCTAssertEqual(plan.strengthWorkouts.first { $0.code == "BACK_BI_R2" }?.exercises.reduce(0) { $0 + $1.sets }, 26)
        XCTAssertEqual(plan.strengthWorkouts.first { $0.code == "SHOULDERS_ARMS_R2" }?.exercises.reduce(0) { $0 + $1.sets }, 27)
        XCTAssertEqual(plan.strengthWorkouts.first { $0.code == "LEGS_CORE_R2" }?.exercises.first?.name, "箱跳")
        XCTAssertEqual(plan.cardioWorkouts.filter { $0.weekday <= 6 }.count, 2)
        XCTAssertTrue(plan.cardioWorkouts.contains { $0.code == "ROPE_SAT_OPTIONAL_R2" && $0.guidance.contains("周末默认") })
        XCTAssertTrue(preference.constraints.contains { $0.contains("Notes 重量口径尚未明确") })
        XCTAssertTrue(plan.isValid)
    }

    func testLowerBodySpecialtyWeekHasThreeStrengthDaysTwoRopeDaysAndAnkleWorkEverySession() throws {
        let preference = TrainingPreferenceSnapshot.lowerBodySpecialtyWeek
        let plan = FatLossCatalog.trainingProgram(preference: preference)

        XCTAssertEqual(preference.revisionCode, "TP-20260914-03")
        XCTAssertEqual(preference.strengthDaysPerWeek, 3)
        XCTAssertEqual(preference.jumpRopeSessionsPerWeek, 2)
        XCTAssertEqual(plan.code, "CUT-LB3-20260914-R1")
        XCTAssertEqual(plan.strengthWorkouts.map(\.weekday), [2, 4, 6])
        XCTAssertEqual(plan.cardioWorkouts.map(\.weekday), [3, 7])
        XCTAssertEqual(plan.cardioWorkouts.map(\.code), ["ROPE_TUE_LB3", "ROPE_SAT_LB3"])
        XCTAssertTrue(plan.strengthWorkouts.allSatisfy { workout in
            workout.exercises.contains { $0.name.contains("踝背屈") }
                && workout.exercises.contains { $0.note.contains("刚性") || $0.name.contains("弹跳") || $0.name.contains("等长") }
        })
        XCTAssertTrue(plan.strengthWorkouts[0].title.contains("前链"))
        XCTAssertTrue(plan.strengthWorkouts[1].title.contains("后链"))
        XCTAssertTrue(plan.strengthWorkouts[2].title.contains("整合"))

        let carry = try XCTUnwrap(plan.strengthWorkouts[0].exercises.first { $0.name == "农夫走" })
        XCTAssertEqual(carry.sets, 6)
        XCTAssertEqual(carry.repsLower, 30)
        XCTAssertEqual(carry.repsUpper, 30)
        XCTAssertEqual(carry.volumeUnitRaw, ExerciseVolumeUnit.meter.rawValue)
        XCTAssertTrue(carry.note.contains("每只哑铃"))
        XCTAssertTrue(carry.note.contains("RPE 7–8"))
        XCTAssertEqual(carry.sets * carry.repsLower, 180)

        XCTAssertTrue(plan.cardioWorkouts.allSatisfy { $0.guidance.contains("RPE 6–7") })
        XCTAssertTrue(plan.cardioWorkouts.allSatisfy { $0.guidance.contains("还能继续") })
        XCTAssertTrue(plan.isValid)
    }
}
