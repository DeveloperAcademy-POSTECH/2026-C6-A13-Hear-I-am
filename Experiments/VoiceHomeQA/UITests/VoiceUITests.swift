import XCTest

final class VoiceUITests: XCTestCase {
    func testButtonsWhenMicrophoneUnavailable() {
        continueAfterFailure=false
        let app=XCUIApplication(bundleIdentifier:"org.heariam.voice86.qa")
        app.launchArguments=["-AppleLanguages","(ko)","-AppleLocale","ko_KR"]
        app.launch()
        // Home listens for 「히얼아이엠」 at once (#90). Refusing the microphone leaves the one button way in.
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let deny=springboard.buttons.matching(NSPredicate(format:"label IN %@",["Don’t Allow","Don't Allow","허용 안 함"])).firstMatch
        if deny.waitForExistence(timeout:20) {deny.tap()}
        let start=app.buttons["home.voice.start"]
        XCTAssertTrue(start.waitForExistence(timeout:15))
        start.tap()
        let transcript=app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "말씀하신 내용이 여기에 표시돼요")).firstMatch
        XCTAssertTrue(transcript.waitForExistence(timeout:15))
        snapshot("stage-initial")
        let next=app.buttons["다음 · 사용 방식"]
        let replay=app.buttons["설명 다시 듣기"]
        XCTAssertFalse(next.exists)
        XCTAssertFalse(replay.exists)
        app.buttons["버튼으로 선택"].tap()
        XCTAssertTrue(next.waitForExistence(timeout:5))
        XCTAssertTrue(replay.exists)
        XCTAssertFalse(next.isEnabled)
        snapshot("manual-controls-expanded")
        app.buttons["버튼 접기"].tap()
        XCTAssertFalse(next.exists)
        XCTAssertFalse(replay.exists)
        let stage=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@", "1번,")).firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout:5))
        stage.tap()
        XCTAssertTrue(next.isEnabled)
        snapshot("stage-selected")
        next.tap()
        XCTAssertTrue(app.staticTexts["어떻게 사용할까요?"].waitForExistence(timeout:5))
        let confirm=app.buttons["다음 · 공간 확인"]
        XCTAssertFalse(confirm.isEnabled)
        app.buttons["버튼 접기"].tap()
        XCTAssertFalse(confirm.exists)
        let practice=app.buttons.containing(.staticText,identifier:"연습용").firstMatch
        practice.tap()
        XCTAssertTrue(confirm.isEnabled)
        snapshot("mode-selected")
        app.buttons["버튼 접기"].tap()
        XCTAssertFalse(confirm.exists)
        app.buttons["버튼으로 선택"].tap()
        XCTAssertTrue(confirm.isEnabled)
        app.buttons["취소 · 이전 선택"].tap()
        XCTAssertTrue(next.waitForExistence(timeout:5))
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(transcript.exists)
        stage.tap();next.tap()
        let performance=app.buttons.containing(.staticText,identifier:"실전용").firstMatch
        performance.tap()
        XCTAssertTrue(confirm.isEnabled)
        snapshot("performance-selected")
        confirm.tap()
        XCTAssertFalse(app.staticTexts["어떻게 사용할까요?"].exists)
        // Simulator cannot restore ARWorldMap. Reaching the existing recovery screen proves
        // manual progression works without microphone or speech-recognition permission.
        XCTAssertTrue(app.buttons["공간 다시 확인"].waitForExistence(timeout:15))
        snapshot("manual-restore-fallback")
    }
    private func snapshot(_ name: String) {
        let attachment=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways
        add(attachment)
    }
}
