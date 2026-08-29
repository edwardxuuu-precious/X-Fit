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

    private func tapRecoveringFromExternalInterruption(
        _ element: @autoclosure () -> XCUIElement,
        in app: XCUIApplication,
        until expectedElement: @autoclosure () -> XCUIElement,
        attempts: Int = 3
    ) -> Bool {
        for _ in 0..<attempts {
            if expectedElement().exists {
                return true
            }
            if app.state != .runningForeground {
                app.activate()
                _ = app.wait(for: .runningForeground, timeout: 3)
                if expectedElement().waitForExistence(timeout: 2) {
                    return true
                }
            }
            let currentElement = element()
            guard currentElement.waitForExistence(timeout: 5) else {
                return expectedElement().exists
            }

            // A real-device notification banner can take focus between the
            // hittability check and XCUIElement.tap(). A coordinate tap avoids
            // recording a false test failure, while the expected state below
            // still proves that the intended control handled the event.
            tapScreenCoordinate(of: currentElement, in: app)
            if expectedElement().waitForExistence(timeout: 4) {
                return true
            }
        }
        return expectedElement().exists
    }

    private func tapRecoveringFromExternalInterruption(
        _ element: @autoclosure () -> XCUIElement,
        in app: XCUIApplication,
        untilElementDisappears disappearingElement: @autoclosure () -> XCUIElement,
        attempts: Int = 3
    ) -> Bool {
        for _ in 0..<attempts {
            if !disappearingElement().exists {
                return true
            }
            if app.state != .runningForeground {
                app.activate()
                _ = app.wait(for: .runningForeground, timeout: 3)
                if disappearingElement().waitForNonExistence(timeout: 2) {
                    return true
                }
            }
            let currentElement = element()
            guard currentElement.waitForExistence(timeout: 5) else {
                return !disappearingElement().exists
            }
            tapScreenCoordinate(of: currentElement, in: app)
            if disappearingElement().waitForNonExistence(timeout: 4) {
                return true
            }
        }
        return !disappearingElement().exists
    }

    private func tapScreenCoordinate(of element: XCUIElement, in app: XCUIApplication) {
        let elementFrame = element.frame
        let appFrame = app.frame
        guard appFrame.width > 0, appFrame.height > 0 else {
            element.tap()
            return
        }
        let offset = CGVector(
            dx: (elementFrame.midX - appFrame.minX) / appFrame.width,
            dy: (elementFrame.midY - appFrame.minY) / appFrame.height
        )
        app.coordinate(withNormalizedOffset: offset).tap()
    }

    private func wakeUIInterruptionMonitor(in app: XCUIApplication) {
        // Keep the fallback tap inside the status-bar edge so that, when no
        // system alert is present, it cannot activate an app control.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.02)).tap()
    }

    private func scrollUp(
        in app: XCUIApplication,
        until element: XCUIElement,
        attempts: Int = 3
    ) -> Bool {
        if element.waitForExistence(timeout: 3) {
            return true
        }
        for _ in 0..<attempts {
            app.swipeUp()
            if element.waitForExistence(timeout: 2) {
                return true
            }
        }
        return element.exists
    }

    private func scrollDown(
        in app: XCUIApplication,
        until element: XCUIElement,
        attempts: Int = 3
    ) -> Bool {
        if element.waitForExistence(timeout: 3) {
            return true
        }
        for _ in 0..<attempts {
            app.swipeDown()
            if element.waitForExistence(timeout: 2) {
                return true
            }
        }
        return element.exists
    }

    private func clockSeconds(_ label: String) -> Int? {
        let components = label.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        return components[0] * 60 + components[1]
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText(value)
    }

    private func launchSeededShareDraftApp() -> XCUIApplication {
        addTeardownBlock {
            let cleanupApp = XCUIApplication()
            cleanupApp.launchArguments = [
                "--ui-testing",
                "--ui-testing-share-draft",
                "--ui-testing-reset-share-draft"
            ]
            cleanupApp.launch()
            XCTAssertTrue(
                cleanupApp.tabBars.buttons["首页"].waitForExistence(timeout: 8),
                "分享草稿测试 teardown 未完成测试键清理"
            )
            cleanupApp.terminate()
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-reset-store",
            "--ui-testing-share-draft",
            "--ui-testing-reset-production-share-draft",
            "--ui-testing-reset-share-draft",
            "--ui-testing-seed-share-draft"
        ]
        app.launch()
        return app
    }

    private func launchAndOpenDailyBuilder(
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + additionalArguments
        app.launch()
        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        let builder = app.buttons["今日编排入口"]
        XCTAssertTrue(tap(trainingTab, until: builder))
        XCTAssertTrue(tap(builder, until: app.staticTexts["编排当天训练"]))
        return app
    }

    private func openTerminologyReview(in app: XCUIApplication) {
        let profileTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 8))
        let settingsButton = app.buttons["打开设置"]
        XCTAssertTrue(
            tap(profileTab, until: settingsButton),
            "切换到“我的”后未出现设置入口"
        )
        settingsButton.tap()

        let reviewLink = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "审核中英文动作名称")
        ).firstMatch
        XCTAssertTrue(scrollUp(in: app, until: reviewLink, attempts: 4))
        reviewLink.tap()
        XCTAssertTrue(app.staticTexts["动作名称审核"].waitForExistence(timeout: 5))
    }

    func testDailyBodyCheckInCreatesBothMarkerTypesAndCancellationIsSafe() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let entry = app.buttons["记录今日体感"]
        XCTAssertTrue(scrollUp(in: app, until: entry, attempts: 3))
        entry.tap()
        XCTAssertTrue(app.navigationBars["今日体感"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["body-muscle-map"].waitForExistence(timeout: 3))

        let score = app.buttons["body-score-4"]
        XCTAssertTrue(score.waitForExistence(timeout: 3))
        score.tap()
        XCTAssertTrue(score.isSelected)

        let notes = app.textFields["body-discomfort-notes"]
        XCTAssertTrue(notes.exists)
        notes.tap()
        notes.typeText("right shoulder test")

        let shoulder = app.buttons["body-region-front-right-shoulder"]
        XCTAssertTrue(scrollUp(in: app, until: shoulder, attempts: 5))
        shoulder.tap()
        XCTAssertTrue(shoulder.isSelected)

        let markerKind = app.segmentedControls["body-marker-kind"]
        XCTAssertTrue(markerKind.waitForExistence(timeout: 3))
        markerKind.buttons["关节 / 筋膜"].tap()
        let jointShoulder = app.buttons["body-region-front-right-shoulder"]
        XCTAssertTrue(jointShoulder.waitForExistence(timeout: 3))
        jointShoulder.tap()

        XCTAssertTrue(scrollUp(in: app, until: app.staticTexts["已标注"], attempts: 4))
        XCTAssertTrue(app.staticTexts["右肩 · 肌肉 / 区域"].exists)
        XCTAssertTrue(app.staticTexts["右肩 · 关节 / 筋膜"].exists)

        app.buttons["保存今日体感"].tap()
        XCTAssertTrue(app.staticTexts["状态不错 · 1 处不适"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["right shoulder test"].exists)
        XCTAssertFalse(app.images["body-muscle-map"].exists)
        XCTAssertFalse(
            app.staticTexts["红色区域 = 肌肉 / 部位不适 · 红点 = 关节 / 筋膜"].exists
        )
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "荧光绿")
        ).firstMatch.exists)

        app.buttons["修改今日体感"].tap()
        XCTAssertTrue(app.navigationBars["今日体感"].waitForExistence(timeout: 5))
        app.buttons["body-score-1"].tap()
        app.buttons["取消今日体感"].tap()

        XCTAssertTrue(app.staticTexts["状态不错 · 1 处不适"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["状态很差"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "今日体感区域与红点共存"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDailyBodyCheckInRemainsUsableInDarkModeAndAccessibilityText() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let entry = app.buttons["记录今日体感"]
        XCTAssertTrue(scrollUp(in: app, until: entry, attempts: 4))
        entry.tap()
        XCTAssertTrue(app.navigationBars["今日体感"].waitForExistence(timeout: 5))

        let map = app.images["body-muscle-map"]
        XCTAssertTrue(scrollUp(in: app, until: map, attempts: 6))
        XCTAssertTrue(map.exists)

        let shoulder = app.buttons["body-region-front-right-shoulder"]
        XCTAssertTrue(scrollUp(in: app, until: shoulder, attempts: 6))
        shoulder.tap()
        XCTAssertTrue(shoulder.isSelected)

        let save = app.buttons["保存今日体感"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.staticTexts["状态一般 · 1 处不适"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "今日体感-深色模式-最大辅助字体"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testWorkoutFeelingIsRequestedBeforeCompletedExerciseCollapsesAndPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-reset-store",
            "--ui-testing-body-feedback"
        ]
        app.launch()

        let resume = app.buttons["继续记录训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(resume, until: app.staticTexts["训练进行中"]))
        XCTAssertFalse(app.buttons["动作感受-painful"].exists)

        let finalSet = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "完成第 ")
        ).firstMatch
        XCTAssertTrue(scrollUp(in: app, until: finalSet, attempts: 6))
        finalSet.tap()

        let painful = app.buttons["动作感受-painful"]
        XCTAssertTrue(scrollUp(in: app, until: painful, attempts: 6))
        XCTAssertTrue(painful.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["跳过感受并收起"].exists)
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "点按展开记录")).firstMatch.exists,
            "选择或跳过感受前不应自动折叠"
        )
        for feeling in ["painful", "exhausted", "hard", "good", "strong"] {
            XCTAssertTrue(app.buttons["动作感受-\(feeling)"].exists)
        }
        let strong = app.buttons["动作感受-strong"]
        strong.tap()
        let completedExercise = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "点按展开记录")
        ).firstMatch
        XCTAssertTrue(completedExercise.waitForExistence(timeout: 5))
        XCTAssertTrue(completedExercise.label.contains("😄"))

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-body-feedback"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["继续记录训练"].waitForExistence(timeout: 8))
        app.buttons["继续记录训练"].tap()
        XCTAssertTrue(app.staticTexts["训练进行中"].waitForExistence(timeout: 5))
        let restoredCompletedExercise = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "点按展开记录")
        ).firstMatch
        XCTAssertTrue(scrollUp(in: app, until: restoredCompletedExercise, attempts: 6))
        restoredCompletedExercise.tap()
        let restoredStrong = app.buttons["动作感受-strong"]
        XCTAssertTrue(scrollUp(in: app, until: restoredStrong, attempts: 6))
        XCTAssertTrue(restoredStrong.isSelected)
    }

    func testWorkoutFeelingIsVisibleInCompletedHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-history"]
        app.launch()

        let fixtureCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "历史详情验证")
        ).firstMatch
        XCTAssertTrue(fixtureCard.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(fixtureCard, until: app.navigationBars["历史详情验证"]))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "有挑战")
        ).firstMatch.waitForExistence(timeout: 5))
    }

    func testStartWorkoutAndCompleteFirstSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["PUSH / 01"].exists)
        XCTAssertFalse(app.staticTexts["查看全部"].exists)

        let startButton = app.buttons["开始记录训练"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        XCTAssertTrue(startButton.isHittable, "今日训练主操作应在首屏可直接点击")
        let activeWorkoutTitle = app.staticTexts["训练进行中"]
        XCTAssertTrue(tap(startButton, until: activeWorkoutTitle))
        XCTAssertTrue(app.staticTexts["按今天状态调整训练量"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["临时加动作"].exists)
        XCTAssertTrue(app.buttons["调整训练量"].firstMatch.exists)

        let rirHelpButton = app.buttons["了解 RIR"].firstMatch
        XCTAssertTrue(rirHelpButton.exists)
        rirHelpButton.tap()
        let rirAlert = app.alerts["RIR 是什么？"]
        XCTAssertTrue(rirAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(
            rirAlert.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "还能再完成几次")
            ).firstMatch.exists
        )
        rirAlert.buttons["知道了"].tap()

        let firstSetButton = app.buttons["完成第 1 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: firstSetButton, attempts: 4))
        firstSetButton.tap()

        XCTAssertTrue(app.staticTexts["组间休息"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["计划默认休息 120 秒"].exists)
        XCTAssertTrue(app.buttons["减少 30 秒休息"].exists)
        XCTAssertTrue(app.buttons["增加 30 秒休息"].exists)

        let timerValue = app.staticTexts["rest-timer-value"]
        XCTAssertTrue(timerValue.exists)
        let valueBeforeDecrease = timerValue.label
        app.buttons["减少 30 秒休息"].tap()
        XCTAssertNotEqual(timerValue.label, valueBeforeDecrease)
        app.buttons["增加 30 秒休息"].tap()

        XCTAssertTrue(app.staticTexts["1/12 组"].exists)

        let restTimerScreenshot = XCTAttachment(screenshot: app.screenshot())
        restTimerScreenshot.name = "组间休息控制"
        restTimerScreenshot.lifetime = .keepAlways
        add(restTimerScreenshot)
    }

    func testFreestyleRestEndsWhenNextSetStarts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let startWorkout = app.buttons["开始训练"]
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(startWorkout, until: app.staticTexts["训练进行中"]))

        let freestyle = app.buttons["自由记录"]
        XCTAssertTrue(freestyle.waitForExistence(timeout: 5))
        freestyle.tap()

        let startFirstSet = app.buttons["开始第 1 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: startFirstSet, attempts: 4))
        startFirstSet.tap()
        XCTAssertTrue(app.buttons["第 1 组进行中"].firstMatch.waitForExistence(timeout: 3))

        let completeFirstSet = app.buttons["完成第 1 组"].firstMatch
        XCTAssertTrue(completeFirstSet.exists)
        completeFirstSet.tap()
        XCTAssertTrue(app.staticTexts["自由组间计时"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["freestyle-rest-timer-value"].exists)

        let startSecondSet = app.buttons["开始第 2 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: startSecondSet, attempts: 3))
        startSecondSet.tap()

        XCTAssertTrue(app.buttons["第 2 组进行中"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["自由组间计时"].exists)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "组后休息")
        ).firstMatch.exists)
    }

    func testFreestyleRestCanBeAbandonedForLaterBackfill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let startWorkout = app.buttons["开始训练"]
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(startWorkout, until: app.staticTexts["训练进行中"]))

        let freestyle = app.buttons["自由记录"]
        XCTAssertTrue(freestyle.waitForExistence(timeout: 5))
        freestyle.tap()

        let startFirstSet = app.buttons["开始第 1 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: startFirstSet, attempts: 4))
        startFirstSet.tap()
        app.buttons["完成第 1 组"].firstMatch.tap()

        let abandon = app.buttons["取消本段休息并稍后补录"]
        XCTAssertTrue(abandon.waitForExistence(timeout: 3))
        abandon.tap()

        XCTAssertFalse(app.staticTexts["自由组间计时"].exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "组后休息")
        ).firstMatch.exists)
        XCTAssertTrue(app.buttons["开始第 2 组"].firstMatch.exists)
    }

    func testFreestyleRestUsesElapsedTimeAfterBackgrounding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let startWorkout = app.buttons["开始训练"]
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(startWorkout, until: app.staticTexts["训练进行中"]))

        let freestyle = app.buttons["自由记录"]
        XCTAssertTrue(freestyle.waitForExistence(timeout: 5))
        freestyle.tap()

        let startFirstSet = app.buttons["开始第 1 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: startFirstSet, attempts: 4))
        startFirstSet.tap()
        app.buttons["完成第 1 组"].firstMatch.tap()

        let timer = app.staticTexts["freestyle-rest-timer-value"]
        XCTAssertTrue(timer.waitForExistence(timeout: 3))
        let before = try XCTUnwrap(clockSeconds(timer.label))

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 3)
        app.activate()

        XCTAssertTrue(timer.waitForExistence(timeout: 5))
        let after = try XCTUnwrap(clockSeconds(timer.label))
        XCTAssertGreaterThanOrEqual(after - before, 2)
    }

    func testFreestyleRestSurvivesTerminationAndPersistentRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-reset-store"
        ]
        app.launch()

        let startWorkout = app.buttons["开始训练"]
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(startWorkout, until: app.staticTexts["训练进行中"]))
        app.buttons["自由记录"].tap()

        let startFirstSet = app.buttons["开始第 1 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: startFirstSet, attempts: 4))
        startFirstSet.tap()
        app.buttons["完成第 1 组"].firstMatch.tap()
        let timer = app.staticTexts["freestyle-rest-timer-value"]
        XCTAssertTrue(timer.waitForExistence(timeout: 3))
        let before = try XCTUnwrap(clockSeconds(timer.label))

        app.terminate()
        Thread.sleep(forTimeInterval: 3)
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent"]
        app.launch()

        let resume = app.buttons["继续记录训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        resume.tap()
        XCTAssertTrue(app.staticTexts["训练进行中"].waitForExistence(timeout: 5))
        let recoveredTimer = app.staticTexts["freestyle-rest-timer-value"]
        XCTAssertTrue(recoveredTimer.waitForExistence(timeout: 5))
        let after = try XCTUnwrap(clockSeconds(recoveredTimer.label))
        XCTAssertGreaterThanOrEqual(after - before, 2)

        app.buttons["取消本段休息并稍后补录"].tap()
        XCTAssertFalse(app.staticTexts["自由组间计时"].exists)
    }

    func testHistoricalRestInputRejectsInvalidTextThenPersistsValidBackfill() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-history"]
        app.launch()

        let fixtureCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "历史详情验证")
        ).firstMatch
        XCTAssertTrue(fixtureCard.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(fixtureCard, until: app.navigationBars["历史详情验证"]))
        app.buttons["编辑历史"].tap()
        XCTAssertTrue(app.navigationBars["编辑历史训练"].waitForExistence(timeout: 5))

        let restField = app.textFields["历史编辑第 1 组休息秒数"]
        XCTAssertTrue(scrollUp(in: app, until: restField, attempts: 6))
        restField.tap()
        restField.typeText("-30")
        XCTAssertEqual(restField.value as? String, "-30")
        XCTAssertTrue(app.staticTexts["第 1 组休息秒数错误"].waitForExistence(timeout: 3))

        app.navigationBars["编辑历史训练"].buttons["保存"].tap()
        let alert = app.alerts["无法保存历史记录"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "只能输入 0–9")
        ).firstMatch.exists)
        alert.buttons["知道了"].tap()

        app.navigationBars["编辑历史训练"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["历史详情验证"].waitForExistence(timeout: 5))
        app.buttons["编辑历史"].tap()
        XCTAssertTrue(app.navigationBars["编辑历史训练"].waitForExistence(timeout: 5))
        let validRestField = app.textFields["历史编辑第 1 组休息秒数"]
        XCTAssertTrue(scrollUp(in: app, until: validRestField, attempts: 6))
        validRestField.tap()
        validRestField.typeText("95")
        XCTAssertEqual(validRestField.value as? String, "95")
        XCTAssertFalse(app.staticTexts["第 1 组休息秒数错误"].exists)
        app.navigationBars["编辑历史训练"].buttons["保存"].tap()

        XCTAssertTrue(app.navigationBars["历史详情验证"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["组后休息 01:35"].waitForExistence(timeout: 5))
    }

    func testCountdownRestDeliversOneBackgroundNotification() throws {
        addUIInterruptionMonitor(withDescription: "通知权限") { alert in
            for title in ["允许", "Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }

        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-short-rest",
            "--ui-testing-notification-status",
            "--ui-testing-reset-rest-notifications",
            "--ui-testing-request-notification-authorization"
        ]
        app.launch()
        wakeUIInterruptionMonitor(in: app)
        XCTAssertTrue(app.staticTexts["通知授权已通过"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["通知横幅已启用"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["锁屏通知已启用"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["通知中心已启用"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["定时摘要未启用"].waitForExistence(timeout: 5))
        let startWorkout = app.buttons["开始训练"]
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(startWorkout, until: app.staticTexts["训练进行中"]))
        let firstSet = app.buttons["完成第 1 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: firstSet, attempts: 4))
        firstSet.tap()
        XCTAssertTrue(app.staticTexts["计划默认休息 5 秒"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["待发送休息通知 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["通知提交错误"].exists)

        app.terminate()
        Thread.sleep(forTimeInterval: 10)
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-short-rest",
            "--ui-testing-notification-status"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.staticTexts["已送达休息通知 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["已送达休息通知 2"].exists)
    }

    func testFreestyleDoesNotDeliverCountdownNotification() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-notification-status",
            "--ui-testing-reset-rest-notifications"
        ]
        app.launch()

        let startWorkout = app.buttons["开始训练"]
        XCTAssertTrue(startWorkout.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(startWorkout, until: app.staticTexts["训练进行中"]))
        app.buttons["自由记录"].tap()

        let startFirstSet = app.buttons["开始第 1 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: startFirstSet, attempts: 4))
        startFirstSet.tap()
        app.buttons["完成第 1 组"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["自由组间计时"].waitForExistence(timeout: 3))

        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 6)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.staticTexts["已送达休息通知 0"].waitForExistence(timeout: 5))
    }

    func testHomeIsAnActionSurfaceWithoutDuplicateDashboards() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-progress"]
        app.launch()

        let start = app.buttons["开始记录训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(start.isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["首页日期"].exists)
        XCTAssertTrue(app.otherElements["今日训练海报"].exists)
        XCTAssertTrue(app.otherElements["首页状态轨道"].exists)
        XCTAssertTrue(app.buttons["最近一次训练入口"].exists)
        XCTAssertFalse(app.buttons["补录训练入口"].exists)
        XCTAssertFalse(app.buttons["训练历史入口"].exists)
        XCTAssertFalse(app.buttons["训练日程入口"].exists)
        XCTAssertFalse(app.staticTexts["最近训练容量"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["最近训练容量图"].exists)
    }

    func testHomePrimaryActionRemainsReachableAtAccessibilityXXXL() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()

        let start = app.buttons["开始记录训练"]
        XCTAssertTrue(scrollUp(in: app, until: start, attempts: 4))
        XCTAssertTrue(start.isHittable)
        XCTAssertFalse(app.staticTexts["PUSH / 01"].exists)
        XCTAssertFalse(app.images["body-muscle-map"].exists)
    }

    func testHomePlanCanBeOpenedForEditing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["今天练什么"].exists)
        XCTAssertFalse(app.staticTexts["12 组"].exists)
        XCTAssertTrue(app.staticTexts["今天感觉怎么样"].exists)
        XCTAssertFalse(app.staticTexts["PUSH / 01"].exists)
        XCTAssertTrue(app.buttons["开始记录训练"].exists)
        XCTAssertFalse(app.staticTexts["准备记录"].exists)
        XCTAssertFalse(app.staticTexts["预计 kg 容量"].exists)
        XCTAssertFalse(app.buttons["今日计划更多操作"].exists)

        let editPlan = app.buttons["修改今日计划"]
        XCTAssertTrue(editPlan.waitForExistence(timeout: 8))
        XCTAssertEqual(editPlan.label, "调整今日计划")
        let workoutTitle = app.staticTexts["推 · 胸肩三头"]
        XCTAssertTrue(workoutTitle.exists)
        XCTAssertLessThan(
            abs(editPlan.frame.midY - workoutTitle.frame.midY),
            2,
            "计划图标应与训练标题垂直居中"
        )
        XCTAssertGreaterThanOrEqual(editPlan.frame.width, 44)
        XCTAssertGreaterThanOrEqual(editPlan.frame.height, 44)
        editPlan.tap()
        XCTAssertTrue(app.staticTexts["编排当天训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天的菜单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["保存并开始记录"].exists)
        XCTAssertTrue(app.buttons["保存今日计划"].exists)
    }

    func testHomeShowsOnlyTheLatestCompletedWorkout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-progress"]
        app.launch()

        let latest = app.buttons["最近一次训练入口"]
        XCTAssertTrue(latest.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["本周拉训练"].exists)
        XCTAssertFalse(app.staticTexts["最近训练容量"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["最近训练容量图"].exists)
    }

    func testHomeEmptyStateOffersPlanAndHistoricalEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-empty"]
        app.launch()

        XCTAssertTrue(app.staticTexts["安排一场训练"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["编排今日训练"].exists)
        XCTAssertFalse(app.buttons["补录训练入口"].exists)
        XCTAssertFalse(app.buttons["最近一次训练入口"].exists)
        XCTAssertFalse(app.staticTexts["最近训练容量"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["最近训练容量图"].exists)
    }

    func testHomeSingleCompletedWorkoutShowsOneRecentEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-single-volume"]
        app.launch()

        let latest = app.buttons["最近一次训练入口"]
        XCTAssertTrue(latest.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["首页容量夹具 0"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "最近一次训练入口").count, 1)
        XCTAssertFalse(app.staticTexts["最近训练容量"].exists)
    }

    func testHomeWithManyCompletedWorkoutsStillShowsOneRecentEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-seven-volumes"]
        app.launch()

        let latest = app.buttons["最近一次训练入口"]
        XCTAssertTrue(latest.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["首页容量夹具 0"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "最近一次训练入口").count, 1)
        XCTAssertFalse(app.descendants(matching: .any)["最近训练容量图"].exists)
    }

    func testHomeCompletedPlanOffersRecordEditingWithoutStartButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-completed"]
        app.launch()

        XCTAssertTrue(app.staticTexts["今天已完成"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["查看今日训练记录"].exists)
        XCTAssertTrue(app.buttons["修改今日记录"].exists)
        XCTAssertFalse(app.buttons["开始记录训练"].exists)
        XCTAssertFalse(app.buttons["修改今日计划"].exists)
        XCTAssertFalse(app.buttons["今日计划更多操作"].exists)

        app.buttons["修改今日记录"].tap()
        XCTAssertTrue(app.navigationBars["编辑历史训练"].waitForExistence(timeout: 5))
    }

    func testHomeActiveSessionSurvivesPersistentRelaunchWithoutDuplication() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-reset-store"
        ]
        app.launch()

        let start = app.buttons["开始记录训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(start, until: app.staticTexts["训练进行中"]))
        app.terminate()

        app.launchArguments = ["--ui-testing", "--ui-testing-persistent"]
        app.launch()
        let resume = app.buttons["继续记录训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["开始记录训练"].exists)
        resume.tap()
        XCTAssertTrue(app.staticTexts["训练进行中"].waitForExistence(timeout: 5))
    }

    func testHomePlanFieldEditPersistsAcrossPersistentRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-reset-store"
        ]
        app.launch()

        let editPlan = app.buttons["修改今日计划"]
        XCTAssertTrue(editPlan.waitForExistence(timeout: 8))
        editPlan.tap()
        XCTAssertTrue(app.staticTexts["编排当天训练"].waitForExistence(timeout: 5))

        let weight = app.textFields["planned-weight-杠铃卧推-1"]
        XCTAssertTrue(scrollUp(in: app, until: weight, attempts: 12))
        replaceText(in: weight, with: "55.5")
        let save = app.buttons["保存今日计划"]
        XCTAssertTrue(save.exists)
        save.tap()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["PUSH / 01"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent"]
        app.launch()
        let relaunchedEditPlan = app.buttons["修改今日计划"]
        XCTAssertTrue(relaunchedEditPlan.waitForExistence(timeout: 8))
        relaunchedEditPlan.tap()
        XCTAssertTrue(app.staticTexts["编排当天训练"].waitForExistence(timeout: 5))
        let relaunchedWeight = app.textFields["planned-weight-杠铃卧推-1"]
        XCTAssertTrue(scrollUp(in: app, until: relaunchedWeight, attempts: 12))
        XCTAssertEqual(relaunchedWeight.value as? String, "55.5")
    }

    func testStatsVolumeTrendSwitchesFromOverallToExerciseHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-progress"]
        app.launch()

        let progressTab = app.tabBars.buttons["进度"]
        XCTAssertTrue(progressTab.waitForExistence(timeout: 8))
        progressTab.tap()

        let trendCard = app.otherElements["训练容量趋势卡片"]
        XCTAssertTrue(scrollUp(in: app, until: trendCard, attempts: 5))
        XCTAssertTrue(app.staticTexts["训练容量趋势"].exists)
        XCTAssertTrue(app.buttons["总容量"].exists)
        XCTAssertTrue(app.buttons["按动作"].exists)

        app.buttons["按动作"].tap()

        XCTAssertTrue(app.buttons["选择趋势动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["所选动作每次训练的训练量 · kg"].exists)
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

    func testTerminologyReviewIsReachableAndExplainsNoHistoryRewrite() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openTerminologyReview(in: app)
        XCTAssertTrue(app.staticTexts["本地候选库已启用"].exists)
        XCTAssertTrue(app.staticTexts["AI API 未连接"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "不会改写已完成训练的原始名称")
            ).firstMatch.exists
        )
    }

    func testTerminologyAcceptAndResetDecisionFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-terminology"]
        app.launch()
        openTerminologyReview(in: app)

        let row = app.buttons["terminology-row-三头下压"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 3))
        row.tap()
        XCTAssertTrue(app.staticTexts["三头下压"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["绳索下压"].exists)

        let accept = app.buttons["terminology-accept-button"]
        XCTAssertTrue(accept.waitForExistence(timeout: 3))
        XCTAssertTrue(accept.isEnabled)
        accept.tap()
        let confirmAccept = app.buttons["确认接受"]
        XCTAssertTrue(confirmAccept.waitForExistence(timeout: 3))
        confirmAccept.tap()

        let completedAlert = app.alerts["完成"]
        XCTAssertTrue(completedAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(
            completedAlert.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "历史名称和训练数据未被修改")
            ).firstMatch.exists
        )
        completedAlert.buttons["知道了"].tap()

        let reset = app.buttons["terminology-reset-button"]
        XCTAssertTrue(reset.waitForExistence(timeout: 3))
        reset.tap()
        let confirmReset = app.buttons["恢复为待审核"]
        XCTAssertTrue(confirmReset.waitForExistence(timeout: 3))
        confirmReset.tap()
        XCTAssertTrue(app.alerts["完成"].waitForExistence(timeout: 3))
        app.alerts["完成"].buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["terminology-accept-button"].waitForExistence(timeout: 3))
    }

    func testTerminologyUnresolvedCandidateCannotBeAccepted() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-terminology"]
        app.launch()
        openTerminologyReview(in: app)

        let row = app.buttons["terminology-row-传统硬拉"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 3))
        row.tap()
        XCTAssertTrue(app.staticTexts["传统硬拉"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["尚无候选"].firstMatch.exists)
        let accept = app.buttons["terminology-accept-button"]
        XCTAssertTrue(accept.waitForExistence(timeout: 3))
        XCTAssertFalse(accept.isEnabled)
        XCTAssertTrue(app.buttons["terminology-reject-button"].isEnabled)
    }

    func testTerminologyDecisionsPersistAcrossRelaunchAndPreserveHistoricalSnapshots() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-reset-store",
            "--ui-testing-terminology"
        ]
        app.launch()
        openTerminologyReview(in: app)

        var row = app.buttons["terminology-row-三头下压"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 4))
        row.tap()
        let completedSetRow = app.descendants(matching: .any)["terminology-completed-set-row"]
        XCTAssertTrue(completedSetRow.waitForExistence(timeout: 5))
        XCTAssertTrue(completedSetRow.label.contains("2"))

        app.buttons["terminology-accept-button"].tap()
        XCTAssertTrue(app.buttons["确认接受"].waitForExistence(timeout: 3))
        app.buttons["确认接受"].tap()
        XCTAssertTrue(app.alerts["完成"].waitForExistence(timeout: 3))
        app.alerts["完成"].buttons["知道了"].tap()

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-terminology"
        ]
        app.launch()
        openTerminologyReview(in: app)
        let reviewedSegment = app.buttons["已处理"].firstMatch
        XCTAssertTrue(reviewedSegment.waitForExistence(timeout: 5))
        reviewedSegment.tap()
        row = app.buttons["terminology-row-三头下压"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 4))
        row.tap()
        XCTAssertTrue(app.staticTexts["已接受候选"].waitForExistence(timeout: 5))

        app.buttons["terminology-reset-button"].tap()
        XCTAssertTrue(app.buttons["恢复为待审核"].waitForExistence(timeout: 3))
        app.buttons["恢复为待审核"].tap()
        XCTAssertTrue(app.alerts["完成"].waitForExistence(timeout: 3))
        app.alerts["完成"].buttons["知道了"].tap()

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-terminology"
        ]
        app.launch()
        openTerminologyReview(in: app)
        row = app.buttons["terminology-row-三头下压"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 4))
        row.tap()
        XCTAssertTrue(app.buttons["terminology-accept-button"].waitForExistence(timeout: 5))

        app.buttons["terminology-reject-button"].tap()
        XCTAssertTrue(app.buttons["确认保留当前名称"].waitForExistence(timeout: 3))
        app.buttons["确认保留当前名称"].tap()
        XCTAssertTrue(app.alerts["完成"].waitForExistence(timeout: 3))
        app.alerts["完成"].buttons["知道了"].tap()

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-terminology"
        ]
        app.launch()
        openTerminologyReview(in: app)
        let rejectedSegment = app.buttons["已处理"].firstMatch
        XCTAssertTrue(rejectedSegment.waitForExistence(timeout: 5))
        rejectedSegment.tap()
        row = app.buttons["terminology-row-三头下压"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 4))
        row.tap()
        XCTAssertTrue(app.staticTexts["保留当前名称"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-history"
        ]
        app.launch()
        XCTAssertTrue(app.navigationBars["训练历史"].waitForExistence(timeout: 8))
        let historyCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "术语历史保护验证")
        ).firstMatch
        XCTAssertTrue(historyCard.waitForExistence(timeout: 5))
        XCTAssertTrue(historyCard.label.contains("2 动作"))
        XCTAssertTrue(historyCard.label.contains("3 组"))
        XCTAssertTrue(tap(historyCard, until: app.navigationBars["术语历史保护验证"]))
        XCTAssertTrue(app.staticTexts["三头下压"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["绳索下压"].exists)
        XCTAssertTrue(app.staticTexts["20 kg × 10"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["25 kg × 12"].exists)
        XCTAssertTrue(app.staticTexts["RIR 2"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["RIR 1"].exists)
    }

    func testAdaptiveDailyBuilderShowsRecommendations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        trainingTab.tap()

        let dailyBuilder = app.buttons["今日编排入口"]
        XCTAssertTrue(dailyBuilder.waitForExistence(timeout: 5))
        XCTAssertTrue(tap(dailyBuilder, until: app.staticTexts["编排当天训练"]))
        let chestButton = app.buttons["胸部"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: chestButton, attempts: 4))
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

    func testShareDraftDeferralSuppressesTheSameDraftUntilANewShareArrives() throws {
        let app = launchSeededShareDraftApp()
        let received = app.staticTexts["已收到一份动作资料"]
        XCTAssertTrue(received.waitForExistence(timeout: 8))
        let deferButton = app.buttons["稍后处理"]
        XCTAssertTrue(deferButton.waitForExistence(timeout: 3))
        deferButton.tap()
        XCTAssertFalse(received.waitForExistence(timeout: 2))

        let reloadDraftButton = app.buttons["重新检查分享草稿"]
        XCTAssertTrue(reloadDraftButton.waitForExistence(timeout: 3))
        reloadDraftButton.tap()
        XCTAssertFalse(received.waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-share-draft"
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 8))
        XCTAssertFalse(received.waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments.append("--ui-testing-seed-share-draft")
        app.launch()
        XCTAssertTrue(received.waitForExistence(timeout: 8), "新 ID 的分享草稿必须重新提醒")
    }

    func testDailyBuilderCanReorderCompactNameCardsByDragging() throws {
        let app = launchAndOpenDailyBuilder()
        let reorder = app.buttons["拖动排序"]
        XCTAssertTrue(reorder.waitForExistence(timeout: 5))
        reorder.tap()

        let first = app.descendants(matching: .any)["排序动作-杠铃卧推"]
        let second = app.descendants(matching: .any)["排序动作-上斜哑铃卧推"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["planned-weight-杠铃卧推-1"].exists)

        first.press(forDuration: 0.8, thenDragTo: second)
        XCTAssertTrue(app.staticTexts["1. 上斜哑铃卧推"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2. 杠铃卧推"].exists)
    }

    func testUITestShareDraftDoesNotLeakIntoProductionStartup() throws {
        let seededApp = launchSeededShareDraftApp()
        XCTAssertTrue(
            seededApp.staticTexts["已收到一份动作资料"].waitForExistence(timeout: 8)
        )
        seededApp.terminate()

        let productionApp = XCUIApplication()
        productionApp.launchArguments = [
            "--disable-cloud-sync",
            "--initialize-empty-cloud-store"
        ]
        productionApp.launch()

        XCTAssertTrue(productionApp.tabBars.buttons["首页"].waitForExistence(timeout: 8))
        let received = productionApp.staticTexts["已收到一份动作资料"]
        if received.waitForExistence(timeout: 3) {
            XCTAssertTrue(
                tapRecoveringFromExternalInterruption(
                    productionApp.buttons["补充信息并加入动作库"],
                    in: productionApp,
                    until: productionApp.navigationBars["新建动作"]
                )
            )
            let nameField = productionApp.textFields["动作名称"]
            XCTAssertTrue(nameField.waitForExistence(timeout: 5))
            XCTAssertNotEqual(
                nameField.value as? String,
                "UI 测试绳索划船",
                "普通启动读取到了 UI 测试键中的草稿"
            )
            productionApp.navigationBars["新建动作"].buttons["取消"].tap()
        }
    }

    func testShareDraftEditorCancellationKeepsDraftAvailable() throws {
        let app = launchSeededShareDraftApp()
        let received = app.staticTexts["已收到一份动作资料"]
        XCTAssertTrue(received.waitForExistence(timeout: 8))
        XCTAssertTrue(
            tapRecoveringFromExternalInterruption(
                app.buttons["补充信息并加入动作库"],
                in: app,
                until: app.navigationBars["新建动作"]
            )
        )
        XCTAssertTrue(
            tapRecoveringFromExternalInterruption(
                app.navigationBars["新建动作"].buttons["取消"],
                in: app,
                untilElementDisappears: app.navigationBars["新建动作"]
            )
        )

        XCTAssertTrue(
            tapRecoveringFromExternalInterruption(
                app.buttons["重新检查分享草稿"],
                in: app,
                until: received
            )
        )
    }

    func testShareDraftSaveFailureKeepsDraftAvailable() throws {
        let app = launchSeededShareDraftApp()
        let received = app.staticTexts["已收到一份动作资料"]
        XCTAssertTrue(received.waitForExistence(timeout: 8))
        app.buttons["补充信息并加入动作库"].tap()
        let urlField = app.textFields["参考链接（可选）"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 4))
        replaceText(in: urlField, with: "ftp://example.com")
        let saveError = app.alerts["保存失败"]
        XCTAssertTrue(
            tapRecoveringFromExternalInterruption(
                app.navigationBars["新建动作"].buttons["保存"],
                in: app,
                until: saveError
            )
        )
        saveError.buttons["知道了"].tap()
        app.navigationBars["新建动作"].buttons["取消"].tap()

        app.buttons["重新检查分享草稿"].tap()
        XCTAssertTrue(received.waitForExistence(timeout: 8))
    }

    func testShareDraftSuccessfulSaveClearsDraft() throws {
        let app = launchSeededShareDraftApp()
        let received = app.staticTexts["已收到一份动作资料"]
        XCTAssertTrue(received.waitForExistence(timeout: 8))
        app.buttons["补充信息并加入动作库"].tap()
        let urlField = app.textFields["参考链接（可选）"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 4))
        replaceText(in: urlField, with: "https://example.com/ui-share")
        app.navigationBars["新建动作"].buttons["保存"].tap()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5))

        app.buttons["重新检查分享草稿"].tap()
        XCTAssertFalse(received.waitForExistence(timeout: 3))
    }

    func testDailyBuilderPickerCancellationPreservesDraftMenuAndParameters() throws {
        executionTimeAllowance = 120
        let app = launchAndOpenDailyBuilder()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1. 杠铃卧推"].exists)

        let firstWeight = app.textFields["planned-weight-杠铃卧推-1"]
        XCTAssertTrue(scrollUp(in: app, until: firstWeight, attempts: 10))
        let originalWeight = firstWeight.value as? String
        let fourthAction = app.staticTexts["4. 绳索下压"]
        XCTAssertTrue(scrollUp(in: app, until: fourthAction, attempts: 10))
        let chest = app.buttons["胸部"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: chest, attempts: 8))
        XCTAssertEqual(chest.value as? String, "已选择")

        let add = app.buttons["当天菜单添加动作"]
        XCTAssertTrue(scrollDown(in: app, until: add, attempts: 12))
        add.tap()
        let pickerBar = app.navigationBars["添加到当天菜单"]
        XCTAssertTrue(pickerBar.waitForExistence(timeout: 5))
        pickerBar.buttons["取消"].tap()

        let actionCount = app.staticTexts["4 个动作"]
        XCTAssertTrue(scrollDown(in: app, until: actionCount, attempts: 12))
        XCTAssertTrue(app.staticTexts["1. 杠铃卧推"].exists)
        XCTAssertTrue(scrollUp(in: app, until: firstWeight, attempts: 10))
        XCTAssertEqual(firstWeight.value as? String, originalWeight)
        XCTAssertTrue(scrollUp(in: app, until: fourthAction, attempts: 10))
        XCTAssertTrue(scrollUp(in: app, until: chest, attempts: 8))
        XCTAssertEqual(chest.value as? String, "已选择")
    }

    func testDailyBuilderNewExerciseCancellationReturnsToPickerWithoutMutation() throws {
        let app = launchAndOpenDailyBuilder()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 5))
        app.buttons["当天菜单添加动作"].tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("UI 取消新建动作")
        app.buttons["新建并加入"].tap()
        XCTAssertTrue(app.navigationBars["新建动作"].waitForExistence(timeout: 5))
        app.navigationBars["新建动作"].buttons["取消"].tap()

        XCTAssertTrue(app.buttons["新建并加入"].exists)
        let cancelAndReturn = app.buttons["取消并返回"]
        XCTAssertTrue(cancelAndReturn.waitForExistence(timeout: 5))
        cancelAndReturn.tap()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["5. UI 取消新建动作"].exists)
    }

    func testDailyBuilderSearchesAndAddsCrossMuscleExercise() throws {
        let app = launchAndOpenDailyBuilder()
        app.buttons["当天菜单添加动作"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("杠铃深蹲")
        let result = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "深蹲")
        ).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.navigationBars["本次设置"].waitForExistence(timeout: 5))
        app.buttons["使用上次设置"].tap()
        XCTAssertTrue(app.staticTexts["5 个动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUp(in: app, until: app.staticTexts["5. 深蹲"], attempts: 8))
    }

    func testDailyBuilderInvalidURLCanBeCorrectedAndSavedWithoutKeyboardBlocking() throws {
        let app = launchAndOpenDailyBuilder()
        app.buttons["当天菜单添加动作"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("UI URL 修正动作")
        app.buttons["新建并加入"].tap()
        let editorBar = app.navigationBars["新建动作"]
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5))
        let urlField = app.textFields["参考链接（可选）"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 4))
        replaceText(in: urlField, with: "ftp://example.com")
        XCTAssertTrue(editorBar.buttons["保存"].isHittable)
        editorBar.buttons["保存"].tap()
        let error = app.alerts["保存失败"]
        XCTAssertTrue(error.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "http 或 https")
        ).firstMatch.exists)
        error.buttons["知道了"].tap()
        replaceText(in: urlField, with: "https://example.com/ui-corrected")
        XCTAssertTrue(editorBar.buttons["保存"].isHittable)
        editorBar.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["本次设置"].waitForExistence(timeout: 5))
        app.buttons["使用上次设置"].tap()
        XCTAssertTrue(app.staticTexts["5 个动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUp(in: app, until: app.staticTexts["5. UI URL 修正动作"], attempts: 8))
    }

    func testDailyBuilderCoreControlsRemainReachableAtAccessibilityXXXL() throws {
        let app = launchAndOpenDailyBuilder(additionalArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ])
        let add = app.buttons["当天菜单添加动作"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isHittable)
        let firstAction = app.staticTexts["1. 杠铃卧推"]
        XCTAssertTrue(firstAction.exists)
        let chest = app.buttons["胸部"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: chest, attempts: 12))
        XCTAssertEqual(chest.value as? String, "已选择")
        XCTAssertTrue(scrollDown(in: app, until: add, attempts: 14))
        add.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["添加到当天菜单"].buttons["新建动作"].exists)
        app.navigationBars["添加到当天菜单"].buttons["新建动作"].tap()
        let name = app.textFields["动作名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("UI 超大字体动作")
        let editorSave = app.navigationBars["新建动作"].buttons["保存"]
        XCTAssertTrue(editorSave.exists)
        XCTAssertTrue(editorSave.isHittable)
    }

    func testActiveWorkoutCanCreateMissingExerciseInlineWithThreeSets() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(tap(app.buttons["开始训练"], until: app.staticTexts["训练进行中"]))
        let add = app.buttons["临时加动作"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("UI 训练中临时动作")
        app.buttons["新建并加入"].tap()
        XCTAssertTrue(app.navigationBars["新建动作"].waitForExistence(timeout: 5))
        app.navigationBars["新建动作"].buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["本次设置"].waitForExistence(timeout: 5))
        app.buttons["使用上次设置"].tap()
        for setNumber in 1...3 {
            let field = app.textFields["actual-reps-UI 训练中临时动作-\(setNumber)"]
            XCTAssertTrue(scrollUp(in: app, until: field, attempts: 12))
        }
        XCTAssertFalse(app.textFields["actual-reps-UI 训练中临时动作-4"].exists)
    }

    func testExercisePickerFiftyCycleStressPreservesMenuAndAvoidsDuplicates() throws {
        executionTimeAllowance = 1_800
        let app = launchAndOpenDailyBuilder()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 5))

        for cycle in 1...50 {
            let add = app.buttons["当天菜单添加动作"]
            XCTAssertTrue(add.waitForExistence(timeout: 5), "第 \(cycle) 轮缺少添加入口")
            add.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5), "第 \(cycle) 轮选择器未打开")
            search.tap()
            search.typeText("UI 压力取消 \(cycle)")
            let create = app.buttons["新建并加入"]
            XCTAssertTrue(create.waitForExistence(timeout: 5), "第 \(cycle) 轮零结果入口缺失")
            create.tap()
            let editorNavigationBar = app.navigationBars["新建动作"]
            XCTAssertTrue(editorNavigationBar.waitForExistence(timeout: 5))
            XCTAssertTrue(
                tapRecoveringFromExternalInterruption(
                    editorNavigationBar.buttons["取消"],
                    in: app,
                    untilElementDisappears: editorNavigationBar
                ),
                "第 \(cycle) 轮无法关闭新建动作页"
            )

            let cancelPicker = app.buttons["取消并返回"]
            XCTAssertTrue(cancelPicker.waitForExistence(timeout: 5), "第 \(cycle) 轮未返回动作选择器")
            XCTAssertTrue(
                tapRecoveringFromExternalInterruption(
                    cancelPicker,
                    in: app,
                    untilElementDisappears: cancelPicker
                ),
                "第 \(cycle) 轮无法返回计划"
            )
            XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 5))
        }

        app.buttons["当天菜单添加动作"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("杠铃深蹲")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "深蹲")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.navigationBars["本次设置"].waitForExistence(timeout: 5))
        app.buttons["使用上次设置"].tap()
        XCTAssertTrue(app.staticTexts["5 个动作"].waitForExistence(timeout: 5))
        let addedSquat = app.staticTexts["5. 深蹲"]
        XCTAssertTrue(scrollUp(in: app, until: addedSquat, attempts: 8))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "5. 深蹲")).count, 1)
    }

    func testDailyBuilderCanCreateMissingExerciseInline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        app.tabBars.buttons["训练"].tap()
        let dailyBuilder = app.buttons["今日编排入口"]
        XCTAssertTrue(dailyBuilder.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(dailyBuilder, until: app.staticTexts["编排当天训练"]))

        let addExercise = app.buttons["当天菜单添加动作"]
        XCTAssertTrue(addExercise.waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(tap(addExercise, until: search))
        search.tap()
        search.typeText("反向北欧弯举测试")

        let createAndAdd = app.buttons["新建并加入"]
        XCTAssertTrue(createAndAdd.waitForExistence(timeout: 5))
        createAndAdd.tap()
        XCTAssertTrue(app.navigationBars["新建动作"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["动作名称"].value as? String, "反向北欧弯举测试")
        XCTAssertTrue(app.textFields["参考链接（可选）"].exists)

        app.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["本次设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["首次建议"].exists)
        app.buttons["使用上次设置"].tap()
        XCTAssertTrue(app.staticTexts["5 个动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            scrollUp(
                in: app,
                until: app.staticTexts["5. 反向北欧弯举测试"],
                attempts: 5
            )
        )
    }

    func testEquipmentPhotoRecognitionShowsMachineMusclesAndAddsConfirmedExercise() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-equipment-recognition"]
        app.launch()

        app.tabBars.buttons["训练"].tap()
        XCTAssertTrue(tap(app.buttons["今日编排入口"], until: app.staticTexts["编排当天训练"]))
        app.buttons["当天菜单添加动作"].tap()

        let recognition = app.buttons["拍照识别器械"]
        XCTAssertTrue(recognition.waitForExistence(timeout: 5))
        recognition.tap()
        XCTAssertTrue(app.navigationBars["拍照识别器械"].waitForExistence(timeout: 5))

        let scan = app.buttons["开始识别器械"]
        XCTAssertTrue(scan.waitForExistence(timeout: 3))
        XCTAssertTrue(scan.isEnabled)
        scan.tap()

        XCTAssertTrue(app.staticTexts["钟摆深蹲机"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pendulum Squat Machine"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "主要肌群")
        ).firstMatch.exists)

        let candidate = app.buttons["识别动作-钟摆深蹲机"]
        XCTAssertTrue(scrollUp(in: app, until: candidate, attempts: 3))
        candidate.tap()
        XCTAssertTrue(app.navigationBars["本次设置"].waitForExistence(timeout: 5))
        app.buttons["使用上次设置"].tap()
        XCTAssertTrue(app.staticTexts["5 个动作"].waitForExistence(timeout: 5))
    }

    func testCountdownRestEndPresentsActionableAlert() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-short-rest"]
        app.launch()

        XCTAssertTrue(tap(app.buttons["开始训练"], until: app.staticTexts["训练进行中"]))
        let firstSet = app.buttons["完成第 1 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: firstSet, attempts: 4))
        firstSet.tap()

        let alert = app.alerts["休息结束"]
        XCTAssertTrue(alert.waitForExistence(timeout: 9))
        XCTAssertTrue(alert.buttons["开始下一组"].exists)
        XCTAssertTrue(alert.buttons["+30 秒"].exists)
        alert.buttons["+30 秒"].tap()
        XCTAssertTrue(app.staticTexts["组间休息"].waitForExistence(timeout: 3))
    }

    func testActiveWorkoutUsesExplicitRIRChoiceAndOneActionLevelSideControl() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(tap(app.buttons["开始训练"], until: app.staticTexts["训练进行中"]))

        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "计划第")).count,
            0,
            "左侧组号已经表达顺序，正常组不应重复显示‘计划第 N 组’"
        )

        let sideControls = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "active-measurement-side-")
        )
        XCTAssertGreaterThan(sideControls.count, 0)
        let firstSideControl = sideControls.firstMatch
        XCTAssertTrue(firstSideControl.waitForExistence(timeout: 3))
        XCTAssertTrue(firstSideControl.buttons["单边"].exists)
        XCTAssertTrue(firstSideControl.buttons["双边"].exists)

        let rir = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "RIR，未记录")
        ).firstMatch
        XCTAssertTrue(rir.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(rir.frame.height, 44, "RIR 点击区域高度必须至少为 44pt")
        rir.tap()
        XCTAssertTrue(app.staticTexts["本组还剩多少余力？"].waitForExistence(timeout: 3))
        app.buttons["RIR 3 · 还能做 3 次"].tap()
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "RIR 3，还能做 3 次")
        ).firstMatch.waitForExistence(timeout: 3))
    }

    func testActiveWorkoutAcceptsThreeDecimalsAndCompactsCompletedSet() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(tap(app.buttons["开始训练"], until: app.staticTexts["训练进行中"]))

        let firstWeight = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "actual-weight-")
        ).firstMatch
        XCTAssertTrue(scrollUp(in: app, until: firstWeight, attempts: 5))
        firstWeight.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 3),
            "点按重量输入框后必须保持键盘焦点，不能因页面重排立即失焦"
        )
        let currentWeight = (firstWeight.value as? String) ?? ""
        firstWeight.typeText(
            String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentWeight.count)
        )
        firstWeight.typeText("8.875")
        XCTAssertEqual(firstWeight.value as? String, "8.875")

        app.swipeDown()
        let complete = app.buttons["完成第 1 组"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        let compact = app.buttons["第 1 组已完成"].firstMatch
        XCTAssertTrue(compact.waitForExistence(timeout: 5))
        XCTAssertTrue(compact.label.contains("8.875"))

        let nextSet = app.textFields.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                "actual-reps-",
                "-2"
            )
        ).firstMatch
        XCTAssertTrue(nextSet.waitForExistence(timeout: 3))
    }

    func testActionEditorPersistsSelectedMuscleGroup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        app.tabBars.buttons["训练"].tap()
        app.buttons["动作库入口"].tap()
        app.buttons["新建动作"].tap()

        let name = app.textFields["动作名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 肌群下拉测试")

        let muscleGroupPicker = app.descendants(matching: .any)["muscle-group-picker"]
        XCTAssertTrue(muscleGroupPicker.waitForExistence(timeout: 3))
        muscleGroupPicker.tap()
        for option in ["胸部", "背部", "肩部", "手臂", "腿部", "臀部", "小腿", "核心", "其他"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["muscle-group-option-\(option)"].exists,
                "目标肌群菜单应包含 \(option)"
            )
        }
        let glutesOption = app.descendants(matching: .any)["muscle-group-option-臀部"]
        XCTAssertTrue(glutesOption.waitForExistence(timeout: 3))
        glutesOption.tap()
        app.buttons["保存"].tap()

        let savedAction = app.staticTexts["UI 肌群下拉测试"]
        XCTAssertTrue(savedAction.waitForExistence(timeout: 5))
        savedAction.tap()
        XCTAssertTrue(app.navigationBars["编辑动作"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)["muscle-group-picker"].value as? String,
            "臀部"
        )
    }

    func testActionEditorPreservesCustomMuscleGroup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        app.tabBars.buttons["训练"].tap()
        app.buttons["动作库入口"].tap()
        app.buttons["新建动作"].tap()

        let name = app.textFields["动作名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 自定义肌群测试")

        let customMuscleGroup = app.textFields["custom-muscle-group-field"]
        XCTAssertTrue(customMuscleGroup.waitForExistence(timeout: 3))
        replaceText(in: customMuscleGroup, with: "有氧")
        app.buttons["保存"].tap()

        let savedAction = app.staticTexts["UI 自定义肌群测试"]
        XCTAssertTrue(savedAction.waitForExistence(timeout: 5))
        savedAction.tap()
        XCTAssertTrue(app.navigationBars["编辑动作"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)["muscle-group-picker"].value as? String,
            "其他"
        )
        XCTAssertEqual(
            app.textFields["custom-muscle-group-field"].value as? String,
            "有氧"
        )
    }

    func testActionEditorPersistsMeterVolumeUnit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        trainingTab.tap()

        let actionLibrary = app.buttons["动作库入口"]
        XCTAssertTrue(actionLibrary.waitForExistence(timeout: 5))
        actionLibrary.tap()

        let newAction = app.buttons["新建动作"]
        XCTAssertTrue(newAction.waitForExistence(timeout: 5))
        newAction.tap()
        XCTAssertTrue(app.navigationBars["新建动作"].waitForExistence(timeout: 5))

        let name = app.textFields["动作名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 单位测试跑")

        let unitPicker = app.descendants(matching: .any)["volume-unit-picker"]
        XCTAssertTrue(unitPicker.waitForExistence(timeout: 3))
        unitPicker.tap()
        let meterOption = app.descendants(matching: .any)["volume-unit-meter"]
        XCTAssertTrue(meterOption.waitForExistence(timeout: 3))
        meterOption.tap()
        app.buttons["保存"].tap()

        let savedAction = app.staticTexts["UI 单位测试跑"]
        XCTAssertTrue(savedAction.waitForExistence(timeout: 5))
        savedAction.tap()
        XCTAssertTrue(app.navigationBars["编辑动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["volume-unit-picker"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["米（距离）"].exists)
    }

    func testActionEditorPersistsBodyweightVolumeUnit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        app.tabBars.buttons["训练"].tap()
        app.buttons["动作库入口"].tap()
        app.buttons["新建动作"].tap()

        let name = app.textFields["动作名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 自重动作")

        let unitPicker = app.descendants(matching: .any)["volume-unit-picker"]
        unitPicker.tap()
        let bodyweight = app.descendants(matching: .any)["volume-unit-bodyweight"]
        XCTAssertTrue(bodyweight.waitForExistence(timeout: 3))
        bodyweight.tap()
        app.buttons["保存"].tap()

        XCTAssertTrue(app.staticTexts["UI 自重动作"].waitForExistence(timeout: 5))
        app.staticTexts["UI 自重动作"].tap()
        XCTAssertTrue(app.staticTexts["自重（按次数）"].waitForExistence(timeout: 3))
    }

    func testTrainingOverviewOpensHistoryScheduleAndQuickSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        trainingTab.tap()

        XCTAssertTrue(app.staticTexts["本周进度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["训练记录入口"].exists)
        XCTAssertTrue(app.buttons["训练计划入口"].exists)
        XCTAssertTrue(app.buttons["今日编排入口"].exists)
        XCTAssertTrue(app.buttons["每周模板入口"].exists)
        XCTAssertTrue(app.buttons["动作库入口"].exists)

        app.buttons["训练记录入口"].tap()
        XCTAssertTrue(app.navigationBars["训练历史"].waitForExistence(timeout: 5))
        app.navigationBars["训练历史"].buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["训练计划入口"].waitForExistence(timeout: 5))
        app.buttons["训练计划入口"].tap()
        XCTAssertTrue(app.staticTexts["训练日程"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["每周模板入口"].waitForExistence(timeout: 5))
        app.buttons["每周模板入口"].tap()
        XCTAssertTrue(app.staticTexts["我的每周模板"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["动作库入口"].waitForExistence(timeout: 5))
        app.buttons["动作库入口"].tap()
        XCTAssertTrue(app.staticTexts["动作库"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["大肌群-胸部"].waitForExistence(timeout: 5))
        app.buttons["大肌群-胸部"].tap()
        XCTAssertTrue(app.buttons["小肌群-上胸"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["小肌群-中胸"].exists)

        app.buttons["小肌群-上胸"].tap()
        XCTAssertTrue(app.staticTexts["上斜哑铃卧推"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 个动作"].exists)
        XCTAssertFalse(app.staticTexts["杠铃卧推"].exists)
    }

    func testHistoricalWorkoutEntryIsReachableFromProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        app.tabBars.buttons["我的"].tap()
        let syncLink = app.buttons["历史同步"]
        XCTAssertTrue(scrollUp(in: app, until: syncLink))
        syncLink.tap()

        let backfillButton = app.buttons["逐场手动补录"]
        XCTAssertTrue(backfillButton.waitForExistence(timeout: 5))
        backfillButton.tap()
        XCTAssertTrue(app.navigationBars["补录过去训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["训练名称"].exists)
    }

    func testHistoricalWorkoutImportIsReachableFromProfile() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        app.tabBars.buttons["我的"].tap()
        let syncLink = app.buttons["历史同步"]
        XCTAssertTrue(scrollUp(in: app, until: syncLink))
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

    func testPerSetPyramidPlanSideModesAndLiveSetDelta() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let editPlan = app.buttons["修改今日计划"]
        XCTAssertTrue(editPlan.waitForExistence(timeout: 8))
        editPlan.tap()
        XCTAssertTrue(app.staticTexts["编排当天训练"].waitForExistence(timeout: 5))

        let pattern = app.segmentedControls["set-plan-pattern-杠铃卧推"]
        XCTAssertTrue(scrollUp(in: app, until: pattern, attempts: 10))
        XCTAssertTrue(pattern.buttons["固定重量"].exists)
        XCTAssertTrue(pattern.buttons["金字塔递增"].exists)
        XCTAssertTrue(pattern.buttons["金字塔递减"].exists)
        pattern.buttons["金字塔递增"].tap()

        let firstWeight = app.textFields["planned-weight-杠铃卧推-1"]
        let secondWeight = app.textFields["planned-weight-杠铃卧推-2"]
        let firstReps = app.textFields["planned-reps-杠铃卧推-1"]
        let secondReps = app.textFields["planned-reps-杠铃卧推-2"]
        XCTAssertTrue(firstWeight.waitForExistence(timeout: 3))
        XCTAssertEqual(firstWeight.value as? String, "40")
        XCTAssertEqual(secondWeight.value as? String, "42.5")
        XCTAssertEqual(firstReps.value as? String, "8")
        XCTAssertEqual(secondReps.value as? String, "6")

        let plannedMeasurementSide = app.segmentedControls["plan-measurement-side-杠铃卧推"]
        XCTAssertTrue(plannedMeasurementSide.waitForExistence(timeout: 3))
        plannedMeasurementSide.buttons["单边"].tap()

        let saveAndStart = app.buttons["保存并开始记录"]
        XCTAssertTrue(scrollUp(in: app, until: saveAndStart, attempts: 16))
        XCTAssertTrue(tap(saveAndStart, until: app.staticTexts["训练进行中"]))

        let planSummary = app.staticTexts["计划 3 组 · 金字塔递增"].firstMatch
        XCTAssertTrue(scrollDown(in: app, until: planSummary, attempts: 8))
        XCTAssertTrue(planSummary.exists)
        XCTAssertTrue(
            app.staticTexts["40 kg（单边） × 8（单边）"].firstMatch.waitForExistence(timeout: 3)
        )

        let adjustVolume = app.buttons["adjust-volume-杠铃卧推"]
        XCTAssertTrue(adjustVolume.waitForExistence(timeout: 3))
        adjustVolume.tap()
        app.buttons["增加一组"].tap()
        XCTAssertTrue(app.staticTexts["组数差 +1"].waitForExistence(timeout: 3))
        let extraSetLabel = app.staticTexts["加练"]
        XCTAssertTrue(scrollUp(in: app, until: extraSetLabel, attempts: 6))
        XCTAssertTrue(extraSetLabel.exists)

        XCTAssertTrue(scrollDown(in: app, until: adjustVolume, attempts: 6))
        adjustVolume.tap()
        app.buttons["减少最后未完成组"].tap()
        XCTAssertFalse(app.staticTexts["组数差 +1"].exists)

        adjustVolume.tap()
        app.buttons["减少最后未完成组"].tap()
        XCTAssertTrue(app.staticTexts["组数差 -1"].waitForExistence(timeout: 3))

        let actualMeasurementSide = app.segmentedControls["active-measurement-side-杠铃卧推"]
        XCTAssertTrue(scrollUp(in: app, until: actualMeasurementSide, attempts: 5))
        actualMeasurementSide.buttons["双边"].tap()
        XCTAssertTrue(
            app.staticTexts["40 kg（双边） × 8（双边）"].firstMatch.waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.staticTexts["40 kg（单边） × 8（单边）"].firstMatch.exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "逐组计划与实际差异"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testExerciseLibrarySearchesSquatAliasAndSupportsEditDeleteRestore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        app.tabBars.buttons["训练"].tap()
        let library = app.buttons["动作库入口"]
        XCTAssertTrue(library.waitForExistence(timeout: 6))
        library.tap()
        XCTAssertTrue(app.staticTexts["动作库"].firstMatch.waitForExistence(timeout: 5))

        let search = app.textFields["exercise-library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 4))
        search.tap()
        search.typeText("严格深蹲")

        let squatRow = app.staticTexts["exercise-name-深蹲"]
        XCTAssertTrue(squatRow.waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["严格深蹲"].exists)

        let menu = app.buttons["exercise-menu-深蹲"]
        XCTAssertTrue(menu.waitForExistence(timeout: 4))
        menu.tap()
        XCTAssertTrue(app.buttons["编辑动作"].exists)
        XCTAssertTrue(app.buttons["删除动作"].exists)
        app.buttons["编辑动作"].tap()
        let nameField = app.textFields["动作名称"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 4))
        XCTAssertEqual(nameField.value as? String, "深蹲")
        app.buttons["取消"].tap()

        XCTAssertTrue(menu.waitForExistence(timeout: 4))
        menu.tap()
        app.buttons["删除动作"].tap()

        let alert = app.alerts["删除这个动作？"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "历史训练记录仍会完整保留")
        ).firstMatch.exists)
        alert.buttons["删除"].tap()
        XCTAssertFalse(squatRow.waitForExistence(timeout: 2))

        let archived = app.buttons["查看已归档动作"]
        XCTAssertTrue(archived.waitForExistence(timeout: 4))
        archived.tap()
        let archivedSquat = app.staticTexts["exercise-name-深蹲"]
        XCTAssertTrue(archivedSquat.waitForExistence(timeout: 4))
        app.buttons["exercise-menu-深蹲"].tap()
        app.buttons["恢复动作"].tap()
        XCTAssertFalse(archivedSquat.waitForExistence(timeout: 2))

        app.buttons["返回可用动作"].tap()
        XCTAssertTrue(
            app.staticTexts["exercise-name-深蹲"].waitForExistence(timeout: 4)
        )
    }
}
