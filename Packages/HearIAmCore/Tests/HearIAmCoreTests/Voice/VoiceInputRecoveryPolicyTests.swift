import XCTest
@testable import HearIAmCore

final class VoiceInputRecoveryPolicyTests: XCTestCase {
    func testOutageHasThreeRetriesAndRemainsExhaustedUntilExplicitRecovery() {
        var policy = VoiceInputRecoveryPolicy()
        XCTAssertEqual(policy.nextDelay(), 0.5)
        XCTAssertEqual(policy.nextDelay(), 1)
        XCTAssertEqual(policy.nextDelay(), 2)
        // No wall-clock input exists: a long callback gap or repeated engine rebuilds
        // cannot silently create another retry budget.
        for _ in 0..<100 { XCTAssertNil(policy.nextDelay()) }
    }

    func testEmptyFinalsBetweenFailuresCannotCreateAnInfiniteRetryLoop() {
        var policy = VoiceInputRecoveryPolicy()
        var allowedDelays: [Double] = []
        for _ in 0..<100 {
            if let delay = policy.nextDelay() { allowedDelays.append(delay) }
            policy.recordFinalRecognition("")
            policy.recordFinalRecognition(" \t\n\r\u{3000}")
        }
        XCTAssertEqual(allowedDelays, [0.5, 1, 2])
    }

    func testRecognizedFinalCommandRestoresBudget() {
        var policy = VoiceInputRecoveryPolicy()
        for _ in 0..<3 { XCTAssertNotNil(policy.nextDelay()) }
        XCTAssertNil(policy.nextDelay())
        policy.recordFinalRecognition("  P2 지점으로 다시 안내해 줘\n")
        XCTAssertEqual(policy.nextDelay(), 0.5)
        XCTAssertEqual(policy.nextDelay(), 1)
        XCTAssertEqual(policy.nextDelay(), 2)
        XCTAssertNil(policy.nextDelay())
    }

    func testManualNewSessionCanRetryAfterExhaustion() {
        var policy = VoiceInputRecoveryPolicy()
        for _ in 0..<3 { XCTAssertNotNil(policy.nextDelay()) }
        XCTAssertNil(policy.nextDelay())
        policy.reset()
        XCTAssertEqual(policy.nextDelay(), 0.5)
    }

    func testEmptyFinalDuringBackoffDoesNotRestartTheInitialDelay() {
        var policy = VoiceInputRecoveryPolicy()
        XCTAssertEqual(policy.nextDelay(), 0.5)
        policy.recordFinalRecognition("   ")
        XCTAssertEqual(policy.nextDelay(), 1)
        policy.recordFinalRecognition("\n")
        XCTAssertEqual(policy.nextDelay(), 2)
        policy.recordFinalRecognition("")
        XCTAssertNil(policy.nextDelay())
    }
}
