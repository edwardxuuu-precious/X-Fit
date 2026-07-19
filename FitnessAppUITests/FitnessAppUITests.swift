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
}
