import XCTest

final class WorkoutExerciseOrderUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testExerciseExplanationKeepsUnfinishedWorkoutInput() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let weight = app.textFields["actual-weight-杠铃卧推-1"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8)); weight.tap()
        weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 16) + "27.5")
        let explanation = app.buttons["动作说明-杠铃卧推"]
        reveal(explanation, in: app); XCTAssertTrue(explanation.exists); explanation.tap()
        XCTAssertTrue(app.navigationBars["动作说明"].waitForExistence(timeout: 5))
        let candidate = app.buttons["动作说明候选-0025"]
        reveal(candidate, in: app); XCTAssertTrue(candidate.exists); candidate.tap()
        XCTAssertTrue(app.staticTexts["动作说明中文名"].waitForExistence(timeout: 5))
        let play = app.buttons["播放动作演示"]
        reveal(play, in: app); XCTAssertTrue(play.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Goulart")).firstMatch.exists)
        play.tap()
        let ready = app.staticTexts["动作演示已就绪"]
        let unavailable = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "视频暂时无法播放")).firstMatch
        let playbackResult = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: ready)
        if XCTWaiter.wait(for: [playbackResult], timeout: 22) != .completed {
            XCTAssertTrue(unavailable.exists, "网络不可用时应显示文字保底及重试，而不是一直空白")
        }
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertTrue((weight.value as? String ?? "").contains("27.5"))
        XCTAssertFalse(app.buttons["第 1 组已完成"].exists)
    }

    func testInstructionsAreCollapsedAndFullOriginalIsReachableAtLargestType() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-long-exercise-notes",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        XCTAssertTrue(app.textFields["actual-weight-杠铃卧推-1"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["训练口径-杠铃卧推"].exists)
        XCTAssertFalse(app.staticTexts["训练条件-杠铃卧推"].exists)
        XCTAssertFalse(app.staticTexts["训练说明全文-杠铃卧推"].exists)
        let detail = app.buttons["RIR、动作资料与备注"].firstMatch
        reveal(detail, in: app); detail.tap()
        let original = app.staticTexts["训练说明全文-杠铃卧推"]
        reveal(original, in: app)
        XCTAssertTrue(original.label.contains("最后一条：左肘疼痛逐组增加时停止该动作"))
        XCTAssertTrue(app.staticTexts["训练口径-杠铃卧推"].exists)
    }

    func testArrowSortingPersistsAndKeepsCompletedActualAndExpandedExercise() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let weight = app.textFields["actual-weight-杠铃卧推-1"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8)); weight.tap()
        weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 16) + "27.5")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["完成第 1 组"].firstMatch.tap()
        let completed = app.buttons["第 1 组已完成"].firstMatch
        XCTAssertTrue(completed.label.contains("27.5"))
        app.xfitWorkoutAction("调整今日菜单").tap()
        let position = app.staticTexts["排序位置-杠铃卧推"]
        XCTAssertTrue(position.waitForExistence(timeout: 5)); XCTAssertEqual(position.label, "第 1 个动作")
        let down = app.buttons["下移动作-杠铃卧推"]
        XCTAssertTrue(down.isEnabled); down.tap()
        XCTAssertEqual(position.label, "第 2 个动作")
        app.buttons["完成动作排序"].tap()
        XCTAssertTrue(app.staticTexts["展开动作标题-杠铃卧推"].waitForExistence(timeout: 5))
        XCTAssertTrue(completed.label.contains("27.5"))
        app.xfitWorkoutAction("调整今日菜单").tap()
        XCTAssertTrue(position.waitForExistence(timeout: 5)); XCTAssertEqual(position.label, "第 2 个动作")
        app.buttons["上移动作-杠铃卧推"].tap()
        XCTAssertEqual(position.label, "第 1 个动作")
        app.buttons["完成动作排序"].tap()
        XCTAssertTrue(completed.label.contains("27.5"))
    }

    func testNativeDragChangesOnlyCurrentExerciseOrder() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        XCTAssertTrue(app.xfitWorkoutAction("调整今日菜单").waitForExistence(timeout: 8)); app.xfitWorkoutAction("调整今日菜单").tap()
        let position = app.staticTexts["排序位置-杠铃卧推"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        XCTAssertEqual(position.label, "第 1 个动作")
        // Section headers are cells too. Target the real exercise row and UIKit's
        // reorder handle; dragging the header instead dismisses the sheet.
        let first = app.cells.containing(.staticText, identifier: "排序位置-杠铃卧推").firstMatch
        let second = app.cells.containing(.staticText, identifier: "排序位置-上斜哑铃卧推").firstMatch
        XCTAssertTrue(first.exists && second.exists)
        let handle = first.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS %@", "Reorder", "重新排序"
        )).firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5)); XCTAssertTrue(handle.isHittable)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: second.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)))
        XCTAssertTrue(app.navigationBars["动作顺序"].exists, "Native row dragging must keep the sorting sheet open")
        XCTAssertEqual(position.label, "第 2 个动作")
        app.buttons["完成动作排序"].tap()
        XCTAssertTrue(app.staticTexts["展开动作标题-杠铃卧推"].waitForExistence(timeout: 5))
    }

    func testSortingRestoresEditingFieldWithoutCompletingSet() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let start = app.buttons["开始训练"]
        XCTAssertTrue(start.waitForExistence(timeout: 15)); start.tap()
        let weight = app.textFields["actual-weight-杠铃卧推-1"]
        XCTAssertTrue(weight.waitForExistence(timeout: 8)); weight.tap()
        weight.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 16) + "27.5")
        app.xfitWorkoutAction("调整今日菜单").tap()
        let down = app.buttons["下移动作-杠铃卧推"]
        XCTAssertTrue(down.waitForExistence(timeout: 5)); down.tap()
        app.buttons["完成动作排序"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // Do not tap the field again: typing must resume the same input/selection.
        weight.typeText("5")
        XCTAssertEqual(weight.value as? String, "27.55")
        XCTAssertEqual(app.buttons["完成第 1 组"].firstMatch.value as? String, "未完成")
        XCTAssertTrue(app.staticTexts["展开动作标题-杠铃卧推"].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["active-workout-scroll"].firstMatch
        XCTAssertTrue(scroll.exists)
        for _ in 0..<12 {
            let top = max(scroll.frame.minY, app.navigationBars.firstMatch.frame.maxY) + 8
            let navigation = app.otherElements["主导航"]
            let bottom = min(scroll.frame.maxY, navigation.exists ? navigation.frame.minY : app.frame.maxY) - 8
            let visible = CGRect(x: scroll.frame.minX, y: top, width: scroll.frame.width, height: bottom - top)
            var needsDown = false
            if element.exists {
                let frame = element.frame
                // Long, noninteractive original text is read by scrolling to its
                // final line, not by asking XCTest to tap its offscreen center.
                let longText = frame.height > visible.height
                if longText {
                    let tail = CGRect(x: frame.minX, y: frame.maxY - 44, width: frame.width, height: 44)
                    if tail.intersection(visible).height >= 44 { return }
                    needsDown = tail.minY < top
                } else {
                    if element.isHittable && visible.contains(frame) { return }
                    needsDown = frame.minY < top
                }
            }
            let halfStep = min(CGFloat(90), visible.height * 0.2)
            let center = visible.midY
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX, dy: center + (needsDown ? -halfStep : halfStep)))
            let end = origin.withOffset(CGVector(dx: visible.midX, dy: center + (needsDown ? halfStep : -halfStep)))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "unreachable-workout-content"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail("训练内容未滚动到导航栏与底栏之间的可读区域：\(element)")
    }
}
