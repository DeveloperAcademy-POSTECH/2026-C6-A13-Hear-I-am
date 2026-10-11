import XCTest

final class WayDetectUITests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<7 { if element.isHittable { return }; app.swipeUp() }
    }
    private func waitEnabled(_ element: XCUIElement, timeout: TimeInterval = 6) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }
    private func waitForLabel(_ label: String, on element: XCUIElement, timeout: TimeInterval = 6) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        waitForExpectations(timeout: timeout)
    }
    private func launchDemo(_ app: XCUIApplication) {
        app.launchArguments = ["--ui-testing", "--short-test-route"]
        app.launch(); app.tabBars.buttons["측정"].tap()
        let demo = app.switches["demo-toggle"]; reveal(demo, in: app); demo.switches.firstMatch.tap()
        let ready = app.switches["ready-toggle"]
        if !ready.isHittable { app.swipeDown() }; ready.switches.firstMatch.tap()
        app.buttons["start-measurement"].tap()
        let reference = app.buttons["set-reference"]; waitEnabled(reference); reference.tap()
        let departure = app.buttons["begin-walking"]; reveal(departure, in: app); waitEnabled(departure); departure.tap()
    }
    private func step(_ app: XCUIApplication) {
        let button = app.buttons["demo-step"]; reveal(button, in: app); button.tap()
    }
    private func top(_ app: XCUIApplication) { for _ in 0..<4 { app.swipeDown() } }
    private func finish(_ app: XCUIApplication) {
        app.buttons["end-measurement"].tap(); app.buttons["측정 종료"].tap()
        XCTAssertTrue(app.buttons["save-result"].waitForExistence(timeout: 3))
    }
    func testTwoSpotsArriveAutomaticallyAndRefreshReference() {
        let app = XCUIApplication(); launchDemo(app)
        step(app); step(app)
        top(app)
        XCTAssertEqual(app.staticTexts["run-phase"].label, "방향 맞추기")
        XCTAssertFalse(app.buttons["confirm-arrival"].exists)
        XCTAssertFalse(app.buttons["manual-arrival"].exists)
        XCTAssertTrue(app.staticTexts["direction-instruction"].label.contains("3시"))
        XCTAssertTrue(app.staticTexts["auto-start-pending"].exists)
        XCTAssertFalse(app.buttons["begin-walking"].exists)
        let align = app.buttons["demo-align"]; reveal(align, in: app); align.tap()
        top(app); waitForLabel("이동 중", on: app.staticTexts["run-phase"])
        XCTAssertFalse(app.buttons["begin-walking"].exists)
        step(app); step(app); top(app)
        XCTAssertTrue(app.buttons["save-result"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["경로 완료"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "POC completion choice"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testWalkingSpeaksClockCorrectionAndConfirmsRecovery() {
        let app = XCUIApplication(); launchDemo(app)
        let right = app.buttons["오른쪽 한 칸"]; reveal(right, in: app); right.tap()
        top(app)
        let guidance = app.staticTexts["last-guidance"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 6))
        expectation(for: NSPredicate(format: "value CONTAINS %@", "11시"), evaluatedWith: guidance)
        waitForExpectations(timeout: 6)
        XCTAssertEqual(app.staticTexts["run-phase"].label, "이동 중")
        let align = app.buttons["demo-align"]; reveal(align, in: app); align.tap()
        expectation(for: NSPredicate(format: "value == %@", "방향 맞음."), evaluatedWith: guidance)
        waitForExpectations(timeout: 6)
        XCTAssertEqual(app.staticTexts["run-phase"].label, "이동 중")
        top(app)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Walking clock correction recovery"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPauseFreezesLegButKeepsTotalAndPreservesTarget() {
        let app = XCUIApplication(); launchDemo(app); step(app)
        let pause = app.buttons["pause-measurement"]
        if !pause.isHittable { app.swipeDown() }; pause.tap()
        step(app); top(app)
        let count = app.staticTexts["step-count"]
        XCTAssertEqual(count.value as? String, "1")
        app.buttons["open-recovery"].tap()
        let resume = app.buttons["resume-walking"]; waitEnabled(resume); resume.tap()
        XCTAssertEqual(app.staticTexts["run-phase"].label, "이동 중")
        XCTAssertEqual(app.staticTexts["step-count"].value as? String, "0")
    }
    func testSaveAndDiscardPersistAcrossRelaunch() {
        let app = XCUIApplication(); launchDemo(app); step(app); finish(app)
        app.buttons["discard-result"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-ui-test-data"]; app.launch()
        app.tabBars.buttons["기록"].tap(); XCTAssertTrue(app.staticTexts["저장한 기록이 없어요"].exists)
        app.terminate(); launchDemo(app); step(app); finish(app)
        app.buttons["save-result"].tap()
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-ui-test-data"]; app.launch()
        app.tabBars.buttons["기록"].tap(); XCTAssertTrue(app.staticTexts["두 스팟 시험"].exists)
        XCTAssertFalse(app.staticTexts["저장한 기록이 없어요"].exists)
    }
    func testInterruptedSessionOffersSaveOrDiscard() {
        let app = XCUIApplication(); launchDemo(app)
        app.terminate(); app.launchArguments = ["--ui-testing", "--preserve-ui-test-data"]; app.launch()
        XCTAssertTrue(app.staticTexts["남아 있는 측정 기록"].waitForExistence(timeout: 5))
        app.buttons["저장 안 함"].tap()
        XCTAssertTrue(app.navigationBars["경로"].waitForExistence(timeout: 5))
    }
    func testDashboardClockAxisAndSettings() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["기록"].tap(); app.buttons["sample-results"].tap()
        let direction = app.segmentedControls["chart-metric"].buttons["방향"]
        reveal(direction, in: app); direction.tap()
        XCTAssertTrue(app.staticTexts["현재 정면에서 목표가 있는 방향"].exists)
        let settings = app.buttons["그래프 설정"]; reveal(settings, in: app); settings.tap()
        let zoom = app.sliders["그래프 표시 시간"]; reveal(zoom, in: app)
        XCTAssertTrue(zoom.exists); zoom.adjust(toNormalizedSliderPosition: 0.8)
        let reset = app.buttons["전체 구간 보기"]; reveal(reset, in: app); reset.tap()
        XCTAssertTrue(app.staticTexts["한 화면에 60초"].exists)
        settings.tap(); top(app)
        let chart = app.descendants(matching: .any).matching(identifier: "measurement-chart").firstMatch
        reveal(chart, in: app); chart.tap()
        XCTAssertTrue(app.staticTexts["chart-selection"].waitForExistence(timeout: 3))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "POC graph settings"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testResetDirectionPreservesStepsWithoutStartingToWalk() {
        let app = XCUIApplication(); launchDemo(app); step(app)
        let right = app.buttons["오른쪽 한 칸"]; reveal(right, in: app); right.tap()
        let reset = app.buttons["reset-direction"]; XCTAssertTrue(reset.isHittable); reset.tap()
        top(app)
        XCTAssertEqual(app.staticTexts["run-phase"].label, "방향 맞추기")
        XCTAssertEqual(app.staticTexts["step-count"].value as? String, "1")
        XCTAssertEqual(app.staticTexts["direction-instruction"].label, "정면.")
        let departure = app.buttons["begin-walking"]; reveal(departure, in: app); waitEnabled(departure)
        XCTAssertEqual(departure.label, "계속 걷기")
        departure.tap()
        XCTAssertEqual(app.staticTexts["run-phase"].label, "이동 중")
        step(app); top(app)
        XCTAssertTrue(app.staticTexts["direction-instruction"].label.contains("3시"))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Automatic arrival next spot"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testBackgroundRecoversWithDirectionResetAndKeepsSteps() {
        let app = XCUIApplication(); launchDemo(app); step(app)
        XCUIDevice.shared.press(.home); app.activate(); top(app)
        XCTAssertEqual(app.staticTexts["run-phase"].label, "일시정지")
        app.buttons["reset-direction"].tap(); top(app)
        XCTAssertEqual(app.staticTexts["run-phase"].label, "방향 맞추기")
        XCTAssertEqual(app.staticTexts["step-count"].value as? String, "1")
        let departure = app.buttons["begin-walking"]; reveal(departure, in: app); waitEnabled(departure)
        XCTAssertTrue(app.buttons["reset-direction"].isEnabled)
    }
    func testVoiceAndHapticPreviewSettings() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["설정"].tap()
        app.switches["음성 안내"].switches.firstMatch.tap()
        app.switches["진동 알림"].switches.firstMatch.tap()
        let preview = app.buttons["guidance-preview-turn"]; XCTAssertFalse(preview.isEnabled)
        app.switches["진동 알림"].switches.firstMatch.tap(); XCTAssertTrue(preview.isEnabled); preview.tap()
    }
}
