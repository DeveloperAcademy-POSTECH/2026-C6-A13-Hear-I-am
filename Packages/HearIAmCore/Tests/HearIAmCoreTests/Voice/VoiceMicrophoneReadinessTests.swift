import XCTest
@testable import HearIAmCore

final class VoiceMicrophoneReadinessTests: XCTestCase {
    func testNewTurnWaitsForInputAndStartupDeadlineBelongsToOwner() {
        let gate = VoiceMicrophoneReadiness()
        XCTAssertFalse(gate.isReady)
        XCTAssertNil(gate.lastBufferTime)
        XCTAssertFalse(gate.isStalled(at: 100))
    }

    func testBuiltInMicrophoneNeedsSustainedInputAndNotifiesOnce() {
        var gate = VoiceMicrophoneReadiness()
        for index in 0..<4 {
            XCTAssertFalse(gate.ingest(frameCount: 1024, sampleRate: 48_000,
                                       channelCount: 1, at: Double(index) * 1024 / 48_000))
        }
        XCTAssertFalse(gate.isReady)
        XCTAssertTrue(gate.ingest(frameCount: 1024, sampleRate: 48_000,
                                  channelCount: 1, at: 4 * 1024 / 48_000))
        XCTAssertTrue(gate.isReady)
        XCTAssertFalse(gate.ingest(frameCount: 1024, sampleRate: 48_000,
                                   channelCount: 1, at: 5 * 1024 / 48_000))
    }

    func testBluetoothMicrophoneUsesDurationRatherThanFixedFrameCount() {
        var gate = VoiceMicrophoneReadiness()
        XCTAssertFalse(gate.ingest(frameCount: 1024, sampleRate: 16_000,
                                   channelCount: 1, at: 1))
        XCTAssertTrue(gate.ingest(frameCount: 1024, sampleRate: 16_000,
                                  channelCount: 1, at: 1.064))
    }

    func testSilenceAlsoEstablishesReadinessAtExactDurationBoundary() {
        // Speech amplitude is deliberately not part of this gate. Silent valid PCM is input.
        var gate = VoiceMicrophoneReadiness()
        for index in 0..<9 {
            XCTAssertFalse(gate.ingest(frameCount: 480, sampleRate: 48_000,
                                       channelCount: 2, at: Double(index) / 100))
        }
        XCTAssertTrue(gate.ingest(frameCount: 480, sampleRate: 48_000,
                                  channelCount: 2, at: 0.09))
    }

    func testInvalidBuffersDoNotEstablishReadinessOrRefreshWatchdog() {
        var gate = VoiceMicrophoneReadiness()
        let invalid: [(Int, Double, Int, Double)] = [
            (0, 48_000, 1, 1), (-1, 48_000, 1, 1), (4800, 0, 1, 1),
            (4800, -48_000, 1, 1), (4800, .infinity, 1, 1), (4800, .nan, 1, 1),
            (4800, 48_000, 0, 1), (4800, 48_000, -1, 1),
            (4800, 48_000, 1, .nan), (4800, 48_000, 1, .infinity),
            (4800, 48_000, 1, -1)
        ]
        for (frames, rate, channels, time) in invalid {
            XCTAssertFalse(gate.ingest(frameCount: frames, sampleRate: rate,
                                       channelCount: channels, at: time))
        }
        XCTAssertFalse(gate.isReady)
        XCTAssertNil(gate.lastBufferTime)
        XCTAssertTrue(gate.ingest(frameCount: 4800, sampleRate: 48_000,
                                  channelCount: 1, at: 1))
        XCTAssertFalse(gate.ingest(frameCount: 0, sampleRate: 48_000,
                                   channelCount: 1, at: 3))
        XCTAssertEqual(gate.lastBufferTime, 1)
        XCTAssertTrue(gate.isStalled(at: 3))
    }

    func testIsolatedShortBurstCannotCombineWithMuchLaterInput() {
        var gate = VoiceMicrophoneReadiness()
        XCTAssertFalse(gate.ingest(frameCount: 2400, sampleRate: 48_000,
                                   channelCount: 1, at: 1))
        XCTAssertFalse(gate.ingest(frameCount: 2400, sampleRate: 48_000,
                                   channelCount: 1, at: 2.1))
        XCTAssertFalse(gate.isReady)
        XCTAssertTrue(gate.ingest(frameCount: 2400, sampleRate: 48_000,
                                  channelCount: 1, at: 2.15))
    }

    func testRetiredTurnReadinessDoesNotCarryIntoNextTurn() {
        var gate = VoiceMicrophoneReadiness()
        XCTAssertTrue(gate.ingest(frameCount: 4800, sampleRate: 48_000,
                                  channelCount: 1, at: 1))
        gate.reset()
        XCTAssertFalse(gate.isReady)
        XCTAssertNil(gate.lastBufferTime)
        XCTAssertFalse(gate.ingest(frameCount: 2400, sampleRate: 48_000,
                                   channelCount: 1, at: 2))
        XCTAssertFalse(gate.isReady)
    }

    func testWatchdogDetectsStoppedInputAndRejectsBackwardClock() {
        var gate = VoiceMicrophoneReadiness()
        XCTAssertTrue(gate.ingest(frameCount: 4800, sampleRate: 48_000,
                                  channelCount: 1, at: 10))
        XCTAssertFalse(gate.ingest(frameCount: 4800, sampleRate: 48_000,
                                   channelCount: 1, at: 9))
        XCTAssertEqual(gate.lastBufferTime, 10)
        XCTAssertFalse(gate.isStalled(at: 9))
        XCTAssertFalse(gate.isStalled(at: 11.99))
        XCTAssertTrue(gate.isStalled(at: 12))
        XCTAssertFalse(gate.isStalled(at: .nan))
        XCTAssertFalse(gate.isStalled(at: .infinity))
        XCTAssertFalse(gate.isStalled(at: 12, timeout: 0))
        XCTAssertFalse(gate.isStalled(at: 12, timeout: .nan))
        XCTAssertFalse(gate.ingest(frameCount: 1024, sampleRate: 48_000,
                                   channelCount: 1, at: 12.1))
        XCTAssertFalse(gate.isStalled(at: 13))
    }
}
