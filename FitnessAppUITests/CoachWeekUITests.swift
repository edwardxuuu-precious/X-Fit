import XCTest

final class CoachWeekUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func openCoach(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-coach-week"] + additionalArguments
        app.launch()
        let profile = app.buttons["主导航-我的"]
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()
        let link = app.buttons["我的-整周训练教练"]
        reveal(link, app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.navigationBars["整周训练教练"].waitForExistence(timeout: 5))
        return app
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        func visible() -> Bool {
            guard element.exists && element.isHittable else { return false }
            guard element.elementType == .textField else { return true }
            let navigation = app.navigationBars.firstMatch
            if navigation.exists && element.frame.minY < navigation.frame.maxY { return false }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists && element.frame.maxY > keyboard.frame.minY { return false }
            return true
        }
        if visible() { return }
        for id in ["整周教练-编辑收起键盘", "整周教练-收起键盘"] {
            let done = app.buttons[id]
            if done.exists && done.isHittable { done.tap(); break }
        }
        for _ in 0..<12 where !visible() { app.swipeDown() }
        for _ in 0..<12 where !visible() { app.swipeUp() }
    }

    private func revealDayForTap(_ element: XCUIElement, _ app: XCUIApplication) {
        func visible() -> Bool {
            guard element.exists && element.isHittable else { return false }
            return element.frame.minY >= app.navigationBars.firstMatch.frame.maxY &&
                element.frame.maxY <= app.frame.maxY - 100
        }
        func scroll(_ down: Bool) {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.35 : 0.70))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.70 : 0.35))
            start.press(forDuration: 0.2, thenDragTo: end)
        }
        for _ in 0..<28 where !visible() { scroll(true) }
        for _ in 0..<28 where !visible() { scroll(false) }
        XCTAssertTrue(visible(), "日期必须位于导航栏与底栏之间才能点击")
    }

    private func enable(_ control: XCUIElement, in app: XCUIApplication) {
        reveal(control, app)
        XCTAssertTrue(control.exists)
        // XCTest may report a lazy Form row as hittable while the switch is below the tab bar.
        for _ in 0..<3 {
            if control.frame.maxY > app.frame.maxY - 100 { app.swipeUp() }
            else if control.frame.minY < app.navigationBars.firstMatch.frame.maxY { app.swipeDown() }
            else { break }
        }
        if (control.value as? String) != "1" {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(control.value as? String, "1")
    }

    private func generateExplicitCardioException(_ app: XCUIApplication, withWeekendCardio: Bool = false) {
        enable(app.switches["本周自定七日目标例外"], in: app)
        let reason = app.textFields["本周例外原因"]
        reveal(reason, app); XCTAssertTrue(reason.exists)
        reason.tap(); reason.typeText("仅本周本人确认有氧缺额与休息安排")
        if withWeekendCardio {
            let weekend = app.buttons["仅本周加入周六跳绳和周日Zone 2"]
            reveal(weekend, app); weekend.tap()
        }
        let generate = app.buttons["整周教练-生成"]
        reveal(generate, app); generate.tap()
    }

    func testAlternatingWeekDisplaysPyramidAndDropBeforeConfirmation() {
        let app = openCoach(additionalArguments: ["--ui-testing-coach-week-alternating"])
        let generate = app.buttons["整周教练-生成"]
        reveal(generate, app); generate.tap()
        let first = app.buttons["整周教练-日期-2026-11-16"]
        revealDayForTap(first, app)
        XCTAssertTrue(first.label.contains("胸肩力量"))
        first.tap()
        XCTAssertTrue(app.navigationBars["2026-11-16"].waitForExistence(timeout: 5))
        let drop = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "第4工作组后")).firstMatch
        reveal(drop, app); XCTAssertTrue(drop.exists)
        let startingLoad = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "首组重量 W")).firstMatch
        reveal(startingLoad, app); XCTAssertTrue(startingLoad.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)
    }

    func testSevenDayDraftAndEditsRemainSeparateUntilExplicitReview() {
        let app = openCoach()
        let generate = app.buttons["整周教练-生成"]
        reveal(generate, app); generate.tap()

        let dates = ["16", "17", "18", "19", "20", "21", "22"].map { "2026-11-\($0)" }
        for day in dates {
            let row = app.buttons["整周教练-日期-\(day)"]
            reveal(row, app)
            XCTAssertTrue(row.exists, "七日草案缺少 \(day)")
        }
        let firstVersion = app.staticTexts["当前草案版本：第1版"]
        reveal(firstVersion, app)
        XCTAssertTrue(firstVersion.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)

        let first = app.buttons["整周教练-日期-2026-11-16"]
        revealDayForTap(first, app); first.tap()
        XCTAssertTrue(app.navigationBars["2026-11-16"].waitForExistence(timeout: 5))
        let weight = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "重量")).firstMatch
        reveal(weight, app); XCTAssertTrue(weight.exists)
        weight.tap(); weight.typeText("30")
        let reason = app.textFields["整周教练-逐组修改原因"]
        reveal(reason, app); reason.tap(); reason.typeText("本人校准首组")
        let save = app.buttons["保存逐组新版本"]
        reveal(save, app); XCTAssertTrue(save.isEnabled); save.tap()
        let secondVersion = app.staticTexts["当前草案版本：第2版"]
        reveal(secondVersion, app)
        XCTAssertTrue(secondVersion.waitForExistence(timeout: 5))

        let second = app.buttons["整周教练-日期-2026-11-17"]
        revealDayForTap(second, app); second.tap()
        let secondWeight = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", "重量")).firstMatch
        reveal(secondWeight, app); XCTAssertTrue(secondWeight.exists)
        secondWeight.tap(); secondWeight.typeText("25")
        let secondReason = app.textFields["整周教练-逐组修改原因"]
        reveal(secondReason, app); secondReason.tap(); secondReason.typeText("本人调整另一日")
        let saveSecond = app.buttons["保存逐组新版本"]
        reveal(saveSecond, app); XCTAssertTrue(saveSecond.isEnabled); saveSecond.tap()
        let thirdVersion = app.staticTexts["当前草案版本：第3版"]
        reveal(thirdVersion, app)
        XCTAssertTrue(thirdVersion.waitForExistence(timeout: 5))
        let firstEdit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本人校准首组")).firstMatch
        reveal(firstEdit, app); XCTAssertTrue(firstEdit.exists)
        let secondEdit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本人调整另一日")).firstMatch
        reveal(secondEdit, app); XCTAssertTrue(secondEdit.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)
    }

    func testConfirmationRequiresCompleteReviewAndPreservesOriginalRequest() {
        let app = openCoach()
        generateExplicitCardioException(app)
        let confirm = app.buttons["整周教练-确认"]
        reveal(confirm, app)
        XCTAssertTrue(confirm.exists)
        XCTAssertFalse(confirm.isEnabled, "七日审阅前不得写正式安排")
        let review = app.switches["整周教练-完整审阅"]
        enable(review, in: app)
        XCTAssertTrue(confirm.isEnabled, "隔离 fixture 应产生无阻断的完整七日候选")
        confirm.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.waitForExistence(timeout: 8))
        let originalRequest = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "核对原请求")).firstMatch
        reveal(originalRequest, app); XCTAssertTrue(originalRequest.exists)
        originalRequest.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "已完整回读；未创建新请求")).firstMatch.waitForExistence(timeout: 5))
        let reviewLink = app.buttons["回顾原草案、本人修改、实际与恢复"]
        reveal(reviewLink, app); reviewLink.tap()
        XCTAssertTrue(app.navigationBars["整周训练回顾"].waitForExistence(timeout: 5))
        let unknown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "是否训练未知")).firstMatch
        reveal(unknown, app); XCTAssertTrue(unknown.exists)
    }

    func testDatedLowerChainExceptionDoesNotBecomeOngoingDefault() {
        let app = openCoach()
        let toggle = app.switches["本周前链／后链／综合专项"]
        enable(toggle, in: app)
        let reason = app.textFields["本周例外原因"]
        reveal(reason, app); reason.tap(); reason.typeText("本周本人选择下肢专项")
        let generate = app.buttons["整周教练-生成"]
        reveal(generate, app); generate.tap()
        let exception = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2026-11-16 至 2026-11-22")).firstMatch
        reveal(exception, app); XCTAssertTrue(exception.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "到期不续排")).firstMatch.exists)
        let firstDay = app.buttons["整周教练-日期-2026-11-16"]
        let lastDay = app.buttons["整周教练-日期-2026-11-22"]
        reveal(firstDay, app); XCTAssertTrue(firstDay.exists)
        reveal(lastDay, app); XCTAssertTrue(lastDay.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)
    }

    func testRopeAndZone2HaveSeparateTypedDetails() {
        let app = openCoach()
        generateExplicitCardioException(app, withWeekendCardio: true)
        let rope = app.buttons["整周教练-日期-2026-11-18"]
        reveal(rope, app); rope.tap()
        let ropeTitle = app.staticTexts["跳绳 · 独立有氧"]
        reveal(ropeTitle, app); XCTAssertTrue(ropeTitle.exists)
        let ropeDetails = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "实际跳绳由当天跳绳菜单记录")).firstMatch
        reveal(ropeDetails, app); XCTAssertTrue(ropeDetails.exists)
        app.navigationBars["2026-11-18"].buttons.firstMatch.tap()
        let bike = app.buttons["整周教练-日期-2026-11-22"]
        reveal(bike, app); bike.tap()
        let zoneTitle = app.staticTexts["Zone 2 · 独立有氧"]
        reveal(zoneTitle, app); XCTAssertTrue(zoneTitle.exists)
        let zoneDetails = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "实际时长")).firstMatch
        reveal(zoneDetails, app); XCTAssertTrue(zoneDetails.exists)
    }

    func testMissingCardioIdentityBlocksFormalWrite() {
        let app = openCoach(additionalArguments: ["--ui-testing-coach-week-missing-cardio"])
        generateExplicitCardioException(app, withWeekendCardio: true)
        let zoneDay = app.buttons["整周教练-日期-2026-11-22"]
        reveal(zoneDay, app); zoneDay.tap()
        let missing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "记录动作身份待确认")).firstMatch
        reveal(missing, app); XCTAssertTrue(missing.exists)
        app.navigationBars["2026-11-22"].buttons.firstMatch.tap()
        let review = app.switches["整周教练-完整审阅"]
        enable(review, in: app)
        let confirm = app.buttons["整周教练-确认"]
        reveal(confirm, app)
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(app.staticTexts["当前有缺项或规则阻断；先修改并重新验证。"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)
    }

    func testDefaultWeekendRestKeepsCardioGapOpen() {
        let app = openCoach()
        let generate = app.buttons["整周教练-生成"]
        reveal(generate, app); generate.tap()
        let saturday = app.buttons["整周教练-日期-2026-11-21"]
        let sunday = app.buttons["整周教练-日期-2026-11-22"]
        reveal(saturday, app); XCTAssertTrue(saturday.label.contains("休息"))
        reveal(sunday, app); XCTAssertTrue(sunday.label.contains("休息"))
        let ropeGap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "跳绳候选缺1次")).firstMatch
        let zoneGap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Zone 2候选缺1次")).firstMatch
        reveal(ropeGap, app); XCTAssertTrue(ropeGap.exists)
        reveal(zoneGap, app); XCTAssertTrue(zoneGap.exists)
        enable(app.switches["整周教练-完整审阅"], in: app)
        let confirm = app.buttons["整周教练-确认"]
        reveal(confirm, app); XCTAssertFalse(confirm.isEnabled)
        let exception = app.buttons["将当前七日目标确认为仅本周例外"]
        reveal(exception, app); XCTAssertTrue(exception.exists)
    }

    func testCoreGapNeedsExplicitReasonAndSingleWeekConsent() {
        let app = openCoach(additionalArguments: ["--ui-testing-coach-week-no-core"])
        let generate = app.buttons["整周教练-生成"]
        reveal(generate, app); generate.tap()
        let gap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "腹部每周至少4个不同动作")).firstMatch
        reveal(gap, app); XCTAssertTrue(gap.exists)
        let confirm = app.buttons["整周教练-确认"]
        reveal(confirm, app); XCTAssertFalse(confirm.isEnabled)
        let coreException = app.switches["整周教练-确认本周腹部例外"]
        reveal(coreException, app); XCTAssertEqual(coreException.value as? String, "0")
        enable(coreException, in: app)
        let reason = app.textFields["本周腹部例外原因"]
        reveal(reason, app); reason.tap(); reason.typeText("恢复周本人选择本周腹部例外")
        let exception = app.buttons["仅确认本周腹部例外"]
        reveal(exception, app); XCTAssertTrue(exception.isEnabled); exception.tap()
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本周腹部例外")).firstMatch
        reveal(note, app); XCTAssertTrue(note.waitForExistence(timeout: 5))
        let resetConsent = app.switches["整周教练-确认本周腹部例外"]
        reveal(resetConsent, app); XCTAssertEqual(resetConsent.value as? String, "0")
        let ropeGap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "跳绳候选缺1次")).firstMatch
        let zoneGap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Zone 2候选缺1次")).firstMatch
        reveal(ropeGap, app); XCTAssertTrue(ropeGap.exists)
        reveal(zoneGap, app); XCTAssertTrue(zoneGap.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)
    }

    func testPastUnrecordedRestCanBeReviewedWithoutCreatingWorkout() {
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = .current
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
        let pastWeekStart = calendar.isDateInToday(currentWeek) ? calendar.date(byAdding: .day, value: -7, to: currentWeek)! : currentWeek
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: pastWeekStart)
        let app = openCoach(additionalArguments: ["--ui-testing-coach-week-past-rest"])
        let generate = app.buttons["整周教练-生成"]
        reveal(generate, app); generate.tap()
        let day = app.buttons["整周教练-日期-\(date)"]
        reveal(day, app); XCTAssertTrue(day.exists); day.tap()
        XCTAssertTrue(app.navigationBars[date].waitForExistence(timeout: 5))
        let reason = app.textFields["过去日期核对原因"]
        reveal(reason, app); XCTAssertTrue(reason.exists)
        let confirmRest = app.buttons["本人确认当天休息"]
        reveal(confirmRest, app); XCTAssertFalse(confirmRest.isEnabled)
        reveal(reason, app); reason.tap(); reason.typeText("本人核对当天休息")
        reveal(confirmRest, app); XCTAssertTrue(confirmRest.isEnabled); confirmRest.tap()
        let reviewed = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本人核对休息")).firstMatch
        reveal(reviewed, app); XCTAssertTrue(reviewed.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)
    }

    func testGenerateCoreOnlyExceptionLeavesCardioUndecided() {
        let app = openCoach(additionalArguments: ["--ui-testing-coach-week-no-core"])
        enable(app.switches["整周教练-生成时腹部例外"], in: app)
        let reason = app.textFields["生成时腹部例外原因"]
        reveal(reason, app); reason.tap(); reason.typeText("本人本周恢复需要腹部例外")
        let generate = app.buttons["整周教练-生成"]
        reveal(generate, app); generate.tap()
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本周腹部例外")).firstMatch
        reveal(note, app); XCTAssertTrue(note.exists)
        let ropeGap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "跳绳候选缺1次")).firstMatch
        let zoneGap = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Zone 2候选缺1次")).firstMatch
        reveal(ropeGap, app); XCTAssertTrue(ropeGap.exists)
        reveal(zoneGap, app); XCTAssertTrue(zoneGap.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)
    }

    func testUnknownPreservedArrangementCanBeReviewedWithoutInventingHistory() {
        let app = openCoach(additionalArguments: ["--ui-testing-coach-week-preserved-unknown"])
        let generate = app.buttons["整周教练-生成"]
        reveal(generate, app); generate.tap()
        let originalRoot = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "草案根 ")).firstMatch
        reveal(originalRoot, app)
        XCTAssertTrue(originalRoot.exists)
        let originalRootLabel = originalRoot.label

        let monday = app.buttons["整周教练-日期-2026-11-16"]
        reveal(monday, app); monday.tap()
        let sourceID = "7F942CE4-1372-445E-AC38-87EBE06D8604"
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", sourceID)).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "原安排没有可核验的逐组快照")).firstMatch.exists)
        let reason = app.textFields["核对原因"]
        reveal(reason, app); reason.tap(); reason.typeText("本人核对该原日程本周属于胸部力量，原逐组记录仍未知")
        let save = app.buttons["保存保留安排注记并重验整周"]
        reveal(save, app); XCTAssertTrue(save.isEnabled); save.tap()

        let reviewedRoot = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "草案根 ")).firstMatch
        reveal(reviewedRoot, app)
        XCTAssertTrue(reviewedRoot.waitForExistence(timeout: 5))
        XCTAssertNotEqual(reviewedRoot.label, originalRootLabel, "本人核对须产生新 root 并保留原草案")
        let reviewNote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本人核对该原日程本周属于胸部力量")).firstMatch
        reveal(reviewNote, app); XCTAssertTrue(reviewNote.exists)
        let retainedID = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", sourceID)).firstMatch
        reveal(retainedID, app); XCTAssertTrue(retainedID.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)
    }

    func testEditedExistingWeekExceptionRequiresExplicitReconfirmation() {
        let app = openCoach()
        generateExplicitCardioException(app)
        let originalRoot = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "草案根 ")).firstMatch
        reveal(originalRoot, app); XCTAssertTrue(originalRoot.exists)
        let originalRootLabel = originalRoot.label

        let friday = app.buttons["整周教练-日期-2026-11-20"]
        reveal(friday, app)
        if friday.exists && friday.frame.midY > app.frame.maxY - 100 { app.swipeUp() }
        friday.tap()
        XCTAssertTrue(app.navigationBars["2026-11-20"].waitForExistence(timeout: 5))
        let focus = app.textFields["整周教练-当日目标"]
        reveal(focus, app); XCTAssertTrue(focus.exists)
        focus.tap()
        let oldFocus = (focus.value as? String) ?? ""
        focus.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldFocus.count) + "胸")
        let reason = app.textFields["整周教练-目标修改原因"]
        reveal(reason, app); reason.tap(); reason.typeText("本人把周五目标改为胸部")
        let save = app.buttons["保存新版本"]
        reveal(save, app); XCTAssertTrue(save.isEnabled); save.tap()

        let staleGoal = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本周例外目标已更改")).firstMatch
        reveal(staleGoal, app); XCTAssertTrue(staleGoal.exists)
        let reconfirm = app.buttons["重新确认当前七日为仅本周新例外"]
        reveal(reconfirm, app); XCTAssertTrue(reconfirm.exists)
        XCTAssertFalse(reconfirm.isEnabled, "已有例外的人工修改须填写新的明确原因")
        let newReason = app.textFields["重新确认本周目标原因"]
        reveal(newReason, app); newReason.tap(); newReason.typeText("本人重新确认改后七日目标仅适用于这周")
        reveal(reconfirm, app)
        XCTAssertTrue(reconfirm.isEnabled)
        reconfirm.tap()

        let newRoot = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "草案根 ")).firstMatch
        reveal(newRoot, app); XCTAssertTrue(newRoot.waitForExistence(timeout: 5))
        XCTAssertNotEqual(newRoot.label, originalRootLabel)
        let newException = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "本人重新确认改后七日目标仅适用于这周")).firstMatch
        reveal(newException, app); XCTAssertTrue(newException.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "正式七日日程已保存并独立回读")).firstMatch.exists)
    }
}
