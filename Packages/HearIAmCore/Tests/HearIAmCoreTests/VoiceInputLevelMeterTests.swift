import XCTest
@testable import HearIAmCore

final class VoiceInputLevelMeterTests: XCTestCase {
    func testSilentInputStaysFlat() {
        var meter = VoiceInputLevelMeter()
        for i in 0..<100 { _ = meter.ingest(rms: 0, at: Double(i) / 50) }
        XCTAssertEqual(meter.level, 0)
    }
    func testLouderSpeechProducesLargerEnvelopeAndSilenceDecays() {
        var quiet = VoiceInputLevelMeter(), loud = VoiceInputLevelMeter()
        for i in 0..<50 {
            _ = quiet.ingest(rms: 0.008, at: Double(i) / 50)
            _ = loud.ingest(rms: 0.15, at: Double(i) / 50)
        }
        XCTAssertGreaterThan(loud.level, quiet.level + 0.3)
        let peak = loud.level
        _ = loud.ingest(rms: 0, at: 1)
        XCTAssertGreaterThan(loud.level, 0)
        XCTAssertLessThan(loud.level, peak)
        for i in 51..<125 { _ = loud.ingest(rms: 0, at: Double(i) / 50) }
        XCTAssertEqual(loud.level, 0)
    }
    func testInputRateDoesNotIncreaseDisplayRate() {
        for rate in [16_000.0, 48_000.0] {
            var meter = VoiceInputLevelMeter()
            var emissions: [Double] = []
            for i in 0..<Int(rate / 256) {
                let time = Double(i * 256) / rate
                if meter.ingest(rms: 0.1, at: time) != nil { emissions.append(time) }
            }
            XCTAssertLessThanOrEqual(emissions.count, 20)
            XCTAssertGreaterThan(emissions.count, 10)
            XCTAssertTrue(zip(emissions.dropFirst(), emissions).allSatisfy { $0 - $1 >= 0.05 - 1e-9 })
        }
    }
    func testInvalidSamplesCannotPolluteEnvelope() {
        var meter = VoiceInputLevelMeter()
        _ = meter.ingest(rms: 0.1, at: 10)
        let level = meter.level
        for rms in [Double.nan, .infinity, -1] { XCTAssertNil(meter.ingest(rms: rms, at: 11)) }
        for time in [Double.nan, .infinity, -1, 9, 10] { XCTAssertNil(meter.ingest(rms: 1, at: time)) }
        XCTAssertEqual(meter.level, level)
        _ = meter.ingest(rms: 100, at: 10.1)
        XCTAssertTrue((0...1).contains(meter.level))
    }
    func testNewTurnAndLongInputGapDoNotReuseAnOldPeak() {
        var meter = VoiceInputLevelMeter()
        _ = meter.ingest(rms: 1, at: 1)
        XCTAssertGreaterThan(meter.level, 0)
        meter.reset()
        XCTAssertEqual(meter.level, 0)
        XCTAssertEqual(meter.ingest(rms: 0, at: 2), 0)
        _ = meter.ingest(rms: 1, at: 2.1)
        XCTAssertEqual(meter.ingest(rms: 0, at: 5), 0)
    }
}
