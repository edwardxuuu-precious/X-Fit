import XCTest
@testable import FitnessApp

@MainActor
final class PrepPresentationTests: XCTestCase {
    private let day = FatLossCalendar.date(2026, 9, 7)

    private func recipe(_ name: String = "测试菜", ingredients: [RecipeIngredient], portions: Double = 2) throws -> RecipeVersion {
        try RecipeVersion(draft: RecipeDraft(key: UUID().uuidString, title: name, ingredients: ingredients,
                                            steps: ["分成两份后及时冷藏"], equipment: ["蒸锅"], householdPortion: "两份",
                                            portions: portions, cookingMinutes: 15, storageNote: "及时冷藏并充分复热"))
    }

    func testKnownAmountsAreScaledPerMealBeforeCombining() throws {
        let id = UUID()
        let lunch = PlannedMeal(programID: id, date: day, mealType: .lunch,
                                recipe: try recipe(ingredients: [.init(name: "冬瓜", amountText: "整批200g", referenceGrams: 200)]))
        let dinner = PlannedMeal(programID: id, date: day, mealType: .dinner,
                                 recipe: try recipe(ingredients: [.init(name: "冬瓜", amountText: "整批300g", referenceGrams: 300)]))
        let item = try XCTUnwrap(FatLossService.shoppingList(meals: [lunch, dinner]).first)
        XCTAssertEqual(item.referenceGrams, 250)
        XCTAssertEqual(item.portions, 2)
        XCTAssertEqual(PrepPresentation.amountSummary(item), "约 250 g 合计 · 用于 2 餐")
    }

    func testMixedUnknownAmountNeverAppearsAsCompleteTotal() throws {
        let id = UUID()
        let lunch = PlannedMeal(programID: id, date: day, mealType: .lunch,
                                recipe: try recipe(ingredients: [.init(name: "冬瓜", amountText: "整批200g", referenceGrams: 200)]))
        let dinner = PlannedMeal(programID: id, date: day, mealType: .dinner,
                                 recipe: try recipe(ingredients: [.init(name: "冬瓜", amountText: "中碗1碗")]))
        let item = try XCTUnwrap(FatLossService.shoppingList(meals: [lunch, dinner]).first)
        XCTAssertNil(item.referenceGrams)
        XCTAssertFalse(PrepPresentation.amountSummary(item).contains("合计"))
        XCTAssertTrue(PrepPresentation.amountSummary(item).contains("待折算"))
        XCTAssertEqual(item.amounts.count, 2)
    }

    func testMedicalPendingOverridesAvailableReferenceWeight() {
        let item = ShoppingItem(name: "鸡肉", portions: 2, amounts: ["旧配方参考"], isMedicalPortionPending: true, referenceGrams: 200)
        XCTAssertEqual(PrepPresentation.group(for: item), .pending)
        XCTAssertEqual(PrepPresentation.amountSummary(item), "待确认用量 · 用于 2 餐")
        XCTAssertFalse(PrepPresentation.amountSummary(item).contains("200"))
    }

    func testWaterAndPantryAreSeparatedWithoutAssumingInventory() {
        func item(_ name: String) -> ShoppingItem {
            ShoppingItem(name: name, portions: 1, amounts: [], isMedicalPortionPending: false)
        }
        XCTAssertEqual(PrepPresentation.group(for: item("温水")), .water)
        XCTAssertEqual(PrepPresentation.group(for: item("清水")), .water)
        XCTAssertEqual(PrepPresentation.group(for: item("生抽")), .pantry)
        XCTAssertEqual(PrepPresentation.group(for: item("冬瓜")), .purchase)
        XCTAssertTrue(PrepPresentation.Group.pantry.rawValue.contains("核对库存"))
    }

    func testSelectedMealsExcludeOtherDatesProgramsBreakfastSnacksAndInactivePlans() throws {
        let program = FatLossProgram(startDate: day, endDate: FatLossCalendar.adding(91, to: day))
        let draft = try recipe(ingredients: [])
        let lunch = PlannedMeal(programID: program.id, date: day, mealType: .lunch, recipe: draft)
        let dinner = PlannedMeal(programID: program.id, date: day, mealType: .dinner, recipe: draft)
        let breakfast = PlannedMeal(programID: program.id, date: day, mealType: .breakfast, recipe: draft)
        let snack = PlannedMeal(programID: program.id, date: day, mealType: .snack, recipe: draft)
        let otherDate = PlannedMeal(programID: program.id, date: FatLossCalendar.adding(1, to: day), mealType: .lunch, recipe: draft)
        let otherProgram = PlannedMeal(programID: UUID(), date: day, mealType: .lunch, recipe: draft)
        let replaced = PlannedMeal(programID: program.id, date: day, mealType: .lunch, recipe: draft)
        replaced.isCurrent = false
        let skipped = PlannedMeal(programID: program.id, date: day, mealType: .dinner, recipe: draft)
        skipped.statusRaw = "skipped"
        let selected = PrepPresentation.selectedMeals([snack, dinner, otherDate, breakfast, replaced, otherProgram, lunch, skipped], programID: program.id, date: day)
        XCTAssertEqual(selected.map(\.id), [lunch.id, dinner.id])
    }

    func testShareStartsWithOnePortionPackingThenGroupedShoppingAndKeepsPendingVisible() throws {
        let program = FatLossProgram(startDate: day, endDate: FatLossCalendar.adding(91, to: day))
        let lunch = PlannedMeal(programID: program.id, date: day, mealType: .lunch,
                                recipe: try recipe("午餐测试菜", ingredients: [
                                    .init(name: "鸡肉", amountText: "旧配方", referenceGrams: 200, isMedicalPortionPending: true),
                                    .init(name: "冬瓜", amountText: "整批300g", referenceGrams: 300),
                                    .init(name: "温水", amountText: "按蛋量调整"),
                                    .init(name: "生抽", amountText: "整批5mL")
                                ]))
        let breakfast = PlannedMeal(programID: program.id, date: day, mealType: .breakfast,
                                    recipe: try recipe("早餐不进备餐单", ingredients: []))
        let text = FatLossService.prepText(program: program, date: day, meals: [breakfast, lunch])
        XCTAssertTrue(text.contains("共 1 餐。早餐自理"))
        XCTAssertTrue(text.contains("准备 1 份 · 装入午餐餐盒"))
        XCTAssertTrue(text.contains("只取一半"))
        XCTAssertFalse(text.contains("早餐不进备餐单"))
        XCTAssertTrue(text.contains("鸡肉：待确认用量"))
        XCTAssertFalse(text.contains("200 g"))
        XCTAssertTrue(text.contains("冬瓜：约 150 g 合计"))
        XCTAssertTrue(text.contains("请先核对库存"))
        let packingIndex = try XCTUnwrap(text.range(of: "装入午餐餐盒")?.lowerBound)
        let shoppingIndex = try XCTUnwrap(text.range(of: "需要购买")?.lowerBound)
        let stepsIndex = try XCTUnwrap(text.range(of: "制作 / 保存与复热")?.lowerBound)
        XCTAssertLessThan(packingIndex, shoppingIndex)
        XCTAssertLessThan(shoppingIndex, stepsIndex)
        let purchaseSection = try XCTUnwrap(text.components(separatedBy: "需要购买").last?.components(separatedBy: "家中常备").first)
        XCTAssertFalse(purchaseSection.contains("温水"))
        XCTAssertFalse(purchaseSection.contains("生抽"))
    }
}
