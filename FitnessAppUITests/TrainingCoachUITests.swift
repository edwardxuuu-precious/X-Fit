import XCTest

final class TrainingCoachUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWeekSwipesAtLargestTextSize() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-home-plan-week",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.otherElements["训练周历"].waitForExistence(timeout: 20))
        revealWeek(app)
        app.otherElements["训练周历"].swipeLeft()
        let future = app.buttons["训练日期-" + dateKey(Calendar.current.date(byAdding: .day, value: 7, to: Date())!)]
        XCTAssertTrue(future.waitForExistence(timeout: 3))
        XCTAssertTrue(future.isSelected)
        let title = app.staticTexts["训练-训练标题"]
        reveal(title, app: app, fullyVisible: true)
        title.swipeLeft()
        XCTAssertTrue(future.isSelected, "从训练标题横拖不应切换周")
        revealWeek(app)
        app.otherElements["训练周历"].swipeRight()
        let today = app.buttons["训练日期-" + dateKey(Date())]
        XCTAssertTrue(today.waitForExistence(timeout: 3))
        XCTAssertTrue(today.isSelected)
    }

    private func revealWeek(_ app: XCUIApplication) {
        let week = app.otherElements["训练周历"]
        reveal(week, app: app, fullyVisible: true)
        reveal(app.buttons["下一周"], app: app, fullyVisible: true)
        XCTAssertTrue(week.isHittable)
    }

    private func homePlanWeek(large: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-home-plan-week"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let week = app.otherElements["训练周历"]
        XCTAssertTrue(week.waitForExistence(timeout: 20))
        let probe = app.staticTexts["训练-只读校验"]
        XCTAssertTrue(probe.exists)
        let before = probe.value as? String
        XCTAssertNotNil(before)
        revealWeek(app)
        week.swipeLeft()
        XCTAssertTrue(app.staticTexts["下周保存计划"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["训练日期-" + dateKey(Calendar.current.date(byAdding: .day, value: 7, to: Date())!)].isSelected)
        let view = app.buttons["训练-查看计划"]
        let start = app.buttons["开始训练"]
        reveal(view, app: app, fullyVisible: true)
        XCTAssertTrue(view.isHittable)
        XCTAssertTrue(start.exists)
        XCTAssertGreaterThanOrEqual(view.frame.height, 44)
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        XCTAssertGreaterThanOrEqual(view.frame.width, 44)
        XCTAssertGreaterThanOrEqual(start.frame.width, 44)
        XCTAssertLessThanOrEqual(view.frame.maxX, start.frame.minX)
        capture(large ? "home-plan-large" : "home-plan-normal", app: app)
        view.tap()
        let savedAction = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "计划-动作-", "保存的计划动作")).firstMatch
        XCTAssertTrue(savedAction.waitForExistence(timeout: 5))
        XCTAssertEqual(savedAction.value as? String, "已收起")
        reveal(savedAction, app: app, fullyVisible: true)
        XCTAssertGreaterThanOrEqual(savedAction.frame.height, 44)
        savedAction.tap()
        let savedNotes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "计划-说明-")).firstMatch
        reveal(savedNotes, app: app, fullyVisible: true)
        XCTAssertGreaterThanOrEqual(savedNotes.frame.height, 44)
        savedNotes.tap()
        XCTAssertFalse(app.staticTexts["模板已修改动作"].exists)
        XCTAssertTrue(app.staticTexts["保存的备注"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "25 kg")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "20 kg")).firstMatch.exists)
        let unknownAction = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "计划-动作-", "待校准负重动作")).firstMatch
        reveal(unknownAction, app: app, fullyVisible: true)
        unknownAction.tap()
        let unknown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "重量待校准 · 6" )).firstMatch
        reveal(unknown, app: app)
        XCTAssertTrue(unknown.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "第1组 · 0 kg")).firstMatch.exists)
        XCTAssertFalse(app.buttons["完成第 1 组"].exists)
        capture(large ? "saved-plan-large" : "saved-plan-normal", app: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["下周保存计划"].waitForExistence(timeout: 5))
        XCTAssertEqual(probe.value as? String, before)
        XCTAssertTrue(app.buttons["训练日期-" + dateKey(Calendar.current.date(byAdding: .day, value: 7, to: Date())!)].isSelected)
        XCTAssertTrue(app.staticTexts["其他日期活动训练"].exists)
        revealWeek(app)
        let next = app.buttons["训练日期-" + dateKey(Calendar.current.date(byAdding: .day, value: 8, to: Date())!)]
        let emptyDay = next.exists ? next : app.buttons["训练日期-" + dateKey(Calendar.current.date(byAdding: .day, value: 6, to: Date())!)]
        emptyDay.tap()
        reveal(view, app: app, fullyVisible: true)
        view.tap()
        XCTAssertTrue(app.staticTexts["计划-无保存明细"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["模板已修改动作"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(probe.value as? String, before)
        revealWeek(app)
        app.buttons["训练日期-" + dateKey(Calendar.current.date(byAdding: .day, value: 7, to: Date())!)].tap()
        revealWeek(app)
        capture(large ? "week-before-right-large" : "week-before-right-normal", app: app)
        week.swipeRight()
        let today = app.buttons["训练日期-" + dateKey(Date())]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isSelected)
        revealWeek(app)
        XCTAssertTrue(app.buttons["下一周"].exists)
        app.buttons["下一周"].tap()
        XCTAssertTrue(app.staticTexts["下周保存计划"].waitForExistence(timeout: 5))
        revealWeek(app)
        let y = week.frame.minY
        week.swipeUp()
        XCTAssertTrue(app.staticTexts["下周保存计划"].exists)
        XCTAssertLessThan(week.frame.minY, y - 5, "从日期条开始竖拖仍应滚动页面")
        revealWeek(app)
        XCTAssertEqual(probe.value as? String, before)
        app.buttons["训练-回到今天"].tap()
        XCTAssertTrue(app.buttons["训练日期-" + dateKey(Date())].isSelected)
        XCTAssertEqual(app.staticTexts["训练-训练标题"].label, "准备开练")
        XCTAssertFalse(app.buttons["训练-回到今天"].exists)
    }

    func testHomePlanWeek() { homePlanWeek(large: false) }
    func testHomePlanWeekAccessibilityLarge() { homePlanWeek(large: true) }

    func testSavedPlanIllustratedCards() { illustratedCards(large: false) }
    func testSavedPlanIllustratedCardsAccessibilityLarge() { illustratedCards(large: true) }

    private func illustratedCards(large: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-home-plan-week", "--ui-testing-saved-plan-cards"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.otherElements["训练周历"].waitForExistence(timeout: 20))
        revealWeek(app)
        app.otherElements["训练周历"].swipeLeft()
        let view = app.buttons["训练-查看计划"]
        reveal(view, app: app, fullyVisible: true)
        view.tap()
        XCTAssertTrue(app.navigationBars["查看计划"].waitForExistence(timeout: 5))
        let names = ["史密斯卧推，胸部主项", "器械上斜卧推，上胸推举", "坐姿飞鸟，胸部夹胸", "站姿绳索夹胸，胸部夹胸",
            "史密斯肩推，肩前束", "坐姿哑铃侧平举，肩中束", "绳索反向飞鸟，肩后束", "器械坐姿侧平举，肩中束"]
        let allCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "计划-动作-"))
        let expandAll = app.buttons["计划-全部展开"]
        reveal(expandAll, app: app, fullyVisible: true)
        expandAll.tap()
        XCTAssertEqual(expandAll.label, "收起全部动作")
        XCTAssertEqual(allCards.count, names.count)
        XCTAssertTrue(allCards.allElementsBoundByIndex.allSatisfy { $0.value as? String == "已展开" })
        expandAll.tap()
        XCTAssertEqual(expandAll.label, "展开全部动作")
        XCTAssertTrue(allCards.allElementsBoundByIndex.allSatisfy { $0.value as? String == "已收起" })
        for (index, name) in names.enumerated() {
            let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "计划-动作-", name)).firstMatch
            reveal(card, app: app, fullyVisible: true)
            XCTAssertTrue(card.isHittable)
            XCTAssertGreaterThanOrEqual(card.frame.height, 44)
            XCTAssertGreaterThanOrEqual(card.frame.width, 44)
            XCTAssertEqual(card.value as? String, "已收起")
            capture("saved-plan-card-\(large ? "large" : "normal")-\(index)", app: app)
        }
        let last = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "计划-动作-", names[7])).firstMatch
        last.tap()
        XCTAssertEqual(last.value as? String, "已展开")
        capture(large ? "saved-plan-color-expanded-large" : "saved-plan-color-expanded-normal", app: app)
        last.tap()
        XCTAssertEqual(last.value as? String, "已收起")
        capture(large ? "saved-plan-color-collapsed-large" : "saved-plan-color-collapsed-normal", app: app)
        last.tap()
        let rir = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "RIR 1–2")).firstMatch
        reveal(rir, app: app)
        XCTAssertTrue(rir.exists)
        let condition = app.staticTexts["本组后条件递减，安全换片时执行"]
        reveal(condition, app: app)
        XCTAssertTrue(condition.exists)
        let notes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "计划-说明-")).firstMatch
        reveal(notes, app: app, fullyVisible: true)
        XCTAssertGreaterThanOrEqual(notes.frame.height, 44)
        let originalNotes = app.staticTexts["隔离测试保存的完整备注。不能安全快速换片时跳过递减，不同时做两种强化。"]
        notes.tap()
        XCTAssertEqual(notes.value as? String, "已展开")
        notes.tap()
        XCTAssertEqual(notes.value as? String, "已收起")
        XCTAssertFalse(originalNotes.exists)
        notes.tap()
        XCTAssertEqual(notes.value as? String, "已展开")
        reveal(originalNotes, app: app)
        XCTAssertTrue(originalNotes.exists)
        capture(large ? "saved-plan-full-notes-large" : "saved-plan-full-notes-normal", app: app)
    }

    func testHomePlanContinuesOriginalOtherDateSession() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-home-plan-week"]
        app.launch()
        XCTAssertTrue(app.otherElements["训练周历"].waitForExistence(timeout: 20))
        app.otherElements["训练周历"].swipeLeft()
        let probe = app.staticTexts["训练-只读校验"]
        let before = probe.value as? String
        let start = app.buttons["开始训练"]
        reveal(start, app: app, fullyVisible: true); start.tap()
        XCTAssertTrue(app.alerts["操作未完成"].waitForExistence(timeout: 5))
        app.alerts.buttons["知道了"].tap()
        XCTAssertEqual(probe.value as? String, before)
        let resume = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练-其他日期继续-")).firstMatch
        XCTAssertTrue(resume.exists)
        reveal(resume, app: app, fullyVisible: true); resume.tap()
        XCTAssertTrue(app.staticTexts["原会话保留动作"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["第 1 组已完成"].firstMatch.exists)
        capture("home-plan-original-session-resumed", app: app)
    }

    func testHomePlanStartUsesIndependentRightAction() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-home-plan-week", "--ui-testing-home-plan-no-active"]
        app.launch()
        XCTAssertTrue(app.otherElements["训练周历"].waitForExistence(timeout: 20))
        app.otherElements["训练周历"].swipeLeft()
        let start = app.buttons["开始训练"]
        reveal(start, app: app, fullyVisible: true); start.tap()
        XCTAssertTrue(app.buttons["完成第 1 组"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.navigationBars["查看计划"].exists)
        capture("home-plan-started-with-right-action", app: app)
    }

    private func launch(ready: Bool, large: Bool = false, preview: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-meal-camera-unavailable"] + (ready ? ["--ui-testing-coach-ready"] : [])
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if preview { app.launchArguments.append("--ui-redesign-preview") }
        app.launch()
        XCTAssertTrue(app.buttons["主导航-训练"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.xfitTabButtons.count, 5)
        XCTAssertTrue(app.buttons["主导航-训练"].isSelected)
        XCTAssertTrue(app.otherElements["训练周历"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["展开本周日期"].exists)
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let day = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let sourceDay = app.buttons["训练日期-" + formatter.string(from: day)]
        if sourceDay.waitForExistence(timeout: 2) {
            sourceDay.tap()
            XCTAssertTrue(app.otherElements["训练-当天实际"].waitForExistence(timeout: 5))
        } else {
            let today = app.buttons["训练日期-" + formatter.string(from: Date())]
            XCTAssertTrue(today.isSelected)
            XCTAssertFalse(app.buttons["训练-训练总结"].exists)
        }
        return app
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, fullyVisible: Bool = false) {
        for _ in 0..<8 {
            if !fullyVisible {
                if element.isHittable { return }
                app.scrollViews.firstMatch.swipeUp()
                continue
            }
            let navigationBottom = app.navigationBars.allElementsBoundByIndex.filter(\.isHittable).map { $0.frame.maxY }.max() ?? app.frame.minY
            let brand = app.staticTexts["训练。"]
            let top = max(navigationBottom, brand.exists && brand.isHittable ? brand.frame.maxY + 8 : app.frame.minY)
            let visibleTabs = app.xfitTabButtons.allElementsBoundByIndex.filter(\.isHittable)
            var bottom = visibleTabs.isEmpty ? app.frame.maxY : app.xfitTabBar.frame.minY
            let fixedPlan = app.buttons["复盘-下一次计划"]
            if fixedPlan.exists && fixedPlan.isHittable && element.identifier != fixedPlan.identifier {
                bottom = min(bottom, fixedPlan.frame.minY)
            }
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.minY >= top + 8 && frame.maxY <= bottom - 8 { return }
                // Hold before release so scroll inertia cannot overshoot the visible area.
                let viewport = max(1, bottom - top)
                let delta = (top + bottom) / 2 - frame.midY
                let distance = min(max(abs(delta), 32), min(180, viewport * 0.35))
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                    .withOffset(CGVector(dx: 0, dy: (top + bottom) / 2 - app.frame.minY))
                let end = start.withOffset(CGVector(dx: 0, dy: delta < 0 ? -distance : distance))
                start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            } else {
                app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            }
        }
        if fullyVisible { XCTFail("目标控件仍未完整进入可操作区域：\(element.identifier)") }
        else { XCTAssertTrue(element.isHittable, "目标元素不能正常滚动到达：\(element)") }
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func openSummary(_ app: XCUIApplication) {
        XCTAssertFalse(app.buttons["训练-训练总结"].exists)
        app.buttons["主导航-进展"].tap()
        let summary = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "进展-最近训练-", "下肢综合 · 隔离测试")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        reveal(summary, app: app, fullyVisible: true)
        for title in ["查看本次复盘", "补充恢复反馈", "审阅下一次计划", "核对安排保存结果", "查看已确认安排"] {
            XCTAssertFalse(app.buttons[title].exists, "首页不再分散显示训练总结内部的操作")
        }
        XCTAssertFalse(app.staticTexts["可查看"].exists)
        summary.tap()
        XCTAssertTrue(app.navigationBars["训练总结"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["反馈-下一步或保存"].exists, "进入总结不自动弹出反馈")
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func assertWeekControls(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let dates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练日期-"))
        XCTAssertEqual(dates.count, 7, file: file, line: line)
        for date in dates.allElementsBoundByIndex {
            XCTAssertTrue(date.isHittable, file: file, line: line)
            XCTAssertGreaterThanOrEqual(date.frame.width, 44, file: file, line: line)
            XCTAssertGreaterThanOrEqual(date.frame.height, 44, file: file, line: line)
        }
    }

    func testPersistentWeekKeepsTodayIndependentOfSelectedDate() {
        // Week navigation does not depend on a coach session two days ago;
        // that fixture is outside the visible week on Mondays and Tuesdays.
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let today = app.buttons["训练日期-" + dateKey(Date())]
        XCTAssertTrue(today.waitForExistence(timeout: 20))
        XCTAssertTrue(today.isSelected)
        XCTAssertEqual(today.value as? String, "今天，已选中")
        assertWeekControls(app)
        capture("week-01-today-selected", app: app)

        let other = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@",
            "训练日期-", today.identifier)).firstMatch
        other.tap()
        XCTAssertTrue(other.isSelected)
        XCTAssertEqual(other.value as? String, "已选中")
        XCTAssertFalse(today.isSelected)
        XCTAssertEqual(today.value as? String, "今天，未选中")
        assertWeekControls(app)
        capture("week-02-today-and-selection", app: app)

        app.buttons["训练-回到今天"].tap()
        XCTAssertTrue(today.isSelected)
        XCTAssertEqual(today.value as? String, "今天，已选中")
        XCTAssertFalse(app.buttons["训练-回到今天"].exists)
    }

    private func verifyUpcomingTimeline(large: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-loop", "--ui-testing-home-timeline"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let today = app.buttons["训练日期-" + dateKey(Date())]
        XCTAssertTrue(today.waitForExistence(timeout: 20))
        assertWeekControls(app)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练-接下来-"))
        XCTAssertEqual(rows.count, 2)
        let bike = rows.matching(NSPredicate(format: "label CONTAINS %@", "固定单车")).firstMatch
        reveal(bike, app: app)
        XCTAssertTrue(bike.label.contains("35 分钟"))
        XCTAssertFalse(bike.label.contains("R1"))
        XCTAssertFalse(bike.label.contains("2026-"))
        capture(large ? "timeline-large" : "timeline-normal", app: app)
        bike.tap()
        XCTAssertTrue(app.navigationBars["训练安排"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["日程-日期菜单-" + dateKey(Date().addingTimeInterval(86_400))].exists)
        XCTAssertFalse(app.buttons["日程-日期菜单-" + dateKey(Date().addingTimeInterval(172_800))].exists)
        XCTAssertTrue(app.buttons["安排-完整日程"].exists)
        capture(large ? "timeline-detail-large" : "timeline-detail", app: app)
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.otherElements["训练周历"].waitForExistence(timeout: 5))
        XCTAssertTrue(today.isSelected)
        XCTAssertEqual(today.value as? String, "今天，已选中")
        for _ in 0..<8 {
            if today.isHittable { break }
            app.scrollViews.firstMatch.swipeDown()
        }
        assertWeekControls(app)
        let tomorrow = app.buttons["训练日期-" + dateKey(Date().addingTimeInterval(86_400))]
        // Sunday has no tomorrow button in a Monday-start week.
        if tomorrow.exists {
            tomorrow.tap()
            XCTAssertTrue(tomorrow.isSelected)
            XCTAssertEqual(today.value as? String, "今天，未选中")
            XCTAssertFalse(rows.matching(NSPredicate(format: "label CONTAINS %@", "固定单车")).firstMatch.exists)
            XCTAssertTrue(rows.matching(NSPredicate(format: "label CONTAINS %@", "背部＋二头")).firstMatch.exists)
        }
    }

    func testUpcomingTimelineOpensOnlyTheChosenPlanAndPreservesSelectedDate() {
        verifyUpcomingTimeline(large: false)
    }

    func testUpcomingTimelineLargeTypeKeepsDatesAndPlanNavigationReachable() {
        verifyUpcomingTimeline(large: true)
    }

    func testTrainingStatusStaysWithPartialWorkoutTitleAndPendingPlanIsSeparate() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-recorded-day", "--ui-testing-recorded-day-partial"]
        app.launch()
        let status = app.staticTexts["训练-当天状态"]
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        XCTAssertEqual(status.label, "已记录 17/20 组")
        let title = app.staticTexts["训练-训练标题"]
        XCTAssertEqual(title.label, "UI实际下肢")
        XCTAssertGreaterThanOrEqual(status.frame.minY, title.frame.maxY)
        XCTAssertLessThanOrEqual(status.frame.minY - title.frame.maxY, 16)
        assertWeekControls(app)
        capture("week-03-partial-status-with-title", app: app)
        let pending = app.buttons["训练-其他待完成安排"]
        reveal(pending, app: app)
        XCTAssertTrue(pending.label.contains("另有"))
        XCTAssertTrue(pending.label.contains("待完成"))
    }

    func testFiveSprintPagesKeepTrainingNutritionProgressToolsAndProfileEntries() {
        let app = launch(ready: true)
        XCTAssertTrue(app.staticTexts["训练。"].exists)
        capture("01-training", app: app)
        revealWeek(app)
        let today = app.buttons["训练日期-" + dateKey(Date())]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        XCTAssertTrue(today.isSelected)
        app.buttons["下一周"].tap()
        let nextWeekDay = app.buttons["训练日期-" + dateKey(Calendar.current.date(byAdding: .day, value: 7, to: Date())!)]
        XCTAssertTrue(nextWeekDay.waitForExistence(timeout: 5))
        XCTAssertTrue(nextWeekDay.isSelected)
        let returnToToday = app.buttons["训练-回到今天"]
        XCTAssertTrue(returnToToday.waitForExistence(timeout: 5))
        XCTAssertTrue(returnToToday.isHittable)
        returnToToday.tap()
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(today.isSelected)
        XCTAssertFalse(returnToToday.exists)
        capture("00-training-today", app: app)
        app.buttons["主导航-饮食"].tap()
        XCTAssertTrue(app.staticTexts["饮食。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["饮食-记录一餐"].exists)
        capture("02-nutrition", app: app)
        app.buttons["主导航-进展"].tap()
        XCTAssertTrue(app.staticTexts["进展。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["身体"].exists)
        capture("03-progress", app: app)
        app.buttons["主导航-工具"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["工具中心"].waitForExistence(timeout: 5))
        capture("04-tools", app: app)
        app.buttons["主导航-我的"].tap()
        XCTAssertTrue(app.staticTexts["我的。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["训练历史"].exists)
        capture("04-profile", app: app)
    }

    func testRecordMealKeepsPhotoEntryAndCancelDoesNotAddAnotherMeal() {
        let app = launch(ready: true)
        app.buttons["主导航-饮食"].tap()
        XCTAssertTrue(app.staticTexts["隔离示例餐食"].waitForExistence(timeout: 5))
        app.buttons["饮食-记录一餐"].tap()
        // confirmationDialog exposes an outer button and its labelled child on iOS 26.
        let photo = app.buttons.matching(identifier: "饮食-拍照记餐").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5)); photo.tap()
        XCTAssertTrue(app.navigationBars["拍照记餐"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["餐食照片-保存"].isEnabled)
        app.buttons["餐食照片-取消"].tap()
        XCTAssertTrue(app.buttons["饮食-最近一餐"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "饮食-最近一餐").count, 1)
    }

    func testMorningFeedbackIsOneQuestionAtATimeAndUnknownDateKeepsDraft() {
        let app = launch(ready: false)
        openSummary(app)
        let morning = app.buttons["复盘-次晨恢复"]
        reveal(morning, app: app); morning.tap()
        XCTAssertTrue(app.buttons["没有不适"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["和平时一样"].exists)
        capture("05-feedback", app: app)
        app.buttons["没有不适"].tap(); app.buttons["反馈-下一步或保存"].tap()
        XCTAssertTrue(app.buttons["和平时一样"].waitForExistence(timeout: 4))
        app.buttons["和平时一样"].tap(); app.buttons["反馈-下一步或保存"].tap()
        XCTAssertTrue(app.buttons["恢复不错"].waitForExistence(timeout: 4))
        app.buttons["恢复不错"].tap(); app.buttons["反馈-下一步或保存"].tap()
        XCTAssertTrue(app.buttons["复盘-下一次计划"].waitForExistence(timeout: 5))
        capture("06-review", app: app)
        app.buttons["复盘-下一次计划"].tap()
        let generate = app.buttons["计划-生成草案"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5)); generate.tap()
        let review = app.buttons["计划-审阅确认"]
        XCTAssertTrue(review.waitForExistence(timeout: 5)); XCTAssertFalse(review.isEnabled)
        XCTAssertTrue(app.staticTexts["尚未选择"].exists)
        capture("07-draft", app: app)
    }

    func testCompletePlanConfirmationSavesAndReadonlySnapshotRetainsDateAndDose() {
        let app = launch(ready: true)
        openSummary(app)
        app.buttons["复盘-下一次计划"].tap()
        let review = app.buttons["计划-审阅确认"]
        XCTAssertTrue(review.waitForExistence(timeout: 6)); XCTAssertTrue(review.isEnabled)
        capture("08-plan", app: app)
        review.tap()
        let checkbox = app.switches["确认-核对完整计划"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["确认-保存安排"].isEnabled)
        reveal(checkbox, app: app); checkbox.tap()
        XCTAssertTrue(app.buttons["确认-保存安排"].isEnabled)
        app.buttons["确认-保存安排"].tap()
        XCTAssertTrue(app.staticTexts["页标题-已安排"].waitForExistence(timeout: 8))
        capture("09-saved", app: app)
        app.buttons["完成"].tap()
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["训练总结"].waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "进展-最近训练-", "下肢综合 · 隔离测试")).firstMatch.waitForExistence(timeout: 5))
        openSummary(app)
        app.buttons["复盘-下一次计划"].tap()
        let snapshot = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "完整快照保留")).firstMatch
        reveal(snapshot, app: app); snapshot.tap()
        XCTAssertTrue(app.staticTexts["已保存安排 · 完整确认快照"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["测试腿举"].exists)
        capture("10-confirmed-snapshot", app: app)
    }

    func testHomeOmitsSummaryAndProgressKeepsRecoveryAndPlanReachable() {
        for ready in [false, true] {
            let app = launch(ready: ready)
            capture(ready ? "summary-home-with-ready-plan" : "summary-home-with-missing-recovery", app: app)
            openSummary(app)
            XCTAssertTrue(app.buttons["复盘-次晨恢复"].exists)
            XCTAssertTrue(app.buttons["复盘-下一次计划"].exists)
        }
    }

    func testLargestTextSummaryKeepsRecoveryAndPlanReachable() {
        let app = launch(ready: false, large: true)
        openSummary(app)
        let morning = app.buttons["复盘-次晨恢复"]
        reveal(morning, app: app, fullyVisible: true)
        XCTAssertGreaterThanOrEqual(morning.frame.height, 44)
        capture("summary-large", app: app)
        morning.tap()
        XCTAssertTrue(app.navigationBars["次晨恢复"].waitForExistence(timeout: 5))
        let choice = app.buttons["没有不适"]
        reveal(choice, app: app); choice.tap()
        XCTAssertTrue(choice.isSelected)
        app.navigationBars["次晨恢复"].buttons["稍后"].tap()
        XCTAssertTrue(app.navigationBars["训练总结"].waitForExistence(timeout: 5))
        reveal(morning, app: app, fullyVisible: true); morning.tap()
        XCTAssertTrue(app.navigationBars["次晨恢复"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["没有不适"].isSelected, "取消的反馈不能写入已有记录")
        app.navigationBars["次晨恢复"].buttons["稍后"].tap()
        XCTAssertTrue(app.navigationBars["训练总结"].waitForExistence(timeout: 5))
        let next = app.buttons["复盘-下一次计划"]
        XCTAssertTrue(next.isHittable)
        XCTAssertGreaterThanOrEqual(next.frame.height, 44)
        next.tap()
        XCTAssertTrue(app.navigationBars["下一次计划"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["计划-生成草案"].exists)
    }

    func testSprintSecondaryPagesAndEditorsRemainReachableWithoutSaving() {
        let app = launch(ready: true, preview: true)
        app.buttons["主导航-我的"].tap()
        app.buttons["身体记录"].tap()
        XCTAssertTrue(app.navigationBars["身体数据"].waitForExistence(timeout: 5))
        capture("11-body-records", app: app)
        app.buttons["快速记录体重"].tap()
        XCTAssertTrue(app.textFields["快速体重输入"].waitForExistence(timeout: 5))
        capture("12-weight-editor", app: app)
        app.buttons["取消"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["模板与动作"].tap()
        let library = app.buttons["动作库入口"]
        reveal(library, app: app); library.tap()
        XCTAssertTrue(app.navigationBars["动作库"].waitForExistence(timeout: 5))
        capture("13-exercise-library", app: app)
        app.buttons["新建动作"].tap()
        XCTAssertTrue(app.navigationBars["新建动作"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        capture("14-exercise-editor", app: app)
        app.buttons["取消"].tap()
        app.buttons["主导航-进展"].tap()
        let goal = app.buttons["目标与周期"]
        reveal(goal, app: app); goal.tap()
        XCTAssertTrue(app.navigationBars["目标与周期"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["减脂每周复盘"].waitForExistence(timeout: 5))
        capture("15-goal-cycle", app: app)
        app.buttons["主导航-饮食"].tap()
        let allMeals = app.buttons["餐单、备餐与全部餐食"]
        reveal(allMeals, app: app); allMeals.tap()
        XCTAssertTrue(app.navigationBars["餐单与备餐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["饮食-明日备餐"].waitForExistence(timeout: 5))
        capture("16-nutrition-tools", app: app)
        let prep = app.buttons["饮食-明日备餐"]
        reveal(prep, app: app); prep.tap()
        XCTAssertTrue(app.buttons["备餐-食谱-午餐"].waitForExistence(timeout: 5))
        capture("17-meal-prep", app: app)
        app.buttons["备餐-食谱-午餐"].tap()
        XCTAssertTrue(app.navigationBars["食谱详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["食谱-原配方份数"].exists)
        capture("18-recipe", app: app)
    }

    func testSprintLargeTypeNavigationBodyAndDataActionsRemainReachable() {
        let app = launch(ready: true, large: true, preview: true)
        assertWeekControls(app)
        capture("19-large-training", app: app)
        app.buttons["主导航-饮食"].tap()
        let meal = app.buttons["饮食-记录一餐"]
        reveal(meal, app: app)
        XCTAssertGreaterThanOrEqual(meal.frame.height, 44)
        capture("20-large-nutrition", app: app)
        app.buttons["主导航-进展"].tap()
        let trends = app.buttons["全部训练趋势与历史"]
        reveal(trends, app: app); trends.tap()
        XCTAssertTrue(app.navigationBars["训练趋势"].waitForExistence(timeout: 5))
        capture("21a-large-training-trends", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["身体"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["进展-身体趋势图"].firstMatch.exists)
        let body = app.buttons["记录与查看身体数据"]
        reveal(body, app: app)
        XCTAssertGreaterThanOrEqual(body.frame.height, 44)
        capture("21-large-progress", app: app)
        body.tap()
        XCTAssertTrue(app.navigationBars["身体数据"].waitForExistence(timeout: 5))
        capture("21b-large-body-records", app: app)
        app.buttons["主导航-我的"].tap()
        let settings = app.buttons["打开设置"]
        reveal(settings, app: app); settings.tap()
        XCTAssertTrue(app.buttons["设置-数据"].waitForExistence(timeout: 5))
        app.buttons["设置-数据"].tap()
        let generate = app.buttons["设置-生成备份"]
        reveal(generate, app: app)
        XCTAssertGreaterThanOrEqual(generate.frame.height, 44)
        XCTAssertTrue(app.buttons["设置-导入备份"].exists)
        capture("22-large-data", app: app)
    }

    func testSprintWorkoutKeepsPrefillEditableAndCompletesOnlySelectedSet() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let weight = app.textFields["actual-weight-预填测试推胸-1"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8))
        XCTAssertEqual(weight.value as? String, "25")
        XCTAssertEqual(app.buttons["完成第 1 组"].firstMatch.value as? String, "未完成")
        weight.tap()
        weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "22.5")
        app.buttons["完成"].firstMatch.tap()
        capture("23-workout-editable", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap()
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertEqual(weight.value as? String, "22.5")
        XCTAssertEqual(app.buttons["完成第 1 组"].firstMatch.value as? String, "未完成")
        let complete = app.buttons["完成第 1 组"].firstMatch
        reveal(complete, app: app); complete.tap()
        XCTAssertTrue(app.buttons["第 1 组已完成"].exists)
        XCTAssertEqual(app.buttons["完成第 2 组"].firstMatch.value as? String, "未完成")
        capture("24-workout-only-one-completed", app: app)
    }
}
