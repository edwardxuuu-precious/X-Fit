import XCTest

final class PyramidHistoryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNextPlanShowsEveryActualAndPlannedSetAtLargestType() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-coach-ready",
            "--ui-testing-meal-camera-unavailable", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["主导航-训练"].waitForExistence(timeout: 20))

        XCTAssertFalse(app.buttons["训练-训练总结"].exists)
        app.buttons["主导航-进展"].tap()
        let summary = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "进展-最近训练-", "下肢综合 · 隔离测试")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        reveal(summary, app); summary.tap()
        XCTAssertTrue(app.navigationBars["训练总结"].waitForExistence(timeout: 6))
        let nextPlan = app.buttons["复盘-下一次计划"]
        XCTAssertTrue(nextPlan.waitForExistence(timeout: 5)); nextPlan.tap()
        XCTAssertTrue(app.navigationBars["下一次计划"].waitForExistence(timeout: 6))

        // ready generates a draft from actuals and feedback in the isolated
        // fixture. Verify its full comparison directly; regeneration and save
        // are covered by TrainingCoachUITests rather than adding that detour
        // to this read-only largest-type presentation check.
        assertComparison("测试腿举", groups: 4, actualWeight: "65", app: app)
        assertComparison("测试腿屈伸", groups: 3, actualWeight: "35", app: app)
        XCTAssertFalse(app.buttons["确认-保存安排"].exists)
    }

    func testNotesChestPlateRotationCanBeFoundFromTemporaryExerciseSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let originalWeight = app.textFields["actual-weight-预填测试推胸-1"]
        XCTAssertTrue(originalWeight.waitForExistence(timeout: 8))
        let originalValue = originalWeight.value as? String
        let addExercise = app.xfitWorkoutAction("临时加动作")
        XCTAssertTrue(addExercise.waitForExistence(timeout: 5)); addExercise.tap()
        XCTAssertTrue(app.navigationBars["添加临时动作"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("胸前")
        let rotation = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "杠铃片胸前转体")).firstMatch
        XCTAssertTrue(rotation.waitForExistence(timeout: 5))
        let dismissKeyboard = app.buttons["动作搜索-收起键盘"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5)); dismissKeyboard.tap()
        reveal(rotation, app)
        XCTAssertGreaterThanOrEqual(rotation.frame.height, 44)
        XCTAssertFalse(app.buttons["新建并加入"].exists)
        capture("notes-plate-rotation-chest-search", app)
        app.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(originalWeight.waitForExistence(timeout: 5))
        XCTAssertEqual(originalWeight.value as? String, originalValue)
        XCTAssertFalse(app.buttons["切换动作-杠铃片胸前转体"].exists)
        XCTAssertEqual(app.buttons["完成第 1 组"].firstMatch.value as? String, "未完成")
    }

    private func assertComparison(_ name: String, groups: Int, actualWeight: String, app: XCUIApplication) {
        let comparison = app.descendants(matching: .any).matching(identifier: "历史计划对比-" + name).firstMatch
        XCTAssertTrue(comparison.waitForExistence(timeout: 6))
        let heading = comparison.staticTexts["上次实际 → 本次计划"]
        reveal(heading, app)
        XCTAssertTrue(heading.isHittable)
        XCTAssertTrue(comparison.staticTexts["上次\(groups)组 · 本次\(groups)计划组"].exists)
        XCTAssertEqual(comparison.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "上次：")).count, groups)
        XCTAssertEqual(comparison.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "计划：")).count, groups)
        XCTAssertEqual(comparison.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "上次：\(actualWeight) × 10")).count, groups)
        for number in 1...groups {
            let row = comparison.staticTexts["第\(number)组"]
            reveal(row, app)
            XCTAssertTrue(row.isHittable, "\(name)第\(number)组的历史与计划比较应可逐组查看")
        }
        capture("history-plan-\(name)-all-sets-largest-type", app)
    }

    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        for _ in 0..<14 {
            let viewport = scroll.frame
            let navigation = app.navigationBars.firstMatch
            let tabBar = app.descendants(matching: .any).matching(identifier: "主导航").firstMatch
            let review = app.buttons["计划-审阅确认"]
            // Compare against the actual unobscured viewport. Adding an
            // artificial margin here rejected a fully visible 220pt button
            // whose bottom sat 6pt above the fixed review control (R3 AX).
            let top = max(viewport.minY, navigation.exists ? navigation.frame.maxY : viewport.minY)
            var bottom = min(viewport.maxY, tabBar.exists ? tabBar.frame.minY : app.frame.maxY)
            if review.exists { bottom = min(bottom, review.frame.minY) }
            let visible = CGRect(x: viewport.minX, y: top, width: viewport.width, height: bottom - top)
            guard visible.height > 0 else { break }
            var needsDown = false
            var distance = visible.height
            if item.exists {
                let frame = item.frame
                if item.isHittable && visible.contains(frame) { return }
                needsDown = frame.minY < visible.minY
                distance = needsDown ? visible.minY - frame.minY : max(24, frame.maxY - visible.maxY)
            }
            // R2 video shows full-screen swipes alternating past these controls.
            // Use a bounded drag in the actual unobscured scroll area, shortening
            // it near the target instead of increasing the attempt budget.
            let cap = distance > visible.height ? min(320, visible.height * 0.7) : min(180, visible.height * 0.4)
            let travel = min(cap, max(24, distance + 8))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX, dy: visible.midY + (needsDown ? -travel / 2 : travel / 2)))
            let end = origin.withOffset(CGVector(dx: visible.midX, dy: visible.midY + (needsDown ? travel / 2 : -travel / 2)))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "unreachable-content-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        capture("unreachable-content-viewport", app)
        XCTFail("内容必须完整滚动到导航栏与固定底栏之间：\(item)")
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
