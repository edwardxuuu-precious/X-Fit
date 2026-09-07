import XCTest

final class RedesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["训练"].waitForExistence(timeout: 15))
        return app
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 {
            if item.exists && item.isHittable && item.frame.minY < app.frame.height - 100 { return }
            app.swipeUp()
        }
        XCTAssertTrue(item.isHittable)
    }
    func testRecipeIngredientsStepsAndReferencePortions() {
        let app = launch()
        app.tabBars.buttons["饮食"].tap()
        let prep = app.buttons["饮食-明日备餐"]
        reveal(prep, app); prep.tap()
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
        app.tabBars.buttons["我的"].tap()
        capture("20-profile", app)
        let backup = app.buttons["我的-备份与恢复"]
        reveal(backup, app); backup.tap()
        let generate = app.buttons["设置-生成备份"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        XCTAssertTrue(generate.isHittable, "备份入口必须直接到数据页")
        capture("21-backup", app)
        generate.tap()
        XCTAssertTrue(app.buttons["分享最新备份"].waitForExistence(timeout: 5))
        app.buttons["设置-偏好"].tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label CONTAINS %@", "训练日提醒")).firstMatch.waitForExistence(timeout: 5))
        capture("22-preferences", app)
        app.buttons["设置-数据"].tap()
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["设置-导入备份"].exists)
    }
    func testReviewDraftSaveAndHistoricalReadback() {
        let app = launch()
        app.tabBars.buttons["目标"].tap()
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
        app.tabBars.buttons["我的"].tap()
        let backup = app.buttons["我的-备份与恢复"]
        reveal(backup, app); backup.tap()
        let generate = app.buttons["设置-生成备份"]
        reveal(generate, app)
        XCTAssertGreaterThanOrEqual(generate.frame.height, 44)
        capture("23-large-backup", app)
        app.tabBars.buttons["目标"].tap()
        let review = app.buttons["减脂每周复盘"]
        reveal(review, app); review.tap()
        XCTAssertTrue(app.buttons["复盘-底部保存"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["复盘-底部保存"].isHittable)
        capture("24-large-review", app)
        app.tabBars.buttons["饮食"].tap()
        let prep = app.buttons["饮食-明日备餐"]
        reveal(prep, app); prep.tap()
        let lunch = app.buttons["备餐-食谱-午餐"]
        reveal(lunch, app); lunch.tap()
        let toggle = app.buttons["食谱-切换内容"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertTrue(toggle.isHittable)
        toggle.tap()
        let step = app.descendants(matching: .any)["食谱-步骤-1"].firstMatch
        reveal(step, app)
        capture("25-large-recipe", app)
    }
    func testCoreTrainingAndResume() {
        let app = launch()
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        let start = app.buttons["开始记录训练"]
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
        app.tabBars.buttons["饮食"].tap()
        app.tabBars.buttons["训练"].tap()
        XCTAssertTrue(app.buttons["第 1 组已完成"].firstMatch.exists)
    }
    func testCoreMuscleSelection() {
        let app = launch()
        app.buttons["开始记录训练"].tap()
        let add = app.buttons["临时加动作"]
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
        app.tabBars.buttons["饮食"].tap()
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
        XCTAssertTrue(app.staticTexts["个人份量待确认"].exists)
        capture("06c-portion-info", app)
        app.buttons["关闭"].tap()
        app.buttons["备餐-菜单页"].tap()
        XCTAssertTrue(app.staticTexts["备餐-份数摘要"].exists)
    }
    func testCoreGoalReviewAndMuscles() {
        let app = launch()
        app.tabBars.buttons["目标"].tap()
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
        app.tabBars.buttons["训练"].tap()
        let library = app.buttons["训练计划与动作库"]
        reveal(library, app); library.tap()
        // Exercise selection is checked independently through a new day plan.
    }
    func testCycleImportAndExportRemainReachable() {
        let app = launch()
        let training = app.buttons["训练-减脂计划导入"]
        reveal(training, app); training.tap()
        XCTAssertTrue(app.navigationBars["全身训练计划"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        let export = app.buttons["导出减脂周期"]
        reveal(export, app); export.tap()
        let generate = app.buttons["生成周期 CSV"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5)); generate.tap()
        XCTAssertTrue(app.buttons["保存或分享 CSV"].waitForExistence(timeout: 5))
        capture("11-cycle-export", app)
    }
    func testLargeTypePrimaryActionsRemainReachable() {
        let app = launch(large: true)
        let start = app.buttons["开始记录训练"]
        reveal(start, app)
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        capture("09-large-type-training", app)
        app.tabBars.buttons["饮食"].tap()
        let edit = app.buttons["饮食-调整实吃-早餐"]
        reveal(edit, app); edit.tap()
        XCTAssertTrue(app.buttons["保存计划实吃"].waitForExistence(timeout: 5))
        capture("10-large-type-meal", app)
    }
    func testLargeTypeTrainingDistributionCanScrollToExplanation() {
        let app = launch(large: true)
        app.tabBars.buttons["目标"].tap()
        let distribution = app.buttons["目标-训练分布"]
        reveal(distribution, app); distribution.tap()
        let explanation = app.staticTexts["仅计已完成工作组；复合动作可计入多个肌群。灰色表示没有相应记录，不表示恢复状态。"]
        reveal(explanation, app)
        XCTAssertTrue(explanation.isHittable)
        capture("12-large-type-distribution", app)
    }

    func testLargeTypeCurrentProgressAndPrepRemainReachable() {
        let app = launch(large: true)
        app.tabBars.buttons["目标"].tap()
        let record = app.buttons["目标-记录体重"]
        reveal(record, app)
        XCTAssertGreaterThanOrEqual(record.frame.height, 44)
        capture("13-large-type-progress", app)
        app.tabBars.buttons["饮食"].tap()
        let prep = app.buttons["饮食-明日备餐"]
        reveal(prep, app); prep.tap()
        XCTAssertTrue(app.navigationBars["明日备餐"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["备餐-分享"].isHittable)
        XCTAssertGreaterThan(app.staticTexts["餐盒计划"].frame.height, 50, "必须实际启用辅助功能大字体，不能仅传入无效参数")
        capture("14-large-type-prep", app)
        app.buttons["备餐-采购页"].tap()
        let pantry = app.staticTexts["家中常备 · 核对库存"]
        reveal(pantry, app)
        XCTAssertTrue(pantry.isHittable)
        app.swipeUp()
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
            XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 10))
            app.tabBars.buttons["我的"].tap()
            let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "身体数据")).firstMatch
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
