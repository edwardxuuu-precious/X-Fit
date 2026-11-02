import XCTest

final class TrainingExperienceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testHistoryDefaultRecordingKeepsInputAcrossRIRNotesReentryAndCompletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-history-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let weight = app.textFields["actual-weight-杠铃卧推-1"]
        let reps = app.textFields["actual-reps-杠铃卧推-1"]
        let rir = app.buttons["rir-杠铃卧推-1"]
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        XCTAssertEqual(weight.value as? String, "25")
        XCTAssertEqual(app.staticTexts["实际口径-杠铃卧推"].label, "重量双边 · 次数双边")
        XCTAssertEqual(reps.value as? String, "12")
        XCTAssertEqual(rir.value as? String, "—")
        XCTAssertTrue(rir.isHittable)
        let table = XCTAttachment(screenshot: app.screenshot())
        table.name = "recording-history-default-table"; table.lifetime = .keepAlways; add(table)
        weight.tap()
        weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2)); weight.typeText("27.5")
        rir.tap()
        XCTAssertTrue(app.buttons["RIR 2 · 还能做 2 次"].waitForExistence(timeout: 5))
        let sheet = XCTAttachment(screenshot: app.screenshot())
        sheet.name = "recording-rir-sheet"; sheet.lifetime = .keepAlways; add(sheet)
        app.buttons["取消"].firstMatch.tap()
        XCTAssertEqual(weight.value as? String, "27.5")
        XCTAssertEqual(reps.value as? String, "12")
        XCTAssertEqual(rir.value as? String, "—")
        rir.tap(); app.buttons["RIR 2 · 还能做 2 次"].tap()
        XCTAssertEqual(rir.value as? String, "2")
        XCTAssertEqual(app.buttons["完成第 1 组"].firstMatch.value as? String, "未完成")
        let notesToggle = app.buttons["动作备注入口-杠铃卧推"]
        reveal(notesToggle, in: app); notesToggle.tap()
        let notes = app.textViews["动作备注-杠铃卧推"]
        reveal(notes, in: app); notes.tap(); notes.typeText("本次录入备注")
        let keyboardDone = app.buttons["完成"].firstMatch
        if keyboardDone.exists { keyboardDone.tap() }
        reveal(notesToggle, in: app); notesToggle.tap()
        XCTAssertFalse(notes.exists)
        XCTAssertTrue(notesToggle.label.contains("本次录入备注"))
        let detail = app.buttons["RIR、动作资料与备注"].firstMatch
        XCTAssertTrue(detail.exists)
        app.navigationBars.buttons.firstMatch.tap()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap()
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        reveal(weight, in: app)
        XCTAssertEqual(weight.value as? String, "27.5"); XCTAssertEqual(reps.value as? String, "12")
        XCTAssertEqual(rir.value as? String, "2")
        let complete = app.buttons["完成第 1 组"].firstMatch
        reveal(complete, in: app); complete.tap()
        let completed = app.buttons["第 1 组已完成"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5)); XCTAssertTrue(completed.label.contains("27.5"))
        rir.tap(); app.buttons["RIR 3 · 还能做 3 次"].tap()
        XCTAssertTrue(completed.exists)
        XCTAssertEqual(completed.value as? String, "已完成")
        XCTAssertEqual(rir.value as? String, "3")
        rir.tap(); app.buttons["不记录 RIR"].tap()
        XCTAssertEqual(rir.value as? String, "—")
        XCTAssertEqual(completed.value as? String, "已完成")
        reveal(notesToggle, in: app)
        XCTAssertTrue(notesToggle.label.contains("本次录入备注"))
        if !notes.exists { notesToggle.tap() }
        reveal(notes, in: app); XCTAssertTrue((notes.value as? String)?.contains("本次录入备注") == true)
        let final = XCTAttachment(screenshot: app.screenshot())
        final.name = "recording-notes-persisted"; final.lifetime = .keepAlways; add(final)
    }

    func testTemplateActionSearchAddsOnlyDraftAndCancelKeepsLibraryUnchanged() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview"]
        app.launch()
        let mine = app.buttons["主导航-我的"]
        XCTAssertTrue(mine.waitForExistence(timeout: 15)); mine.tap()
        app.buttons["模板与动作"].tap()
        app.buttons["专项模板入口"].tap()
        app.buttons["新建专项模板"].tap()
        let addAction = app.buttons["模板添加动作"]
        func revealTemplateAction() {
            let navigation = app.navigationBars["新建专项模板"]
            XCTAssertTrue(navigation.waitForExistence(timeout: 5))
            let containers = app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
            guard let form = containers.first(where: \.isHittable) else {
                return XCTFail("模板sheet必须有可见的Form滚动容器")
            }
            let viewport = form.frame.intersection(app.frame)
            let top = max(viewport.minY, navigation.frame.maxY) + 8
            let bottom = viewport.maxY - 8
            for _ in 0..<10 {
                if addAction.exists && addAction.isHittable && addAction.frame.minY >= top && addAction.frame.maxY < bottom { return }
                let center = (top + bottom) / 2
                let delta = addAction.exists ? center - addAction.frame.midY : -180
                let distance = min(max(abs(delta), 32), min(180, (bottom - top) * 0.35))
                let start = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: viewport.midX, dy: center - app.frame.minY))
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: delta < 0 ? -distance : distance)))
            }
            XCTAssertTrue(addAction.isHittable && addAction.frame.minY >= top && addAction.frame.maxY < bottom)
        }
        XCTAssertTrue(addAction.waitForExistence(timeout: 5)); revealTemplateAction(); addAction.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("bench")
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "杠铃卧推")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        let hide = app.buttons["动作搜索-收起键盘"]
        if hide.exists { hide.tap() }
        bench.tap()
        let templateShot = XCTAttachment(screenshot: app.screenshot())
        templateShot.name = "template-after-search-selection"
        templateShot.lifetime = .keepAlways
        add(templateShot)
        XCTAssertTrue(app.navigationBars["新建专项模板"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["杠铃卧推"].exists)
        revealTemplateAction()
        XCTAssertTrue(addAction.exists && addAction.isHittable, "添加动作必须仍可滚动到并点击")
        XCTAssertGreaterThanOrEqual(addAction.frame.height, 44)
        app.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["专项模板"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "新训练计划")).firstMatch.exists)
    }

    func testLargestTypeCanReachAddSetAndCompleteFrozenInstructions() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-long-exercise-notes",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        func revealWorkoutContent(_ element: XCUIElement) {
            let scroll = app.scrollViews["active-workout-scroll"].firstMatch
            XCTAssertTrue(scroll.exists)
            for _ in 0..<10 {
                let top = max(scroll.frame.minY, app.navigationBars.firstMatch.frame.maxY) + 8
                let rail = app.xfitTabBar
                let bottom = min(scroll.frame.maxY, rail.exists ? rail.frame.minY : app.frame.maxY) - 8
                let visible = CGRect(x: scroll.frame.minX, y: top, width: scroll.frame.width, height: bottom - top)
                guard visible.height > 0 else { return XCTFail("训练正文必须有可见的滚动区域") }
                var needsDown = false
                var longTextDistance: CGFloat?
                if element.exists {
                    let frame = element.frame
                    if frame.height > visible.height {
                        // Read the end of long original text; its offscreen
                        // center does not need to be a tappable control.
                        let tail = CGRect(x: frame.minX, y: frame.maxY - 44, width: frame.width, height: 44)
                        if tail.intersection(visible).height >= 44 { return }
                        needsDown = tail.minY < top
                        longTextDistance = abs(tail.midY - visible.midY)
                    } else {
                        if element.isHittable && visible.contains(frame) { return }
                        needsDown = frame.minY < top
                    }
                }
                let halfStep = longTextDistance.map { min($0 / 2, visible.height * 0.35) }
                    ?? min(CGFloat(90), visible.height * 0.2)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let from = origin.withOffset(CGVector(dx: visible.midX, dy: visible.midY + (needsDown ? -halfStep : halfStep)))
                let to = origin.withOffset(CGVector(dx: visible.midX, dy: visible.midY + (needsDown ? halfStep : -halfStep)))
                from.press(forDuration: 0.05, thenDragTo: to)
            }
            XCTFail("最大字号下必须能滚动到训练控件或完整说明末尾：\(element)")
        }
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let weight = app.textFields["actual-weight-杠铃卧推-1"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8))
        revealWorkoutContent(weight)
        XCTAssertGreaterThanOrEqual(weight.frame.height, 44)
        let rir = app.buttons["rir-杠铃卧推-1"]
        revealWorkoutContent(rir); rir.tap()
        let rirChoice = app.buttons["RIR 2 · 还能做 2 次"]
        let rirScroll = app.otherElements["workout-rir-sheet"].scrollViews.firstMatch
        XCTAssertTrue(rirScroll.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            if rirChoice.exists && rirChoice.isHittable
                && rirChoice.frame.minY >= app.navigationBars["记录余力"].frame.maxY
                && rirChoice.frame.maxY <= app.frame.maxY - 8 { break }
            rirScroll.swipeUp()
        }
        XCTAssertTrue(rirChoice.waitForExistence(timeout: 5))
        XCTAssertTrue(rirChoice.isHittable)
        let rirShot = XCTAttachment(screenshot: app.screenshot())
        rirShot.name = "workout-rir-largest-type"; rirShot.lifetime = .keepAlways; add(rirShot)
        rirChoice.tap()
        XCTAssertEqual(rir.value as? String, "2")
        let addSetButton = app.buttons["active-add-set-杠铃卧推"]
        revealWorkoutContent(addSetButton)
        XCTAssertGreaterThanOrEqual(addSetButton.frame.height, 44)
        let reduceButton = app.buttons["active-reduce-set-杠铃卧推"]
        revealWorkoutContent(reduceButton)
        XCTAssertGreaterThanOrEqual(reduceButton.frame.height, 44)
        XCTAssertTrue(reduceButton.isHittable)
        let details = app.buttons["RIR、动作资料与备注"].firstMatch
        revealWorkoutContent(details); details.tap()
        let fullNotes = app.staticTexts["训练说明全文-杠铃卧推"]
        revealWorkoutContent(fullNotes)
        XCTAssertTrue(fullNotes.waitForExistence(timeout: 5))
        XCTAssertTrue(fullNotes.label.contains("跳绳只能替代有氧，不能算完成背部力量训练。"))
        XCTAssertTrue(fullNotes.label.hasSuffix("最后一条：左肘疼痛逐组增加时停止该动作，手臂训练可以省去，不补组。"))
        XCTAssertGreaterThan(fullNotes.frame.width, 220)
        XCTAssertGreaterThan(fullNotes.frame.height, 100)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "workout-table-largest-type"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCompletedExerciseCanBeExpandedAndReceiveAnIncompleteExtraSet() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        XCTAssertTrue(app.textFields["actual-weight-预填测试推胸-1"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["实际口径-预填测试推胸"].label, "重量单边 · 次数双边")
        for number in 1...4 {
            let complete = app.buttons["完成第 \(number) 组"].firstMatch
            reveal(complete, in: app); complete.tap()
        }
        let skipFeeling = app.buttons["跳过感受并收起"]
        reveal(skipFeeling, in: app); skipFeeling.tap()
        let collapsed = app.buttons["切换动作-预填测试推胸"]
        reveal(collapsed, in: app); collapsed.tap()
        let reduce = app.buttons["active-reduce-set-预填测试推胸"]
        reveal(reduce, in: app)
        XCTAssertFalse(reduce.isEnabled)
        let addSetButton = app.buttons["active-add-set-预填测试推胸"]
        XCTAssertGreaterThanOrEqual(addSetButton.frame.height, 48)
        reveal(addSetButton, in: app); addSetButton.tap()
        let extra = app.textFields["actual-weight-预填测试推胸-5"]
        XCTAssertTrue(extra.waitForExistence(timeout: 5))
        XCTAssertEqual(extra.value as? String, "20")
        XCTAssertEqual(app.buttons["完成第 5 组"].firstMatch.value as? String, "未完成")
        for number in 1...4 { XCTAssertTrue(app.buttons["第 \(number) 组已完成"].exists) }
    }

    func testVisibleAddSetKeepsCompletedRowsAndExtraDraftAcrossReentry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let first = app.textFields["actual-weight-预填测试推胸-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        first.tap()
        first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        first.typeText("27.5")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["完成第 1 组"].firstMatch.tap()
        let done = app.buttons["第 1 组已完成"]
        XCTAssertTrue(done.label.contains("27.5"))

        let addSetButton = app.buttons["active-add-set-预填测试推胸"]
        reveal(addSetButton, in: app)
        XCTAssertTrue(addSetButton.isHittable)
        addSetButton.tap()
        let extraWeight = app.textFields["actual-weight-预填测试推胸-5"]
        let extraReps = app.textFields["actual-reps-预填测试推胸-5"]
        reveal(extraWeight, in: app)
        XCTAssertEqual(extraWeight.value as? String, "20")
        XCTAssertEqual(extraReps.value as? String, "10")
        extraWeight.tap()
        extraWeight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        extraWeight.typeText("22.5")
        app.buttons["完成"].firstMatch.tap()
        extraReps.tap()
        extraReps.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        extraReps.typeText("12")
        app.buttons["完成"].firstMatch.tap()

        let details = app.buttons["RIR、动作资料与备注"].firstMatch
        reveal(details, in: app)
        details.tap()
        let rir = app.buttons["rir-预填测试推胸-5"]
        XCTAssertTrue(rir.label.contains("RIR，未记录"))
        app.navigationBars.buttons.firstMatch.tap()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        reveal(extraWeight, in: app)
        XCTAssertEqual(extraWeight.value as? String, "22.5")
        XCTAssertEqual(extraReps.value as? String, "12")
        XCTAssertEqual(app.buttons["完成第 5 组"].firstMatch.value as? String, "未完成")
        XCTAssertTrue(done.label.contains("27.5"))
        let remove = app.buttons["active-reduce-set-预填测试推胸"]
        reveal(remove, in: app)
        remove.tap()
        let confirmReduction = app.buttons["确认减组"]
        XCTAssertTrue(confirmReduction.waitForExistence(timeout: 5))
        confirmReduction.tap()
        XCTAssertFalse(extraWeight.exists)
        XCTAssertTrue(done.exists)
        for number in 2...4 {
            XCTAssertEqual(app.buttons["完成第 \(number) 组"].firstMatch.value as? String, "未完成")
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "workout-table-extra-set-conservation"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testReduceDefaultSetsProtectsDraftAndRestoresAfterReentry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let firstWeight = app.textFields["actual-weight-预填测试推胸-1"]
        XCTAssertTrue(firstWeight.waitForExistence(timeout: 8))
        for number in 1...2 {
            let complete = app.buttons["完成第 \(number) 组"].firstMatch
            reveal(complete, in: app); complete.tap()
            XCTAssertTrue(app.buttons["第 \(number) 组已完成"].exists)
        }
        let fourth = app.textFields["actual-weight-预填测试推胸-4"]
        reveal(fourth, in: app); fourth.tap()
        fourth.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        fourth.typeText("22.5")
        app.buttons["完成"].firstMatch.tap()
        let reduce = app.buttons["active-reduce-set-预填测试推胸"]
        reveal(reduce, in: app); reduce.tap()
        let cancel = app.buttons["取消"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertEqual(fourth.value as? String, "22.5")
        reveal(reduce, in: app); reduce.tap()
        let confirm = app.buttons["确认减组"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertFalse(fourth.exists)
        reveal(reduce, in: app); reduce.tap()
        XCTAssertFalse(app.textFields["actual-weight-预填测试推胸-3"].exists)
        XCTAssertTrue(app.buttons["第 1 组已完成"].exists)
        XCTAssertTrue(app.buttons["第 2 组已完成"].exists)
        let addSet = app.buttons["active-add-set-预填测试推胸"]
        let aligned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(addSet.frame.midY - reduce.frame.midY) <= 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [aligned], timeout: 5), .completed, "加组和减组按钮应在同一行")
        let reducedScreenshot = XCTAttachment(screenshot: app.screenshot())
        reducedScreenshot.name = "planned-sets-reduced-to-two"
        reducedScreenshot.lifetime = .keepAlways
        add(reducedScreenshot)
        app.navigationBars.buttons.firstMatch.tap()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap()
        let restore = app.buttons["active-restore-reduced-set-预填测试推胸"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        reveal(restore, in: app); restore.tap()
        XCTAssertTrue(app.textFields["actual-weight-预填测试推胸-3"].exists)
        reveal(restore, in: app); restore.tap()
        XCTAssertTrue(fourth.waitForExistence(timeout: 5))
        XCTAssertEqual(fourth.value as? String, "22.5")
        XCTAssertTrue(app.buttons["第 1 组已完成"].exists)
        XCTAssertTrue(app.buttons["第 2 组已完成"].exists)
    }

    func testReducingAllSetsShowsSkippedAndCanBeRestored() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let reduce = app.buttons["active-reduce-set-预填测试推胸"]
        XCTAssertTrue(reduce.waitForExistence(timeout: 8))
        for _ in 0..<4 { reveal(reduce, in: app); reduce.tap() }
        let skipped = app.staticTexts["active-skipped-预填测试推胸"]
        XCTAssertTrue(skipped.waitForExistence(timeout: 5))
        XCTAssertFalse(reduce.isEnabled)
        XCTAssertFalse(app.buttons["结束本次训练"].isEnabled)
        let restore = app.buttons["active-restore-reduced-set-预填测试推胸"]
        reveal(restore, in: app); restore.tap()
        XCTAssertTrue(app.textFields["actual-weight-预填测试推胸-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(reduce.isEnabled)
    }

    func testDirectPartialReplacementKeepsCompletedRowsAndDefaultsToTwoSetsAfterReentry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        XCTAssertTrue(app.textFields["actual-weight-预填测试推胸-1"].waitForExistence(timeout: 8))
        for number in 1...2 {
            let complete = app.buttons["完成第 \(number) 组"].firstMatch
            reveal(complete, in: app); complete.tap()
        }
        let replace = app.buttons["active-replace-exercise-预填测试推胸"]
        reveal(replace, in: app)
        assertMinimumTapHeight(replace, in: app)
        replace.tap()
        chooseReplacementBench(in: app)
        XCTAssertTrue(app.steppers["组数：2"].waitForExistence(timeout: 5))
        app.buttons["使用上次设置"].tap()

        let newFirst = app.textFields["actual-weight-杠铃卧推-1"]
        XCTAssertTrue(newFirst.waitForExistence(timeout: 8))
        XCTAssertEqual(newFirst.value as? String, "0", "新动作不能继承原推胸的25kg")
        XCTAssertTrue(app.textFields["actual-weight-杠铃卧推-2"].exists)
        XCTAssertFalse(app.textFields["actual-weight-杠铃卧推-3"].exists)
        XCTAssertFalse(app.textFields["actual-weight-预填测试推胸-3"].exists)
        let oldAction = app.buttons["切换动作-预填测试推胸"]
        reveal(oldAction, in: app)
        XCTAssertTrue(oldAction.label.contains("已完成 2 组"))
        oldAction.tap()
        XCTAssertTrue(app.buttons["第 1 组已完成"].exists)
        XCTAssertTrue(app.buttons["第 2 组已完成"].exists)
        XCTAssertTrue(app.buttons["第 1 组已完成"].label.contains("25 kg（单边） × 8（双边）"))
        XCTAssertTrue(app.buttons["第 2 组已完成"].label.contains("20 kg（单边） × 10（双边）"))
        XCTAssertFalse(app.buttons["active-replace-exercise-预填测试推胸"].isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "active-partial-replacement-completed-source-and-new-action"
        shot.lifetime = .keepAlways
        add(shot)

        app.navigationBars.buttons.firstMatch.tap()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap()
        let newAction = app.buttons["切换动作-杠铃卧推"]
        reveal(newAction, in: app); newAction.tap()
        XCTAssertTrue(newFirst.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["actual-weight-杠铃卧推-2"].exists)
        XCTAssertFalse(app.textFields["actual-weight-杠铃卧推-3"].exists)
        app.scrollViews["active-workout-scroll"].swipeDown()
        app.scrollViews["active-workout-scroll"].swipeDown()
        let currentShot = XCTAttachment(screenshot: app.screenshot())
        currentShot.name = "active-replacement-current-action-and-kept-source"
        currentShot.lifetime = .keepAlways
        add(currentShot)
    }

    func testReplacementDraftConfirmationAndPickerSetupCancellationKeepOriginalInput() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let fourth = app.textFields["actual-weight-预填测试推胸-4"]
        XCTAssertTrue(fourth.waitForExistence(timeout: 8))
        reveal(fourth, in: app); fourth.tap()
        fourth.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        fourth.typeText("22.5")
        let replace = app.buttons["active-replace-exercise-预填测试推胸"]
        app.buttons["完成"].firstMatch.tap()
        reveal(replace, in: app); replace.tap()
        let warning = app.alerts["剩余组已有输入"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        warning.buttons["取消"].tap()
        XCTAssertEqual(fourth.value as? String, "22.5")
        XCTAssertFalse(app.navigationBars["替换剩余动作"].exists)

        replace.tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        warning.buttons["继续选择替换动作"].tap()
        XCTAssertTrue(app.navigationBars["替换剩余动作"].waitForExistence(timeout: 5))
        app.navigationBars["替换剩余动作"].buttons["取消"].tap()
        XCTAssertEqual(fourth.value as? String, "22.5")
        XCTAssertFalse(app.buttons["切换动作-杠铃卧推"].exists)

        replace.tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        warning.buttons["继续选择替换动作"].tap()
        chooseReplacementBench(in: app)
        XCTAssertTrue(app.steppers["组数：4"].waitForExistence(timeout: 5))
        app.navigationBars["本次设置"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["替换剩余动作"].waitForExistence(timeout: 5))
        app.navigationBars["替换剩余动作"].buttons["取消"].tap()
        XCTAssertEqual(fourth.value as? String, "22.5")
        for number in 1...4 {
            XCTAssertTrue(app.textFields["actual-weight-预填测试推胸-\(number)"].exists)
            XCTAssertEqual(app.buttons["完成第 \(number) 组"].firstMatch.value as? String, "未完成")
        }
        XCTAssertFalse(app.textFields["actual-weight-杠铃卧推-1"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap()
        XCTAssertTrue(fourth.waitForExistence(timeout: 5))
        XCTAssertEqual(fourth.value as? String, "22.5")
    }

    func testZeroCompletedReplacementAtLargestTypeKeepsDirectButtonReachableAndUsesChosenCount() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let replace = app.buttons["active-replace-exercise-预填测试推胸"]
        XCTAssertTrue(replace.waitForExistence(timeout: 8))
        reveal(replace, in: app)
        assertMinimumTapHeight(replace, in: app)
        XCTAssertGreaterThanOrEqual(replace.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(replace.frame.maxX, app.frame.maxX)
        replace.tap()
        chooseReplacementBench(in: app)
        let sets = app.steppers["组数：4"]
        XCTAssertTrue(sets.waitForExistence(timeout: 5))
        let decrease = sets.buttons["Decrement"].firstMatch
        let use = app.buttons["使用上次设置"]
        for _ in 0..<10 {
            let top = app.navigationBars["本次设置"].frame.maxY
            if decrease.isHittable && decrease.frame.minY >= top
                && decrease.frame.maxY < use.frame.minY - 8 { break }
            if decrease.frame.minY < top { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(decrease.isHittable); decrease.tap()
        XCTAssertTrue(app.steppers["组数：3"].waitForExistence(timeout: 5))
        XCTAssertTrue(use.exists); use.tap()
        let newFirst = app.textFields["actual-weight-杠铃卧推-1"]
        XCTAssertTrue(newFirst.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["active-replace-exercise-预填测试推胸"].exists)
        XCTAssertTrue(app.textFields["actual-weight-杠铃卧推-3"].exists)
        XCTAssertFalse(app.textFields["actual-weight-杠铃卧推-4"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "active-zero-completed-replacement-largest-type"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCameraReplacementDefaultsToRemainingSetsAndKeepsChosenCount() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill", "--ui-testing-equipment-recognition"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        for number in 1...2 {
            let complete = app.buttons["完成第 \(number) 组"].firstMatch
            XCTAssertTrue(complete.waitForExistence(timeout: 8))
            reveal(complete, in: app); complete.tap()
        }
        let replace = app.buttons["active-replace-exercise-预填测试推胸"]
        reveal(replace, in: app); replace.tap()
        let camera = app.buttons["拍照识别器械"]
        XCTAssertTrue(camera.waitForExistence(timeout: 5)); camera.tap()
        let scan = app.buttons["开始识别器械"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5)); scan.tap()
        let candidate = app.buttons["识别动作-钟摆深蹲机"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 8))
        for _ in 0..<5 {
            if candidate.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(candidate.isHittable); candidate.tap()
        let sets = app.steppers["组数：2"]
        XCTAssertTrue(sets.waitForExistence(timeout: 5))
        sets.buttons["Increment"].tap()
        XCTAssertTrue(app.steppers["组数：3"].exists)
        app.buttons["使用上次设置"].tap()
        XCTAssertTrue(app.textFields["actual-weight-钟摆深蹲机-1"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["actual-weight-钟摆深蹲机-3"].exists)
        XCTAssertFalse(app.textFields["actual-weight-钟摆深蹲机-4"].exists)
        XCTAssertTrue(app.buttons["切换动作-预填测试推胸"].label.contains("已完成 2 组"))
    }

    private func assertMinimumTapHeight(_ element: XCUIElement, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line) {
        guard let pixelWidth = XCUIScreen.main.screenshot().image.cgImage?.width,
              app.frame.width > 0 else {
            return XCTFail("无法读取屏幕像素尺寸", file: file, line: line)
        }
        let scale = CGFloat(pixelWidth) / app.frame.width
        XCTAssertGreaterThanOrEqual((element.frame.height * scale).rounded(), (44 * scale).rounded(),
            "触控高度至少为44pt，按显示像素核对", file: file, line: line)
    }

    private func chooseReplacementBench(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["替换剩余动作"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("杠铃卧推")
        let hide = app.buttons["动作搜索-收起键盘"]
        if hide.waitForExistence(timeout: 3) && hide.isHittable { hide.tap() }
        else { search.typeText("\n") }
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "杠铃卧推")).firstMatch
        for _ in 0..<8 {
            let top = app.navigationBars["替换剩余动作"].frame.maxY
            if option.exists && option.isHittable && option.frame.minY >= top { break }
            app.swipeUp()
        }
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertTrue(option.isHittable)
        option.tap()
        XCTAssertTrue(app.navigationBars["本次设置"].waitForExistence(timeout: 5))
    }

    func testHistoryEditKeepsSkippedExerciseAtZeroSets() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent", "--ui-testing-reset-store"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let first = app.buttons["完成第 1 组"].firstMatch
        reveal(first, in: app); first.tap()
        let next = app.buttons["切换动作-上斜哑铃卧推"]
        XCTAssertTrue(next.waitForExistence(timeout: 5)); reveal(next, in: app); next.tap()
        let reduce = app.buttons["active-reduce-set-上斜哑铃卧推"]
        XCTAssertTrue(reduce.waitForExistence(timeout: 5))
        for _ in 0..<3 { reveal(reduce, in: app); reduce.tap() }
        XCTAssertTrue(app.staticTexts["active-skipped-上斜哑铃卧推"].exists)
        app.buttons["结束本次训练"].tap()
        let confirm = app.buttons["完成训练"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let close = app.buttons["关闭训练完成反馈"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        let actual = app.descendants(matching: .any)["训练-当天实际"]
        XCTAssertTrue(actual.waitForExistence(timeout: 5))
        let record = actual.buttons.containing(.staticText, identifier: "训练-训练标题").firstMatch
        reveal(record, in: app); record.tap()
        let edit = app.buttons["编辑历史"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(app.navigationBars["编辑历史训练"].waitForExistence(timeout: 5))
        let zeroSets = app.steppers["history-edit-set-count-上斜哑铃卧推"]
        reveal(zeroSets, in: app)
        XCTAssertEqual(zeroSets.label, "完成组数：0")
        let untouched = app.steppers["history-edit-set-count-绳索下压"]
        reveal(untouched, in: app)
        XCTAssertEqual(untouched.label, "完成组数：0")
        app.navigationBars["编辑历史训练"].buttons["保存"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(app.navigationBars["编辑历史训练"].waitForExistence(timeout: 5))
        reveal(zeroSets, in: app)
        XCTAssertEqual(zeroSets.label, "完成组数：0", "保存历史编辑不能替跳过的动作生成完成组")
        reveal(untouched, in: app)
        XCTAssertEqual(untouched.label, "完成组数：0", "保存历史编辑不能替其他未做动作生成完成组")
        app.terminate()
    }

    func testConfirmedDailyPrefillIsEditableSurvivesReentryAndOnlyCompletesOnTap() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-daily-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let firstWeight = app.textFields["actual-weight-预填测试推胸-1"]
        XCTAssertTrue(firstWeight.waitForExistence(timeout: 8))
        for number in 1...4 {
            let weight = app.textFields["actual-weight-预填测试推胸-\(number)"]
            let reps = app.textFields["actual-reps-预填测试推胸-\(number)"]
            XCTAssertEqual(weight.value as? String, number == 1 ? "25" : "20")
            XCTAssertEqual(reps.value as? String, number == 1 ? "8" : "10")
            XCTAssertEqual(app.buttons["完成第 \(number) 组"].firstMatch.value as? String, "未完成")
        }
        firstWeight.tap()
        firstWeight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        firstWeight.typeText("22.5")
        app.buttons["完成"].firstMatch.tap()
        let firstReps = app.textFields["actual-reps-预填测试推胸-1"]
        firstReps.tap()
        firstReps.typeText(XCUIKeyboardKey.delete.rawValue)
        firstReps.typeText("9")
        app.buttons["完成"].firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertEqual(firstWeight.value as? String, "22.5")
        XCTAssertEqual(firstReps.value as? String, "9")
        XCTAssertEqual(app.buttons["完成第 1 组"].firstMatch.value as? String, "未完成")
        let detail = app.buttons["RIR、动作资料与备注"].firstMatch
        reveal(detail, in: app)
        detail.tap()
        for number in 1...4 {
            XCTAssertTrue(app.buttons["rir-预填测试推胸-\(number)"].label.contains("RIR，未记录"))
        }
        let restore = app.buttons["恢复计划默认值"].firstMatch
        reveal(restore, in: app)
        restore.tap()
        XCTAssertEqual(firstWeight.value as? String, "25")
        XCTAssertEqual(firstReps.value as? String, "8")
        let complete = app.buttons["完成第 1 组"].firstMatch
        reveal(complete, in: app)
        complete.tap()
        XCTAssertTrue(app.buttons["第 1 组已完成"].exists)
        for number in 2...4 {
            XCTAssertEqual(app.buttons["完成第 \(number) 组"].firstMatch.value as? String, "未完成")
        }
        XCTAssertFalse(app.staticTexts["训练完成-实际总结"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "daily-r2-prefill-edit-restore-user-completion"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testConfirmedNewActionIsExplicitInPreviewAndCanStartWithoutManualCatalogEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview", "--ui-testing-confirmed-plan-import",
                               "--ui-testing-confirmed-plan-new-catalog"]
        app.launch()
        openTrainingPlan(app)
        let load = app.buttons["已确认计划-导入"]
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        load.tap()
        let explanation = app.staticTexts["已确认计划-新增动作说明"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertTrue(explanation.label.contains("新增 1 个动作"))
        XCTAssertTrue(app.staticTexts["测试MTS下斜推胸机 · kg · 胸部"].exists)
        let confirm = app.buttons["已确认计划-确认导入"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["已确认计划-结果"].waitForExistence(timeout: 5))
        let firstDay = app.buttons["已确认计划-查看首日"]
        reveal(firstDay, in: app)
        firstDay.tap()
        assertSourceDayMenu(app)
        let start = app.buttons["日期菜单-开始力量"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let weight = app.textFields["actual-weight-测试MTS器械下斜推胸-1"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertTrue(["", "重量"].contains(weight.value as? String ?? ""))
        XCTAssertEqual(app.buttons["完成第 1 组"].firstMatch.value as? String, "未完成")
    }

    func testConfirmedPlanCanBeReviewedImportedAndStartedWithHistoryDefaultsAndPerSetTargets() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview", "--ui-testing-confirmed-plan-import"]
        app.launch()
        openTrainingPlan(app)
        let load = app.buttons["已确认计划-导入"]
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        load.tap()
        XCTAssertTrue(app.staticTexts["IMPORT-UI-R1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "顶组 · 8–10")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "回退组 · 10–12")).firstMatch.exists)
        let confirm = app.buttons["已确认计划-确认导入"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["已确认计划-结果"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已确认计划-结果"].label.contains("1 项日程"))
        load.tap()
        XCTAssertTrue(app.navigationBars["确认加入日程"].waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "核验已导入计划")
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(app.navigationBars["训练编排"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已确认计划-结果"].label.contains("新增 0 项日程"))
        let firstDay = app.buttons["已确认计划-查看首日"]
        reveal(firstDay, in: app)
        firstDay.tap()
        assertSourceDayMenu(app)
        let start = app.buttons["日期菜单-开始力量"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.scrollViews["active-workout-scroll"].waitForExistence(timeout: 5))
        for number in 1...2 {
            let weight = app.textFields["actual-weight-测试推胸-\(number)"]
            XCTAssertTrue(weight.exists)
            XCTAssertEqual(weight.value as? String, "25", "匹配历史实际优先，原计划目标仍保留")
            XCTAssertEqual(app.buttons["完成第 \(number) 组"].firstMatch.value as? String, "未完成")
            XCTAssertEqual(app.buttons["rir-测试推胸-\(number)"].value as? String, "—")
        }
        XCTAssertFalse(app.textFields["actual-reps-测试推胸-3"].exists, "历史四组不得扩成本次四组")
        XCTAssertEqual(app.textFields["actual-reps-测试推胸-1"].value as? String, "12")
        XCTAssertEqual(app.textFields["actual-reps-测试推胸-2"].value as? String, "12")
        let firstTarget = app.descendants(matching: .any).matching(identifier: "训练目标-测试推胸-1").firstMatch
        let secondTarget = app.descendants(matching: .any).matching(identifier: "训练目标-测试推胸-2").firstMatch
        XCTAssertTrue(firstTarget.label.contains("8–10") && firstTarget.label.contains("RIR 3"))
        XCTAssertTrue(secondTarget.label.contains("10–12") && secondTarget.label.contains("RIR 2–3"))
        XCTAssertFalse(app.staticTexts["训练完成-实际总结"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "confirmed-plan-history-defaults-and-original-top-backoff"
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testNewWorkoutPrefillsHistoricalDraftAndRestoresOriginalPlanWithoutCompleting() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-history-prefill"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        XCTAssertTrue(app.textFields["actual-weight-杠铃卧推-1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["历史预填，非本次负重建议 · 可修改"].exists,
            "已确认说明全部默认收纳，不在动作表上方重复展示")

        // Four completed historical sets must not expand today's three-set plan.
        XCTAssertEqual(app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "actual-weight-杠铃卧推-")
        ).count, 3)
        for number in 1...3 {
            XCTAssertEqual(app.textFields["actual-weight-杠铃卧推-\(number)"].value as? String, "25")
            XCTAssertEqual(app.textFields["actual-reps-杠铃卧推-\(number)"].value as? String, "12")
            XCTAssertEqual(app.buttons["完成第 \(number) 组"].firstMatch.value as? String, "未完成")
        }
        XCTAssertFalse(app.buttons["第 1 组已完成"].exists)

        let detail = app.buttons["RIR、动作资料与备注"].firstMatch
        reveal(detail, in: app)
        detail.tap()
        XCTAssertTrue(app.staticTexts["历史预填，非本次负重建议 · 可修改"].waitForExistence(timeout: 5))
        let side = app.descendants(matching: .any)["active-measurement-side-杠铃卧推"]
        XCTAssertTrue(side.buttons["双边"].isSelected)
        for number in 1...3 {
            let rir = app.buttons["rir-杠铃卧推-\(number)"]
            XCTAssertTrue(rir.label.contains("RIR，未记录"),
                "历史RIR不能复制为本次实际；当前无障碍名称：\(rir.label)")
        }
        let restore = app.buttons["恢复计划默认值"].firstMatch
        for _ in 0..<6 {
            if restore.isHittable { break }
            // Restore now lives below the group table inside expanded notes.
            app.scrollViews["active-workout-scroll"].swipeUp()
        }
        XCTAssertTrue(restore.isHittable)
        restore.tap()
        XCTAssertTrue(app.staticTexts["实际记录与原计划分别保留"].waitForExistence(timeout: 5))
        for number in 1...3 {
            XCTAssertEqual(app.textFields["actual-weight-杠铃卧推-\(number)"].value as? String, "40")
            XCTAssertEqual(app.textFields["actual-reps-杠铃卧推-\(number)"].value as? String, "8")
            XCTAssertEqual(app.buttons["完成第 \(number) 组"].firstMatch.value as? String, "未完成")
        }
        XCTAssertFalse(app.buttons["关闭训练完成反馈"].exists)
    }

    func testSeatedDipBilingualSearchUsesCanonicalActionAndCannotRestoreMergedDuplicate() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-seated-dip"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let addExercise = app.xfitWorkoutAction("临时加动作")
        XCTAssertTrue(addExercise.waitForExistence(timeout: 10))
        addExercise.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("seated dip")

        let pickerOptions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "exercise-picker-option-"))
        let standard = pickerOptions.matching(NSPredicate(
            format: "label BEGINSWITH %@", "坐姿器械臂屈伸"
        ))
        XCTAssertTrue(standard.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(standard.count, 1)
        let standardLabel = standard.firstMatch.label
        XCTAssertTrue(standardLabel.contains("Seated Dip"), standardLabel)
        XCTAssertTrue(standardLabel.contains("肱三头肌") && standardLabel.contains("胸部"), standardLabel)
        XCTAssertFalse(standardLabel.contains("Shoulder Press Machine") || standardLabel.contains("Unverified"), standardLabel)
        let merged = pickerOptions.matching(NSPredicate(format: "label BEGINSWITH %@", "seated dip")).firstMatch
        XCTAssertTrue(merged.waitForExistence(timeout: 5))
        XCTAssertTrue(merged.label.contains("已合并") && merged.label.contains("使用主动作"), merged.label)
        XCTAssertFalse(merged.label.contains("恢复"), "合并条目不能普通恢复成重复动作：\(merged.label)")

        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "seated dip".count))
        search.typeText("坐姿器械臂屈伸")
        XCTAssertTrue(standard.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(standard.count, 1)
        XCTAssertTrue(merged.waitForExistence(timeout: 5))
        let hideKeyboard = app.buttons["动作搜索-收起键盘"]
        if hideKeyboard.exists { hideKeyboard.tap() }
        merged.tap()
        XCTAssertTrue(app.navigationBars["本次设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["坐姿器械臂屈伸"].exists,
            "合并源应打开标准动作的设置，而不是恢复源UUID")
        let setCount = app.steppers.matching(NSPredicate(format: "label BEGINSWITH %@", "组数：")).firstMatch
        XCTAssertTrue(setCount.waitForExistence(timeout: 5))
        guard let configuredSetCount = Int(setCount.label.replacingOccurrences(of: "组数：", with: "")),
              (1...12).contains(configuredSetCount) else {
            return XCTFail("本次设置必须显示真实配置的组数：\(setCount.label)")
        }
        app.buttons["使用上次设置"].tap()
        let addedTitle = app.staticTexts["展开动作标题-坐姿器械臂屈伸"]
        reveal(addedTitle, in: app)
        XCTAssertEqual(app.textFields.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "actual-reps-坐姿器械臂屈伸-"
        )).count, configuredSetCount, "使用上次设置须按刚确认的组数添加一次，不受旧默认3组影响")
        for number in 1...configuredSetCount {
            XCTAssertTrue(app.textFields["actual-reps-坐姿器械臂屈伸-\(number)"].exists)
        }
        XCTAssertFalse(app.textFields["actual-reps-坐姿器械臂屈伸-\(configuredSetCount + 1)"].exists)
        XCTAssertFalse(app.textFields["actual-reps-seated dip-1"].exists)

        let addAgain = app.xfitWorkoutAction("临时加动作")
        XCTAssertTrue(addAgain.waitForExistence(timeout: 5))
        addAgain.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("seated dip")
        XCTAssertTrue(app.staticTexts["没有找到“seated dip”"].waitForExistence(timeout: 5))
        XCTAssertFalse(standard.firstMatch.exists)
        XCTAssertFalse(merged.exists,
            "标准动作已加入本次后，其合并源也须排除，不能再加一份重复训练")
    }

    func testFailedWorkoutSaveStaysVisibleAfterBackAndTabSwitchThenRetryPersistsWithoutCompleting() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("保存失败注入只在模拟器的独立 UI 测试存储执行，不触及手机数据")
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent", "--ui-testing-reset-store",
                               "--ui-testing-workout-save-failure"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        XCTAssertTrue(app.scrollViews["active-workout-scroll"].waitForExistence(timeout: 10))
        let banner = app.staticTexts["训练保存失败提示"]
        XCTAssertFalse(banner.exists, "Initial workout preparation must not trigger the test failure")

        let weight = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "actual-weight-")).firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        let weightID = weight.identifier
        weight.tap()
        let old = (weight.value as? String) ?? ""
        weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        weight.typeText("25.125")
        let done = app.buttons["完成"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["操作失败"].exists, "Save failure must remain non-modal when leaving")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["继续训练"].waitForExistence(timeout: 5))
        XCTAssertTrue(banner.exists, "The failure must outlive the workout view")
        app.xfitTabButtons["饮食"].tap()
        XCTAssertTrue(app.buttons["饮食-记录一餐"].waitForExistence(timeout: 5))
        XCTAssertTrue(banner.exists, "The failure must stay visible on another tab")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "workout-save-failure-after-back-and-tab"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["重试训练保存"].tap()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["训练完成-实际总结"].exists)
        XCTAssertFalse(app.buttons["关闭训练完成反馈"].exists)
        app.xfitTabButtons["训练"].tap()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(app.textFields[weightID].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields[weightID].value as? String, "25.125")
        XCTAssertTrue(app.buttons["完成第 1 组"].firstMatch.exists)

        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-persistent"]
        app.launch()
        XCTAssertTrue(resume.waitForExistence(timeout: 15))
        XCTAssertFalse(banner.exists)
        resume.tap()
        XCTAssertTrue(app.scrollViews["active-workout-scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields[weightID].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields[weightID].value as? String, "25.125", "Explicit retry must save the actual value across restart")
        XCTAssertTrue(app.buttons["完成第 1 组"].firstMatch.exists)
        XCTAssertFalse(app.buttons["关闭训练完成反馈"].exists)
    }

    func testFinishingPartialWorkoutShowsSavedActualSummaryAndCanCloseIt() {
        let app = XCUIApplication()
        finishOneWorkingSet(in: app)
        let summary = app.staticTexts["训练完成-实际总结"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.hasPrefix("1 个工作组"))
        XCTAssertTrue(app.staticTexts["本次训练已记录"].exists)
        let card = app.descendants(matching: .any)["训练完成-卡片"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 1))
        let close = app.buttons["关闭训练完成反馈"]
        XCTAssertTrue(close.isEnabled && close.isHittable)
        let done = app.buttons["训练完成-完成按钮"]
        XCTAssertTrue(done.isEnabled && done.isHittable)
        let closeFrame = close.frame
        let doneFrame = done.frame
        let summaryFrame = summary.frame
        XCTAssertGreaterThanOrEqual(closeFrame.width, 44)
        XCTAssertGreaterThanOrEqual(closeFrame.height, 44)
        XCTAssertGreaterThanOrEqual(doneFrame.height, 54)
        XCTAssertEqual(doneFrame.midX, app.frame.midX, accuracy: 2)
        XCTAssertEqual(summaryFrame.midX, app.frame.midX, accuracy: 2)
        XCTAssertGreaterThanOrEqual(doneFrame.minX, app.frame.minX + 20)
        XCTAssertLessThanOrEqual(doneFrame.maxX, app.frame.maxX - 20)
        XCTAssertLessThanOrEqual(abs(closeFrame.union(doneFrame).midY - app.frame.midY), app.frame.height * 0.05,
            "可见完成反馈应位于屏幕中央，不回到顶部横幅")
        XCTAssertFalse(app.buttons["主导航-饮食"].isHittable, "玻璃浮层期间不得误触底部导航")
        attachCompletion(app, name: "completion-centered-glass")
        close.tap()
        XCTAssertTrue(app.buttons["训练-日期菜单"].waitForExistence(timeout: 5))
        XCTAssertFalse(summary.exists)
        XCTAssertEqual(app.staticTexts["训练-当天状态"].label, "已记录 1/12 组",
            "提前结束不得让周历把只有一组实际记录显示为全部完成")
    }

    func testCompletionFireworksRecordingAndDoneReturnsToTraining() {
        let app = XCUIApplication()
        finishOneWorkingSet(in: app, arguments: ["--ui-testing-animations"])
        let summary = app.staticTexts["训练完成-实际总结"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        XCTAssertTrue(summary.label.hasPrefix("1 个工作组"))
        attachCompletion(app, name: "completion-fireworks-running")
        Thread.sleep(forTimeInterval: 2)
        let done = app.buttons["训练完成-完成按钮"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.buttons["训练-日期菜单"].waitForExistence(timeout: 5))
        XCTAssertFalse(summary.exists)
        XCTAssertEqual(app.staticTexts["训练-当天状态"].label, "已记录 1/12 组")
    }

    func testCompletionAtLargestTypeKeepsCloseAndDoneReachable() {
        let app = XCUIApplication()
        finishOneWorkingSet(in: app, arguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let summary = app.staticTexts["训练完成-实际总结"]
        XCTAssertTrue(summary.waitForExistence(timeout: 3))
        let close = app.buttons["关闭训练完成反馈"]
        XCTAssertTrue(close.isHittable)
        let done = app.buttons["训练完成-完成按钮"]
        let content = app.scrollViews["训练完成-内容滚动"]
        for _ in 0..<3 {
            if done.isHittable { break }
            XCTAssertTrue(content.exists, "大字号溢出时卡片内容必须可滚动")
            content.swipeUp()
        }
        XCTAssertTrue(done.isHittable)
        XCTAssertTrue(close.isHittable, "滚动卡片不能带走关闭入口")
        attachCompletion(app, name: "completion-largest-type")
        done.tap()
        XCTAssertTrue(app.buttons["训练-日期菜单"].waitForExistence(timeout: 5))
    }

    private func finishOneWorkingSet(in app: XCUIApplication, arguments: [String] = []) {
        app.launchArguments = ["--ui-testing"] + arguments
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        let completeSet = app.buttons["完成第 1 组"].firstMatch
        reveal(completeSet, in: app)
        completeSet.tap()
        XCTAssertTrue(app.buttons["第 1 组已完成"].firstMatch.waitForExistence(timeout: 5))
        let finish = app.buttons["完成本次训练"].firstMatch
        reveal(finish, in: app)
        finish.tap()
        let confirm = app.buttons["完成训练"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    private func attachCompletion(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertSourceDayMenu(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["训练菜单"].waitForExistence(timeout: 5))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertTrue(app.descendants(matching: .any)["日期菜单-" + formatter.string(from: Date())].exists)
    }

    private func openTrainingPlan(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["主导航-我的"].waitForExistence(timeout: 15))
        app.buttons["主导航-我的"].tap()
        let management = app.buttons["模板与动作"]
        reveal(management, in: app); management.tap()
        let plans = app.buttons["训练管理-训练编排导入"]
        XCTAssertTrue(plans.waitForExistence(timeout: 5))
        reveal(plans, in: app); plans.tap()
        XCTAssertTrue(app.navigationBars["训练编排"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["active-workout-scroll"].firstMatch
        for _ in 0..<10 {
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY + 60
            if element.exists && element.isHittable && element.frame.minY >= top + 8
                && element.frame.maxY < app.xfitTabBar.frame.minY - 8 { return }
            let needsDown = element.exists && element.frame.minY < top + 8
            if scroll.exists {
                let bottom = min(scroll.frame.maxY, app.xfitTabBar.frame.minY) - 8
                let middle = (max(scroll.frame.minY, top) + bottom) / 2
                let step = min(CGFloat(90), (bottom - top) * 0.2)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let from = origin.withOffset(CGVector(dx: scroll.frame.midX, dy: middle + (needsDown ? -step : step)))
                let to = origin.withOffset(CGVector(dx: scroll.frame.midX, dy: middle + (needsDown ? step : -step)))
                from.press(forDuration: 0.05, thenDragTo: to)
            } else if needsDown { app.swipeDown() }
            else { app.swipeUp() }
        }
        let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY + 60
        XCTAssertTrue(element.isHittable && element.frame.minY >= top + 8
            && element.frame.maxY < app.xfitTabBar.frame.minY - 8)
    }

    func testForegroundHomeReturnsToTodayWithoutEndingAnUnfinishedWorkout() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        start.tap()
        XCTAssertTrue(app.scrollViews["active-workout-scroll"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        let resume = app.buttons["继续训练"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练日期-"))
        guard let today = days.allElementsBoundByIndex.first(where: { $0.isSelected }),
              let otherDay = days.allElementsBoundByIndex.first(where: { !$0.isSelected }) else {
            return XCTFail("周历必须提供当前日期和可选择的其他日期")
        }
        let todayID = today.identifier
        let chosenID = otherDay.identifier
        otherDay.tap()
        XCTAssertTrue(otherDay.isSelected)
        XCTAssertEqual(days.allElementsBoundByIndex.first(where: { $0.isSelected })?.identifier, chosenID)

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        let isToday = NSPredicate(format: "isSelected == true")
        expectation(for: isToday, evaluatedWith: today)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(days.allElementsBoundByIndex.first(where: { $0.isSelected })?.identifier, todayID)
        XCTAssertFalse(app.buttons["关闭训练完成反馈"].exists)
        resume.tap()
        XCTAssertTrue(app.scrollViews["active-workout-scroll"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["完成第 1 组"].firstMatch.exists,
            "回前台只刷新首页日期，不结束训练或标记实际组完成")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        otherDay.tap()
        XCTAssertTrue(otherDay.isSelected)
        XCTAssertEqual(days.allElementsBoundByIndex.first(where: { $0.isSelected })?.identifier, chosenID)
        app.buttons["训练日程"].tap()
        XCTAssertTrue(app.navigationBars["训练日程"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["训练日程"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        expectation(for: isToday, evaluatedWith: today)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(days.allElementsBoundByIndex.first(where: { $0.isSelected })?.identifier, todayID,
            "排期页面回前台也须回到今天，不能被库里的未结束训练阻断")
    }

    func testTodayButtonAndScheduleReturnPreserveChosenDayUntilExplicitToday() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview"]
        app.launch()
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练日期-"))
        XCTAssertTrue(days.firstMatch.waitForExistence(timeout: 15))
        guard let originalDay = days.allElementsBoundByIndex.first(where: { $0.isSelected }),
              let otherDay = days.allElementsBoundByIndex.first(where: { !$0.isSelected }) else {
            return XCTFail("周历必须提供可选择的其他日期")
        }
        otherDay.tap()
        XCTAssertTrue(otherDay.isSelected)
        app.buttons["训练日程"].tap()
        XCTAssertTrue(app.navigationBars["训练日程"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["日程-回到今天"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(otherDay.isSelected, "从日程返回不能重置用户选中的历史日期")
        app.buttons["训练-回到今天"].tap()
        XCTAssertTrue(originalDay.isSelected)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "training-fixture-local-today-and-shared-date"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
