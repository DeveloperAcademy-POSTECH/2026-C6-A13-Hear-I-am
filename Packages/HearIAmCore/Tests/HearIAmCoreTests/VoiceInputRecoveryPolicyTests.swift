import XCTest
@testable import HearIAmCore

final class VoiceInputRecoveryPolicyTests: XCTestCase {
    func testPersistentOutageHasThreeBoundedRetries() {
        var policy = VoiceInputRecoveryPolicy()
        XCTAssertEqual(policy.nextDelay(at: 0), 0.5)
        XCTAssertEqual(policy.nextDelay(at: 0.5), 1)
        XCTAssertEqual(policy.nextDelay(at: 1.5), 2)
        XCTAssertNil(policy.nextDelay(at: 3.5))
        XCTAssertNil(policy.nextDelay(at: 4))
    }
    func testSuccessfulUtteranceOrNewSessionResetsBudget() {
        var policy = VoiceInputRecoveryPolicy()
        _ = policy.nextDelay(at: 0)
        _ = policy.nextDelay(at: 1)
        policy.reset()
        XCTAssertEqual(policy.nextDelay(at: 2), 0.5)
    }
    func testSeparateOutageAfterHealthyIntervalGetsFreshBudget() {
        var policy = VoiceInputRecoveryPolicy()
        _ = policy.nextDelay(at: 0)
        _ = policy.nextDelay(at: 1)
        _ = policy.nextDelay(at: 2)
        XCTAssertEqual(policy.nextDelay(at: 32), 0.5)
    }
    func testRepeatedRebuildWithoutHealthyIntervalDoesNotResetBudget() {
        var policy = VoiceInputRecoveryPolicy()
        _ = policy.nextDelay(at: 0)
        _ = policy.nextDelay(at: 20)
        _ = policy.nextDelay(at: 40)
        XCTAssertNil(policy.nextDelay(at: 60))
    }
}
