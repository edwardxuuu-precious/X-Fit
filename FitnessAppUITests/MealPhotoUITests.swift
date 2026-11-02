import XCTest

final class MealPhotoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(cameraFixture: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview", "--ui-testing-meal-camera-unavailable"]
        if cameraFixture { app.launchArguments.append("--ui-testing-meal-camera-fixture") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.xfitTabButtons["饮食"].waitForExistence(timeout: 15))
        app.xfitTabButtons["饮食"].tap()
        return app
    }

    private func captureFixture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "meal-fixture-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openCamera(in app: XCUIApplication) {
        let record = app.buttons["饮食-记录一餐"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        let camera = app.buttons.matching(identifier: "饮食-拍照记餐").firstMatch
        XCTAssertTrue(camera.waitForExistence(timeout: 5))
        camera.tap()
    }

    func testPhotoEntryAndUnavailableCameraCanCancelWithoutRecording() {
        let app = launch()
        let count = app.descendants(matching: .any)["饮食-已记录餐数"].firstMatch.label
        openCamera(in: app)
        XCTAssertTrue(app.navigationBars["拍照记餐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["餐食照片-相册"].exists)
        XCTAssertFalse(app.buttons["餐食照片-保存"].isEnabled)
        captureFixture("camera-unavailable", in: app)
        app.buttons["餐食照片-取消"].tap()
        XCTAssertTrue(app.buttons["饮食-记录一餐"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["饮食-已记录餐数"].firstMatch.label, count)
    }

    func testPhotoOnlyMealAppearsInTimelineAndCanAppendToSameMeal() {
        let app = launch(cameraFixture: true)
        openCamera(in: app)
        let save = app.buttons["餐食照片-保存"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        captureFixture("capture-confirmation", in: app)
        save.doubleTap()
        let cards = app.buttons.matching(identifier: "饮食-最近一餐")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(app.descendants(matching: .any)["饮食-已记录餐数"].firstMatch.label, "已记录1条餐食")
        captureFixture("photo-timeline", in: app)
        cards.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["餐食详情"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["餐食详情-照片数"].label, "1 张原照片")
        XCTAssertTrue(app.staticTexts["营养未知 · 尚未评估"].exists)
        XCTAssertFalse(app.staticTexts["0 kcal"].exists)
        app.buttons["餐食详情-追加照片"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["餐食详情-照片数"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["餐食详情-照片数"].label, "2 张原照片")
        captureFixture("meal-detail-two-photos", in: app)
        app.buttons["餐食详情-关闭"].tap()
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(app.descendants(matching: .any)["饮食-已记录餐数"].firstMatch.label, "已记录1条餐食")
    }

    func testWeekReviewEntryShowsRecordingCoverageWithoutInventingCalories() {
        let app = launch(large: true)
        let review = app.buttons["饮食-餐食周回顾"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if review.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(review.isHittable)
        review.tap()
        XCTAssertTrue(app.navigationBars["餐食周回顾"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["餐食周回顾-覆盖说明"].exists)
        XCTAssertTrue(app.staticTexts["餐食周回顾-起始日期"].isHittable)
        XCTAssertTrue(app.staticTexts["餐食周回顾-结束日期"].isHittable)
        captureFixture("week-review-large-type", in: app)
        let export = app.buttons["餐食周回顾-导出"]
        for _ in 0..<8 {
            if export.isHittable { break }
            app.swipeUp()
        }
        XCTAssertFalse(export.isEnabled)
        XCTAssertFalse(app.staticTexts["0 kcal"].exists)
    }
}
