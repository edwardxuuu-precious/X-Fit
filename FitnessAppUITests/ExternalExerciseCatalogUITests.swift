import XCTest

/// Uses the normal template editor and its exercise picker against the isolated UI-test store.
final class ExternalExerciseCatalogUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testReviewedPulldownShowsSpecificConflictAndKeepsOriginalSourceSteps() {
        let app = launchTemplateEditor()
        openPicker(in: app)
        openExternalCatalog(in: app)
        replaceSearch(with: "0818", in: app)
        let action = app.buttons["扩展动作-0818"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        XCTAssertTrue(app.staticTexts["扩展动作中文名"].waitForExistence(timeout: 5))
        let reviewHeading = app.staticTexts["变式待核对"]
        reveal(reviewHeading, in: app)
        XCTAssertTrue(reviewHeading.exists)
        let conflict = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "对握", "正握")).firstMatch
        XCTAssertFalse(conflict.exists, "长核对说明默认收起，避免占用详情首屏")
        let reviewDisclosure = app.buttons["扩展库核对说明"]
        XCTAssertTrue(reviewDisclosure.exists)
        capture("reviewed-pulldown-compact-default", in: app)
        reviewDisclosure.tap()
        reveal(conflict, in: app)
        XCTAssertTrue(conflict.exists, "复核后仍须显示该来源的握法冲突")
        reviewDisclosure.tap()
        XCTAssertFalse(conflict.exists, "核对后可以收起并回到紧凑布局")
        let chinese = app.buttons["中文参考步骤（上游）"]
        reveal(chinese, in: app)
        let originalChinese = app.staticTexts["1. 调整座椅高度并将自己面向电缆机。"]
        XCTAssertFalse(originalChinese.exists, "中文长步骤默认收起")
        chinese.tap()
        reveal(originalChinese, in: app)
        XCTAssertTrue(originalChinese.exists, "展开后原中文参考完整可读")
        chinese.tap()
        XCTAssertFalse(originalChinese.exists)
        let instructions = app.buttons["English instructions"]
        reveal(instructions, in: app)
        instructions.tap()
        let original = app.staticTexts["2. Grasp the handles with an overhand grip, hands shoulder-width apart."]
        reveal(original, in: app)
        XCTAssertTrue(original.exists, "原始英文不能被本地猜测重写")
        capture("reviewed-pulldown-retains-conflict-and-source", in: app)
    }

    func testUnresolvedAddKeepsReviewCompactAndUnitRequired() {
        let app = launchTemplateEditor()
        openPicker(in: app)
        openExternalCatalog(in: app)
        replaceSearch(with: "0818", in: app)
        app.buttons["扩展动作-0818"].tap()
        let add = app.buttons["扩展库加入个人动作"]
        reveal(add, in: app)
        XCTAssertTrue(add.exists)
        add.tap()
        let save = app.buttons["扩展库保存并使用"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        let conflict = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "对握", "正握")).firstMatch
        XCTAssertFalse(conflict.exists)
        let review = app.buttons["扩展库核对说明"]
        reveal(review, in: app)
        capture("unresolved-add-compact-default", in: app)
        review.tap()
        reveal(conflict, in: app)
        XCTAssertTrue(conflict.exists)
        XCTAssertFalse(save.isEnabled, "展开说明不代替选择计量单位")
        review.tap()
        XCTAssertFalse(conflict.exists)
    }

    func testFullCatalogSupportsBilingualSearchEquipmentFilterAndSourceLicense() {
        let app = launchTemplateEditor()
        openPicker(in: app)
        openExternalCatalog(in: app)

        let count = app.staticTexts["扩展库结果数量"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(normalizedCount(count.label), "1324 / 1324 个动作")
        capture("external-catalog-full-library", in: app)

        replaceSearch(with: "史密斯卧推", in: app)
        let smithBench = app.buttons["扩展动作-0748"]
        XCTAssertTrue(smithBench.waitForExistence(timeout: 5))
        replaceSearch(with: "Smith bench", in: app)
        XCTAssertTrue(smithBench.waitForExistence(timeout: 5), "英文搜索也应找到同一来源动作")
        capture("external-catalog-bilingual-smith-search", in: app)

        replaceSearch(with: "", in: app)
        let equipment = app.buttons["扩展库器械筛选"]
        revealAtTop(equipment, in: app)
        equipment.tap()
        let smithEquipment = app.buttons["史密斯机"]
        XCTAssertTrue(smithEquipment.waitForExistence(timeout: 5))
        smithEquipment.tap()
        XCTAssertEqual(normalizedCount(count.label), "48 / 1324 个动作")
        replaceSearch(with: "goblet", in: app)
        XCTAssertEqual(normalizedCount(count.label), "0 / 1324 个动作",
            "器械筛选必须约束搜索结果，不能仅改变筛选按钮的文字")

        replaceSearch(with: "Smith bench", in: app)
        reveal(smithBench, in: app)
        smithBench.tap()
        XCTAssertTrue(app.staticTexts["扩展动作中文名"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["扩展动作中文名"].label, "史密斯卧推")
        XCTAssertTrue(app.staticTexts["smith bench press"].exists)
        let chineseSteps = app.buttons["中文参考步骤（上游）"]
        reveal(chineseSteps, in: app)
        let englishSteps = app.buttons["English instructions"]
        reveal(englishSteps, in: app)
        englishSteps.tap()
        let firstEnglishStep = app.staticTexts["1. Adjust the height of the smith machine bar to chest level."]
        reveal(firstEnglishStep, in: app)
        XCTAssertTrue(firstEnglishStep.exists)
        let source = app.staticTexts["Exercises Dataset · MIT · 来源 ID 0748"]
        reveal(source, in: app)
        XCTAssertTrue(source.exists)
        capture("external-catalog-reference-steps-and-source", in: app)

        app.navigationBars["动作详情"].buttons["BackButton"].tap()
        finishCatalogSearch(in: app)
        let license = app.buttons["扩展库来源许可"]
        XCTAssertTrue(license.waitForExistence(timeout: 5))
        license.tap()
        XCTAssertTrue(app.navigationBars["来源与许可"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Exercises Dataset"].exists)
        let mit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "MIT License")).firstMatch
        XCTAssertTrue(mit.waitForExistence(timeout: 5))
        let pinnedVersion = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "版本 7455efae")).firstMatch
        XCTAssertTrue(pinnedVersion.exists)
        capture("external-catalog-mit-license-and-fixed-version", in: app)
        app.navigationBars["来源与许可"].buttons["完成"].tap()
        XCTAssertTrue(app.navigationBars["扩展动作库"].waitForExistence(timeout: 5))
    }

    func testExistingBenchIsReusedAndReturnsToOriginalTemplate() {
        let app = launchTemplateEditor()
        openPicker(in: app)
        openExternalCatalog(in: app)
        replaceSearch(with: "0025", in: app)
        let bench = app.buttons["扩展动作-0025"]
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()
        let reuse = app.buttons["扩展库复用-杠铃卧推"]
        XCTAssertTrue(reuse.waitForExistence(timeout: 5), "默认 fixture 已有杠铃卧推，应提供复用入口")
        reveal(reuse, in: app)
        reuse.tap()

        XCTAssertTrue(app.navigationBars["新建专项模板"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "杠铃卧推")).count, 1)
        XCTAssertTrue(app.staticTexts["胸部 · 杠铃 · kg"].exists,
            "复用应沿用个人动作器械和单位")
        capture("external-catalog-reused-existing-bench-in-template", in: app)

        openPicker(in: app)
        openExternalCatalog(in: app)
        replaceSearch(with: "0025", in: app)
        app.buttons["扩展动作-0025"].tap()
        XCTAssertTrue(app.staticTexts["扩展动作中文名"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["扩展库复用-杠铃卧推"].exists,
            "已经加入当前模板的动作不能再次提供可选的复用按钮")
    }

    func testNewActionRequiresUnitAndRepeatedChoiceReusesOnePersonalAction() {
        let app = launchTemplateEditor()
        openPicker(in: app)
        replaceSearch(with: "壶铃高脚杯", in: app)
        XCTAssertEqual(personalGobletButtons(in: app).count, 0,
            "此用例使用默认 seed 中尚不存在的来源动作 0534")
        openExternalCatalog(in: app)
        replaceSearch(with: "0534", in: app)
        let goblet = app.buttons["扩展动作-0534"]
        XCTAssertTrue(goblet.waitForExistence(timeout: 5))
        goblet.tap()
        let addPersonal = app.buttons["扩展库加入个人动作"]
        XCTAssertTrue(addPersonal.waitForExistence(timeout: 5))
        reveal(addPersonal, in: app)
        addPersonal.tap()
        let save = app.buttons["扩展库保存并使用"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["扩展库新动作名称"].value as? String, "壶铃高脚杯深蹲")
        XCTAssertFalse(save.isEnabled, "没有明确选择单位时不得保存")
        capture("external-catalog-unit-required-before-save", in: app)

        app.buttons["扩展库单位选择"].tap()
        let kilogram = app.buttons["kg（重量 × 次数）"]
        XCTAssertTrue(kilogram.waitForExistence(timeout: 5))
        kilogram.tap()
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.navigationBars["新建专项模板"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["壶铃高脚杯深蹲"].exists)
        capture("external-catalog-added-action-returned-to-template", in: app)

        openPicker(in: app)
        openExternalCatalog(in: app)
        replaceSearch(with: "0534", in: app)
        app.buttons["扩展动作-0534"].tap()
        XCTAssertTrue(app.staticTexts["此来源动作已加入个人库。"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["此动作已在本次选择中。"].exists)
        XCTAssertFalse(app.buttons["扩展库加入个人动作"].exists)
        XCTAssertFalse(app.buttons["扩展库复用-壶铃高脚杯深蹲"].exists)
        capture("external-catalog-already-selected-prevents-duplicate", in: app)

        returnToPersonalPicker(in: app)
        app.navigationBars["添加模板动作"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["新建专项模板"].waitForExistence(timeout: 5))
        app.navigationBars["新建专项模板"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["专项模板"].waitForExistence(timeout: 5))
        app.buttons["新建专项模板"].tap()
        openPicker(in: app)
        replaceSearch(with: "壶铃高脚杯", in: app)
        XCTAssertEqual(personalGobletButtons(in: app).count, 1,
            "取消模板草稿后，显式保存的个人动作仍应只有一条")
        openExternalCatalog(in: app)
        replaceSearch(with: "0534", in: app)
        app.buttons["扩展动作-0534"].tap()
        let reuse = app.buttons["扩展库复用-壶铃高脚杯深蹲"]
        XCTAssertTrue(reuse.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["扩展库加入个人动作"].exists)
        reveal(reuse, in: app)
        reuse.tap()
        XCTAssertTrue(app.navigationBars["新建专项模板"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "壶铃高脚杯深蹲")).count, 1)
        capture("external-catalog-repeated-choice-reuses-personal-action", in: app)
    }

    private func launchTemplateEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview"]
        app.launch()
        let mine = app.buttons["主导航-我的"]
        XCTAssertTrue(mine.waitForExistence(timeout: 15))
        mine.tap()
        app.buttons["模板与动作"].tap()
        app.buttons["专项模板入口"].tap()
        app.buttons["新建专项模板"].tap()
        XCTAssertTrue(app.navigationBars["新建专项模板"].waitForExistence(timeout: 5))
        return app
    }

    private func openPicker(in app: XCUIApplication) {
        let addAction = app.buttons["模板添加动作"]
        XCTAssertTrue(addAction.waitForExistence(timeout: 5))
        reveal(addAction, in: app)
        addAction.tap()
        XCTAssertTrue(app.navigationBars["添加模板动作"].waitForExistence(timeout: 5))
    }

    private func openExternalCatalog(in app: XCUIApplication) {
        let external = app.buttons["打开扩展动作库"]
        reveal(external, in: app)
        external.tap()
        XCTAssertTrue(app.navigationBars["扩展动作库"].waitForExistence(timeout: 5))
    }

    private func returnToPersonalPicker(in app: XCUIApplication) {
        app.navigationBars["动作详情"].buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["扩展动作库"].waitForExistence(timeout: 5))
        finishCatalogSearch(in: app)
        let bar = app.navigationBars["扩展动作库"]
        let back = bar.buttons["BackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
        XCTAssertTrue(app.navigationBars["添加模板动作"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func finishCatalogSearch(in app: XCUIApplication) {
        // iOS 27 restores the active search bar on returning from a result. Its
        // observed Close control temporarily replaces Back and the source toolbar.
        let bar = app.navigationBars["扩展动作库"]
        for title in ["Close", "关闭"] {
            let close = bar.buttons[title]
            if close.exists && close.isHittable { close.tap(); return }
        }
    }

    private func replaceSearch(with query: String, in app: XCUIApplication) {
        let search = app.searchFields.firstMatch
        // Search belongs to the list's top. Scroll toward that known location rather
        // than guessing that an off-screen search field is below the current rows.
        for _ in 0..<8 {
            if search.exists && search.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(search.exists && search.isHittable)
        search.tap()
        if let current = search.value as? String, current != search.placeholderValue, !current.isEmpty {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        search.typeText(query + "\n")
        if app.keyboards.firstMatch.exists { app.swipeUp() }
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
            object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed,
            "搜索后应通过系统搜索键或列表滚动收起键盘")
    }

    private func personalGobletButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "壶铃高脚杯深蹲"))
    }

    private func normalizedCount(_ label: String) -> String {
        label.replacingOccurrences(of: ",", with: "")
    }

    private func revealAtTop(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(element.exists && element.isHittable, "顶部筛选栏应能通过向下滚动到达")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            let top = app.navigationBars.firstMatch.frame.maxY
            if element.exists && element.frame.minY < top { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "应能通过真实列表滚动到达目标：\(element)")
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
