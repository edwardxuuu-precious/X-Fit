import XCTest

final class RedesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testReadOnlySchedulePreviewWithExplicitPersistentCopy() throws {
        guard ProcessInfo.processInfo.environment["XFIT_SCHEDULE_REAL_PREVIEW"] == "1" else {
            throw XCTSkip("仅在已备份的独立模拟器真实数据副本上显式运行")
        }
        XCTAssertEqual(ProcessInfo.processInfo.environment["SIMULATOR_UDID"], "9C5698EB-9668-4383-9371-030E10D086D3")
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-persistent"]
        app.launch()
        XCTAssertTrue(app.xfitTabButtons["我的"].waitForExistence(timeout: 15))
        app.xfitTabButtons["我的"].tap()
        let schedule = app.buttons["训练日程"]
        reveal(schedule, app); schedule.tap()
        XCTAssertTrue(app.buttons["日程-选择月份"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.buttons["日程-折叠日历"].value as? String, "折叠")
        app.buttons["日程-折叠日历"].tap()
        let recordedDay = app.buttons["日程-日历日期-2026-10-19"]
        XCTAssertTrue(recordedDay.waitForExistence(timeout: 5))
        recordedDay.tap()
        XCTAssertEqual(app.buttons["日程-折叠日历"].value as? String, "折叠")
        capture("schedule-real-copy-month", app)
        app.scrollViews.firstMatch.swipeDown()
        app.scrollViews.firstMatch.swipeDown()
        capture("schedule-real-copy-month-overview", app)
        let actuals = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "实际训练-"))
        XCTAssertTrue(actuals.firstMatch.waitForExistence(timeout: 5))
        app.buttons["日程-折叠日历"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "日程-日历日期-")).firstMatch.waitForExistence(timeout: 5))
        capture("schedule-real-copy-calendar-expanded", app)
        app.buttons["日程-折叠日历"].tap()
        let bike = actuals.matching(NSPredicate(format: "label CONTAINS %@", "固定单车")).firstMatch
        XCTAssertTrue(bike.waitForExistence(timeout: 5))
        reveal(bike, app); bike.tap()
        XCTAssertTrue(app.navigationBars["训练总结"].waitForExistence(timeout: 5))
        capture("schedule-real-copy-cardio-detail", app)
    }
    private func launch(
        large: Bool = false,
        lowerBodyWeek: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview"]
        if lowerBodyWeek { app.launchArguments.append("--ui-testing-lower-body-week") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.xfitTabButtons["训练"].waitForExistence(timeout: 15))
        return app
    }
    private func openTrainingPlan(_ app: XCUIApplication) {
        app.buttons["主导航-我的"].tap()
        let management = app.buttons["模板与动作"]
        reveal(management, app); management.tap()
        let plans = app.buttons["训练管理-训练编排导入"]
        XCTAssertTrue(plans.waitForExistence(timeout: 5))
        reveal(plans, app); plans.tap()
        XCTAssertTrue(app.navigationBars["训练编排"].waitForExistence(timeout: 5))
    }

    private func openSettingsData(_ app: XCUIApplication) {
        app.buttons["主导航-我的"].tap()
        for _ in 0..<6 {
            if app.navigationBars["设置"].exists { break }
            let settings = app.buttons["打开设置"]
            if settings.exists { reveal(settings, app); settings.tap(); break }
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
        }
        let data = app.buttons["设置-数据"]
        XCTAssertTrue(data.waitForExistence(timeout: 5)); data.tap()
    }
    private func openGoal(_ app: XCUIApplication) {
        app.buttons["主导航-进展"].tap()
        for _ in 0..<6 {
            if app.navigationBars["目标与周期"].exists { return }
            let entry = app.buttons["目标与周期"]
            if entry.exists {
                reveal(entry, app); entry.tap()
                XCTAssertTrue(app.navigationBars["目标与周期"].waitForExistence(timeout: 5))
                return
            }
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
        }
        XCTFail("进展中的目标与周期必须可达")
    }
    private func openNutritionTools(_ app: XCUIApplication) {
        app.buttons["主导航-饮食"].tap()
        for _ in 0..<6 {
            if app.navigationBars["餐单与备餐"].exists { return }
            let entry = app.buttons["餐单、备餐与全部餐食"]
            if entry.exists {
                reveal(entry, app); entry.tap()
                XCTAssertTrue(app.navigationBars["餐单与备餐"].waitForExistence(timeout: 5))
                return
            }
            let back = app.navigationBars.buttons.firstMatch
            guard back.exists else { break }
            back.tap()
        }
        XCTFail("饮食中的餐单与备餐必须可达")
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        func bounds() -> (top: CGFloat, bottom: CGFloat) {
            let bars = app.navigationBars.allElementsBoundByIndex.filter {
                $0.frame.height > 0 && $0.frame.intersects(app.frame)
            }
            let top = (bars.map { $0.frame.maxY }.max() ?? app.frame.minY) + 8
            var bottom = app.frame.maxY - 8
            let tabBar = app.xfitTabBar
            if tabBar.exists && app.xfitTabButtons.allElementsBoundByIndex.contains(where: \.isHittable) {
                bottom = min(bottom, tabBar.frame.minY - 8)
            }
            for identifier in ["饮食-拍照记餐", "备餐-底部分享", "食谱-切换内容"] {
                let footer = app.buttons.matching(identifier: identifier).firstMatch
                if footer.exists && footer.isHittable { bottom = min(bottom, footer.frame.minY - 8) }
            }
            return (top, bottom)
        }
        for _ in 0..<8 {
            let visible = bounds()
            if item.exists && item.isHittable && item.frame.midY > visible.top && item.frame.midY < visible.bottom { return }
            let viewport = visible.bottom - visible.top
            guard viewport > 44 else { XCTFail("当前页面必须有可滚动的内容区"); return }
            let center = (visible.top + visible.bottom) / 2
            let delta = item.exists && !item.frame.isEmpty ? center - item.frame.midY : -viewport
            let distance = min(max(abs(delta), 32), viewport * 0.8)
            let startY = delta < 0 ? visible.bottom - 8 : visible.top + 8
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0))
                .withOffset(CGVector(dx: 0, dy: startY - app.frame.minY))
            let end = start.withOffset(CGVector(dx: 0, dy: delta < 0 ? -distance : distance))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        let visible = bounds()
        capture("reveal-budget-exhausted", app)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "reveal-budget-exhausted-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
        XCTAssertTrue(item.isHittable)
        XCTAssertGreaterThan(item.frame.midY, visible.top, "点击中心必须位于导航栏下方")
        XCTAssertLessThan(item.frame.midY, visible.bottom, "点击中心必须位于当前固定底部操作区上方")
    }
    private func launchRecordedDay(partial: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview", "--ui-testing-recorded-day"]
        if partial { app.launchArguments.append("--ui-testing-recorded-day-partial") }
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["训练-当天状态"].waitForExistence(timeout: 15))
        return app
    }

    private func verifyMonthlySchedule(large: Bool) {
        let app = launchRecordedDay(partial: true, large: large)
        let dayButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练日期-"))
        guard let other = dayButtons.allElementsBoundByIndex.first(where: { !$0.isSelected }) else {
            return XCTFail("需要一个可选择的其他日期")
        }
        let chosen = String(other.identifier.dropFirst("训练日期-".count))
        other.tap()
        app.buttons["训练日程"].tap()
        let month = app.buttons["日程-选择月份"]
        XCTAssertTrue(month.waitForExistence(timeout: 8))
        let expectedMonth = String(chosen.prefix(7))
        XCTAssertEqual(month.value as? String, expectedMonth)
        XCTAssertFalse(app.staticTexts["页标题-训练日程"].exists, "正文不再重复导航标题")
        XCTAssertFalse(app.buttons["日程-分类-记录"].exists)
        let calendar = app.buttons["日程-折叠日历"]
        XCTAssertGreaterThanOrEqual(calendar.frame.height, 44)
        XCTAssertEqual(calendar.value as? String, "折叠")
        XCTAssertFalse(app.buttons["日程-日历日期-" + chosen].exists)
        month.tap()
        XCTAssertTrue(app.navigationBars["选择月份"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertEqual(month.value as? String, expectedMonth)
        app.buttons["日程-上个月"].tap()
        XCTAssertNotEqual(month.value as? String, expectedMonth)
        capture("schedule-month-previous", app)
        app.buttons["日程-下个月"].tap()
        XCTAssertEqual(month.value as? String, expectedMonth)
        calendar.tap()
        let selectedDate = app.buttons["日程-日历日期-" + chosen]
        XCTAssertTrue(selectedDate.waitForExistence(timeout: 5))
        capture(large ? "schedule-calendar-large" : "schedule-calendar-normal", app)
        selectedDate.tap()
        XCTAssertEqual(calendar.value as? String, "折叠")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(other.isSelected, "切月、日期定位与返回不能修改首页选日")
        app.buttons["训练日程"].tap()
        app.buttons["日程-回到今天"].tap()
        let oldPlan = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI旧安排")).firstMatch
        reveal(oldPlan, app)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "日程-安排操作-")).firstMatch.exists,
            "卡片按确认稿只保留类型、名称和状态，安排操作从长按进入")
        oldPlan.press(forDuration: 1)
        app.buttons["跳过训练"].tap()
        app.alerts.buttons["确认跳过"].tap()
        XCTAssertTrue(oldPlan.label.contains("已跳过"))
        oldPlan.press(forDuration: 1); app.buttons["恢复训练"].tap()
        XCTAssertFalse(oldPlan.label.contains("已跳过"))
        app.buttons["新增训练安排"].tap()
        XCTAssertTrue(app.buttons["从现有模板安排"].waitForExistence(timeout: 5))
        app.buttons["从现有模板安排"].tap()
        XCTAssertTrue(app.navigationBars["临时加练"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        capture(large ? "schedule-month-small-accessibility" : "schedule-month-normal", app)
        let actual = app.buttons["实际训练-DAD00000-0000-4000-8000-000000000001"]
        reveal(actual, app)
        XCTAssertEqual(app.buttons.matching(identifier: actual.identifier).count, 1, "关联实际仅展示一次")
        XCTAssertTrue(actual.label.contains("17/20"))
        XCTAssertFalse(app.staticTexts["已记录 17/20 组"].exists, "列表使用图形，无障碍标签保留精确数字")
        XCTAssertTrue(oldPlan.exists, "待完成安排与实际同屏保留")
        capture(large ? "schedule-graphics-small-accessibility" : "schedule-graphics-normal", app)
        actual.tap()
        XCTAssertTrue(app.navigationBars["UI实际下肢"].waitForExistence(timeout: 8))
    }

    func testMonthlySchedulePreservesDateActionsAndLinkedActualDetail() {
        verifyMonthlySchedule(large: false)
    }

    func testMonthlyScheduleRemainsUsableAtLargestAccessibilitySize() {
        verifyMonthlySchedule(large: true)
    }

    func testEmptyMonthCalendarDateRetainsDateMenuAndMonth() {
        let app = launchRecordedDay()
        app.buttons["训练日程"].tap()
        let future = Calendar.current.date(byAdding: .year, value: 3, to: Date())!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"
        let targetMonth = formatter.string(from: future)
        app.buttons["日程-选择月份"].tap()
        for _ in 0..<3 { app.buttons["下一年"].tap() }
        app.buttons["日程-月份-" + targetMonth].tap()
        XCTAssertTrue(app.staticTexts["日程-空月份"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["日程-选择月份"].value as? String, targetMonth)
        app.buttons["日程-折叠日历"].tap()
        app.buttons["日程-日历日期-" + targetMonth + "-01"].tap()
        XCTAssertEqual(app.buttons["日程-折叠日历"].value as? String, "折叠")
        let emptyDate = app.buttons["日程-空日期"]
        XCTAssertTrue(emptyDate.waitForExistence(timeout: 5))
        XCTAssertTrue(emptyDate.isHittable)
        capture("schedule-empty-month-selected-date", app)
        emptyDate.tap()
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(app.buttons["日程-选择月份"].value as? String, targetMonth)
    }

    func testIndependentActualAndOldPlanRemainDistinctAndHistoryOnlyDayIsReachable() {
        let app = launchRecordedDay()
        XCTAssertEqual(app.staticTexts["训练-当天状态"].label, "已记录训练")
        XCTAssertTrue(app.buttons["训练-其他待完成安排"].label.contains("安排待完成"))
        let actual = app.staticTexts["训练-训练标题"]
        XCTAssertTrue(actual.exists, app.debugDescription)
        XCTAssertTrue(actual.isHittable)
        XCTAssertTrue(app.buttons["训练-其他待完成安排"].exists)
        capture("day-status-actual-with-pending-plan", app)
        actual.tap()
        XCTAssertTrue(app.navigationBars["UI实际下肢"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        let calendar = app.buttons["训练日程"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5)); calendar.tap()
        let olderDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        app.buttons["日程-选择月份"].tap()
        if Calendar.current.component(.year, from: olderDate) < Calendar.current.component(.year, from: Date()) {
            app.buttons["上一年"].tap()
        }
        app.buttons["日程-月份-" + formatter.string(from: olderDate)].tap()
        let older = app.buttons["实际训练-DAD00000-0000-4000-8000-000000000002"]
        for _ in 0..<12 {
            if older.exists && older.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(older.isHittable, "没有日程的实际训练日也必须出现在日程列表")
        older.tap()
        XCTAssertTrue(app.navigationBars["UI无安排实际"].waitForExistence(timeout: 8))
    }

    func testPartialActualSeventeenOfTwentyAndCurrentMainPages() {
        let app = launchRecordedDay(partial: true)
        XCTAssertEqual(app.staticTexts["训练-当天状态"].label, "已记录 17/20 组")
        XCTAssertTrue(app.buttons["训练-其他待完成安排"].label.contains("安排待完成"))
        capture("day-status-seventeen-of-twenty", app)
        app.buttons["训练日程"].tap()
        let actualRow = app.buttons["实际训练-DAD00000-0000-4000-8000-000000000001"]
        XCTAssertTrue(actualRow.waitForExistence(timeout: 5))
        XCTAssertTrue(actualRow.label.contains("17/20"))
        XCTAssertFalse(app.staticTexts["已记录 17/20 组"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI旧安排")).firstMatch.exists)
        capture("day-status-schedule-partial", app)
        app.xfitTabButtons["饮食"].tap(); capture("entry-nutrition-current", app)
        app.xfitTabButtons["进展"].tap(); capture("entry-progress-current", app)
        app.xfitTabButtons["我的"].tap(); capture("entry-profile-current", app)
        XCTAssertEqual(app.xfitTabButtons.count, 5)
    }

    func testActualDayRemainsReadableAtAccessibilityTextSize() {
        let app = launchRecordedDay(partial: true, large: true)
        XCTAssertEqual(app.staticTexts["训练-当天状态"].label, "已记录 17/20 组")
        let actual = app.staticTexts["训练-训练标题"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        reveal(actual, app)
        capture("day-status-accessibility-size", app)
        actual.tap()
        XCTAssertTrue(app.navigationBars["UI实际下肢"].waitForExistence(timeout: 8))
    }
    func testRecipeIngredientsStepsAndReferencePortions() {
        let app = launch()
        openNutritionTools(app)
        let prep = app.buttons["饮食-明日备餐"]
        reveal(prep, app)
        XCTAssertTrue(prep.isEnabled)
        capture("large-recipe-prep-entry-above-fixed-actions", app)
        prep.tap()
        XCTAssertTrue(app.navigationBars["明日备餐"].waitForExistence(timeout: 5))
        let lunch = app.buttons["备餐-食谱-午餐"]
        XCTAssertTrue(lunch.waitForExistence(timeout: 5)); lunch.tap()
        XCTAssertTrue(app.navigationBars["食谱详情"].waitForExistence(timeout: 5))
        let portions = app.staticTexts["食谱-原配方份数"]
        XCTAssertTrue(portions.label.contains("原配方 2 份"))
        capture("16-recipe-ingredients", app)
        XCTAssertTrue(app.buttons["食谱-切换内容"].isHittable)
        app.buttons["食谱-切换内容"].tap()
        let step = app.descendants(matching: .any)["食谱-步骤-1"].firstMatch
        XCTAssertTrue(step.exists)
        capture("17-recipe-steps", app)
        app.buttons["食谱-切换内容"].tap()
        let ingredient = app.buttons["食谱-食材-去皮鸡肉"]
        reveal(ingredient, app); ingredient.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "医生")).firstMatch.exists)
    }
    func testProfileBackupDirectEntryAndSettingsTabs() {
        let app = launch()
        app.xfitTabButtons["我的"].tap()
        capture("20-profile", app)
        openSettingsData(app)
        let generate = app.buttons["设置-生成备份"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        XCTAssertTrue(generate.isHittable, "设置的数据模式必须可直接生成备份")
        capture("21-backup", app)
        generate.tap()
        XCTAssertTrue(app.buttons["分享最新备份"].waitForExistence(timeout: 5))
        app.buttons["设置-通用"].tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label CONTAINS %@", "训练日提醒")).firstMatch.waitForExistence(timeout: 5))
        capture("22-preferences", app)
        app.buttons["设置-数据"].tap()
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["设置-导入备份"].exists)
    }
    func testReviewDraftSaveAndHistoricalReadback() {
        let app = launch()
        openGoal(app)
        let review = app.buttons["减脂每周复盘"]
        reveal(review, app); review.tap()
        XCTAssertTrue(app.staticTexts["复盘-均重"].waitForExistence(timeout: 5))
        capture("18-weekly-progress", app)
        func focusAboveSave(_ field: XCUIElement) {
            let save = app.buttons["复盘-底部保存"]
            for _ in 0..<8 {
                if field.exists && field.isHittable && field.frame.midY < save.frame.minY - 20 { break }
                app.swipeUp()
            }
            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        }
        let note = app.textFields["本周体重、饥饿、腹胀与训练表现"]
        focusAboveSave(note); note.typeText("本周训练状态稳定")
        XCTAssertTrue(app.buttons["复盘-底部保存"].isHittable)
        capture("19a-review-keyboard", app)
        app.buttons["减脂完成输入"].tap()
        let next = app.textFields["下一步（如维持观察、换菜、复查）"]
        focusAboveSave(next); next.typeText("继续观察腰围")
        app.buttons["减脂完成输入"].tap()
        capture("19-review-draft", app)
        app.buttons["复盘-底部保存"].tap()
        let history = app.buttons["复盘-历史"]
        reveal(history, app); history.tap()
        let savedNote = app.staticTexts["本周训练状态稳定"]
        reveal(savedNote, app)
        XCTAssertTrue(savedNote.isHittable)
        XCTAssertTrue(app.staticTexts["下一步：继续观察腰围"].exists)
    }
    func testLargeTypeRecipeReviewAndDataActions() {
        let app = launch(large: true)
        app.xfitTabButtons["我的"].tap()
        openSettingsData(app)
        let generate = app.buttons["设置-生成备份"]
        reveal(generate, app)
        XCTAssertGreaterThanOrEqual(generate.frame.height, 44)
        capture("23-large-backup", app)
        openGoal(app)
        let review = app.buttons["减脂每周复盘"]
        reveal(review, app); review.tap()
        XCTAssertTrue(app.buttons["复盘-底部保存"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["复盘-底部保存"].isHittable)
        capture("24-large-review", app)
        openNutritionTools(app)
        let prep = app.buttons["饮食-明日备餐"]
        reveal(prep, app)
        XCTAssertTrue(prep.isEnabled)
        capture("large-progress-prep-entry-above-fixed-actions", app)
        prep.tap()
        XCTAssertTrue(app.navigationBars["明日备餐"].waitForExistence(timeout: 5))
        let menuPage = app.buttons["备餐-菜单页"]
        XCTAssertTrue(menuPage.isSelected)
        let lunch = app.buttons["备餐-食谱-午餐"]
        reveal(lunch, app)
        XCTAssertTrue(menuPage.isSelected, "滚动寻找午餐时必须保留分装页")
        lunch.tap()
        let toggle = app.buttons["食谱-切换内容"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        let step = app.descendants(matching: .any)["食谱-步骤-1"].firstMatch
        reveal(step, app)
        capture("25-large-recipe", app)
    }
    func testCoreTrainingAndResume() {
        let app = launch()
        XCTAssertEqual(app.xfitTabButtons.count, 5)
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.isHittable)
        capture("01-training-home", app)
        start.tap()
        let complete = app.buttons["完成第 1 组"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 8))
        XCTAssertEqual(complete.value as? String, "未完成")
        capture("02-training-record", app)
        reveal(complete, app); complete.tap()
        XCTAssertTrue(app.buttons["第 1 组已完成"].firstMatch.waitForExistence(timeout: 5))
        let completed = app.buttons["第 1 组已完成"].firstMatch
        XCTAssertEqual(completed.value as? String, "已完成")
        capture("02a-training-completed-set", app)
        completed.tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertEqual(complete.value as? String, "未完成")
        complete.tap()
        app.xfitTabButtons["饮食"].tap()
        app.xfitTabButtons["训练"].tap()
        XCTAssertTrue(app.buttons["第 1 组已完成"].firstMatch.exists)
    }
    func testCoreMuscleSelection() {
        let app = launch()
        app.buttons["开始训练"].tap()
        let add = app.xfitWorkoutAction("临时加动作")
        XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let exerciseSearch = app.searchFields.firstMatch
        XCTAssertTrue(exerciseSearch.waitForExistence(timeout: 5))
        exerciseSearch.tap(); exerciseSearch.typeText("高位下拉\n")
        XCTAssertTrue(app.staticTexts["高位下拉"].firstMatch.waitForExistence(timeout: 5))
        let map = app.buttons["打开肌群图筛选"]
        XCTAssertTrue(map.waitForExistence(timeout: 5)); map.tap()
        XCTAssertTrue(app.textFields["肌群中文搜索"].waitForExistence(timeout: 5))
        let chestRegion = app.buttons["training-region-front-chest"]
        XCTAssertTrue(chestRegion.isHittable); chestRegion.tap()
        XCTAssertEqual(app.buttons["胸部"].value as? String, "已选择")
        let shoulder = app.buttons["training-region-front-right-shoulder"]
        XCTAssertTrue(shoulder.isHittable)
        shoulder.tap()
        XCTAssertEqual(app.buttons["肩部"].value as? String, "已选择")
        XCTAssertEqual(app.buttons["胸部"].value as? String, "已选择", "相邻肩部点击不得取消胸部")
        shoulder.tap()
        XCTAssertEqual(app.buttons["肩部"].value as? String, "未选择")
        capture("03-muscle-selection", app)
        for name in ["肩部", "腿部", "小腿"] { app.buttons[name].tap() }
        capture("03c-muscle-reference-selection", app)
        for name in ["肩部", "腿部", "小腿"] { app.buttons[name].tap() }
        app.buttons["背面"].tap()
        let backRegion = app.buttons["training-region-back-left-lat"]
        XCTAssertTrue(backRegion.isHittable); backRegion.tap()
        XCTAssertEqual(app.buttons["背部"].value as? String, "已选择")
        capture("03b-muscle-back", app)
        backRegion.tap()
        XCTAssertEqual(app.buttons["背部"].value as? String, "未选择")
        app.buttons["完成"].tap()
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertTrue(map.label.contains("胸部"))
        XCTAssertFalse(app.staticTexts["高位下拉"].firstMatch.exists)
        map.tap()
        XCTAssertTrue(app.textFields["肌群中文搜索"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["胸部"].value as? String, "已选择")
        app.buttons["清除"].tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertEqual(map.label, "按肌群选择")
        XCTAssertTrue(app.staticTexts["高位下拉"].firstMatch.waitForExistence(timeout: 5))
    }
    func testCoreFoodActualAndPrep() {
        let app = launch()
        openNutritionTools(app)
        XCTAssertTrue(app.buttons["饮食-调整实吃-早餐"].waitForExistence(timeout: 5))
        capture("04-food-home", app)
        app.buttons["饮食-调整实吃-早餐"].tap()
        XCTAssertTrue(app.buttons["保存计划实吃"].waitForExistence(timeout: 5))
        capture("05-actual-meal-editor", app)
        app.buttons["保存计划实吃"].tap()
        XCTAssertTrue(app.staticTexts["已记录"].firstMatch.waitForExistence(timeout: 5))
        let prep = app.buttons["饮食-明日备餐"]
        reveal(prep, app); prep.tap()
        XCTAssertTrue(app.navigationBars["明日备餐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["备餐-份数摘要"].exists)
        XCTAssertTrue(app.buttons["备餐-首屏用量说明"].isHittable)
        capture("06-tomorrow-prep", app)
        app.buttons["备餐-采购页"].tap()
        let winterMelon = app.staticTexts["备餐用量-冬瓜"]
        reveal(winterMelon, app)
        XCTAssertTrue(winterMelon.label.contains("合计"))
        capture("06b-shopping-list", app)
        let portions = app.buttons["备餐-用量说明"]
        let fixedShare = app.buttons["备餐-底部分享"]
        for _ in 0..<5 {
            if portions.exists && portions.isHittable && portions.frame.maxY < fixedShare.frame.minY - 12 { break }
            app.swipeUp()
        }
        XCTAssertLessThan(portions.frame.maxY, fixedShare.frame.minY - 12)
        portions.tap()
        XCTAssertTrue(app.navigationBars["份量说明"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["页标题-份量待确认"].exists)
        capture("06c-portion-info", app)
        app.buttons["关闭"].tap()
        app.buttons["备餐-菜单页"].tap()
        XCTAssertTrue(app.staticTexts["备餐-份数摘要"].exists)
    }
    func testCoreGoalReviewAndMuscles() {
        let app = launch()
        openGoal(app)
        XCTAssertTrue(app.descendants(matching: .any)["目标-主目标"].firstMatch.waitForExistence(timeout: 5))
        let average = app.descendants(matching: .any)["目标-当前均重"].firstMatch
        XCTAssertTrue(average.waitForExistence(timeout: 5))
        XCTAssertTrue(average.isHittable, "当前均重应在首屏直接可见")
        XCTAssertTrue(app.buttons["目标-记录体重"].isHittable)
        capture("07-goal-home", app)
        let review = app.buttons["减脂每周复盘"]
        reveal(review, app); review.tap()
        XCTAssertTrue(app.navigationBars["每周复盘"].waitForExistence(timeout: 5), "确实打开复盘后才采集截图")
        capture("08-weekly-review", app)
        app.xfitTabButtons["我的"].tap()
        let library = app.buttons["模板与动作"]
        reveal(library, app); library.tap()
        // Exercise selection is checked independently through a new day plan.
    }
    func testCycleImportAndExportRemainReachable() {
        let app = launch()
        openTrainingPlan(app)
        XCTAssertTrue(app.navigationBars["训练编排"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["训练编排-版本"].waitForExistence(timeout: 5), "只有一版时也应能看到明确的编排选择入口")
        // The ordinary preview fixture runs the current preference migration before
        // creating its first program; historical revisions have dedicated tests.
        XCTAssertTrue(app.staticTexts["TP-20261021-06"].exists, "当前fixture应关联已生效的递增金字塔偏好版本")
        XCTAssertTrue(app.staticTexts["CUT-4D-20260908"].exists, "当前fixture的首周编排快照必须与偏好版本一起核对")
        capture("training-week-overview", app)
        let preview = app.buttons["预览减脂训练导入"]
        reveal(preview, app); preview.tap()
        XCTAssertTrue(app.navigationBars["导入前预览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["训练导入-摘要"].firstMatch.exists)
        let importAction = app.buttons["确认导入减脂训练"]
        XCTAssertTrue(importAction.exists)
        let summary = app.descendants(matching: .any)["训练导入-摘要"].firstMatch
        capture("training-week-import-preview", app)
        XCTAssertTrue(importAction.label.hasPrefix("导入"), "按钮应明确是导入操作：\(importAction.label)")
        XCTAssertTrue(
            importAction.label.hasSuffix("条训练日程") || importAction.label.hasSuffix("条日程"),
            "导入数量应随本周真实日期冲突变化；预览摘要：\(summary.label)，按钮：\(importAction.label)"
        )
        XCTAssertTrue(importAction.isEnabled, "当天已有手动训练时，仍应允许导入其余无冲突日期")
        XCTAssertTrue(importAction.isHittable, "主要导入操作应直接可点击，不应藏在导航栏或冲突开关后")
        importAction.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@",
            "已导入 ", "条训练日程"
        )).firstMatch.waitForExistence(timeout: 5))
        capture("training-week-import-visible-result", app)
        app.xfitTabButtons["我的"].tap()
        openSettingsData(app)
        let export = app.buttons["设置-导出减脂周期"]
        reveal(export, app); export.tap()
        XCTAssertTrue(app.navigationBars["周期导出"].waitForExistence(timeout: 5))
        let generate = app.buttons["生成 CSV"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5)); generate.tap()
        XCTAssertTrue(app.buttons["保存或分享 CSV"].waitForExistence(timeout: 5))
        capture("11-cycle-export", app)
    }

    func testConfirmedLowerBodyWeekShowsFarmerCarryAndRPEExplanation() {
        let app = launch(lowerBodyWeek: true)
        openTrainingPlan(app)
        XCTAssertTrue(app.navigationBars["训练编排"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["训练编排-时段状态"].label, "历史编排")
        XCTAssertEqual(app.staticTexts["训练编排-日期范围"].label, "2026-09-14 至 2026-09-20")
        let preferenceRevision = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "TP-20260914-03")
        ).firstMatch
        XCTAssertTrue(preferenceRevision.waitForExistence(timeout: 5))

        let monday = app.buttons["训练编排-力量-LOWER_FRONT_LB3"]
        reveal(monday, app); monday.tap()
        let farmerCarry = app.staticTexts["农夫走"]
        reveal(farmerCarry, app)
        XCTAssertTrue(farmerCarry.isHittable)
        XCTAssertTrue(app.staticTexts["6 组 × 30米 · 休息 75 秒"].exists)
        // Only Monday is expanded, and farmer carry is its final exercise.
        // Exercise notes now live inside each native details disclosure.
        guard let farmerDetails = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "计划详情与依据"
        )).allElementsBoundByIndex.last else {
            return XCTFail("农夫走必须提供计划详情与负重口径说明入口")
        }
        reveal(farmerDetails, app); farmerDetails.tap()
        let dumbbellConvention = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "每只哑铃")).firstMatch
        reveal(dumbbellConvention, app)
        XCTAssertTrue(dumbbellConvention.exists)

        let rope = app.buttons["训练编排-有氧-ROPE_TUE_LB3"]
        reveal(rope, app)
        XCTAssertTrue(rope.waitForExistence(timeout: 5))
        XCTAssertTrue(rope.label.contains("10 轮 · 约 18 分钟"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "呼吸加快但仍能说短句")).firstMatch.exists)
        rope.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "呼吸加快但仍能说短句")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "还能继续约 3–4 分钟")).firstMatch.exists)

        let saturday = app.buttons["训练编排-有氧-ROPE_SAT_LB3"]
        reveal(saturday, app)
        XCTAssertTrue(saturday.exists)
        XCTAssertTrue(saturday.label.contains("12 轮 · 约 24 分钟"))
        capture("lower-body-week-farmer-carry-rpe", app)
    }

    func testConfirmedLowerBodyWeekImportsTuesdayAndSaturdayRopeSchedules() {
        let app = launch(lowerBodyWeek: true)
        let trainingDays = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练日期-"))
        guard let initialDay = trainingDays.allElementsBoundByIndex.first(where: { $0.isSelected }) else {
            return XCTFail("训练首页必须提供明确选中的日期")
        }
        let initialDayID = initialDay.identifier
        openTrainingPlan(app)

        let tuesdayPlan = app.buttons["训练编排-有氧-ROPE_TUE_LB3"]
        reveal(tuesdayPlan, app)
        XCTAssertTrue(tuesdayPlan.label.contains("10 轮 · 约 18 分钟"))
        let saturdayPlan = app.buttons["训练编排-有氧-ROPE_SAT_LB3"]
        reveal(saturdayPlan, app)
        XCTAssertTrue(saturdayPlan.label.contains("12 轮 · 约 24 分钟"))
        let preview = app.buttons["预览减脂训练导入"]
        reveal(preview, app)
        preview.tap()
        XCTAssertTrue(app.navigationBars["导入前预览"].waitForExistence(timeout: 5))
        let tuesdayRope = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "2026-09-15", "跳绳间歇 · 技术与燃脂")
        ).firstMatch
        reveal(tuesdayRope, app)
        XCTAssertTrue(tuesdayRope.exists)
        let saturdayRope = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "2026-09-19", "跳绳混合间歇 · 燃脂")
        ).firstMatch
        reveal(saturdayRope, app)
        XCTAssertTrue(saturdayRope.exists)

        let confirm = app.buttons["确认导入减脂训练"]
        reveal(confirm, app)
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(confirm.label.contains("5 条训练日程"))
        confirm.tap()
        XCTAssertTrue(app.navigationBars["训练编排"].waitForExistence(timeout: 5))
        app.buttons["主导航-训练"].tap()
        func revealEarlier(_ item: XCUIElement) {
            for _ in 0..<12 {
                if item.exists && item.isHittable && item.frame.minY > 60 && item.frame.maxY < app.xfitTabBar.frame.minY { return }
                app.swipeDown()
            }
            XCTAssertTrue(item.isHittable)
        }
        // Importing a historical week must not pull the homepage away from today.
        let calendar = app.buttons["训练日程"]
        revealEarlier(calendar)
        XCTAssertTrue(app.buttons[initialDayID].isSelected, "导入历史周计划不能改变首页选中的日期")
        XCTAssertEqual(trainingDays.allElementsBoundByIndex.first(where: { $0.isSelected })?.identifier, initialDayID)
        calendar.tap()
        XCTAssertTrue(app.navigationBars["训练日程"].waitForExistence(timeout: 5))
        // The current schedule shows one month; explicitly open the imported week.
        let month = app.buttons["日程-选择月份"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        guard let displayedMonth = month.value as? String,
              let displayedYear = Int(displayedMonth.prefix(4)) else {
            return XCTFail("日程月份必须提供明确年月，才能定位历史导入周")
        }
        month.tap()
        XCTAssertTrue(app.navigationBars["选择月份"].waitForExistence(timeout: 5))
        if displayedYear > 2026 {
            for _ in 2026..<displayedYear { app.buttons["上一年"].tap() }
        } else if displayedYear < 2026 {
            for _ in displayedYear..<2026 { app.buttons["下一年"].tap() }
        }
        let importedMonth = app.buttons["日程-月份-2026-09"]
        XCTAssertTrue(importedMonth.waitForExistence(timeout: 5)); importedMonth.tap()
        XCTAssertEqual(month.value as? String, "2026-09")
        for (day, name) in [("2026-09-19", "跳绳混合间歇 · 燃脂"), ("2026-09-15", "跳绳间歇 · 技术与燃脂")] {
            app.buttons["日程-折叠日历"].tap()
            let dayLocator = app.buttons["日程-日历日期-" + day]
            XCTAssertTrue(dayLocator.waitForExistence(timeout: 5)); dayLocator.tap()
            let header = app.buttons["日程-日期菜单-" + day]
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            let entry = app.buttons.matching(NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@", "补录完成情况-跳绳", name
            )).firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 5), "\(day) 必须保留原跳绳名称与历史补录入口")
            reveal(entry, app)
            XCTAssertTrue(entry.label.contains(name))
            entry.tap()
            XCTAssertTrue(app.navigationBars["跳绳"].waitForExistence(timeout: 5))
            let save = app.buttons["保存跳绳记录"]
            reveal(save, app)
            XCTAssertTrue(save.isHittable)
            app.navigationBars["跳绳"].buttons["取消"].tap()
            XCTAssertTrue(app.navigationBars["训练日程"].waitForExistence(timeout: 5))
        }
        capture("lower-body-week-rope-schedules", app)
    }

    func testTrainingHomeOmitsWeekImportAndSummaryWhileManagementRetainsImport() {
        let app = launch()
        for identifier in ["训练-继续安排本周", "训练-安排本周", "训练-减脂计划导入", "训练-训练总结"] {
            XCTAssertFalse(app.buttons[identifier].exists)
        }
        XCTAssertFalse(app.staticTexts["训练编排与导入"].exists)
        XCTAssertTrue(app.buttons["训练-日期菜单"].exists)
        openTrainingPlan(app)
        XCTAssertTrue(app.buttons["训练编排-版本"].waitForExistence(timeout: 5))
        let preview = app.buttons["预览减脂训练导入"]
        reveal(preview, app); XCTAssertTrue(preview.isHittable)
    }

    func testTrainingManagementImportRemainsReachableAtLargestTextSize() {
        let app = launch(large: true)
        openTrainingPlan(app)
        let range = app.staticTexts["训练编排-日期范围"]
        reveal(range, app); XCTAssertTrue(range.isHittable)
        let preview = app.buttons["预览减脂训练导入"]
        reveal(preview, app); preview.tap()
        XCTAssertTrue(app.navigationBars["导入前预览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["确认导入减脂训练"].isHittable)
        app.navigationBars["导入前预览"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["训练编排"].waitForExistence(timeout: 5))
    }

    func testConfirmedTrainingPreferenceIsVisibleFromProfile() {
        let app = launch()
        app.xfitTabButtons["我的"].tap()
        let preference = app.buttons["偏好与编排"]
        reveal(preference, app)
        XCTAssertTrue(preference.exists); preference.tap()
        XCTAssertTrue(app.navigationBars["训练偏好"].waitForExistence(timeout: 5))
        // The former combined summary is now presented as distinct source fields.
        XCTAssertTrue(app.staticTexts["四日部位分化"].exists)
        XCTAssertTrue(app.staticTexts["每周4次 · 每次60–90分钟"].exists)
        let focusLimit = app.staticTexts["每次只聚焦 1 个主肌群与 1 个辅助肌群，不采用全身混合训练"]
        reveal(focusLimit, app)
        XCTAssertTrue(focusLimit.exists)
        capture("training-preferences-profile", app)
    }

    func testJumpRopeGroupsAndUnknownTimeAreVisible() {
        let app = launch()
        app.buttons["主导航-工具"].tap()
        let entry = app.buttons["记录跳绳"]
        reveal(entry, app); entry.tap()
        let count = app.textFields["跳绳-次数"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        count.tap(); count.typeText("1550")
        let sets = app.textFields["跳绳-总组数"]
        sets.tap(); sets.typeText("8")
        let keyboardDone = app.buttons["跳绳-收起键盘"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5)); keyboardDone.tap()
        let duration = app.switches["记录时长"]
        if duration.value as? String == "1" { duration.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap() }
        XCTAssertEqual(duration.value as? String, "0")
        let knownTime = app.switches["跳绳-记录具体时间"]
        reveal(knownTime, app)
        if knownTime.value as? String == "1" { knownTime.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap() }
        XCTAssertEqual(knownTime.value as? String, "0")
        let save = app.buttons["保存跳绳记录"]
        reveal(save, app); XCTAssertTrue(save.isEnabled); save.tap()
        let summary = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "1550 个", "8 组")).firstMatch
        reveal(summary, app); XCTAssertTrue(summary.exists)
        let unknownTime = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "时间未知")).firstMatch
        for _ in 0..<4 where !unknownTime.exists { app.swipeDown() }
        XCTAssertTrue(unknownTime.waitForExistence(timeout: 5))
    }

    func testTrainingPlanJumpRopeEntryRemainsReachable() {
        let app = launch()
        openTrainingPlan(app)
        let rope = app.buttons["训练编排-记录跳绳"]
        reveal(rope, app); rope.tap()
        XCTAssertTrue(app.navigationBars["跳绳"].waitForExistence(timeout: 5))
        let knownTime = app.switches["跳绳-记录具体时间"]
        reveal(knownTime, app)
        if knownTime.value as? String == "0" { knownTime.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap() }
        XCTAssertTrue(app.descendants(matching: .any)["跳绳-完成时间"].waitForExistence(timeout: 5))
        let save = app.buttons["保存跳绳记录"]
        reveal(save, app)
        XCTAssertTrue(save.isHittable)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["训练编排"].waitForExistence(timeout: 5))
    }

    func testDurationOnlyJumpRopeCanSaveWithoutAnInventedCount() {
        let app = launch()
        openTrainingPlan(app)
        let rope = app.buttons["训练编排-记录跳绳"]
        reveal(rope, app); rope.tap()
        XCTAssertTrue(app.navigationBars["跳绳"].waitForExistence(timeout: 5))
        let count = app.textFields["跳绳-次数"]
        XCTAssertTrue(count.waitForExistence(timeout: 5), "次数应是可留空的输入，而非默认1000的必填步进器")
        XCTAssertEqual(count.value as? String, "未记录次数（可留空）")
        let save = app.buttons["保存跳绳记录"]
        reveal(save, app)
        XCTAssertTrue(save.isEnabled)
        capture("duration-only-rope-before-save", app)
        save.tap()
        XCTAssertTrue(app.navigationBars["训练编排"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["主导航-工具"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["工具中心"].waitForExistence(timeout: 5))
        capture("duration-only-rope-profile-before-scroll", app)
        let unknown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "次数未知", "有效 600 秒")).firstMatch
        reveal(unknown, app)
        XCTAssertTrue(unknown.exists)
        capture("duration-only-rope-actual-readback", app)
    }

    func testLargeTypePrimaryActionsRemainReachable() {
        let app = launch(large: true)
        let start = app.buttons["开始训练"]
        reveal(start, app)
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        capture("09-large-type-training", app)
        openNutritionTools(app)
        let edit = app.buttons["饮食-调整实吃-早餐"]
        reveal(edit, app); edit.tap()
        XCTAssertTrue(app.buttons["保存计划实吃"].waitForExistence(timeout: 5))
        capture("10-large-type-meal", app)
    }
    func testLargeTypeTrainingDistributionCanScrollToExplanation() {
        let app = launch(large: true)
        openGoal(app)
        let distribution = app.buttons["目标-训练分布"]
        reveal(distribution, app); distribution.tap()
        let explanation = app.staticTexts["仅计已完成工作组；复合动作可计入多个肌群。灰色表示没有相应记录，不表示恢复状态。"]
        reveal(explanation, app)
        XCTAssertTrue(explanation.isHittable)
        capture("12-large-type-distribution", app)
    }

    func testLargeTypeCurrentProgressAndPrepRemainReachable() {
        let app = launch(large: true)
        openGoal(app)
        let record = app.buttons["目标-记录体重"]
        reveal(record, app)
        XCTAssertGreaterThanOrEqual(record.frame.height, 44)
        capture("13-large-type-progress", app)
        openNutritionTools(app)
        let prep = app.buttons["饮食-明日备餐"]
        reveal(prep, app); prep.tap()
        XCTAssertTrue(app.navigationBars["明日备餐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["备餐-分享"].isHittable)
        let prepHeading = app.staticTexts["页标题-备餐"]
        XCTAssertTrue(prepHeading.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(prepHeading.frame.height, 50, "必须实际启用辅助功能大字体，不能仅传入无效参数")
        capture("14-large-type-prep", app)
        let purchasePage = app.buttons["备餐-采购页"]
        reveal(purchasePage, app)
        capture("large-prep-purchase-tab-ready", app)
        purchasePage.tap()
        XCTAssertTrue(purchasePage.isSelected)
        XCTAssertTrue(app.staticTexts["页标题-采购"].waitForExistence(timeout: 5))
        let pantry = app.staticTexts["家中常备 · 核对库存"]
        reveal(pantry, app)
        let bottomShare = app.buttons["备餐-底部分享"]
        XCTAssertTrue(bottomShare.waitForExistence(timeout: 5))
        let topLimit = app.navigationBars["明日备餐"].frame.maxY + 8
        let bottomLimit = bottomShare.frame.minY - 8
        for _ in 0..<8 {
            let tapY = pantry.frame.midY
            if pantry.isHittable && tapY > topLimit && tapY < bottomLimit { break }
            if tapY <= topLimit {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        XCTAssertTrue(pantry.isHittable)
        XCTAssertGreaterThan(pantry.frame.midY, topLimit)
        XCTAssertLessThan(pantry.frame.midY, bottomLimit)
        capture("15-large-type-shopping", app)
        pantry.tap()
        let seasoning = app.staticTexts["备餐用量-姜葱蒜"]
        reveal(seasoning, app)
        XCTAssertTrue(seasoning.label.contains("待折算"))
    }

    func testFullBodyEntryCanSaveWaistOnlyCancelAndEditSameRecord() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent", "--ui-testing-reset-store"]
        app.launch()

        func openBodyData() {
            XCTAssertTrue(app.xfitTabButtons["我的"].waitForExistence(timeout: 10))
            app.xfitTabButtons["我的"].tap()
            let entry = app.buttons["身体记录"]
            reveal(entry, app)
            entry.tap()
            XCTAssertTrue(app.navigationBars["身体数据"].waitForExistence(timeout: 5))
        }
        func openFullEditor() {
            let entry = app.buttons["记录完整身体数据"]
            reveal(entry, app)
            entry.tap()
            XCTAssertTrue(app.navigationBars["记录身体数据"].waitForExistence(timeout: 5))
        }
        func assertOptionalFieldIsEmpty(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(field.exists, file: file, line: line)
            XCTAssertEqual(field.placeholderValue, "可选", file: file, line: line)
            if let value = field.value {
                guard let text = value as? String else {
                    XCTFail("可选输入返回了非文本值：\(value)", file: file, line: line)
                    return
                }
                XCTAssertTrue(text.isEmpty || text == "可选", "字段应为空，实际：\(text)", file: file, line: line)
            }
        }
        func replace(_ field: XCUIElement, with value: String) {
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            field.tap()
            let old = field.value as? String ?? ""
            if !old.isEmpty && old != "可选" {
                // The optional numeric field is trailing-aligned. Place the caret
                // after its value before deleting, rather than in its empty left padding.
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
            assertOptionalFieldIsEmpty(field)
            field.typeText(value)
        }
        func finishNumericInput() {
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            let done = app.buttons["完成"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            XCTAssertTrue(done.isHittable)
            done.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "先通过表单的完成按钮收起数字键盘，再滚动到备注")
        }

        openBodyData()
        openFullEditor()
        replace(app.textFields["完整身体数据-腰围"], with: "96")
        finishNumericInput()
        let notes = app.descendants(matching: .any).matching(identifier: "完整身体数据-备注").firstMatch
        reveal(notes, app); notes.tap(); notes.typeText("UI取消完整身体记录")
        app.navigationBars["记录身体数据"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["身体数据"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI取消完整身体记录")).firstMatch.exists)

        openFullEditor()
        assertOptionalFieldIsEmpty(app.textFields["完整身体数据-腰围"])
        replace(app.textFields["完整身体数据-腰围"], with: "96")
        finishNumericInput()
        reveal(notes, app); notes.tap(); notes.typeText("UI仅腰围持久记录")
        app.navigationBars["记录身体数据"].buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["身体数据"].waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI仅腰围持久记录")).firstMatch
        reveal(row, app)
        let rowEvidence = XCTAttachment(string: row.debugDescription)
        rowEvidence.name = "仅腰围记录的可访问性结构"
        rowEvidence.lifetime = .keepAlways
        add(rowEvidence)
        let recordID = row.identifier
        XCTAssertTrue(recordID.hasPrefix("身体记录-"))
        row.tap()
        XCTAssertTrue(app.navigationBars["编辑身体数据"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["完整身体数据-腰围"].value as? String, "96", "保存后重新打开，应读取实际存储的腰围")
        assertOptionalFieldIsEmpty(app.textFields["完整身体数据-体重"])
        replace(app.textFields["完整身体数据-腰围"], with: "95")
        finishNumericInput()
        app.navigationBars["编辑身体数据"].buttons["保存"].tap()
        let edited = app.buttons[recordID]
        reveal(edited, app)
        XCTAssertEqual(app.buttons.matching(identifier: recordID).count, 1)
        edited.tap()
        XCTAssertTrue(app.navigationBars["编辑身体数据"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["完整身体数据-腰围"].value as? String, "95", "编辑必须写回同一 UUID 的记录")
        assertOptionalFieldIsEmpty(app.textFields["完整身体数据-体重"])
        app.navigationBars["编辑身体数据"].buttons["取消"].tap()

        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent"]
        app.launch()
        openBodyData()
        let restored = app.buttons[recordID]
        reveal(restored, app)
        XCTAssertEqual(app.buttons.matching(identifier: recordID).count, 1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "UI取消完整身体记录")).firstMatch.exists)
        restored.tap()
        XCTAssertTrue(app.navigationBars["编辑身体数据"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["完整身体数据-腰围"].value as? String, "95", "重启后应保留同一记录的更新值")
        assertOptionalFieldIsEmpty(app.textFields["完整身体数据-体重"])
        app.navigationBars["编辑身体数据"].buttons["取消"].tap()
    }

}
