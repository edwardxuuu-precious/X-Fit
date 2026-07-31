import XCTest

final class FitnessAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func tap(
        _ element: XCUIElement,
        until expectedElement: XCUIElement,
        attempts: Int = 2
    ) -> Bool {
        for _ in 0..<attempts {
            if expectedElement.exists {
                return true
            }
            guard element.waitForExistence(timeout: 5) else {
                return expectedElement.exists
            }
            element.tap()
            if expectedElement.waitForExistence(timeout: 4) {
                return true
            }
        }
        return expectedElement.exists
    }

    func testStartWorkoutAndCompleteFirstSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let startButton = app.buttons["开始训练"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        let activeWorkoutTitle = app.staticTexts["训练进行中"]
        XCTAssertTrue(tap(startButton, until: activeWorkoutTitle))
        XCTAssertTrue(app.staticTexts["按今天状态调整菜单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["加动作"].exists)

        let firstSetButton = app.buttons["完成第 1 组"].firstMatch
        XCTAssertTrue(firstSetButton.waitForExistence(timeout: 5))
        firstSetButton.tap()

        XCTAssertTrue(app.staticTexts["组间休息"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1/12 组"].exists)
    }

    func testScheduleAndNutritionPagesAreReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let scheduleButton = app.buttons["日程"]
        XCTAssertTrue(scheduleButton.waitForExistence(timeout: 8))
        scheduleButton.tap()
        XCTAssertTrue(app.staticTexts["训练日程"].waitForExistence(timeout: 5))

        app.tabBars.buttons["首页"].tap()
        let nutritionButton = app.buttons["营养"]
        XCTAssertTrue(nutritionButton.waitForExistence(timeout: 5))
        nutritionButton.tap()
        XCTAssertTrue(app.staticTexts["营养"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["当天还没有餐食"].exists)
    }

    func testProfileGearOpensSettingsAndData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 8))
        let profileTab = app.tabBars.buttons["我的"]
        let settingsButton = app.buttons["打开设置"]
        XCTAssertTrue(tap(profileTab, until: settingsButton))
        settingsButton.tap()

        XCTAssertTrue(app.staticTexts["设置与数据"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apple 健康"].exists)
        XCTAssertTrue(app.staticTexts["数据所有权"].exists)
    }

    func testAdaptiveDailyBuilderShowsRecommendations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        trainingTab.tap()

        XCTAssertTrue(app.buttons["今日编排"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["先计划今天练什么"].waitForExistence(timeout: 5))
        let chestButton = app.buttons["胸部"].firstMatch
        XCTAssertTrue(chestButton.waitForExistence(timeout: 5))
        if !app.staticTexts["肌群建议"].exists {
            chestButton.tap()
        }

        XCTAssertTrue(app.staticTexts["肌群建议"].waitForExistence(timeout: 5))
        if !app.staticTexts["推荐动作"].exists {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["推荐动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["换一组"].exists)
    }

    func testHistoricalWorkoutEntryIsReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let syncLink = app.buttons["同步过去几周训练"]
        XCTAssertTrue(syncLink.waitForExistence(timeout: 8))
        syncLink.tap()

        let backfillButton = app.buttons["逐场手动补录"]
        XCTAssertTrue(backfillButton.waitForExistence(timeout: 5))
        backfillButton.tap()
        XCTAssertTrue(app.navigationBars["补录过去训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["训练名称"].exists)
    }

    func testHistoricalWorkoutImportIsReachableFromToday() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let syncLink = app.buttons["同步过去几周训练"]
        XCTAssertTrue(syncLink.waitForExistence(timeout: 8))
        syncLink.tap()

        XCTAssertTrue(app.navigationBars["历史同步"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["选择历史 CSV"].exists)
    }

    func testWorkoutHistoryShowsDetailsAndReturnsWithoutNavigationError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-history"]
        app.launch()

        XCTAssertTrue(app.navigationBars["训练历史"].waitForExistence(timeout: 8))

        let fixtureCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "历史详情验证")
        ).firstMatch
        XCTAssertTrue(fixtureCard.waitForExistence(timeout: 5))
        XCTAssertTrue(tap(fixtureCard, until: app.navigationBars["历史详情验证"]))
        XCTAssertTrue(app.staticTexts["杠铃卧推"].exists)
        XCTAssertTrue(app.staticTexts["第 1 组"].exists)
        XCTAssertTrue(app.staticTexts["40 kg × 10"].exists)
        XCTAssertTrue(app.staticTexts["维持重量与组数"].exists)

        app.buttons["编辑历史"].tap()
        XCTAssertTrue(app.navigationBars["编辑历史训练"].waitForExistence(timeout: 5))
        let workoutNotes = app.textFields["历史训练备注"]
        XCTAssertTrue(workoutNotes.waitForExistence(timeout: 5))
        workoutNotes.tap()
        workoutNotes.typeText(" UI已编辑")

        let exerciseNotes = app.textFields["动作备注-杠铃卧推"]
        XCTAssertTrue(exerciseNotes.exists)
        exerciseNotes.tap()
        exerciseNotes.typeText(" UI动作备注")
        app.navigationBars["编辑历史训练"].buttons["保存"].tap()

        XCTAssertTrue(app.navigationBars["历史详情验证"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "UI已编辑")
            ).firstMatch.waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "UI动作备注")
            ).firstMatch.exists
        )

        app.navigationBars["历史详情验证"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["训练历史"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.images["exclamationmark.triangle.fill"].exists)
    }
}
