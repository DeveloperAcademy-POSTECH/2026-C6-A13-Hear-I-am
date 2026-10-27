import XCTest
import HearIAmCore
@testable import HearVoiceQA
@MainActor final class VoiceIntegrationTests:XCTestCase {
    func model() -> GuidanceViewModel {
        let m=GuidanceViewModel(voiceExperiment:true)
        m.timer?.invalidate();m.voiceRecognitionRequested=true
        m.voice.bufferedOutput={_,_ in true}
        return m
    }
    func testPerformanceClosesInputThroughPauseAndInterruption() {
        let m=model();defer {m.finish()}
        m.voiceMode = .performance
        XCTAssertTrue(m.voiceShouldListen)
        m.phase = .starting
        XCTAssertTrue(m.voicePerformanceInputClosed);XCTAssertFalse(m.voiceShouldListen)
        for p:GuidancePhase in [.guiding,.paused,.interrupted,.failed] {m.phase=p;XCTAssertFalse(m.voiceShouldListen)}
    }
    func testNewSelectionReopensMicrophoneAfterPerformance() {
        let m=model();defer {m.finish()}
        m.voiceMode = .performance;m.phase = .starting;m.phase = .completed
        XCTAssertFalse(m.voiceRecognitionRequested)
        m.chooseAgain()
        XCTAssertTrue(m.voiceShouldListen);XCTAssertTrue(m.voiceRecognitionRequested)
    }
    func testPracticeRetainsVoiceAndBargeInStopsNarration() {
        let m=model();defer {m.finish()}
        m.voiceMode = .practice;m.phase = .guiding;m.started=true
        let old=m.generation;m.speaking=true
        m.voiceSpeechDetected()
        XCTAssertEqual(m.phase,.paused);XCTAssertTrue(m.voiceTurnActive)
        XCTAssertNotEqual(old,m.generation);XCTAssertTrue(m.instructionDone)
        XCTAssertFalse(m.voicePerformanceInputClosed)
    }
    func testTouchSelectionAndCancellationKeepSeparateSteps() throws {
        let m=model();defer {m.finish()}
        let scan=try QAFixtures.manifest();m.voiceStages=[scan]
        m.select(scan,advanceAutomatically:false)
        XCTAssertTrue(m.canContinueVoiceSelection);XCTAssertFalse(m.voiceChoosingMode)
        m.continueVoiceSelection();XCTAssertTrue(m.voiceChoosingMode)
        XCTAssertFalse(m.canContinueVoiceSelection)
        m.selectVoiceMode(.practice,advanceAutomatically:false)
        XCTAssertTrue(m.canContinueVoiceSelection);XCTAssertEqual(m.phase,.selection)
        m.cancelVoiceSelection();XCTAssertNil(m.selected);XCTAssertNil(m.voiceMode)
        XCTAssertFalse(m.voiceChoosingMode)
    }
    func testPlaceKeywordAndDuplicatePerformanceRemainDisambiguated() throws {
        let m=model();defer {m.finish()}
        let a=try QAFixtures.manifest(),b=try QAFixtures.manifest()
        m.voiceStages=[a,b];m.voiceStagePaths=[a.id:["효자아트홀"],b.id:["대연습실"]]
        m.handleVoiceCommand("효자아트홀 관련 무대 열어줘")
        XCTAssertEqual(m.visibleVoiceStages.map(\.id),[a.id]);XCTAssertNil(m.selected)
        m.handleVoiceCommand("1번")
        XCTAssertEqual(m.selected?.id,a.id);XCTAssertTrue(m.voiceChoosingMode)
    }
}
