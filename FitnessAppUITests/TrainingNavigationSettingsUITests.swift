import XCTest

final class TrainingNavigationSettingsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFiveDestinationsIncludeDedicatedToolsAndOneSettingsEntry() {
        let app = launch()
        let titles = ["训练", "饮食", "进展", "工具", "我的"]
        XCTAssertEqual(app.xfitTabButtons.count, titles.count)
        for title in titles {
            let tab = app.buttons["主导航-" + title]
            XCTAssertTrue(tab.exists)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
        }
        XCTAssertTrue(app.buttons["打开设置"].exists)
        XCTAssertTrue(app.buttons["偏好与编排"].exists)
        XCTAssertFalse(app.buttons["我的-备份与恢复"].exists)
        XCTAssertFalse(app.buttons["更多记录工具"].exists)
        XCTAssertFalse(app.buttons["导入历史训练"].exists)
        capture("five-tabs-profile-single-settings", app)

        app.buttons["主导航-工具"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["工具中心"].waitForExistence(timeout: 5))
        let quickWater = app.buttons["记录喝水"]
        reveal(quickWater, app)
        XCTAssertTrue(quickWater.isHittable)
        XCTAssertTrue(app.buttons["记录跳绳"].exists)
        XCTAssertTrue(app.buttons["记录久坐"].exists)
        XCTAssertTrue(app.buttons["工具记录体重"].exists)
        capture("tools-dedicated-destination", app)
        app.buttons["主导航-训练"].tap()
        XCTAssertTrue(app.buttons["主导航-训练"].isSelected)
    }

    func testSettingsKeepsImportExportAndHealthReachableAtLargestType() {
        let app = launch(large: true)
        app.buttons["主导航-我的"].tap()
        let settings = app.buttons["打开设置"]
        reveal(settings, app); settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["设置-通用"].isSelected)
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label CONTAINS %@", "训练日提醒")).firstMatch.exists)
        let health = app.buttons["设置-健康数据说明"]
        reveal(health, app)
        XCTAssertTrue(health.isHittable)
        let terminology = app.buttons["设置-动作名称审核"]
        reveal(terminology, app)
        XCTAssertTrue(terminology.isHittable)

        app.buttons["设置-数据"].tap()
        let backup = app.buttons["设置-生成备份"]
        XCTAssertTrue(backup.waitForExistence(timeout: 5))
        reveal(backup, app)
        XCTAssertGreaterThanOrEqual(backup.frame.height, 44)
        let historyImport = app.buttons["设置-导入历史训练"]
        reveal(historyImport, app); historyImport.tap()
        XCTAssertTrue(app.navigationBars["导入历史训练"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let export = app.buttons["设置-导出减脂周期"]
        reveal(export, app)
        XCTAssertTrue(export.isHittable)
        XCTAssertGreaterThanOrEqual(export.frame.height, 44)
        export.tap()
        XCTAssertTrue(app.navigationBars["周期导出"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let restore = app.buttons["设置-导入备份"]
        reveal(restore, app)
        XCTAssertTrue(restore.isHittable)
        let csv = app.buttons["设置-生成训练CSV"]
        reveal(csv, app)
        XCTAssertTrue(csv.isHittable)
        capture("settings-data-largest-type", app)
    }

    func testDateSelectionRetainsTodayAndTrainingStatus() {
        let app = launch()
        let days = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "训练日期-"))
        XCTAssertEqual(days.count, 7)
        guard let today = days.allElementsBoundByIndex.first(where: { ($0.value as? String)?.contains("今天") == true }),
              let other = days.allElementsBoundByIndex.first(where: { $0.identifier != today.identifier }) else {
            return XCTFail("需要今天和另外一天")
        }
        let todayLabel = today.label
        other.tap()
        XCTAssertTrue(other.isSelected)
        XCTAssertTrue((today.value as? String)?.contains("今天") == true)
        XCTAssertEqual(today.label, todayLabel)
        today.tap()
        XCTAssertTrue(today.isSelected)
        capture("date-green-selection-without-outline", app)
    }

    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-redesign-preview"]
        if large {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["主导航-训练"].waitForExistence(timeout: 15))
        return app
    }

    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        for _ in 0..<10 {
            let viewport = scroll.frame
            let navigation = app.navigationBars.firstMatch
            let tabBar = app.descendants(matching: .any).matching(identifier: "主导航").firstMatch
            let review = app.buttons["计划-审阅确认"]
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
                needsDown = frame.midY < visible.midY
                distance = abs(frame.midY - visible.midY)
            }
            // R2 small-screen AX shows a one-point clipped card edge after
            // inertial overshoot. Center the complete target with a slow drag
            // and hold its end to stop momentum; retain full-frame assertions.
            let cap = min(180, visible.height * 0.6)
            let travel = min(cap, max(12, distance))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: visible.midX, dy: visible.midY + (needsDown ? -travel / 2 : travel / 2)))
            let end = origin.withOffset(CGVector(dx: visible.midX, dy: visible.midY + (needsDown ? travel / 2 : -travel / 2)))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
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
