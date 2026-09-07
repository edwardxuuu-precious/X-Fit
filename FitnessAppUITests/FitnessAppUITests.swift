import UIKit
import XCTest

final class FitnessAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func openTrainingRoot(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["训练"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        let week = app.descendants(matching: .any)["训练周历"]
        for _ in 0..<6 {
            if week.exists {
                XCTAssertTrue(scrollDown(in: app, until: week, attempts: 8))
                return
            }
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
        }
        XCTAssertTrue(week.waitForExistence(timeout: 5), "未返回训练根页面；不能把切换同一 Tab 当成返回根页面")
    }

    private func openTrainingManagement(in app: XCUIApplication) {
        openTrainingRoot(in: app)
        let entry = app.buttons["训练计划与动作库"]
        XCTAssertTrue(scrollUp(in: app, until: entry, attempts: 8))
        entry.tap()
        XCTAssertTrue(app.buttons["今日编排入口"].waitForExistence(timeout: 5))
    }

    private func openProfileRoot(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["我的"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        let settings = app.buttons["打开设置"]
        for _ in 0..<6 {
            if settings.exists { return }
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }

    private func openGoalRoot(in app: XCUIApplication) {
        let tab = app.tabBars.buttons["目标"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        let feeling = app.buttons["目标-记录体感"]
        for _ in 0..<6 {
            if feeling.exists {
                XCTAssertTrue(scrollDown(in: app, until: feeling, attempts: 8))
                return
            }
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
        }
        XCTAssertTrue(feeling.waitForExistence(timeout: 5))
    }

    private func openBodyCheckIn(in app: XCUIApplication) {
        openGoalRoot(in: app)
        let entry = app.buttons["目标-记录体感"]
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.navigationBars["今日体感"].waitForExistence(timeout: 5))
    }

    private func openBodyMeasurements(in app: XCUIApplication) {
        openProfileRoot(in: app)
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "身体数据")).firstMatch
        XCTAssertTrue(scrollUp(in: app, until: entry, attempts: 6))
        entry.tap()
        XCTAssertTrue(app.buttons["快速记录体重"].waitForExistence(timeout: 5))
    }

    private func openHistory(in app: XCUIApplication) {
        openProfileRoot(in: app)
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "训练历史")).firstMatch
        XCTAssertTrue(scrollUp(in: app, until: entry, attempts: 6))
        entry.tap()
        XCTAssertTrue(app.navigationBars["训练历史"].waitForExistence(timeout: 5))
    }

    private func openStats(in app: XCUIApplication) {
        openGoalRoot(in: app)
        let entry = app.buttons["查看已有训练趋势"]
        let activeEntry = app.buttons["目标-力量趋势"]
        // The routes differ with program presence, but neither route creates a program.
        for _ in 0..<8 {
            if entry.exists && entry.isHittable { entry.tap(); return }
            if activeEntry.exists && activeEntry.isHittable { activeEntry.tap(); return }
            app.swipeUp()
        }
        XCTFail("已有训练统计必须在有或没有减脂周期时均可达")
    }

    private func openTools(in app: XCUIApplication) {
        openProfileRoot(in: app)
        let entry = app.buttons["更多记录工具"]
        XCTAssertTrue(scrollUp(in: app, until: entry, attempts: 6))
        entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["工具中心"].waitForExistence(timeout: 5))
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
        attempts: Int = 4
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
            app.activate()
            Thread.sleep(forTimeInterval: 5)
        }
        return expectedElement().exists
    }

    private func tapRecoveringFromExternalInterruption(
        _ element: @autoclosure () -> XCUIElement,
        in app: XCUIApplication,
        untilElementDisappears disappearingElement: @autoclosure () -> XCUIElement,
        attempts: Int = 4
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
            app.activate()
            Thread.sleep(forTimeInterval: 5)
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
        if element.waitForExistence(timeout: 3), isVisibleInViewport(element, in: app) {
            return true
        }
        for _ in 0..<attempts {
            app.swipeUp()
            if element.waitForExistence(timeout: 2), isVisibleInViewport(element, in: app) {
                return true
            }
        }
        return isVisibleInViewport(element, in: app)
    }

    private func scrollDown(
        in app: XCUIApplication,
        until element: XCUIElement,
        attempts: Int = 3
    ) -> Bool {
        if element.waitForExistence(timeout: 3), isVisibleInViewport(element, in: app) {
            return true
        }
        for _ in 0..<attempts {
            app.swipeDown()
            if element.waitForExistence(timeout: 2), isVisibleInViewport(element, in: app) {
                return true
            }
        }
        return isVisibleInViewport(element, in: app)
    }

    private func isVisibleInViewport(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && app.frame.intersects(element.frame)
    }

    private func clockSeconds(_ label: String) -> Int? {
        let components = label.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        return components[0] * 60 + components[1]
    }

    private func revealAboveBottomNavigation(_ element: XCUIElement, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<5 {
            if element.exists && element.isHittable && element.frame.maxY < tabBar.frame.minY { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertLessThan(element.frame.maxY, tabBar.frame.minY)
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
                cleanupApp.tabBars.buttons["训练"].waitForExistence(timeout: 8),
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
        additionalArguments: [String] = [],
        enterEditing: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + additionalArguments
        app.launch()
        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        let builder = app.buttons["今日编排入口"]
        openTrainingManagement(in: app)
        XCTAssertTrue(builder.exists)
        XCTAssertTrue(tap(builder, until: app.navigationBars["当天训练"]))
        if enterEditing {
            let adjust = app.buttons["调整计划"]
            XCTAssertTrue(adjust.waitForExistence(timeout: 5))
            adjust.tap()
            app.buttons["选好部位，继续"].tap()
            XCTAssertTrue(app.buttons["当天菜单添加动作"].waitForExistence(timeout: 5))
        }
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

        openBodyCheckIn(in: app)
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

        openBodyCheckIn(in: app)
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

        openBodyCheckIn(in: app)

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
        XCTAssertTrue(tapRecoveringFromExternalInterruption(
            save, in: app,
            untilElementDisappears: app.navigationBars["今日体感"]
        ))
        let savedSummary = app.staticTexts["状态一般 · 1 处不适"]
        XCTAssertTrue(scrollUp(in: app, until: savedSummary, attempts: 6))
        XCTAssertTrue(savedSummary.waitForExistence(timeout: 5))

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

        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(resume, until: app.buttons["临时加动作"]))
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
            app.buttons["切换动作-杠铃卧推"].exists,
            "选择或跳过感受前当前动作不应自动折叠"
        )
        for feeling in ["painful", "exhausted", "hard", "good", "strong"] {
            XCTAssertTrue(app.buttons["动作感受-\(feeling)"].exists)
        }
        let strong = app.buttons["动作感受-strong"]
        strong.tap()
        let completedExercise = app.buttons["切换动作-杠铃卧推"]
        XCTAssertTrue(completedExercise.waitForExistence(timeout: 5))
        XCTAssertTrue(completedExercise.label.contains("😄"))

        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-body-feedback"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["继续训练"].waitForExistence(timeout: 8))
        app.buttons["继续训练"].tap()
        XCTAssertTrue(app.staticTexts["训练进行中"].waitForExistence(timeout: 5))
        let restoredCompletedExercise = app.buttons["切换动作-杠铃卧推"]
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
        XCTAssertTrue(app.buttons["临时加动作"].exists)
        XCTAssertFalse(app.staticTexts["按今天状态调整训练量"].exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "adjust-volume-")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "计划默认组间休息")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "训练量单位：")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "与计划：")).firstMatch.exists)

        let details = app.buttons["RIR、动作资料与备注"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: details, attempts: 4))
        details.tap()
        let rirHelpButton = app.buttons["了解 RIR"].firstMatch
        XCTAssertTrue(scrollDown(in: app, until: rirHelpButton, attempts: 4))
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

        XCTAssertFalse(app.staticTexts["组间休息"].exists)
        XCTAssertFalse(app.staticTexts["rest-timer-value"].exists)

        XCTAssertTrue(app.staticTexts["1/12 组"].exists)

        let restTimerScreenshot = XCTAttachment(screenshot: app.screenshot())
        restTimerScreenshot.name = "训练页精简后"
        restTimerScreenshot.lifetime = .keepAlways
        add(restTimerScreenshot)
    }

    func testActiveWorkoutTopMenuRemovesZeroCompletedExerciseAndPersistsAfterRelaunch() throws {
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
        XCTAssertTrue(app.staticTexts["0/12 组"].waitForExistence(timeout: 5))

        let adjustMenu = app.buttons["调整今日菜单"]
        XCTAssertTrue(adjustMenu.waitForExistence(timeout: 5))
        adjustMenu.tap()
        XCTAssertTrue(app.navigationBars["当天训练"].waitForExistence(timeout: 5))

        app.buttons["重新编排"].tap()
        app.buttons["选好部位，继续"].tap()
        app.buttons["动作菜单-杠铃卧推"].tap()
        app.buttons["删除动作"].tap()
        app.buttons["选好动作，继续"].tap()
        let save = app.buttons["保存当前训练"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let saved = app.alerts["训练安排已保存"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(saved.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "进行中的训练安排已同步")
        ).firstMatch.exists)
        saved.buttons["知道了"].tap()
        app.navigationBars["当天训练"].buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.staticTexts["0/9 组"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["杠铃卧推"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent"]
        app.launch()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        resume.tap()
        XCTAssertTrue(app.staticTexts["0/9 组"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["杠铃卧推"].exists)
    }

    func testInProgressWorkoutUsesOneReplanEntryAndPreservesCurrentPlan() throws {
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
        let firstSet = app.buttons["完成第 1 组"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: firstSet, attempts: 4))
        firstSet.tap()
        XCTAssertTrue(app.staticTexts["1/12 组"].waitForExistence(timeout: 5))

        let adjustMenu = app.buttons["调整今日菜单"]
        XCTAssertTrue(adjustMenu.waitForExistence(timeout: 5))
        adjustMenu.tap()
        XCTAssertTrue(app.navigationBars["当天训练"].waitForExistence(timeout: 5))

        let replan = app.buttons["重新编排"]
        XCTAssertTrue(replan.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["调整当前训练"].exists)
        XCTAssertFalse(app.buttons["重新编排当前训练"].exists)
        replan.tap()

        XCTAssertTrue(app.staticTexts["训练部位"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["清空后重新编排"].exists)
        let chest = app.buttons["胸部"]
        XCTAssertTrue(scrollUp(in: app, until: chest, attempts: 4))
        XCTAssertEqual(chest.value as? String, "已选择")

        app.buttons["选好部位，继续"].tap()
        XCTAssertTrue(app.staticTexts["杠铃卧推"].waitForExistence(timeout: 5))
        app.buttons["选好动作，继续"].tap()
        app.buttons["保存当前训练"].tap()

        let saved = app.alerts["训练安排已保存"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.buttons["知道了"].tap()
        app.navigationBars["当天训练"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["1/12 组"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent"]
        app.launch()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        resume.tap()
        XCTAssertTrue(app.staticTexts["1/12 组"].waitForExistence(timeout: 5))
    }

    func testFreestyleRestEndsWhenNextSetStarts() throws {
        try XCTSkipIf(true, "组间休息功能已按已确认需求移除")
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
        try XCTSkipIf(true, "组间休息功能已按已确认需求移除")
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
        try XCTSkipIf(true, "组间休息功能已按已确认需求移除")
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
        try XCTSkipIf(true, "组间休息功能已按已确认需求移除")
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

        let resume = app.buttons["继续训练"]
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

    func testHistoricalEditingDoesNotOfferLegacyRestInput() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-history"]
        app.launch()

        let fixtureCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "历史详情验证")
        ).firstMatch
        XCTAssertTrue(fixtureCard.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(fixtureCard, until: app.navigationBars["历史详情验证"]))
        XCTAssertTrue(tapRecoveringFromExternalInterruption(
            app.buttons["编辑历史"],
            in: app,
            until: app.navigationBars["编辑历史训练"]
        ))

        XCTAssertFalse(app.textFields["历史编辑第 1 组休息秒数"].exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "休息")
        ).firstMatch.exists)
    }

    func testCountdownRestDeliversOneBackgroundNotification() throws {
        try XCTSkipIf(true, "组间休息通知已按已确认需求移除")
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
        try XCTSkipIf(true, "组间休息功能已按已确认需求移除")
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

        let training = app.tabBars.buttons["训练"]
        XCTAssertTrue(training.waitForExistence(timeout: 8))
        XCTAssertEqual(app.tabBars.buttons.allElementsBoundByIndex.map(\.label), ["训练", "饮食", "目标", "我的"])
        XCTAssertTrue(training.isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["训练周历"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["训练-今日安排"].exists)
        let start = app.buttons["开始记录训练"]
        XCTAssertTrue(start.isHittable, "默认训练首屏必须能开始记录")
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        XCTAssertFalse(app.otherElements["今日训练海报"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["首页体重卡片"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["首页体感卡片"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["最近训练容量图"].exists)
        let management = app.buttons["训练计划与动作库"]
        for _ in 0..<6 {
            if management.exists && management.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(management.isHittable)
    }

    func testHomeQuickWeightEntryProgressivelyRevealsFieldsAndDismissesKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-progress"]
        app.launch()

        openBodyMeasurements(in: app)
        let quickEntry = app.buttons["快速记录体重"]
        XCTAssertTrue(quickEntry.waitForExistence(timeout: 5))
        quickEntry.tap()
        XCTAssertTrue(app.navigationBars["快速记录体重"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["快速腰围输入"].exists)

        let weight = app.textFields["快速体重输入"]
        XCTAssertTrue(weight.waitForExistence(timeout: 3))
        replaceText(in: weight, with: "84.2")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        let done = app.toolbars.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        app.buttons["展开更多身体数据"].tap()
        XCTAssertTrue(app.otherElements["更多身体数据表单"].waitForExistence(timeout: 3))

        weight.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let quickEntryScroll = app.scrollViews["quick-body-weight-scroll"]
        XCTAssertTrue(quickEntryScroll.waitForExistence(timeout: 3))
        // Stay in the visible content above the software keyboard. A gesture
        // starting near the bottom of the ScrollView is delivered to the
        // keyboard itself on a physical iPhone, not to the app's ScrollView.
        let dragStart = quickEntryScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let dragEnd = quickEntryScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 2))

        weight.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        app.staticTexts["今天体重"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        let saveWeight = app.buttons["保存体重"]
        XCTAssertTrue(scrollUp(in: app, until: saveWeight, attempts: 3))
        saveWeight.tap()

        XCTAssertTrue(app.staticTexts["84.2 kg"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["身体数据最新摘要"].exists)
        XCTAssertTrue(app.buttons["快速记录体重"].exists)
    }

    func testStatsBodySegmentShowsTrendDirectly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-progress"]
        app.launch()

        let progressTab = app.tabBars.buttons["目标"]
        XCTAssertTrue(progressTab.waitForExistence(timeout: 8))
        openStats(in: app)
        let bodySegment = app.buttons["身体数据"]
        XCTAssertTrue(bodySegment.waitForExistence(timeout: 5))
        bodySegment.tap()

        let trend = app.otherElements["身体数据趋势卡片"]
        XCTAssertTrue(scrollUp(in: app, until: trend, attempts: 4))
        XCTAssertTrue(app.staticTexts["7 日均线"].exists)
        XCTAssertTrue(scrollUp(in: app, until: app.staticTexts["查看完整记录"], attempts: 3))
        XCTAssertFalse(app.staticTexts["打开身体记录"].exists)
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
        XCTAssertTrue(app.buttons["开始记录训练"].exists)
        let editPlan = app.buttons["修改今日计划"]
        XCTAssertTrue(editPlan.waitForExistence(timeout: 8))
        XCTAssertEqual(editPlan.label, "调整")
        XCTAssertTrue(app.staticTexts["推 · 胸肩三头"].firstMatch.exists)
        // AX geometry can report 44 pt as 43.99999999999997 after layout.
        XCTAssertGreaterThanOrEqual(editPlan.frame.width + 0.000001, 44)
        XCTAssertGreaterThanOrEqual(editPlan.frame.height + 0.000001, 44)
        editPlan.tap()
        XCTAssertTrue(app.navigationBars["当天训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["今日计划摘要"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["开始训练"].exists)
        XCTAssertTrue(app.buttons["调整计划"].exists)
        XCTAssertFalse(app.textFields["planned-weight-杠铃卧推-1"].exists)
    }

    func testExistingDailyPlanReplanningStartsAtMusclesAndPreservesCurrentPlan() throws {
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
        XCTAssertTrue(app.navigationBars["当天训练"].waitForExistence(timeout: 5))

        let replan = app.buttons["调整计划"]
        XCTAssertTrue(replan.waitForExistence(timeout: 5))
        XCTAssertEqual(replan.label, "重新编排")
        replan.tap()
        XCTAssertTrue(app.staticTexts["训练部位"].waitForExistence(timeout: 5))

        XCTAssertFalse(app.buttons["清空后重新编排"].exists)
        let chest = app.buttons["胸部"]
        XCTAssertTrue(scrollUp(in: app, until: chest, attempts: 4))
        XCTAssertEqual(chest.value as? String, "已选择")
        app.buttons["取消重新编排"].tap()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 5))

        app.buttons["调整计划"].tap()
        XCTAssertTrue(scrollUp(in: app, until: chest, attempts: 4))
        XCTAssertEqual(chest.value as? String, "已选择")

        app.buttons["选好部位，继续"].tap()
        XCTAssertTrue(app.staticTexts["杠铃卧推"].waitForExistence(timeout: 5))
        app.buttons["选好动作，继续"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["今日计划摘要"].waitForExistence(timeout: 5))
        app.buttons["保存今日计划"].tap()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 8))

        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent"]
        app.launch()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 8))
    }

    func testHomeMenuUsesSlashTitleAndReadyStatusIcon() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-menu-status"]
        app.launch()

        XCTAssertTrue(app.staticTexts["今日训练"].waitForExistence(timeout: 8))
        // The redesign displays the saved title; presentation must not rewrite the stored name.
        XCTAssertTrue(app.staticTexts["核心 + 腿部 · 当天菜单"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["训练-今日安排"].exists)
        XCTAssertTrue(app.buttons["开始记录训练"].isHittable)
        XCTAssertTrue(app.buttons["修改今日计划"].exists)
    }

    func testHomeShowsOnlyTheLatestCompletedWorkout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-progress"]
        app.launch()
        openHistory(in: app)

        let latest = app.staticTexts["本周拉训练"]
        XCTAssertTrue(latest.waitForExistence(timeout: 5))
        XCTAssertTrue(latest.isHittable)
        latest.tap()
        XCTAssertTrue(app.navigationBars["本周拉训练"].waitForExistence(timeout: 5))
    }

    func testHomeEmptyStateOffersPlanAndHistoricalEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-empty"]
        app.launch()

        XCTAssertTrue(app.staticTexts["还没有训练安排"].waitForExistence(timeout: 8))
        let arrange = app.buttons["安排今天训练"]
        XCTAssertTrue(arrange.isHittable)
        arrange.tap()
        XCTAssertTrue(app.navigationBars["当天训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["编排步骤-1"].exists)
        openHistory(in: app)
        XCTAssertTrue(app.staticTexts["还没有完成的训练"].waitForExistence(timeout: 5))
        app.navigationBars["训练历史"].buttons["补录"].tap()
        XCTAssertTrue(app.navigationBars["补录过去训练"].waitForExistence(timeout: 5))
    }

    func testHomeSingleCompletedWorkoutShowsOneRecentEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-single-volume"]
        app.launch()
        openHistory(in: app)

        let record = app.staticTexts["首页容量夹具 0"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "首页容量夹具 ")).count, 1)
        record.tap()
        XCTAssertTrue(app.navigationBars["首页容量夹具 0"].waitForExistence(timeout: 5))
    }

    func testHomeWithManyCompletedWorkoutsStillShowsOneRecentEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-seven-volumes"]
        app.launch()
        openHistory(in: app)

        let newest = app.staticTexts["首页容量夹具 0"]
        let next = app.staticTexts["首页容量夹具 1"]
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        XCTAssertTrue(next.exists)
        XCTAssertLessThan(newest.frame.minY, next.frame.minY)
        for index in 0..<7 {
            let record = app.staticTexts["首页容量夹具 \(index)"]
            XCTAssertTrue(scrollUp(in: app, until: record, attempts: 5), "第 \(index) 场历史必须可达")
        }
        app.staticTexts["首页容量夹具 6"].tap()
        XCTAssertTrue(app.navigationBars["首页容量夹具 6"].waitForExistence(timeout: 5))
    }

    func testHomeCompletedPlanOffersRecordEditingWithoutStartButton() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-completed", "--ui-testing-home-menu-status"]
        app.launch()

        XCTAssertTrue(app.staticTexts["今日训练"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["核心 + 腿部 · 当天菜单"].firstMatch.exists)
        XCTAssertTrue(app.buttons["查看训练记录"].exists)
        XCTAssertTrue(app.buttons["修改今日记录"].exists)
        XCTAssertFalse(app.buttons["开始记录训练"].exists)
        XCTAssertFalse(app.buttons["修改今日计划"].exists)
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
        let resume = app.buttons["继续训练"]
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
        XCTAssertTrue(app.navigationBars["当天训练"].waitForExistence(timeout: 5))

        app.buttons["调整计划"].tap()
        app.buttons["选好部位，继续"].tap()
        let benchMenu = app.buttons["动作菜单-杠铃卧推"]
        XCTAssertTrue(scrollUp(in: app, until: benchMenu, attempts: 8))
        benchMenu.tap()
        app.buttons["单独调整"].tap()

        let weight = app.textFields["planned-weight-杠铃卧推-1"]
        XCTAssertTrue(scrollUp(in: app, until: weight, attempts: 12))
        replaceText(in: weight, with: "55.5")
        app.navigationBars["单独调整"].buttons["完成"].tap()
        app.buttons["选好动作，继续"].tap()
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
        XCTAssertTrue(app.navigationBars["当天训练"].waitForExistence(timeout: 5))
        app.buttons["调整计划"].tap()
        app.buttons["选好部位，继续"].tap()
        let relaunchedBenchMenu = app.buttons["动作菜单-杠铃卧推"]
        XCTAssertTrue(scrollUp(in: app, until: relaunchedBenchMenu, attempts: 8))
        relaunchedBenchMenu.tap()
        app.buttons["单独调整"].tap()
        let relaunchedWeight = app.textFields["planned-weight-杠铃卧推-1"]
        XCTAssertTrue(scrollUp(in: app, until: relaunchedWeight, attempts: 12))
        XCTAssertEqual(relaunchedWeight.value as? String, "55.5")
    }

    func testStatsVolumeTrendSwitchesFromOverallToExerciseHistory() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-progress"]
        app.launch()

        let progressTab = app.tabBars.buttons["目标"]
        XCTAssertTrue(progressTab.waitForExistence(timeout: 8))
        openStats(in: app)

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
        app.buttons["设置-数据"].tap()
        XCTAssertTrue(app.buttons["设置-生成备份"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["设置-导入备份"].exists)
        let explanation = app.buttons["设置-备份说明"]
        revealAboveBottomNavigation(explanation, in: app)
        explanation.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "相同 UUID 的现有记录会跳过")).firstMatch.exists)
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

        let row = app.buttons["terminology-row-MTS 下斜卧推"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 3))
        row.tap()
        XCTAssertTrue(app.staticTexts["MTS 下斜卧推"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hammer Strength MTS Iso-Lateral 下斜推胸"].exists)

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
        revealAboveBottomNavigation(reset, in: app)
        XCTAssertGreaterThanOrEqual(reset.frame.height + 0.000001, 44)
        reset.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
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
        let reviewExerciseName = "MTS 划船"
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-persistent",
            "--ui-testing-reset-store",
            "--ui-testing-terminology"
        ]
        app.launch()
        openTerminologyReview(in: app)

        var row = app.buttons["terminology-row-\(reviewExerciseName)"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 4))
        row.tap()
        let completedSetRow = app.descendants(matching: .any)["terminology-completed-set-row"]
        XCTAssertTrue(completedSetRow.waitForExistence(timeout: 5))
        XCTAssertTrue(completedSetRow.label.contains("0"))

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
        row = app.buttons["terminology-row-\(reviewExerciseName)"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 4))
        row.tap()
        XCTAssertTrue(app.staticTexts["已接受候选"].waitForExistence(timeout: 5))

        let reset = app.buttons["terminology-reset-button"]
        revealAboveBottomNavigation(reset, in: app)
        reset.tap()
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
        row = app.buttons["terminology-row-\(reviewExerciseName)"]
        XCTAssertTrue(scrollUp(in: app, until: row, attempts: 4))
        row.tap()
        XCTAssertTrue(app.buttons["terminology-accept-button"].waitForExistence(timeout: 5))

        let reject = app.buttons["terminology-reject-button"]
        revealAboveBottomNavigation(reject, in: app)
        XCTAssertGreaterThanOrEqual(reject.frame.height + 0.000001, 44)
        reject.tap()
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
        row = app.buttons["terminology-row-\(reviewExerciseName)"]
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
        XCTAssertTrue(historyCard.label.contains("3 工作组"))
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
        app.launchArguments = ["--ui-testing", "--ui-testing-home-empty"]
        app.launch()

        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        openTrainingManagement(in: app)

        let dailyBuilder = app.buttons["今日编排入口"]
        XCTAssertTrue(dailyBuilder.waitForExistence(timeout: 5))
        XCTAssertTrue(tap(dailyBuilder, until: app.navigationBars["当天训练"]))
        let chestButton = app.buttons["胸部"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: chestButton, attempts: 4))
        if !app.buttons["选好部位，继续"].isEnabled {
            chestButton.tap()
        }

        let next = app.buttons["选好部位，继续"]
        XCTAssertTrue(scrollDown(in: app, until: next, attempts: 8))
        XCTAssertTrue(next.isEnabled)
        next.tap()
        XCTAssertTrue(app.buttons["编排步骤-2"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUp(in: app, until: app.staticTexts["推荐动作"], attempts: 6))
        XCTAssertTrue(app.staticTexts["推荐动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["换一组"].exists)
        XCTAssertTrue(app.staticTexts["杠铃 · 胸部"].exists)
        XCTAssertTrue(app.staticTexts["哑铃 · 胸部"].exists)
        let recommendation = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "推荐动作-")
        ).firstMatch
        XCTAssertTrue(recommendation.exists)
        recommendation.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "推荐详情-")
        ).firstMatch.waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.tabBars.buttons["训练"].waitForExistence(timeout: 8))
        XCTAssertFalse(received.waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments.append("--ui-testing-seed-share-draft")
        app.launch()
        XCTAssertTrue(received.waitForExistence(timeout: 8), "新 ID 的分享草稿必须重新提醒")
    }

    func testDailyBuilderShowsSummaryFirstExpandsOneExerciseAndReordersFromHandle() throws {
        let app = launchAndOpenDailyBuilder(enterEditing: false)

        XCTAssertTrue(app.descendants(matching: .any)["今日计划摘要"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["planned-weight-杠铃卧推-1"].exists)

        let expandBench = app.buttons["展开动作-杠铃卧推"]
        XCTAssertTrue(expandBench.waitForExistence(timeout: 5))
        expandBench.tap()
        XCTAssertTrue(app.staticTexts["逐组详情"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["planned-weight-杠铃卧推-1"].exists)
        XCTAssertTrue(app.buttons["动作菜单-杠铃卧推"].exists)
        expandBench.tap()

        let first = app.buttons["展开动作-杠铃卧推"]
        let second = app.buttons["展开动作-上斜哑铃卧推"]
        let firstHandle = app.descendants(matching: .any)["排序把手-杠铃卧推"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(firstHandle.waitForExistence(timeout: 5))

        let dragStart = firstHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let dragEnd = dragStart.withOffset(CGVector(dx: 0, dy: 90))
        dragStart.press(forDuration: 0.8, thenDragTo: dragEnd)
        XCTAssertTrue(app.buttons["展开动作-上斜哑铃卧推"].waitForExistence(timeout: 5))
        XCTAssertLessThan(
            app.buttons["展开动作-上斜哑铃卧推"].frame.minY,
            app.buttons["展开动作-杠铃卧推"].frame.minY
        )

        app.navigationBars["当天训练"].buttons.firstMatch.tap()
        XCTAssertTrue(tap(app.buttons["今日编排入口"], until: app.navigationBars["当天训练"]))
        XCTAssertLessThan(
            app.buttons["展开动作-上斜哑铃卧推"].frame.minY,
            app.buttons["展开动作-杠铃卧推"].frame.minY,
            "排序把手拖动后的顺序应在重新打开后保持"
        )
    }

    func testDailyBuilderScrollsWhenSwipeStartsOnExerciseCard() throws {
        let app = launchAndOpenDailyBuilder(enterEditing: false)
        let first = app.buttons["展开动作-杠铃卧推"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)

        let initialY = first.frame.minY
        first.swipeUp()

        XCTAssertLessThan(
            first.frame.minY,
            initialY - 20,
            "从动作卡片起手上滑时，动作列表必须继续滚动"
        )
    }

    func testDailyBuilderDraftUnlocksMusclesExercisesThenReview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-home-empty"]
        app.launch()

        openTrainingManagement(in: app)
        XCTAssertTrue(tap(app.buttons["今日编排入口"], until: app.navigationBars["当天训练"]))
        XCTAssertTrue(app.buttons["编排步骤-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["编排步骤-2"].exists)
        let nextMuscles = app.buttons["选好部位，继续"]
        XCTAssertTrue(nextMuscles.exists)
        XCTAssertFalse(nextMuscles.isEnabled)

        app.buttons["编排步骤-1"].tap()
        let chest = app.buttons["胸部"].firstMatch
        XCTAssertTrue(chest.waitForExistence(timeout: 3))
        chest.tap()
        XCTAssertTrue(nextMuscles.isEnabled)
        nextMuscles.tap()
        XCTAssertTrue(app.buttons["编排步骤-2"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["编排步骤-3"].exists)

        let bench = app.buttons["推荐动作-杠铃卧推"]
        XCTAssertTrue(scrollUp(in: app, until: bench, attempts: 8))
        bench.tap()
        XCTAssertTrue(app.descendants(matching: .any)["推荐详情-杠铃卧推"].waitForExistence(timeout: 3))
        app.buttons["加入今日动作"].firstMatch.tap()
        let nextExercises = app.buttons["选好动作，继续"]
        XCTAssertTrue(scrollDown(in: app, until: nextExercises, attempts: 10))
        XCTAssertTrue(nextExercises.isEnabled)
        nextExercises.tap()

        XCTAssertTrue(app.buttons["编排步骤-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["今日训练方式"].exists)
        XCTAssertFalse(app.staticTexts["固定重量"].exists)
        XCTAssertFalse(app.staticTexts["金字塔递增"].exists)
        XCTAssertFalse(app.staticTexts["金字塔递减"].exists)
        XCTAssertFalse(app.staticTexts["混合方式"].exists)
        XCTAssertTrue(app.buttons["保存并开始记录"].exists)
        XCTAssertTrue(app.buttons["保存计划，稍后记录"].exists)
    }

    func testDailyBuilderEditsSetsDirectlyWithoutPatternOptions() throws {
        let app = launchAndOpenDailyBuilder()

        app.buttons["动作菜单-杠铃卧推"].tap()
        app.buttons["单独调整"].tap()
        XCTAssertTrue(app.navigationBars["单独调整"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.segmentedControls["set-plan-pattern-杠铃卧推"].exists)
        XCTAssertFalse(app.buttons["固定重量"].exists)
        XCTAssertFalse(app.buttons["金字塔递增"].exists)
        XCTAssertFalse(app.buttons["金字塔递减"].exists)

        let firstWeight = app.textFields["planned-weight-杠铃卧推-1"]
        XCTAssertTrue(scrollUp(in: app, until: firstWeight, attempts: 8))
        replaceText(in: firstWeight, with: "47.5")
        XCTAssertEqual(firstWeight.value as? String, "47.5")
        XCTAssertTrue(app.steppers.firstMatch.exists)
        XCTAssertTrue(app.buttons["完成"].exists)
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

        XCTAssertTrue(productionApp.tabBars.buttons["训练"].waitForExistence(timeout: 8))
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
        XCTAssertTrue(saveError.waitForNonExistence(timeout: 3))
        XCTAssertTrue(tapRecoveringFromExternalInterruption(
            app.navigationBars["新建动作"].buttons["取消"], in: app,
            untilElementDisappears: app.navigationBars["新建动作"]
        ))
        let recheck = app.buttons["重新检查分享草稿"]
        XCTAssertTrue(scrollUp(in: app, until: recheck, attempts: 6))
        XCTAssertTrue(tapRecoveringFromExternalInterruption(recheck, in: app, until: received))
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
        XCTAssertTrue(app.tabBars.buttons["训练"].waitForExistence(timeout: 5))

        app.buttons["重新检查分享草稿"].tap()
        XCTAssertFalse(received.waitForExistence(timeout: 3))
    }

    func testShareDraftAcceptsPastedRednoteTextAsReferenceURL() throws {
        let app = launchSeededShareDraftApp()
        let received = app.staticTexts["已收到一份动作资料"]
        XCTAssertTrue(received.waitForExistence(timeout: 8))
        app.buttons["补充信息并加入动作库"].tap()

        let urlField = app.textFields["参考链接（可选）"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 4))
        replaceText(
            in: urlField,
            with: "爆发力遇到了瓶颈期？试试这4个等长训练！ [https://xhslink.cn/o/39wxGiDcs6G](https://xhslink.cn/o/39wxGiDcs6G) Copy and open rednote to view the note"
        )

        XCTAssertTrue(
            tapRecoveringFromExternalInterruption(
                app.navigationBars["新建动作"].buttons["保存"],
                in: app,
                until: app.tabBars.buttons["训练"]
            )
        )
        XCTAssertFalse(app.alerts["保存失败"].exists)
    }

    func testDailyBuilderPickerCancellationPreservesDraftMenuAndParameters() throws {
        executionTimeAllowance = 120
        let app = launchAndOpenDailyBuilder()
        XCTAssertTrue(app.staticTexts["4 个动作"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["展开动作-杠铃卧推"].exists)

        app.buttons["动作菜单-杠铃卧推"].tap()
        app.buttons["单独调整"].tap()
        let firstWeight = app.textFields["planned-weight-杠铃卧推-1"]
        XCTAssertTrue(scrollUp(in: app, until: firstWeight, attempts: 10))
        let originalWeight = firstWeight.value as? String
        app.navigationBars["单独调整"].buttons["完成"].tap()

        let add = app.buttons["当天菜单添加动作"]
        XCTAssertTrue(scrollDown(in: app, until: add, attempts: 12))
        add.tap()
        let pickerBar = app.navigationBars["添加训练动作"]
        XCTAssertTrue(pickerBar.waitForExistence(timeout: 5))
        pickerBar.buttons["取消"].tap()

        let actionCount = app.staticTexts["4 个动作"].firstMatch
        XCTAssertTrue(scrollDown(in: app, until: actionCount, attempts: 12))
        XCTAssertTrue(app.buttons["展开动作-杠铃卧推"].exists)
        XCTAssertTrue(app.buttons["展开动作-绳索下压"].exists)
        app.buttons["动作菜单-杠铃卧推"].tap()
        app.buttons["单独调整"].tap()
        XCTAssertTrue(scrollUp(in: app, until: firstWeight, attempts: 10))
        XCTAssertEqual(firstWeight.value as? String, originalWeight)
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
        XCTAssertFalse(app.buttons["展开动作-UI 取消新建动作"].exists)
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
        XCTAssertTrue(scrollUp(in: app, until: app.buttons["展开动作-深蹲"], attempts: 8))
    }

    func testExercisePickerDismissesKeyboardAndEditsBuiltInDefinitionWithoutSelecting() throws {
        let app = launchAndOpenDailyBuilder()
        app.buttons["当天菜单添加动作"].tap()

        let pickerBar = app.navigationBars["添加训练动作"]
        let search = app.searchFields.firstMatch
        XCTAssertTrue(pickerBar.waitForExistence(timeout: 5))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("深蹲")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let dismissKeyboard = app.buttons["动作搜索-收起键盘"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 3))
        dismissKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "深蹲")

        let definitionMenu = app.buttons["exercise-definition-menu-深蹲"]
        XCTAssertTrue(definitionMenu.waitForExistence(timeout: 5))
        definitionMenu.tap()
        let editDefinition = app.buttons["编辑动作定义"]
        XCTAssertTrue(editDefinition.waitForExistence(timeout: 3))
        editDefinition.tap()

        let editorBar = app.navigationBars["编辑动作"]
        let name = app.textFields["动作名称"]
        XCTAssertTrue(editorBar.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "深蹲")
        replaceText(in: name, with: "深蹲（已编辑）")
        editorBar.buttons["保存"].tap()

        XCTAssertFalse(app.navigationBars["本次设置"].exists)
        let updatedDefinitionMenu = app.buttons["exercise-definition-menu-深蹲（已编辑）"]
        XCTAssertTrue(updatedDefinitionMenu.waitForExistence(timeout: 5))
        let closeSearch = app.buttons["close"].firstMatch
        if closeSearch.exists {
            closeSearch.tap()
        }
        XCTAssertTrue(pickerBar.waitForExistence(timeout: 5))
        pickerBar.buttons["取消"].tap()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(tapRecoveringFromExternalInterruption(
            editorBar.buttons["保存"],
            in: app,
            until: app.navigationBars["本次设置"]
        ))
        app.buttons["使用上次设置"].tap()
        XCTAssertTrue(app.staticTexts["5 个动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollUp(in: app, until: app.buttons["展开动作-UI URL 修正动作"], attempts: 8))
    }

    func testDailyBuilderCoreControlsRemainReachableAtAccessibilityXXXL() throws {
        let app = launchAndOpenDailyBuilder(additionalArguments: [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ])
        let add = app.buttons["当天菜单添加动作"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isHittable)
        let firstAction = app.buttons["展开动作-杠铃卧推"]
        XCTAssertTrue(firstAction.exists)
        XCTAssertTrue(scrollDown(in: app, until: add, attempts: 14))
        add.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["添加训练动作"].buttons["新建动作"].exists)
        app.navigationBars["添加训练动作"].buttons["新建动作"].tap()
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

    func testExercisePickerRepeatedStressPreservesMenuAndAvoidsDuplicates() throws {
        executionTimeAllowance = 1_800
        let app = launchAndOpenDailyBuilder()
        XCTAssertTrue(app.staticTexts["4 个动作"].waitForExistence(timeout: 5))

        let cycleCount = ProcessInfo.processInfo.environment["XFIT_UI_STRESS_CYCLES"]
            .flatMap(Int.init) ?? 5
        XCTAssertTrue((1...50).contains(cycleCount), "压力循环次数必须在 1...50 之间")

        for cycle in 1...cycleCount {
            let add = app.buttons["当天菜单添加动作"]
            XCTAssertTrue(add.waitForExistence(timeout: 5), "第 \(cycle) 轮缺少添加入口")
            add.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5), "第 \(cycle) 轮选择器未打开")
            search.tap()
            search.typeText("UI 压力取消 \(cycle)")
            let create = app.buttons["新建并加入"]
            XCTAssertTrue(create.waitForExistence(timeout: 5), "第 \(cycle) 轮零结果入口缺失")
            let editorNavigationBar = app.navigationBars["新建动作"]
            XCTAssertTrue(
                tapRecoveringFromExternalInterruption(
                    create,
                    in: app,
                    until: editorNavigationBar
                ),
                "第 \(cycle) 轮无法打开新建动作页"
            )
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
        let addedSquat = app.buttons["展开动作-深蹲"]
        XCTAssertTrue(scrollUp(in: app, until: addedSquat, attempts: 8))
        XCTAssertEqual(app.buttons.matching(identifier: "展开动作-深蹲").count, 1)
    }

    func testDailyBuilderCanCreateMissingExerciseInline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openTrainingManagement(in: app)
        let dailyBuilder = app.buttons["今日编排入口"]
        XCTAssertTrue(dailyBuilder.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(dailyBuilder, until: app.navigationBars["当天训练"]))

        app.buttons["调整计划"].tap()
        app.buttons["选好部位，继续"].tap()
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
                until: app.buttons["展开动作-反向北欧弯举测试"],
                attempts: 5
            )
        )
    }

    func testEquipmentPhotoRecognitionShowsMachineMusclesAndAddsConfirmedExercise() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-equipment-recognition"]
        app.launch()

        openTrainingManagement(in: app)
        XCTAssertTrue(tap(app.buttons["今日编排入口"], until: app.navigationBars["当天训练"]))
        app.buttons["调整计划"].tap()
        app.buttons["选好部位，继续"].tap()
        app.buttons["当天菜单添加动作"].tap()

        let recognition = app.buttons["拍照识别器械"]
        XCTAssertTrue(recognition.waitForExistence(timeout: 5))
        XCTAssertTrue(
            tap(recognition, until: app.navigationBars["拍照识别器械"]),
            "器械识别入口应可靠打开识别页"
        )

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
        try XCTSkipIf(true, "组间休息功能已按已确认需求移除")
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

        let detail = app.buttons["RIR、动作资料与备注"]
        XCTAssertTrue(scrollUp(in: app, until: detail, attempts: 6)); detail.tap()
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

        let done = app.buttons["完成"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        firstWeight.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        let workoutScroll = app.scrollViews["active-workout-scroll"]
        XCTAssertTrue(workoutScroll.waitForExistence(timeout: 3))
        let dragStart = workoutScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let dragEnd = workoutScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        dragStart.press(forDuration: 0.1, thenDragTo: dragEnd)
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))

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

        openTrainingManagement(in: app)
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
        XCTAssertTrue(scrollUp(in: app, until: savedAction, attempts: 12))
        savedAction.tap()
        XCTAssertTrue(app.navigationBars["编辑动作"].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)["muscle-group-picker"].value as? String,
            "臀部"
        )
    }

    func testActionEditorCanDismissKeyboardAndKeepSaveReachable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openTrainingManagement(in: app)
        app.buttons["动作库入口"].tap()
        app.buttons["新建动作"].tap()

        let name = app.textFields["动作名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let done = app.toolbars.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["新建动作"].buttons["保存"].isHittable)
    }

    func testActionEditorTextSelectionDragKeepsKeyboardFocused() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openTrainingManagement(in: app)
        app.buttons["动作库入口"].tap()
        app.buttons["新建动作"].tap()

        let name = app.textFields["动作名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("爆发力训练动作")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let selectionStart = name.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.5))
        let selectionEnd = name.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        selectionStart.press(forDuration: 0.8, thenDragTo: selectionEnd)

        XCTAssertTrue(
            app.keyboards.firstMatch.exists,
            "长按并拖动选择文本时不得触发页面级收键盘手势"
        )
    }

    func testActionEditorSystemMenuSelectAllAndPasteUpdatesField() throws {
        let pastedName = "粘贴后的动作名称"

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["XFIT_UI_TEST_PASTEBOARD"] = pastedName
        app.launch()

        openTrainingManagement(in: app)
        app.buttons["动作库入口"].tap()
        app.buttons["新建动作"].tap()

        let name = app.textFields["动作名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("等待替换的名称")
        name.press(forDuration: 0.8)

        let selectAllChinese = app.menuItems["全选"]
        let selectAllEnglish = app.menuItems["Select All"]
        let selectAll = selectAllChinese.waitForExistence(timeout: 2)
            ? selectAllChinese
            : selectAllEnglish
        XCTAssertTrue(selectAll.exists, "长按输入框后应及时提供系统全选菜单")
        selectAll.tap()

        let pasteChinese = app.menuItems["粘贴"]
        let pasteEnglish = app.menuItems["Paste"]
        let paste = pasteChinese.waitForExistence(timeout: 2)
            ? pasteChinese
            : pasteEnglish
        XCTAssertTrue(paste.exists, "全选后应及时提供系统粘贴菜单")
        paste.tap()

        XCTAssertEqual(name.value as? String, pastedName)
    }

    func testActionEditorPreservesCustomMuscleGroup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openTrainingManagement(in: app)
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
        XCTAssertTrue(scrollUp(in: app, until: savedAction, attempts: 12))
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
        openTrainingManagement(in: app)

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
        XCTAssertTrue(scrollUp(in: app, until: savedAction, attempts: 12))
        savedAction.tap()
        XCTAssertTrue(app.navigationBars["编辑动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["volume-unit-picker"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["米（距离）"].exists)
    }

    func testActionEditorPersistsSecondVolumeUnit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        openTrainingManagement(in: app)
        app.buttons["动作库入口"].tap()
        app.buttons["新建动作"].tap()

        let name = app.textFields["动作名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("UI 等长平板支撑")

        let unitPicker = app.descendants(matching: .any)["volume-unit-picker"]
        XCTAssertTrue(unitPicker.waitForExistence(timeout: 3))
        unitPicker.tap()
        let secondOption = app.descendants(matching: .any)["volume-unit-second"]
        XCTAssertTrue(secondOption.waitForExistence(timeout: 3))
        secondOption.tap()
        app.buttons["保存"].tap()

        let savedAction = app.staticTexts["UI 等长平板支撑"]
        XCTAssertTrue(scrollUp(in: app, until: savedAction, attempts: 12))
        savedAction.tap()
        XCTAssertTrue(app.navigationBars["编辑动作"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["秒（时长）"].exists)
    }

    func testIsometricWorkoutRecordsOneSecondsFieldAndCompletedSummary() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-isometric-seconds"]
        app.launch()

        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(resume, until: app.navigationBars["等长训练进行中"]))

        let secondsField = app.textFields["actual-reps-UI 等长平板支撑-1"]
        XCTAssertTrue(scrollUp(in: app, until: secondsField, attempts: 6))
        XCTAssertEqual(secondsField.value as? String, "45")
        XCTAssertTrue(app.staticTexts["秒数 秒"].exists)
        XCTAssertFalse(app.textFields["actual-weight-UI 等长平板支撑-1"].exists)
        XCTAssertFalse(app.segmentedControls["active-measurement-side-UI 等长平板支撑"].exists)

        let complete = app.buttons["完成第 1 组"]
        XCTAssertTrue(complete.waitForExistence(timeout: 3))
        complete.tap()

        let completed = app.buttons["第 1 组已完成"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(completed.label.contains("45 秒"))
    }

    func testIsometricHistoryDisplaysAndEditsSecondsWithoutWeight() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-history",
            "--ui-testing-isometric-seconds"
        ]
        app.launch()

        let historyCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "等长训练历史验证")
        ).firstMatch
        XCTAssertTrue(historyCard.waitForExistence(timeout: 8))
        XCTAssertTrue(tap(historyCard, until: app.navigationBars["等长训练历史验证"]))
        XCTAssertTrue(app.staticTexts["秒（时长）"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["45 秒"].exists)
        XCTAssertTrue(app.staticTexts["30 秒"].exists)
        XCTAssertTrue(app.staticTexts["训练量 75 秒"].exists)
        XCTAssertTrue(app.staticTexts["该动作按 秒 记录，不与 kg 训练容量相加。"].exists)

        XCTAssertTrue(tapRecoveringFromExternalInterruption(
            app.buttons["编辑历史"],
            in: app,
            until: app.navigationBars["编辑历史训练"]
        ))
        XCTAssertTrue(app.staticTexts["秒数 秒"].waitForExistence(timeout: 5))
        let secondsField = app.textFields["历史编辑-UI 等长平板支撑-第1组-秒数"]
        XCTAssertTrue(secondsField.waitForExistence(timeout: 3))
        XCTAssertEqual(secondsField.value as? String, "45")
        XCTAssertFalse(app.textFields["历史编辑-UI 等长平板支撑-第1组-重量"].exists)
    }

    func testActionEditorPersistsBodyweightVolumeUnit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        openTrainingManagement(in: app)
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

        let savedAction = app.staticTexts["UI 自重动作"]
        XCTAssertTrue(scrollUp(in: app, until: savedAction, attempts: 12))
        savedAction.tap()
        XCTAssertTrue(app.staticTexts["自重（体重 × 次数）"].waitForExistence(timeout: 3))
    }

    func testTrainingOverviewOpensHistoryScheduleAndQuickSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        openTrainingManagement(in: app)

        XCTAssertTrue(app.navigationBars["训练管理"].waitForExistence(timeout: 5))
        let previewShot = XCTAttachment(screenshot: app.screenshot())
        previewShot.name = "26-training-management"; previewShot.lifetime = .keepAlways; add(previewShot)
        XCTAssertTrue(app.buttons["训练记录入口"].exists)
        XCTAssertTrue(app.buttons["训练计划入口"].exists)
        XCTAssertTrue(app.buttons["今日编排入口"].exists)
        XCTAssertTrue(app.buttons["专项模板入口"].exists)
        XCTAssertTrue(app.buttons["动作库入口"].exists)

        app.buttons["训练记录入口"].tap()
        XCTAssertTrue(app.navigationBars["训练历史"].waitForExistence(timeout: 5))
        app.navigationBars["训练历史"].buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["训练计划入口"].waitForExistence(timeout: 5))
        app.buttons["训练计划入口"].tap()
        XCTAssertTrue(app.staticTexts["训练日程"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["专项模板入口"].waitForExistence(timeout: 5))
        app.buttons["专项模板入口"].tap()
        XCTAssertTrue(app.staticTexts["我的专项模板"].waitForExistence(timeout: 5))
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

    func testSpecialTemplateEditorExposesMuscleMultiselectAndExerciseReordering() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["训练"].waitForExistence(timeout: 8))
        openTrainingManagement(in: app)
        XCTAssertTrue(app.buttons["专项模板入口"].waitForExistence(timeout: 5))
        app.buttons["专项模板入口"].tap()

        let pushTemplate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "推 · 胸肩三头")
        ).firstMatch
        XCTAssertTrue(pushTemplate.waitForExistence(timeout: 5))
        let previewShot = XCTAttachment(screenshot: app.screenshot())
        previewShot.name = "27-templates"; previewShot.lifetime = .keepAlways; add(previewShot)
        pushTemplate.tap()

        let muscleMenu = app.buttons["专项模板目标肌群"]
        XCTAssertTrue(muscleMenu.waitForExistence(timeout: 5))
        muscleMenu.tap()
        XCTAssertTrue(app.buttons["背部"].waitForExistence(timeout: 3))
        app.buttons["背部"].tap()
        XCTAssertTrue(muscleMenu.label.contains("背部"))

        let editButton = app.navigationBars.buttons["编辑"]
        XCTAssertTrue(editButton.exists)
        XCTAssertTrue(editButton.isEnabled)
    }

    func testSpecialTemplatesAreManualOnlyAndRemainAvailableToSchedule() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["训练"].waitForExistence(timeout: 8))
        openTrainingManagement(in: app)
        XCTAssertTrue(app.buttons["专项模板入口"].waitForExistence(timeout: 5))
        app.buttons["专项模板入口"].tap()

        XCTAssertTrue(app.staticTexts["模板由你手动安排，不会自动生成日程"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["本周训练"].exists)
        let pushTemplate = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "推 · 胸肩三头")
        ).firstMatch
        XCTAssertTrue(pushTemplate.waitForExistence(timeout: 5))
        pushTemplate.tap()
        XCTAssertTrue(app.navigationBars["编辑专项模板"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["每周自动生成日程"].exists)
        XCTAssertFalse(app.staticTexts["训练日"].exists)

        app.navigationBars.buttons["取消"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["训练计划入口"].waitForExistence(timeout: 5))
        app.buttons["训练计划入口"].tap()
        XCTAssertTrue(app.staticTexts["训练日程"].waitForExistence(timeout: 5))
        app.buttons["新增训练安排"].tap()
        app.buttons["从现有模板安排"].tap()
        XCTAssertTrue(app.navigationBars["临时加练"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["添加"].isEnabled)
        XCTAssertFalse(app.staticTexts["请先在训练页创建并启用一个训练计划。"].exists)
    }

    func testExerciseLibraryFindsChineseExerciseByEnglishAliasAndShowsEquipmentMuscleGroup() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let trainingTab = app.tabBars.buttons["训练"]
        XCTAssertTrue(trainingTab.waitForExistence(timeout: 8))
        openTrainingManagement(in: app)
        XCTAssertTrue(app.buttons["动作库入口"].waitForExistence(timeout: 5))
        app.buttons["动作库入口"].tap()

        let search = app.textFields["exercise-library-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("squat")

        XCTAssertTrue(app.staticTexts["杠铃 · 腿部"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["深蹲"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(scrollUp(in: app, until: backfillButton, attempts: 5))
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

        XCTAssertTrue(app.navigationBars["导入历史训练"].waitForExistence(timeout: 5))
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
        let previewShot = XCTAttachment(screenshot: app.screenshot())
        previewShot.name = "28-history"; previewShot.lifetime = .keepAlways; add(previewShot)
        XCTAssertTrue(tap(fixtureCard, until: app.navigationBars["历史详情验证"]))
        XCTAssertTrue(app.staticTexts["杠铃卧推"].exists)
        XCTAssertTrue(app.staticTexts["第 1 组"].exists)
        XCTAssertTrue(app.staticTexts["40 kg × 10"].exists)
        XCTAssertTrue(app.staticTexts["维持重量与组数"].exists)

        XCTAssertTrue(tapRecoveringFromExternalInterruption(
            app.buttons["编辑历史"],
            in: app,
            until: app.navigationBars["编辑历史训练"]
        ))
        let workoutNotes = app.textFields["历史训练备注"]
        XCTAssertTrue(workoutNotes.waitForExistence(timeout: 5))
        // Tap the first text line, outside the multiline field's scroll-indicator region.
        workoutNotes.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        workoutNotes.typeText(" UI已编辑")
        app.buttons["完成"].tap()

        let exerciseNotes = app.textFields["动作备注-杠铃卧推"]
        XCTAssertTrue(exerciseNotes.exists)
        XCTAssertTrue(scrollUp(in: app, until: exerciseNotes, attempts: 8))
        exerciseNotes.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        exerciseNotes.typeText(" UI动作备注")
        app.buttons["完成"].tap()
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

    func testPerSetPlanSideModesAndLiveSetDeltaWithoutPatternControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let editPlan = app.buttons["修改今日计划"]
        XCTAssertTrue(editPlan.waitForExistence(timeout: 8))
        editPlan.tap()
        XCTAssertTrue(app.navigationBars["当天训练"].waitForExistence(timeout: 5))

        app.buttons["调整计划"].tap()
        app.buttons["选好部位，继续"].tap()
        app.buttons["动作菜单-杠铃卧推"].tap()
        app.buttons["单独调整"].tap()
        XCTAssertFalse(app.segmentedControls["set-plan-pattern-杠铃卧推"].exists)
        XCTAssertFalse(app.buttons["固定重量"].exists)
        XCTAssertFalse(app.buttons["金字塔递增"].exists)
        XCTAssertFalse(app.buttons["金字塔递减"].exists)

        let firstWeight = app.textFields["planned-weight-杠铃卧推-1"]
        let secondWeight = app.textFields["planned-weight-杠铃卧推-2"]
        let firstReps = app.textFields["planned-reps-杠铃卧推-1"]
        let secondReps = app.textFields["planned-reps-杠铃卧推-2"]
        XCTAssertTrue(firstWeight.waitForExistence(timeout: 3))
        replaceText(in: firstWeight, with: "40")
        replaceText(in: secondWeight, with: "42.5")
        replaceText(in: firstReps, with: "8")
        replaceText(in: secondReps, with: "6")
        XCTAssertEqual(secondWeight.value as? String, "42.5")
        XCTAssertEqual(secondReps.value as? String, "6")

        let plannedMeasurementSide = app.segmentedControls["plan-measurement-side-杠铃卧推"]
        XCTAssertTrue(plannedMeasurementSide.waitForExistence(timeout: 3))
        plannedMeasurementSide.buttons["单边"].tap()

        app.navigationBars["单独调整"].buttons["完成"].tap()
        app.buttons["选好动作，继续"].tap()
        let save = app.buttons["保存今日计划"]
        XCTAssertTrue(scrollDown(in: app, until: save, attempts: 16))
        save.tap()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(tap(start, until: app.staticTexts["训练进行中"]))

        XCTAssertFalse(app.staticTexts["固定重量"].exists)
        XCTAssertFalse(app.staticTexts["金字塔递增"].exists)
        XCTAssertFalse(app.staticTexts["金字塔递减"].exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "实际 ")
        ).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["40 kg（单边） × 8（单边）"].exists)
        XCTAssertFalse(app.buttons["adjust-volume-杠铃卧推"].exists)

        let actualMeasurementSide = app.segmentedControls["active-measurement-side-杠铃卧推"]
        XCTAssertTrue(scrollUp(in: app, until: actualMeasurementSide, attempts: 5))
        actualMeasurementSide.buttons["双边"].tap()
        XCTAssertTrue(actualMeasurementSide.buttons["双边"].isSelected)
        XCTAssertFalse(app.staticTexts["40 kg（双边） × 8（双边）"].firstMatch.exists)
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

        openTrainingManagement(in: app)
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

    func testToolsTabShowsConversationFirstAgentAndCompactQuickTools() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        let toolsTab = app.tabBars.buttons["我的"]
        XCTAssertTrue(toolsTab.waitForExistence(timeout: 8))
        openTools(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["工具中心"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["记录跳绳"].exists)
        XCTAssertTrue(app.buttons["记录喝水"].exists)
        XCTAssertTrue(app.buttons["记录久坐"].exists)
        XCTAssertTrue(app.buttons["工具记录体重"].exists)
        XCTAssertTrue(app.textFields["Agent输入"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Agent发送"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Agent状态"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Agent对话"].exists)
        XCTAssertTrue(app.buttons["喝水 250 ml"].exists)
        let previewShot = XCTAttachment(screenshot: app.screenshot())
        previewShot.name = "29-tools"; previewShot.lifetime = .keepAlways; add(previewShot)
    }

    func testToolsAgentRequiresConfirmationBeforeWritingWater() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        openTools(in: app)
        if !app.textFields["Agent输入"].waitForExistence(timeout: 2) {
            app.buttons["打开Agent输入"].tap()
        }
        XCTAssertTrue(app.textFields["Agent输入"].waitForExistence(timeout: 3))

        app.buttons["喝水 250 ml"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Agent工具确认卡"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["已记录 250 ml 饮水"].exists)
        app.buttons["取消"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["Agent工具确认卡"].waitForExistence(timeout: 2))

        app.buttons["喝水 250 ml"].tap()
        XCTAssertTrue(app.buttons["Agent确认执行"].waitForExistence(timeout: 3))
        app.buttons["Agent确认执行"].tap()
        XCTAssertTrue(app.staticTexts["已记录 250 ml 饮水"].waitForExistence(timeout: 5))
    }

    // MARK: - 真机验收（REQ-20260902-125030）

    /// AC-05/AC-06：长期模板完成训练后，仅已完成动作的逐组参数回写模板，且重启后仍保留。
    func testDeviceTemplateWritebackAfterFinishAndPersist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // 等训练种子数据就绪（"4 个动作" 卡片出现说明模板/日程已落库，避免编辑器空列表竞态）
        XCTAssertTrue(
            app.staticTexts["4 个动作"].waitForExistence(timeout: 15),
            "训练卡应在 15 秒内完成种子加载"
        )

        func openPushTemplateEditor() {
            for attempt in 0..<3 {
                openTrainingManagement(in: app)
                let templateList = app.staticTexts["我的专项模板"]
                if !templateList.waitForExistence(timeout: 2) {
                    XCTAssertTrue(app.buttons["专项模板入口"].waitForExistence(timeout: 8))
                    app.buttons["专项模板入口"].tap()
                    XCTAssertTrue(templateList.waitForExistence(timeout: 5))
                }
                let pushTemplate = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS %@", "推 · 胸肩三头")
                ).firstMatch
                XCTAssertTrue(pushTemplate.waitForExistence(timeout: 6))
                pushTemplate.tap()

                // 编辑器动作区就绪信号：未出现空态文案（模板名以 计划名称 输入框的值确认）
                let nameField = app.textFields["计划名称"]
                XCTAssertTrue(nameField.waitForExistence(timeout: 6))
                _ = app.staticTexts["还没有动作，请从动作库添加。"].waitForExistence(timeout: 2)
                if !app.staticTexts["还没有动作，请从动作库添加。"].exists {
                    XCTAssertEqual(nameField.value as? String, "推 · 胸肩三头")
                    return
                }
                // 慢查询竞态：关闭后重试
                app.navigationBars.buttons["取消"].tap()
                _ = app.buttons["专项模板入口"].waitForExistence(timeout: 3)
                if attempt == 2 {
                    XCTFail("模板编辑器三次尝试均未加载出动作列表（持久化存储慢查询竞态）")
                }
            }
        }

        // 1) 预读模板初始逐组值
        openPushTemplateEditor()
        let weightFields = app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", "kg")
        )
        XCTAssertTrue(scrollUp(in: app, until: weightFields.firstMatch, attempts: 6))
        let initialWeights = weightFields.allElementsBoundByIndex.map { $0.value as? String ?? "" }
        XCTAssertEqual(initialWeights.first, "40", "杠铃卧推初始重量应为种子值 40")
        attach(app, "模板初始逐组值-杠铃卧推40")

        let cancelEditor = app.navigationBars.buttons["取消"].firstMatch
        XCTAssertTrue(cancelEditor.waitForExistence(timeout: 5))
        cancelEditor.tap()

        // 2) 返回训练根页面，开始由长期模板发起的训练
        let start = app.buttons["开始记录训练"]
        openTrainingRoot(in: app)
        XCTAssertTrue(start.waitForExistence(timeout: 5), "关闭模板编辑器后应返回训练首页并能开始记录")
        XCTAssertTrue(tap(start, until: app.staticTexts["训练进行中"]))

        // 3) 杠铃卧推 3 组全部改为 44kg × 10 次并逐组完成；其余动作不完成
        for setNumber in 1...3 {
            let weight = app.textFields["actual-weight-杠铃卧推-\(setNumber)"]
            XCTAssertTrue(scrollUp(in: app, until: weight, attempts: 6))
            weight.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            let currentWeight = weight.value as? String ?? ""
            weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentWeight.count))
            weight.typeText("44")

            let reps = app.textFields["actual-reps-杠铃卧推-\(setNumber)"]
            reps.tap()
            let currentReps = reps.value as? String ?? ""
            reps.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentReps.count))
            reps.typeText("10")
            let done = app.buttons["完成"].firstMatch
            if done.waitForExistence(timeout: 2) {
                done.tap()
            }

            let complete = app.buttons["完成第 \(setNumber) 组"].firstMatch
            XCTAssertTrue(scrollUp(in: app, until: complete, attempts: 6))
            complete.tap()
            let compact = app.buttons["第 \(setNumber) 组已完成"].firstMatch
            XCTAssertTrue(compact.waitForExistence(timeout: 5))
            XCTAssertTrue(compact.label.contains("44"), "完成摘要应包含本次重量 44")
        }

        let skipFeeling = app.buttons["跳过感受并收起"]
        if skipFeeling.waitForExistence(timeout: 3) {
            skipFeeling.tap()
        }
        attach(app, "训练完成前-仅杠铃卧推完成")

        // 4) 完成训练（允许其他动作未完成）
        let finish = app.buttons["完成本次训练"].firstMatch
        XCTAssertTrue(scrollUp(in: app, until: finish, attempts: 6))
        // A partly visible button can intersect the viewport while its center
        // remains below the screen. Bring the coordinate tap fully into view.
        for _ in 0..<3 {
            if app.frame.insetBy(dx: 0, dy: 80).contains(CGPoint(x: finish.frame.midX, y: finish.frame.midY)) { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.frame.contains(CGPoint(x: finish.frame.midX, y: finish.frame.midY)))
        XCTAssertTrue(
            tapRecoveringFromExternalInterruption(
                finish,
                in: app,
                until: app.buttons["完成训练"].firstMatch
            )
        )
        app.buttons["完成训练"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["训练进行中"].waitForExistence(timeout: 4))

        // 5) 完成后重新打开编辑器验证回写（同会话；持久化语义由 ScheduleAndDataTests 磁盘容器单元测试覆盖）
        openPushTemplateEditor()

        XCTAssertTrue(scrollUp(in: app, until: weightFields.firstMatch, attempts: 6))
        if !app.staticTexts["上斜哑铃卧推"].exists {
            app.swipeUp()
        }
        let updatedWeights = weightFields.allElementsBoundByIndex.map { $0.value as? String ?? "" }
        let updatedReps = app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", "次数")
        ).allElementsBoundByIndex.map { $0.value as? String ?? "" }

        XCTAssertEqual(
            updatedWeights.filter { $0 == "44" }.count, 3,
            "杠铃卧推 3 组重量均应回写为 44，实际 \(updatedWeights)"
        )
        XCTAssertEqual(
            updatedReps.filter { $0 == "10" }.count, 3,
            "杠铃卧推 3 组次数均应回写为 10，实际 \(updatedReps)"
        )
        XCTAssertTrue(
            updatedWeights.contains("16"),
            "未完成的上斜哑铃卧推不应回写，仍应保留初始重量 16，实际 \(updatedWeights)"
        )
        attach(app, "重启后模板逐组值-44x10已回写")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
