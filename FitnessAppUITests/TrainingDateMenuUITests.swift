import XCTest

final class CardioWorkoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testCardioActualCancelEditAndDateMenu() { exerciseFlow(large: false) }
    func testCardioActualCancelEditAndDateMenuAtLargestTextSize() { exerciseFlow(large: true) }

    private func show(_ element: XCUIElement, app: XCUIApplication) {
        if app.keyboards.firstMatch.exists { app.buttons["有氧-收起键盘"].tap() }
        let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            scroll.swipeUp(velocity: .slow)
        }
        XCTFail("控件不可达：\(element.identifier)")
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func exerciseFlow(large: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-home-timeline", "--ui-testing-cardio-menu"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let record = app.buttons["训练-记录有氧"]
        XCTAssertTrue(record.waitForExistence(timeout: 20)); show(record, app: app); record.tap()
        XCTAssertTrue(app.navigationBars["记录有氧"].waitForExistence(timeout: 5))
        let save = app.buttons["有氧-保存实际"]
        show(save, app: app); XCTAssertFalse(save.isEnabled, "目标不能自动成为实际")
        app.navigationBars["记录有氧"].buttons["取消"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5)); show(record, app: app); record.tap()
        let minutes = app.textFields["有氧-实际分钟"], level = app.textFields["有氧-Level"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        minutes.tap(); minutes.typeText("35")
        show(level, app: app); level.tap(); level.typeText("10")
        show(save, app: app); save.tap()
        let metric = app.descendants(matching: .any)["训练-有氧指标"]
        XCTAssertTrue(metric.waitForExistence(timeout: 5)); XCTAssertEqual(metric.label, "35 分钟 · Level 10")
        XCTAssertFalse(app.buttons["训练-训练总结"].exists)
        XCTAssertFalse(app.staticTexts["阻力"].exists)
        capture(large ? "cardio-home-large" : "cardio-home", app: app)
        app.buttons["主导航-进展"].tap()
        let summary = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "进展-最近训练-", "固定单车")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5)); show(summary, app: app); summary.tap()
        XCTAssertTrue(app.navigationBars["训练总结"].waitForExistence(timeout: 5))
        let actual = app.descendants(matching: .any)["有氧-实际摘要"]
        XCTAssertEqual(actual.label, "35 分钟 · Level 10")
        let edit = app.buttons["有氧-修改记录"]; show(edit, app: app); edit.tap()
        XCTAssertTrue(app.navigationBars["修改有氧记录"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["有氧-实际分钟"].value as? String, "35")
        XCTAssertEqual(app.textFields["有氧-Level"].value as? String, "10")
        app.navigationBars["修改有氧记录"].buttons["取消"].tap()
        show(actual, app: app); XCTAssertEqual(actual.label, "35 分钟 · Level 10")
        capture(large ? "cardio-summary-large" : "cardio-summary", app: app)
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        app.buttons["主导航-训练"].tap()
        let menu = app.buttons["训练-日期菜单"]
        for _ in 0..<10 { if menu.isHittable { break }; app.scrollViews.firstMatch.swipeDown(velocity: .slow) }
        menu.tap()
        let menuSummary = app.buttons["日期菜单-有氧总结"]
        XCTAssertTrue(menuSummary.waitForExistence(timeout: 5)); show(menuSummary, app: app); menuSummary.tap()
        XCTAssertTrue(app.navigationBars["训练总结"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["有氧-实际摘要"].label, "35 分钟 · Level 10")
    }
}

