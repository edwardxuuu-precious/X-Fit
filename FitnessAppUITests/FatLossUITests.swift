import XCTest

final class FatLossUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(started: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + (started ? ["--ui-testing-fat-loss-started"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["训练"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.buttons["训练"].isSelected)
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.buttons["减脂完成输入"]
        if done.waitForExistence(timeout: 2) { done.tap() }
    }

    private func openNutritionFields(in app: XCUIApplication) {
        let calories = app.textFields["实吃-热量 kcal"]
        if !calories.exists {
            let disclosure = app.buttons["实吃-展开营养"]
            reveal(disclosure, in: app)
            XCTAssertTrue(disclosure.exists)
            if disclosure.value as? String != "已展开" { disclosure.tap() }
        }
        reveal(calories, in: app)
        XCTAssertTrue(calories.exists)
    }

    private func createProgram(in app: XCUIApplication) {
        app.tabBars.buttons["目标"].tap()
        let create = app.buttons["创建减脂周期"]
        reveal(create, in: app)
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        XCTAssertTrue(app.buttons["目标-记录体重"].waitForExistence(timeout: 5))
    }

    private func openMealCalendar(in app: XCUIApplication) {
        app.tabBars.buttons["饮食"].tap()
        let calendar = app.buttons["饮食-餐单日历"]
        reveal(calendar, in: app)
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        calendar.tap()
    }

    private func importMealsAndReturnHome(in app: XCUIApplication) {
        openMealCalendar(in: app)
        XCTAssertTrue(app.staticTexts["当天尚未导入餐单"].waitForExistence(timeout: 5))
        app.buttons["预览导入餐单"].tap()
        XCTAssertTrue(app.buttons["确认导入餐单"].waitForExistence(timeout: 5))
        app.buttons["确认导入餐单"].tap()
        XCTAssertTrue(app.buttons["计划餐-早餐"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let breakfast = app.buttons["饮食-按计划吃了-早餐"]
        reveal(breakfast, in: app)
        XCTAssertTrue(breakfast.waitForExistence(timeout: 5))
        XCTAssertTrue(breakfast.isHittable)
    }

    func testProgramCreationRequiresExplicitMealImport() {
        let app = launch()
        createProgram(in: app)
        app.tabBars.buttons["饮食"].tap()
        XCTAssertFalse(app.buttons["饮食-按计划吃了-早餐"].exists)
        openMealCalendar(in: app)
        XCTAssertTrue(app.staticTexts["当天尚未导入餐单"].waitForExistence(timeout: 5))
        app.buttons["预览导入餐单"].tap()
        XCTAssertTrue(app.buttons["确认导入餐单"].waitForExistence(timeout: 5))
        app.buttons["确认导入餐单"].tap()
        XCTAssertTrue(app.buttons["14 天餐单预览"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["当天尚未导入餐单"].exists)
    }

    func testMedicalTargetsStayUnconfirmedAfterCreation() {
        let app = launch()
        createProgram(in: app)
        let health = app.buttons["目标与健康档案"]
        reveal(health, in: app)
        health.tap()
        XCTAssertTrue(app.staticTexts["营养目标待确认"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["2400"].exists)
        XCTAssertFalse(app.staticTexts["160 g"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2400")).firstMatch.exists)
        XCTAssertTrue(app.buttons["新增减脂目标版本"].exists)
    }

    func testHomeKeepsFourTabsAndGoalWeightEntry() {
        let app = launch()
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        for title in ["训练", "饮食", "目标", "我的"] { XCTAssertTrue(app.tabBars.buttons[title].exists) }
        createProgram(in: app)
        let weight = app.buttons["目标-记录体重"]
        reveal(weight, in: app)
        XCTAssertTrue(weight.exists)
        weight.tap()
        XCTAssertTrue(app.textFields["快速体重输入"].waitForExistence(timeout: 5))
    }

    func testMealActualFeedbackPartialNutritionPrepAndReviewFlow() {
        let app = launch(started: true)
        createProgram(in: app)
        importMealsAndReturnHome(in: app)
        let quickRecord = app.buttons["饮食-按计划吃了-早餐"]
        quickRecord.tap()
        let breakfast = app.buttons["饮食-调整实吃-早餐"]
        XCTAssertTrue(breakfast.waitForExistence(timeout: 5))
        XCTAssertFalse(quickRecord.exists)
        XCTAssertEqual(app.staticTexts["饮食-已记录餐数"].value as? String, "1/3")
        breakfast.tap()
        let notes = app.textFields["计划餐实吃备注"]
        reveal(notes, in: app)
        notes.tap(); notes.typeText("按餐单吃完，口味清淡")
        dismissKeyboard(in: app)
        let bloating = app.buttons["计划餐腹胀反馈"]
        reveal(bloating, in: app); bloating.tap()
        app.buttons["轻"].tap()
        openNutritionFields(in: app)
        let calories = app.textFields["实吃-热量 kcal"]
        reveal(calories, in: app)
        calories.tap(); calories.typeText("300")
        dismissKeyboard(in: app)
        let save = app.buttons["保存计划实吃"]
        reveal(save, in: app); save.tap()
        XCTAssertTrue(breakfast.waitForExistence(timeout: 5))
        XCTAssertFalse(quickRecord.exists)
        breakfast.tap()
        openNutritionFields(in: app)
        let caloriesReadback = app.textFields["实吃-热量 kcal"]
        reveal(caloriesReadback, in: app)
        XCTAssertEqual(caloriesReadback.value as? String, "300")
        let proteinReadback = app.textFields["实吃-蛋白质 g"]
        reveal(proteinReadback, in: app)
        XCTAssertTrue(proteinReadback.exists)
        XCTAssertTrue(proteinReadback.isHittable)
        XCTAssertEqual(proteinReadback.placeholderValue, "未知")
        // iOS devices may expose an empty field as nil; Simulator may expose
        // its placeholder as value. Neither representation is a numeric zero.
        if let value = proteinReadback.value {
            guard let text = value as? String else {
                XCTFail("未知蛋白质返回了非文本值：\(value)")
                return
            }
            XCTAssertTrue(text.isEmpty || text == "未知", "未知蛋白质不能回读为数值：\(text)")
        }
        let unknownEvidence = XCTAttachment(string: "placeholder=\(proteinReadback.placeholderValue ?? "nil"); value=\(String(describing: proteinReadback.value))")
        unknownEvidence.name = "未知蛋白质字段读取"
        unknownEvidence.lifetime = .keepAlways
        add(unknownEvidence)
        let notesReadback = app.textFields["计划餐实吃备注"]
        reveal(notesReadback, in: app)
        XCTAssertEqual(notesReadback.value as? String, "按餐单吃完，口味清淡")
        app.navigationBars.buttons["关闭"].tap()
        let prep = app.buttons["饮食-明日备餐"]
        reveal(prep, in: app)
        prep.tap()
        let share = app.buttons["备餐-分享"]
        reveal(share, in: app)
        XCTAssertTrue(share.exists)
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 3) || app.buttons["拷贝"].exists || app.buttons["Copy"].exists)
        let shareScreenshot = XCTAttachment(screenshot: app.screenshot())
        shareScreenshot.name = "备餐系统分享面板"
        shareScreenshot.lifetime = .keepAlways
        add(shareScreenshot)
        // iOS 26 presents an anchored share popover. Its visible Copy action
        // completes a local share; swiping the underlying prep list cannot dismiss it.
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", "Copy", "拷贝")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        let prepDone = app.buttons["备餐-完成"]
        XCTAssertTrue(prepDone.waitForExistence(timeout: 5))
        let returnedToPrep = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: prepDone)
        XCTAssertEqual(XCTWaiter.wait(for: [returnedToPrep], timeout: 5), .completed)
        prepDone.tap()
        XCTAssertTrue(app.buttons["饮食-明日备餐"].waitForExistence(timeout: 5))
        app.tabBars.buttons["目标"].tap()
        let review = app.buttons["减脂每周复盘"]
        reveal(review, in: app); review.tap()
        let saveReview = app.buttons["保存减脂周复盘"]
        reveal(saveReview, in: app)
        XCTAssertTrue(saveReview.waitForExistence(timeout: 5)); saveReview.tap()
        XCTAssertTrue(app.staticTexts["已保存。后续补记不会修改这个快照。"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "减脂周复盘完整流程"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testReplacingUnrecordedMealKeepsPlanHistory() {
        let app = launch(started: true)
        createProgram(in: app)
        importMealsAndReturnHome(in: app)
        let lunch = app.buttons["饮食-调整实吃-午餐"]
        reveal(lunch, in: app); lunch.tap()
        let replacePicker = app.buttons["计划餐替换选择"]
        reveal(replacePicker, in: app)
        replacePicker.tap()
        let replacement = app.buttons["小馒头＋蒸蛋"]
        let menu = app.collectionViews.containing(.button, identifier: "选择菜式").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "先确认菜式菜单已展开")
        // The collection's frame includes offscreen rows. Keep gestures within
        // its visible top viewport and resolve coordinates before cells recycle.
        let menuFrame = menu.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: menuFrame.midX, dy: menuFrame.minY + 340))
        let end = origin.withOffset(CGVector(dx: menuFrame.midX, dy: menuFrame.minY + 90))
        for _ in 0..<6 {
            if replacement.exists && replacement.isHittable { break }
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(replacement.waitForExistence(timeout: 5)); replacement.tap()
        let reason = app.textFields["计划餐换菜原因"]
        reveal(reason, in: app); reason.tap(); reason.typeText("测试换菜反馈")
        dismissKeyboard(in: app)
        let replace = app.buttons["保存换菜"]
        reveal(replace, in: app); replace.tap()
        XCTAssertTrue(lunch.waitForExistence(timeout: 5)); lunch.tap()
        let history = app.staticTexts["这餐的计划历史"]
        reveal(history, in: app)
        XCTAssertTrue(history.exists)
    }
}
