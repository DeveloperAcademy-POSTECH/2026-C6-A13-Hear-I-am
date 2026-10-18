import XCTest
@testable import HearIAmCore

final class GuidanceInteractionSettingsTests: XCTestCase {
    func testDefaultWaitsForInstructionCompletion() {
        let suite="speech-step-tests-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let settings=GuidanceInteractionSettings(defaults:defaults)
        XCTAssertFalse(settings.advanceDuringSpeech)
        XCTAssertFalse(settings.canAdvanceInstruction(done:false,speaking:true,audioFailed:false))
        XCTAssertFalse(settings.canAdvanceInstruction(done:false,speaking:false,audioFailed:false))
        XCTAssertFalse(settings.canAdvanceInstruction(done:true,speaking:true,audioFailed:false))
        XCTAssertTrue(settings.canAdvanceInstruction(done:true,speaking:false,audioFailed:false))
    }
    func testSavedOptionAllowsEarlyAdvanceAndCanBeDisabledAgain() {
        let suite="speech-step-tests-"+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        defaults.set(true,forKey:GuidanceInteractionSettings.advanceDuringSpeechKey)
        let reloaded=GuidanceInteractionSettings(defaults:UserDefaults(suiteName:suite)!)
        XCTAssertTrue(reloaded.advanceDuringSpeech)
        XCTAssertTrue(reloaded.canAdvanceInstruction(done:false,speaking:true,audioFailed:false))
        XCTAssertTrue(reloaded.canAdvanceInstruction(done:false,speaking:false,audioFailed:false))
        XCTAssertFalse(reloaded.canAdvanceInstruction(done:false,speaking:false,audioFailed:true))
        defaults.set(false,forKey:GuidanceInteractionSettings.advanceDuringSpeechKey)
        XCTAssertFalse(GuidanceInteractionSettings(defaults:defaults).canAdvanceInstruction(done:false,speaking:true,audioFailed:false))
    }
}