final class TrainingDateMenuUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-home-timeline", "--ui-testing-date-menu"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["训练-日期菜单"].waitForExistence(timeout: 20))
        return app
    }
    private func day(_ offset: Int = 0) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
    }
    private func show(_ element: XCUIElement, app: XCUIApplication, fullyVisible: Bool = false) {
        if app.keyboards.firstMatch.exists {
            let done = app.buttons["跳绳菜单-收起键盘"]
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            done.tap()
        }
        let scroller = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch
        var movingDown = false
        for _ in 0..<10 {
            if element.exists {
                let top = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map { $0.frame.maxY }.max() ?? app.frame.minY
                let coveredField = element.elementType == .textField && element.frame.midY <= top + 8
                let visibleTabs = app.xfitTabButtons.allElementsBoundByIndex.filter(\.isHittable)
                let bottom = visibleTabs.isEmpty ? app.frame.maxY : app.xfitTabBar.frame.minY
                let fullyUncovered = element.frame.minY >= top + 8 && element.frame.maxY <= bottom - 8
                if element.isHittable && !coveredField && (!fullyVisible || fullyUncovered) { return }
                if fullyVisible {
                    // isHittable also accepts the visible sliver of a large
                    // button whose centre is covered by the bottom navigation.
                    let viewport = max(1, bottom - top)
                    let delta = (top + bottom) / 2 - element.frame.midY
                    let distance = min(max(abs(delta), 32), min(180, viewport * 0.35))
                    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                        .withOffset(CGVector(dx: 0, dy: (top + bottom) / 2 - app.frame.minY))
                    let end = start.withOffset(CGVector(dx: 0, dy: delta < 0 ? -distance : distance))
                    start.press(forDuration: 0.1, thenDragTo: end)
                    continue
                }
                movingDown = element.frame.midY < top + 8
            }
            if movingDown { scroller.swipeDown(velocity: .slow) }
            else { scroller.swipeUp(velocity: .slow) }
        }
        XCTFail("无法将控件滚动到可操作区域：\(element.identifier)")
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    private func openAddRope(_ app: XCUIApplication) {
        app.buttons["日期菜单-添加项目"].tap()
        let rope = app.cells.containing(.button, identifier: "日期菜单-添加跳绳").firstMatch
        XCTAssertTrue(rope.waitForExistence(timeout: 5))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: rope)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 5), .completed)
        rope.tap()
        XCTAssertTrue(app.navigationBars["安排跳绳"].waitForExistence(timeout: 5))
    }
    private func launchSupersededMenu(large: Bool = false, actuals: Bool = false, loads: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-home-timeline", "--ui-testing-superseded-menu"]
        if actuals { app.launchArguments.append("--ui-testing-superseded-actuals") }
        if loads { app.launchArguments.append("--ui-testing-superseded-load-history") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["训练-日期菜单"].waitForExistence(timeout: 20))
        return app
    }

    func testSupersededPlansAreHiddenAndVoluntarySkipCanRestore() { verifySupersededMenu(large: false) }
    func testSupersededPlansAreHiddenAndVoluntarySkipCanRestoreAtLargestTextSize() { verifySupersededMenu(large: true) }

    private func verifySupersededMenu(large: Bool) {
        let app = launchSupersededMenu(large: large)
        let oldID = "F53446EA-1488-43C4-93BD-C6842CCD8101"
        let currentID = "F53446EA-1488-43C4-93BD-C6842CCD8102"
        let voluntaryID = "F53446EA-1488-43C4-93BD-C6842CCD8103"
        let next = app.buttons["训练-接下来-F53446EA-1488-43C4-93BD-C6842CCD8202"]
        show(next, app: app, fullyVisible: true)
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(app.buttons["训练-接下来-F53446EA-1488-43C4-93BD-C6842CCD8201"].exists)
        let menu = app.buttons["训练-日期菜单"]
        show(menu, app: app, fullyVisible: true); menu.tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["日期菜单-项目-" + oldID].exists)
        XCTAssertFalse(app.buttons["日期菜单-记录跳绳-" + oldID].exists)
        XCTAssertFalse(app.buttons["日期菜单-管理安排-" + oldID].exists)
        let record = app.buttons["日期菜单-记录跳绳-" + currentID]
        XCTAssertTrue(record.exists)
        let skipped = app.buttons["已跳过的安排（1）"]
        show(skipped, app: app, fullyVisible: true); skipped.tap()
        let manage = app.buttons["日期菜单-管理安排-" + voluntaryID]
        show(manage, app: app, fullyVisible: true); manage.tap()
        XCTAssertTrue(app.buttons["恢复这次训练"].waitForExistence(timeout: 5))
        app.buttons["恢复这次训练"].tap()
        let restore = app.alerts["恢复这次训练？"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.buttons["确认恢复"].tap()
        XCTAssertTrue(app.buttons["日期菜单-记录跳绳-" + voluntaryID].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["已跳过的安排（1）"].exists)
        let closeResult = app.buttons["计划管理-关闭结果"]
        show(closeResult, app: app); closeResult.tap()
        show(record, app: app, fullyVisible: true); record.tap()
        XCTAssertTrue(app.navigationBars["记录跳绳"].waitForExistence(timeout: 5))
        let count = app.textFields["跳绳菜单-实际次数"]
        show(count, app: app); count.tap(); count.typeText("650")
        let save = app.buttons["跳绳菜单-保存实际"]
        show(save, app: app, fullyVisible: true); save.tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        let current = app.descendants(matching: .any)["日期菜单-项目-" + currentID]
        let saved = current.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "日期菜单-跳绳记录-", "650 个")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertTrue(current.staticTexts["已完成"].exists)
        XCTAssertFalse(record.exists)
        XCTAssertFalse(app.descendants(matching: .any)["日期菜单-项目-" + oldID].exists)
        capture(large ? "superseded-menu-current-and-voluntary-large" : "superseded-menu-current-and-voluntary", app: app)
    }

    func testHiddenSupersededCardsKeepLinkedActualsVisible() {
        let app = launchSupersededMenu(actuals: true)
        app.buttons["训练-日期菜单"].tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["日期菜单-项目-F53446EA-1488-43C4-93BD-C6842CCD8101"].exists)
        let actual = app.buttons["实际训练-F53446EA-1488-43C4-93BD-C6842CCD8104"]
        show(actual, app: app, fullyVisible: true); XCTAssertTrue(actual.isHittable)
        let rope = app.buttons["日期菜单-跳绳记录-F53446EA-1488-43C4-93BD-C6842CCD8105"]
        show(rope, app: app, fullyVisible: true); rope.tap()
        XCTAssertTrue(app.navigationBars["跳绳记录"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["跳绳记录-次数"].value as? String, "700 次")
        XCTAssertEqual(app.descendants(matching: .any)["跳绳记录-有效时长"].value as? String, "480 秒")
        XCTAssertEqual(app.descendants(matching: .any)["跳绳记录-日期"].value as? String, day())
        capture("superseded-menu-retained-actual-readback", app: app)
    }

    func testHistoricalSupersededArrangementKeepsReadonlySourceWithoutBackfillActions() {
        let app = launchSupersededMenu()
        app.buttons["训练日程"].tap()
        XCTAssertTrue(app.navigationBars["训练日程"].waitForExistence(timeout: 5))
        let retired = app.buttons.matching(identifier: "日程-被替代安排-F53446EA-1488-43C4-93BD-C6842CCD8101")
            .matching(NSPredicate(format: "label CONTAINS %@", "已被新版替代")).firstMatch
        show(retired, app: app, fullyVisible: true); retired.tap()
        XCTAssertTrue(app.staticTexts["已被新版替代 · 原处方保留"].firstMatch.exists)
        let source = app.staticTexts["隔离菜单跳绳"]
        show(source, app: app); XCTAssertTrue(source.isHittable)
        show(retired, app: app, fullyVisible: true)
        retired.press(forDuration: 1)
        XCTAssertFalse(app.buttons["恢复训练"].exists)
        XCTAssertFalse(app.buttons["改期并恢复"].exists)
        capture("superseded-history-readonly-source", app: app)
    }

    func testHistoricalSupersededSourceShowsEveryPlannedLoadUnitAndSide() {
        let app = launchSupersededMenu(loads: true)
        app.buttons["训练日程"].tap()
        XCTAssertTrue(app.navigationBars["训练日程"].waitForExistence(timeout: 5))
        let retired = app.buttons["日程-被替代安排-F53446EA-1488-43C4-93BD-C6842CCD8101"]
        show(retired, app: app, fullyVisible: true); retired.tap()
        for text in ["以下为原计划目标，未作为实际训练记录。", "隔离原计划推胸",
                     "第 1 组计划 · 20 kg × 8 次", "第 2 组计划 · 25 kg × 8 次",
                     "负重口径 · 单边 · 次数口径 · 双边", "负重口径 · 双边 · 次数口径 · 未注明"] {
            let target = app.staticTexts[text].firstMatch
            show(target, app: app, fullyVisible: true); XCTAssertTrue(target.isHittable)
        }
        capture("superseded-history-original-loads-and-sides", app: app)
    }

    func testHomeRemovesToolsButPreservesCalendarAndProfileDestinations() {
        let app = launch()
        for name in ["训练计划与动作库", "完整日历与菜单管理", "训练历史", "记录跳绳"] {
            XCTAssertFalse(app.buttons[name].exists)
        }
        XCTAssertTrue(app.buttons["训练日程"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "主导航-")).count, 5)
        app.swipeUp(); capture("home-without-tools", app: app)
        app.buttons["主导航-我的"].tap()
        XCTAssertTrue(app.buttons["训练历史"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["模板与动作"].exists)
    }
    func testRopePlanRecordCancelAndReadback() { exerciseFlow(large: false) }
    func testRopePlanRecordCancelAndReadbackAtLargestTextSize() { exerciseFlow(large: true) }
    private func exerciseFlow(large: Bool) {
        let app = launch(large: large)
        app.buttons["训练-日期菜单"].tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-选择日期"].exists)
        // Old unlinked records remain readable and do not acquire inferred active duration.
        let legacy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "日期菜单-跳绳记录-")).firstMatch
        show(legacy, app: app); legacy.tap()
        XCTAssertTrue(app.navigationBars["跳绳记录"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["跳绳记录-次数"].value as? String, "未知")
        let legacyDuration = app.descendants(matching: .any)["跳绳记录-旧时长"]
        show(legacyDuration, app: app)
        XCTAssertEqual(legacyDuration.value as? String, "480 秒")
        capture(large ? "rope-legacy-detail-large" : "rope-legacy-detail", app: app)
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        openAddRope(app)
        let planSave = app.buttons["跳绳菜单-保存安排"]
        show(planSave, app: app)
        XCTAssertFalse(planSave.isEnabled)
        show(app.textFields["跳绳菜单-计划有效分钟"], app: app)
        app.textFields["跳绳菜单-计划有效分钟"].tap()
        app.textFields["跳绳菜单-计划有效分钟"].typeText("10")
        show(planSave, app: app); planSave.tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "日期菜单-记录跳绳-")).firstMatch
        show(record, app: app, fullyVisible: true); record.tap()
        XCTAssertTrue(app.navigationBars["记录跳绳"].waitForExistence(timeout: 5))
        show(app.buttons["跳绳菜单-保存实际"], app: app)
        XCTAssertFalse(app.buttons["跳绳菜单-保存实际"].isEnabled, "计划目标不能自动变成实际")
        app.navigationBars["记录跳绳"].buttons["取消"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5), "取消不应完成安排")
        show(record, app: app, fullyVisible: true); record.tap()
        show(app.textFields["跳绳菜单-实际有效分钟"], app: app)
        app.textFields["跳绳菜单-实际有效分钟"].tap()
        app.textFields["跳绳菜单-实际有效分钟"].typeText("8")
        let actualSave = app.buttons["跳绳菜单-保存实际"]
        show(actualSave, app: app); actualSave.tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        XCTAssertFalse(record.exists)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "日期菜单-跳绳记录-", "有效 480 秒")).firstMatch
        show(saved, app: app); capture(large ? "date-menu-large" : "date-menu", app: app); saved.tap()
        XCTAssertTrue(app.navigationBars["跳绳记录"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["跳绳记录-次数"].value as? String, "未知")
        let activeDuration = app.descendants(matching: .any)["跳绳记录-有效时长"]
        show(activeDuration, app: app)
        XCTAssertEqual(activeDuration.value as? String, "480 秒")
        capture(large ? "rope-readback-large" : "rope-readback", app: app)
    }
    func testFutureDatePlanDoesNotBecomeActualOrChangeHomeSelection() {
        let app = launch()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练-接下来-")).firstMatch
        show(first, app: app); first.tap()
        let dateMenu = app.buttons["日程-日期菜单-" + day(1)]
        XCTAssertTrue(dateMenu.waitForExistence(timeout: 5)); dateMenu.tap()
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + day(1)].waitForExistence(timeout: 5))
        openAddRope(app)
        app.textFields["跳绳菜单-计划次数"].tap()
        app.textFields["跳绳菜单-计划次数"].typeText("1200")
        let save = app.buttons["跳绳菜单-保存安排"]; show(save, app: app); save.tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "日期菜单-记录跳绳-")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["目标 · 1200 次"].exists)
        capture("future-date-menu", app: app)
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        let today = app.buttons["训练日期-" + day()]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isSelected)
    }

    func testPlanManagementUsesDateMenuAndPreservesPlansAcrossCancelUndoAndReschedule() {
        exerciseManagementFlow(large: false)
    }

    func testPlanManagementUsesDateMenuAndPreservesPlansAtLargestTextSize() {
        exerciseManagementFlow(large: true)
    }

    private func exerciseManagementFlow(large: Bool) {
        let app = launch(large: large)
        XCTAssertFalse(app.buttons["修改今日计划"].exists, "低频计划管理入口不再单独占据首页")
        XCTAssertFalse(app.buttons["调整计划"].exists)
        capture(large ? "managed-home-large" : "managed-home", app: app)
        app.buttons["训练-日期菜单"].tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))

        let managementPrefix = "日期菜单-管理安排-"
        let before = Set(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", managementPrefix))
            .allElementsBoundByIndex.map(\.identifier))
        openAddRope(app)
        let count = app.textFields["跳绳菜单-计划次数"]
        show(count, app: app); count.tap(); count.typeText("1200")
        let savePlan = app.buttons["跳绳菜单-保存安排"]
        show(savePlan, app: app); XCTAssertTrue(savePlan.isEnabled); savePlan.tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        let added = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", managementPrefix))
            .allElementsBoundByIndex.map(\.identifier).filter { !before.contains($0) }
        guard added.count == 1, let managementID = added.first else {
            return XCTFail("保存一次手动跳绳应仅新增一个可管理的计划：\(added)")
        }
        let scheduleID = String(managementID.dropFirst(managementPrefix.count))
        let manage = app.buttons[managementID]
        let record = app.buttons["日期菜单-记录跳绳-" + scheduleID]
        let card = app.descendants(matching: .any)["日期菜单-项目-" + scheduleID].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5), "创建目标不能自动生成实际完成记录")
        show(manage, app: app); manage.tap()
        XCTAssertTrue(app.buttons["调整训练日期"].waitForExistence(timeout: 5))
        capture(large ? "managed-actions-large" : "managed-actions", app: app)

        // Editing is still the existing manual-rope editor; cancel must retain its target.
        app.buttons["编辑本次训练内容"].tap()
        XCTAssertTrue(app.navigationBars["调整跳绳"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["跳绳菜单-计划次数"].value as? String, "1200")
        show(app.textFields["跳绳菜单-计划次数"], app: app)
        app.textFields["跳绳菜单-计划次数"].tap()
        app.textFields["跳绳菜单-计划次数"].typeText("9")
        app.navigationBars["调整跳绳"].buttons["取消"].tap()
        show(manage, app: app); manage.tap()
        XCTAssertTrue(app.buttons["编辑本次训练内容"].waitForExistence(timeout: 5))
        app.buttons["编辑本次训练内容"].tap()
        XCTAssertTrue(app.navigationBars["调整跳绳"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["跳绳菜单-计划次数"].value as? String, "1200")
        app.navigationBars["调整跳绳"].buttons["取消"].tap()

        show(manage, app: app); manage.tap()
        XCTAssertTrue(app.buttons["跳过这次训练"].waitForExistence(timeout: 5))
        app.buttons["跳过这次训练"].tap()
        let skip = app.alerts["跳过这次训练？"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.textFields.firstMatch.tap(); skip.textFields.firstMatch.typeText("临时有事")
        skip.buttons["取消"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5), "取消跳过应保留同一条待练计划")

        show(manage, app: app); manage.tap(); app.buttons["跳过这次训练"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.buttons["确认跳过"].tap()
        let result = app.staticTexts["计划管理-结果"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "已跳过这次训练")
        XCTAssertFalse(record.exists, "跳过的计划收进折叠列表，不能继续作为待练项目显示")
        let undo = app.buttons["计划管理-撤销"]
        show(undo, app: app); undo.tap()
        XCTAssertEqual(result.label, "已撤销本次调整")
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        show(app.buttons["计划管理-关闭结果"], app: app); app.buttons["计划管理-关闭结果"].tap()

        // Restore through the same schedule's management button inside the skipped disclosure.
        show(manage, app: app); manage.tap(); app.buttons["跳过这次训练"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.textFields.firstMatch.tap(); skip.textFields.firstMatch.typeText("临时有事")
        skip.buttons["确认跳过"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let skippedList = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "已跳过的安排")).firstMatch
        show(skippedList, app: app); skippedList.tap()
        show(manage, app: app)
        XCTAssertTrue(card.staticTexts["已跳过"].exists)
        capture(large ? "managed-skipped-large" : "managed-skipped", app: app)
        manage.tap()
        XCTAssertTrue(app.buttons["恢复这次训练"].waitForExistence(timeout: 5))
        app.buttons["恢复这次训练"].tap()
        let restore = app.alerts["恢复这次训练？"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.buttons["取消"].tap()
        XCTAssertTrue(card.staticTexts["已跳过"].exists, "取消恢复不能改变跳过状态")
        show(manage, app: app); manage.tap(); app.buttons["恢复这次训练"].tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 5)); restore.buttons["确认恢复"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "已恢复这次训练")
        show(app.buttons["计划管理-关闭结果"], app: app); app.buttons["计划管理-关闭结果"].tap()

        // Previewing tomorrow and cancelling the sheet must leave the source date untouched.
        show(manage, app: app); manage.tap(); app.buttons["调整训练日期"].tap()
        XCTAssertTrue(app.navigationBars["调整训练日期"].waitForExistence(timeout: 5))
        selectTomorrowForManagedPlan(app)
        let preview = app.buttons["计划管理-预览改期"]
        XCTAssertTrue(preview.isEnabled); preview.tap()
        XCTAssertTrue(app.navigationBars["确认改期"].waitForExistence(timeout: 5))
        capture(large ? "managed-date-preview-large" : "managed-date-preview", app: app)
        app.navigationBars["确认改期"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["调整训练日期"].waitForExistence(timeout: 5))
        app.navigationBars["调整训练日期"].buttons["取消"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + day()].waitForExistence(timeout: 5))
        XCTAssertTrue(record.exists)

        show(manage, app: app); manage.tap(); app.buttons["调整训练日期"].tap()
        XCTAssertTrue(app.navigationBars["调整训练日期"].waitForExistence(timeout: 5))
        selectTomorrowForManagedPlan(app)
        XCTAssertTrue(preview.isEnabled); preview.tap()
        let confirm = app.buttons["计划管理-确认改期"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.hasPrefix("已改期至"))
        XCTAssertFalse(manage.exists, "改期后原日期不能残留同一条待练安排")
        let view = app.buttons["计划管理-查看"]
        show(view, app: app); view.tap()
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + day(1)].waitForExistence(timeout: 5))
        XCTAssertTrue(manage.exists, "查看必须定位到明天的同一条计划UUID")
        XCTAssertFalse(record.exists, "未来计划不能因为改期而变成实际或提前可记录")
        capture(large ? "managed-rescheduled-large" : "managed-rescheduled", app: app)
        show(undo, app: app); undo.tap()
        XCTAssertEqual(result.label, "已撤销本次调整")
        XCTAssertFalse(manage.exists, "撤销改期后该UUID应从目标日移回原日期")
        app.navigationBars["训练菜单"].buttons.firstMatch.tap()
        let homeDate = app.buttons["训练-日期菜单"]
        show(homeDate, app: app); homeDate.tap()
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + day()].waitForExistence(timeout: 5))
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        show(manage, app: app); manage.tap(); app.buttons["编辑本次训练内容"].tap()
        XCTAssertTrue(app.navigationBars["调整跳绳"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["跳绳菜单-计划次数"].value as? String, "1200", "改期与撤销不得修改训练内容")
        app.navigationBars["调整跳绳"].buttons["取消"].tap()
        capture(large ? "managed-restored-original-large" : "managed-restored-original", app: app)
    }

    private let pastPlanID = "F53446EA-1488-43C4-93BD-C6842CCD8101"
    private let pastCompanionID = "F53446EA-1488-43C4-93BD-C6842CCD8102"

    private func launchPastReschedule(_ variant: String? = nil, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-past-reschedule"]
        if let variant { app.launchArguments.append("--ui-testing-past-reschedule-" + variant) }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["训练-日期菜单"].waitForExistence(timeout: 20))
        // Foreground refresh intentionally selects today. Exercise the user's explicit
        // week-strip selection after launch rather than relying on the fixture's startup selection.
        let offset = variant == "today" ? 0 : variant == "future" ? 1 : -1
        let selectedDay = app.buttons["训练日期-" + day(offset)]
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练日期-")).firstMatch.waitForExistence(timeout: 5))
        if !selectedDay.exists && offset != 0 {
            let week = app.buttons[offset < 0 ? "上一周" : "下一周"].firstMatch
            XCTAssertTrue(week.waitForExistence(timeout: 5))
            show(week, app: app, fullyVisible: true)
            week.tap()
        }
        XCTAssertTrue(selectedDay.waitForExistence(timeout: 5), "本轮fixture日期必须在可见周历内")
        selectedDay.tap()
        XCTAssertTrue(selectedDay.isSelected, "先明确选中目标日期，再验证改期入口的状态")
        return app
    }

    private func openPastReschedule(_ app: XCUIApplication) {
        let direct = app.buttons["训练-调整过去计划日期"]
        XCTAssertTrue(direct.waitForExistence(timeout: 5))
        show(direct, app: app, fullyVisible: true); direct.tap()
        XCTAssertTrue(app.navigationBars["调整训练日期"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["训练菜单"].exists, "首页入口应直接打开改期表单")
    }

    private func openDateMenu(_ app: XCUIApplication, localDay: String) {
        let menu = app.buttons["训练-日期菜单"]
        show(menu, app: app); menu.tap()
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + localDay].waitForExistence(timeout: 5))
    }

    private func returnHomeFromDateMenu(_ app: XCUIApplication) {
        app.navigationBars["训练菜单"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["训练-日期菜单"].waitForExistence(timeout: 5))
    }

    private func previewAndConfirmPastReschedule(_ app: XCUIApplication) {
        let preview = app.buttons["计划管理-预览改期"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5)); XCTAssertTrue(preview.isEnabled); preview.tap()
        XCTAssertTrue(app.navigationBars["确认改期"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["原日期"].exists)
        XCTAssertTrue(app.staticTexts["新日期"].exists)
        let confirm = app.buttons["计划管理-确认改期"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let result = app.staticTexts["过去计划改期-结果"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.hasPrefix("已改期至"))
    }

    func testPastCardioDirectRescheduleCancelsPreviewsMovesToTodayAndUndoes() {
        let app = launchPastReschedule()
        let direct = app.buttons["训练-调整过去计划日期"]
        XCTAssertTrue(direct.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["训练-有氧指标"].label, "40 分钟")
        openDateMenu(app, localDay: day(-1))
        let plan = app.buttons["日期菜单-管理安排-" + pastPlanID]
        let companion = app.buttons["日期菜单-管理安排-" + pastCompanionID]
        XCTAssertTrue(plan.exists); XCTAssertTrue(companion.exists)
        returnHomeFromDateMenu(app)
        capture("past-cardio-direct-entry", app: app)

        openPastReschedule(app)
        let preview = app.buttons["计划管理-预览改期"]
        XCTAssertTrue(preview.isEnabled, "过去计划的初始目标应为今天，无需重新选日即可预览")
        preview.tap()
        XCTAssertTrue(app.navigationBars["确认改期"].waitForExistence(timeout: 5))
        capture("past-cardio-today-preview", app: app)
        app.navigationBars["确认改期"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["调整训练日期"].waitForExistence(timeout: 5))
        app.navigationBars["调整训练日期"].buttons["取消"].tap()
        XCTAssertTrue(direct.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["过去计划改期-结果"].exists)
        openDateMenu(app, localDay: day(-1))
        XCTAssertTrue(plan.exists, "预览后取消必须保留原日的同一计划")
        XCTAssertTrue(companion.exists)
        returnHomeFromDateMenu(app)

        openPastReschedule(app)
        previewAndConfirmPastReschedule(app)
        openDateMenu(app, localDay: day(-1))
        XCTAssertFalse(plan.exists, "保存后原日不能残留同一计划")
        XCTAssertTrue(companion.exists, "改一场不能顺延或删除同日另一场")
        returnHomeFromDateMenu(app)
        app.buttons["过去计划改期-查看"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + day()].waitForExistence(timeout: 5))
        XCTAssertTrue(plan.exists, "查看改期结果必须定位到原计划UUID")
        XCTAssertEqual(app.buttons.matching(identifier: "日期菜单-管理安排-" + pastPlanID).count, 1)
        XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "日期菜单-管理安排-")).count, 1,
            "今天既有的其他安排应保留，查看必须直接打开包含改期计划的菜单")
        XCTAssertTrue(app.staticTexts["目标 · 40 分钟"].exists)
        XCTAssertFalse(companion.exists, "同日另一场仍留在原日期")
        returnHomeFromDateMenu(app)
        XCTAssertTrue(app.buttons["训练日期-" + day()].isSelected)
        XCTAssertFalse(direct.exists, "今天的计划不显示过去计划改期入口")
        app.buttons["过去计划改期-撤销"].tap()
        XCTAssertEqual(app.staticTexts["过去计划改期-结果"].label, "已撤销本次调整")
        XCTAssertTrue(app.buttons["训练日期-" + day()].isSelected, "撤销恢复数据，当前查看日期保持不变")
        app.buttons["过去计划改期-查看"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + day(-1)].waitForExistence(timeout: 5))
        XCTAssertTrue(plan.exists); XCTAssertTrue(companion.exists)
        XCTAssertTrue(app.staticTexts["目标 · 40 分钟"].exists)
        returnHomeFromDateMenu(app)
        XCTAssertTrue(app.buttons["训练日期-" + day(-1)].isSelected)
        show(direct, app: app); XCTAssertTrue(direct.isHittable)
        app.buttons["过去计划改期-关闭结果"].tap()
        XCTAssertFalse(app.staticTexts["过去计划改期-结果"].exists)
    }

    func testPastRopeDirectRescheduleCrossesMonthAndPreservesTargetAndCompanion() {
        let app = launchPastReschedule("rope")
        XCTAssertTrue(app.buttons["训练-打开跳绳菜单"].exists)
        openPastReschedule(app)
        let nextMonth = Calendar.current.dateInterval(of: .month, for: Date())!.end
        let targetDate = Calendar.current.date(byAdding: .day, value: 4, to: nextMonth)!
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let targetDay = formatter.string(from: targetDate)
        selectManagedPlanDate(targetDate, app: app)
        previewAndConfirmPastReschedule(app)
        app.buttons["过去计划改期-查看"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + targetDay].waitForExistence(timeout: 5))
        let plan = app.buttons["日期菜单-管理安排-" + pastPlanID]
        XCTAssertTrue(plan.exists)
        XCTAssertFalse(app.buttons["日期菜单-记录跳绳-" + pastPlanID].exists, "改到未来不能产生实际或提前记录")
        XCTAssertTrue(app.staticTexts["目标 · 1200 次 · 有效 8 分钟 · 含休息 10 分钟"].exists)
        XCTAssertTrue(app.staticTexts["保留原跳绳目标"].exists)
        capture("past-rope-rescheduled-next-month", app: app)
        returnHomeFromDateMenu(app)
        XCTAssertTrue(app.buttons["训练日期-" + targetDay].isSelected)
        XCTAssertFalse(app.buttons["训练-调整过去计划日期"].exists, "未来计划不显示过去计划入口")
        app.buttons["过去计划改期-撤销"].tap()
        XCTAssertEqual(app.staticTexts["过去计划改期-结果"].label, "已撤销本次调整")
        app.buttons["过去计划改期-查看"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + day(-1)].waitForExistence(timeout: 5))
        XCTAssertTrue(plan.exists)
        XCTAssertTrue(app.buttons["日期菜单-管理安排-" + pastCompanionID].exists)
        XCTAssertTrue(app.staticTexts["目标 · 1200 次 · 有效 8 分钟 · 含休息 10 分钟"].exists)
    }

    func testPastStrengthDirectRescheduleIsReachableAtLargestTextSize() {
        let app = launchPastReschedule("strength", large: true)
        XCTAssertTrue(app.buttons["开始训练"].exists)
        openPastReschedule(app)
        XCTAssertTrue(app.staticTexts["背部 · 隔离改期力量"].exists)
        let conflict = app.staticTexts["这一天已有另一场力量训练，请选择其他日期。"]
        show(conflict, app: app)
        XCTAssertTrue(conflict.exists, "保留今天原力量安排，最大字号下也应提示冲突")
        XCTAssertFalse(app.buttons["计划管理-预览改期"].isEnabled, "不能把过去力量计划静默合并进已有力量训练日")
        capture("past-strength-reschedule-large", app: app)
        app.navigationBars["调整训练日期"].buttons["取消"].tap()
        let direct = app.buttons["训练-调整过去计划日期"]
        show(direct, app: app); XCTAssertTrue(direct.isHittable)
    }

    func testDirectPastRescheduleIsHiddenForTodayFutureStartedAndRecordedPlans() {
        for variant in ["today", "future", "started", "actual"] {
            let app = launchPastReschedule(variant)
            XCTAssertFalse(app.buttons["训练-调整过去计划日期"].exists, "\(variant) 不应显示过去待练计划入口")
            if variant == "started" { XCTAssertTrue(app.buttons["继续训练"].exists) }
            if variant == "actual" {
                XCTAssertTrue(app.otherElements["训练-当天实际"].exists)
                XCTAssertFalse(app.buttons["训练-训练总结"].exists)
            }
            app.terminate()
        }
    }

    private func selectTomorrowForManagedPlan(_ app: XCUIApplication) {
        selectManagedPlanDate(Calendar.current.date(byAdding: .day, value: 1, to: Date())!, app: app)
    }

    private func selectManagedPlanDate(_ targetDate: Date, app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["计划管理-新日期"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        show(picker, app: app)
        let fieldButton = picker.buttons.firstMatch
        if fieldButton.exists { fieldButton.tap() } else { picker.tap() }
        if !Calendar.current.isDate(Date(), equalTo: targetDate, toGranularity: .month) {
            let nextMonth = app.buttons.matching(NSPredicate(format: "label IN %@", ["下个月", "下月", "Next Month", "Next month"]))
                .allElementsBoundByIndex.first(where: \.isHittable)
            guard let nextMonth else { return XCTFail("系统日期选择器缺少可访问的下个月按钮：\(app.debugDescription)") }
            nextMonth.tap()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月d日"
        let chineseDate = formatter.string(from: targetDate)
        formatter.locale = Locale(identifier: "en_US"); formatter.dateFormat = "MMMM d, yyyy"
        let englishDate = formatter.string(from: targetDate)
        let fullDate = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", chineseDate, englishDate))
            .allElementsBoundByIndex.first(where: \.isHittable)
        let number = String(Calendar.current.component(.day, from: targetDate))
        let dayButton = app.buttons.matching(NSPredicate(format: "label IN %@", [number, number + "日"]))
            .allElementsBoundByIndex.first(where: \.isHittable)
        let dayText = app.staticTexts.matching(NSPredicate(format: "label IN %@", [number, number + "日"]))
            .allElementsBoundByIndex.first(where: \.isHittable)
        guard let target = fullDate ?? dayButton ?? dayText else {
            return XCTFail("系统日期选择器中无法找到目标日期的可访问日期：\(app.debugDescription)")
        }
        target.tap()
        // The system compact picker keeps its popup open after choosing a day.
        let dismissPopup = app.buttons["PopoverDismissRegion"]
        if dismissPopup.exists && dismissPopup.isHittable {
            dismissPopup.tap()
        } else if let dismissRegion = app.descendants(matching: .any)
            .matching(identifier: "PopoverDismissRegion").allElementsBoundByIndex.first(where: \.isHittable) {
            dismissRegion.tap()
        }
        let preview = app.buttons["计划管理-预览改期"]
        if !preview.isHittable {
            capture("managed-picker-dismiss-failure", app: app)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "managed-picker-dismiss-failure-tree"
            tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(preview.isHittable, "选日后系统弹层应关闭，原生预览按钮必须可操作")
    }
}
