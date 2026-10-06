import XCTest

final class DirectionHapticsUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-reset", "--ui-preview", "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
    }

    private func reveal(_ element: XCUIElement, attempts: Int = 12) {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Missing element: \(element)")
    }
    private func enabled(_ element: XCUIElement, timeout: TimeInterval = 8) {
        let predicate = NSPredicate(format: "exists == true AND enabled == true")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout), .completed)
    }
    private func revealBelowEditorPreview(_ element: XCUIElement) {
        // XCTest can report a scrolled-out Form control as hittable underneath the pinned preview.
        for _ in 0..<10 {
            let top = app.buttons["previewAfter"].frame.maxY + 12
            let bottom = app.frame.maxY - 30
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.minY >= top && frame.maxY <= bottom { return }
                let center = CGPoint(x: app.frame.midX, y: (top + bottom) / 2)
                let offset: CGFloat = frame.minY < top ? 140 : -140
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: center.x, dy: center.y)).press(forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: center.x, dy: center.y + offset)))
            } else { app.swipeUp() }
        }
        XCTFail("Editor control remains covered by the preview: \(element)")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testHardwareExperienceReachesRotationInput() {
        app.tabBars.buttons["랜덤 체험"].tap()
        reveal(app.buttons["startRandom"]); app.buttons["startRandom"].tap()
        let status = app.descendants(matching: .any).matching(identifier: "rotationStatus").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let ready = expectation(for: NSPredicate(format: "label CONTAINS %@", "느낀 방향으로 돌려주세요"), evaluatedWith: status)
        let result = XCTWaiter.wait(for: [ready], timeout: 12)
        capture("hardware-experience")
        let issue = app.staticTexts["rotationIssue"]
        XCTAssertEqual(result, .completed, issue.exists ? issue.label : status.label)
        app.buttons["rotationPause"].tap()
        XCTAssertTrue(app.buttons["rotationResume"].exists)
    }

    func testHardwareFrontHoldAutomaticallyReachesSecondRound() {
        app.terminate()
        app.launchArguments += ["--hardware-test-front"]
        app.launch()
        app.tabBars.buttons["랜덤 체험"].tap()
        reveal(app.buttons["startRandom"]); app.buttons["startRandom"].tap()
        let score = app.staticTexts["randomScore"]
        let second = expectation(for: NSPredicate(format: "label == %@", "이번 체험 2회 확인"), evaluatedWith: score)
        let result = XCTWaiter.wait(for: [second], timeout: 25)
        capture("hardware-two-rounds")
        let issue = app.staticTexts["rotationIssue"]
        XCTAssertEqual(result, .completed, issue.exists ? issue.label : "자동 진행이 두 번째 확인까지 도달하지 못함")
        app.buttons["rotationPause"].tap()
    }

    func testHardwareWrongHoldAutomaticallyReachesSecondRound() {
        app.terminate()
        app.launchArguments += ["--rotation-test-sequence"]
        app.launch()
        app.tabBars.buttons["랜덤 체험"].tap()
        reveal(app.buttons["startRandom"]); app.buttons["startRandom"].tap()
        let status = app.descendants(matching: .any).matching(identifier: "rotationStatus").firstMatch
        let wrong = expectation(for: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                "오답이에요", "정답: 오른쪽 · 내 응답: 앞"), evaluatedWith: status)
        XCTAssertEqual(XCTWaiter.wait(for: [wrong], timeout: 12), .completed)
        capture("hardware-incorrect-feedback")
        let second = expectation(for: NSPredicate(format: "label == %@", "이번 체험 2회 확인"), evaluatedWith: app.staticTexts["randomScore"])
        XCTAssertEqual(XCTWaiter.wait(for: [second], timeout: 15), .completed)
        XCTAssertFalse(app.staticTexts["rotationIssue"].exists)
        app.buttons["rotationPause"].tap()
    }

    func testDelayedMotionWaitsForSensorBeforeStarting() {
        app.terminate()
        app.launchArguments += ["--motion-start-delay"]
        app.launch()
        app.tabBars.buttons["랜덤 체험"].tap()
        reveal(app.buttons["startRandom"]); app.buttons["startRandom"].tap()
        let status = app.descendants(matching: .any).matching(identifier: "rotationStatus").firstMatch
        let waiting = expectation(for: NSPredicate(format: "label CONTAINS %@", "회전 센서를 준비"), evaluatedWith: status)
        XCTAssertEqual(XCTWaiter.wait(for: [waiting], timeout: 2), .completed)
        let ready = expectation(for: NSPredicate(format: "label CONTAINS %@", "느낀 방향으로 돌려주세요"), evaluatedWith: status)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["rotationIssue"].exists)
        app.buttons["rotationPause"].tap()
    }

    func testMissingHapticStartCannotLeaveExperienceStuckAndCanRetry() {
        assertHapticTimeoutAndRetry(argument: "--haptic-start-stall", message: "진동 시작 응답이 없습니다")
    }

    func testMissingHapticCompletionCannotLeaveExperienceStuckAndCanRetry() {
        assertHapticTimeoutAndRetry(argument: "--haptic-completion-stall", message: "진동 완료 응답이 없습니다")
    }

    private func assertHapticTimeoutAndRetry(argument: String, message: String) {
        app.terminate(); app.launchArguments.append(argument); app.launch()
        app.tabBars.buttons["랜덤 체험"].tap()
        reveal(app.buttons["startRandom"]); app.buttons["startRandom"].tap()
        let resume = app.buttons["rotationResume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["rotationIssue"].label.contains(message))
        XCTAssertEqual(app.staticTexts["randomScore"].label, "이번 체험 0회 확인")
        capture("haptic-timeout-recovery")
        resume.tap()
        let status = app.descendants(matching: .any).matching(identifier: "rotationStatus").firstMatch
        let recovered = expectation(for: NSPredicate(format: "label CONTAINS %@", "느낀 방향으로 돌려주세요"), evaluatedWith: status)
        XCTAssertEqual(XCTWaiter.wait(for: [recovered], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["rotationIssue"].exists)
        app.buttons["rotationPause"].tap()
    }

    func testEditSaveNewVersionAndPersistWithoutChangingPreset() {
        capture("01-library")
        app.buttons["preset_A"].tap()
        reveal(app.buttons["editSet"]); app.buttons["editSet"].tap()
        let name = app.textFields["setName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        reveal(name); name.tap()
        let old = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "무대 실험")
        app.buttons["완료"].tap()
        app.buttons["previewAfter"].tap()
        enabled(app.buttons["previewAfter"])
        let timeline = app.descendants(matching: .any).matching(identifier: "liveTimeline").firstMatch
        XCTAssertTrue(timeline.exists)
        let beforeValue = timeline.value as? String
        reveal(app.buttons["진동 강도 줄이기"]); app.buttons["진동 강도 줄이기"].tap()
        XCTAssertEqual(app.textFields["진동 강도 값"].value as? String, "95")
        XCTAssertTrue(timeline.isHittable, "The graph must remain on screen beside scrolled controls")
        XCTAssertNotEqual(timeline.value as? String, beforeValue)
        XCTAssertTrue((timeline.value as? String ?? "").contains("95%"))
        capture("02-editor-live-graph")
        let duration = app.buttons["연속 진동 길이 늘리기"]
        reveal(duration); duration.tap()
        XCTAssertTrue(timeline.isHittable)
        XCTAssertTrue((timeline.value as? String ?? "").contains("110ms"))
        capture("03-editor-scrolled-graph")
        app.navigationBars.buttons["저장"].tap()
        XCTAssertTrue(app.buttons["editSet"].waitForExistence(timeout: 5))
        app.tabBars.buttons["편집"].tap()
        XCTAssertTrue(app.staticTexts["무대 실험"].waitForExistence(timeout: 5))
        app.buttons["editUserSet"].tap()
        reveal(app.textFields["진동 강도 값"])
        XCTAssertEqual(app.textFields["진동 강도 값"].value as? String, "95")
        app.navigationBars.buttons["저장"].tap()
        let version = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "v2 ·")).firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset" }
        app.launch()
        XCTAssertTrue(app.buttons["preset_A"].exists)
        app.tabBars.buttons["편집"].tap()
        XCTAssertTrue(app.staticTexts["무대 실험"].waitForExistence(timeout: 5))
        XCTAssertTrue(version.exists)
    }

    func testHapticLengthUpdatesGraphPlaybackAndPersistsPerDirection() {
        app.buttons["preset_B"].tap()
        reveal(app.buttons["editSet"]); app.buttons["editSet"].tap()
        let length = app.textFields["전체 햅틱 길이 값"]
        XCTAssertTrue(length.waitForExistence(timeout: 5))
        XCTAssertEqual(length.value as? String, "70")
        let timeline = app.descendants(matching: .any).matching(identifier: "liveTimeline").firstMatch
        app.buttons["전체 햅틱 길이 늘리기"].tap()
        XCTAssertEqual(length.value as? String, "80")
        XCTAssertTrue(timeline.isHittable)
        XCTAssertTrue((timeline.value as? String ?? "").contains("연속 진동 100% / 50% / 80ms"))
        XCTAssertTrue(app.staticTexts["patternDurationSummary"].label.contains("0.08초"))
        capture("length-control-and-live-graph")
        app.buttons["previewAfter"].tap()
        enabled(app.buttons["previewAfter"])
        XCTAssertFalse(app.alerts["확인해 주세요"].exists)
        app.navigationBars.buttons["저장"].tap()
        app.tabBars.buttons["편집"].tap()
        app.buttons["editUserSet"].tap()
        XCTAssertTrue(length.waitForExistence(timeout: 5))
        XCTAssertEqual(length.value as? String, "80")
        app.segmentedControls["directionPicker"].buttons["↓ 뒤"].tap()
        XCTAssertEqual(length.value as? String, "880", "Editing front must not change back")
        app.navigationBars.buttons["저장"].tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-reset" }; app.launch()
        app.tabBars.buttons["편집"].tap(); app.buttons["editUserSet"].tap()
        XCTAssertTrue(length.waitForExistence(timeout: 5))
        XCTAssertEqual(length.value as? String, "80")
        app.segmentedControls["directionPicker"].buttons["↓ 뒤"].tap()
        XCTAssertEqual(length.value as? String, "880")
    }

    func testIndividualTapCanBecomeAnAdjustableLengthPulse() {
        app.buttons["preset_B"].tap()
        reveal(app.buttons["editSet"]); app.buttons["editSet"].tap()
        let timeline = app.descendants(matching: .any).matching(identifier: "liveTimeline").firstMatch
        let advanced = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "상세 편집")).firstMatch
        revealBelowEditorPreview(advanced); advanced.tap()
        let tapLength = app.buttons["enableTapLength_0"]
        revealBelowEditorPreview(tapLength); tapLength.tap()
        let converted = expectation(for: NSPredicate(format: "value CONTAINS %@", "연속 진동 100% / 50% / 70ms"), evaluatedWith: timeline)
        XCTAssertEqual(XCTWaiter.wait(for: [converted], timeout: 3), .completed)
        let increase = app.buttons["stepLength_0_increase"]
        revealBelowEditorPreview(increase); increase.tap()
        XCTAssertTrue(timeline.isHittable)
        XCTAssertTrue((timeline.value as? String ?? "").contains("연속 진동 100% / 50% / 80ms"), "\(timeline.value ?? "missing timeline")")
        capture("individual-tap-length")
        app.buttons["previewAfter"].tap()
        enabled(app.buttons["previewAfter"])
        XCTAssertFalse(app.alerts["확인해 주세요"].exists)
        app.navigationBars.buttons["저장"].tap()
        app.tabBars.buttons["편집"].tap(); app.buttons["editUserSet"].tap()
        let length = app.textFields["전체 햅틱 길이 값"]
        XCTAssertTrue(length.waitForExistence(timeout: 5))
        XCTAssertEqual(length.value as? String, "80")
    }

    func testRotationConfirmationAutoAdvancePauseAndNoHistory() {
        app.terminate()
        app.launchArguments += ["--rotation-test-sequence"]
        app.launch()
        XCTAssertFalse(app.tabBars.buttons["비교"].exists)
        app.tabBars.buttons["랜덤 체험"].tap()
        let start = app.buttons["startRandom"]
        reveal(start); start.tap()
        let pause = app.buttons["rotationPause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5)); pause.tap()
        XCTAssertTrue(app.buttons["rotationResume"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["randomScore"].label, "이번 체험 0회 확인")
        app.buttons["rotationResume"].tap()
        let status = app.descendants(matching: .any).matching(identifier: "rotationStatus").firstMatch
        let score = app.staticTexts["randomScore"]
        // First cue is right. Staying at front must submit an incorrect answer on its own.
        let wrong = expectation(for: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                "오답이에요", "정답: 오른쪽 · 내 응답: 앞"), evaluatedWith: status)
        XCTAssertEqual(XCTWaiter.wait(for: [wrong], timeout: 12), .completed)
        XCTAssertEqual(score.label, "이번 체험 1회 확인")
        capture("04-wrong-rotation-submitted")
        // No next button. The second cue is back and captures a fresh reference.
        let back = app.buttons["simulateBack"]
        enabled(back, timeout: 10); back.tap()
        let correct = expectation(for: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                                  "정답이에요", "정답: 뒤 · 내 응답: 뒤"), evaluatedWith: status)
        XCTAssertEqual(XCTWaiter.wait(for: [correct], timeout: 5), .completed)
        XCTAssertEqual(score.label, "이번 체험 2회 확인")
        capture("05-correct-rotation-submitted")
        // The third target is front: stay still, without an answer button.
        let front = expectation(for: NSPredicate(format: "label == %@", "이번 체험 3회 확인"), evaluatedWith: score)
        XCTAssertEqual(XCTWaiter.wait(for: [front], timeout: 12), .completed)
        pause.tap()
        let stopped = expectation(for: NSPredicate(format: "label != %@", "이번 체험 3회 확인"), evaluatedWith: score)
        stopped.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 4), .completed)
        XCTAssertTrue(app.buttons["rotationResume"].exists)
        app.navigationBars.buttons["닫기"].tap()
        reveal(start); start.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5)); pause.tap()
        XCTAssertEqual(score.label, "이번 체험 0회 확인")
    }

    func testRotationStopsWhenAppLeavesForeground() {
        app.tabBars.buttons["랜덤 체험"].tap()
        reveal(app.buttons["startRandom"]); app.buttons["startRandom"].tap()
        XCTAssertTrue(app.buttons["rotationPause"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["rotationResume"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["randomScore"].label, "이번 체험 0회 확인")
    }

    func testToolbarSettingsPersistAndDriveRandomPreparation() {
        XCTAssertFalse(app.tabBars.buttons["설정"].exists)
        XCTAssertFalse(app.tabBars.buttons["비교"].exists)
        app.buttons["openSettings"].tap()
        let preparation = app.steppers["preparationTime"]
        XCTAssertTrue(preparation.waitForExistence(timeout: 5))
        preparation.buttons.element(boundBy: 0).tap()
        preparation.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(preparation.label.contains("1초"))
        app.buttons["전체 진동 세기 줄이기"].tap()
        XCTAssertEqual(app.textFields["전체 진동 세기 값"].value as? String, "95")
        let sound = app.switches["successSoundSetting"]
        reveal(sound)
        sound.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(sound.value as? String, "0")
        app.buttons["previewSuccessSound"].tap()
        XCTAssertFalse(app.alerts["알림음을 확인해 주세요"].exists)
        reveal(app.buttons["previewIncorrectSound"]); app.buttons["previewIncorrectSound"].tap()
        XCTAssertFalse(app.alerts["알림음을 확인해 주세요"].exists)
        capture("08-settings")
        let appearance = app.buttons["appearanceSetting"]
        reveal(appearance); appearance.tap()
        app.buttons["다크"].tap()
        capture("09-settings-dark")
        app.navigationBars.buttons["완료"].tap()
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-reset" }; app.launch()
        app.tabBars.buttons["랜덤 체험"].tap()
        let hint = app.staticTexts["시작을 누르고 1초 동안 눈을 감으세요."]
        reveal(hint)
        XCTAssertTrue(hint.exists)
        capture("10-random-dark")
        app.buttons["openSettings"].tap()
        XCTAssertTrue(preparation.waitForExistence(timeout: 5))
        XCTAssertTrue(preparation.label.contains("1초"))
        XCTAssertEqual(app.textFields["전체 진동 세기 값"].value as? String, "95")
        XCTAssertEqual(app.switches["successSoundSetting"].value as? String, "0")
    }

    func testLargeTextNavigationAndSettingsRemainUsable() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        capture("11-large-text-library")
        XCTAssertTrue(app.buttons["openSettings"].exists)
        app.tabBars.buttons["랜덤 체험"].tap()
        let start = app.buttons["startRandom"]
        reveal(start); XCTAssertTrue(start.isEnabled)
        capture("12-large-text-random")
        app.buttons["openSettings"].tap()
        let preparation = app.steppers["preparationTime"]
        let increase = preparation.buttons.element(boundBy: 1)
        reveal(increase)
        increase.tap()
        XCTAssertTrue(preparation.label.contains("4초"))
        capture("13-large-text-settings")
        app.navigationBars.buttons["완료"].tap()
    }
}
