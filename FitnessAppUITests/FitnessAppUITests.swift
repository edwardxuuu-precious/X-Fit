import XCTest

final class FitnessAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testStartWorkoutAndCompleteFirstSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let startButton = app.buttons["开始训练"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        startButton.tap()

        XCTAssertTrue(app.staticTexts["训练进行中"].waitForExistence(timeout: 5))

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
        app.tabBars.buttons["我的"].tap()

        let settingsButton = app.buttons["打开设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.staticTexts["设置与数据"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Apple 健康"].exists)
        XCTAssertTrue(app.staticTexts["数据所有权"].exists)
    }
}
