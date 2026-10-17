import XCTest
@testable import HearIAmCore

final class SignalSoundTests: XCTestCase {
    let all: [SignalSound]=WarningLevel.allCases.map { .warning($0) }+[.arrival]
        + [40,60,80].flatMap { [SignalSound.buzz(hertz:$0,harmonic:false),.buzz(hertz:$0,harmonic:true)] }

    func rms(_ s: ArraySlice<Float>) -> Float { (s.map { $0*$0 }.reduce(0,+)/Float(max(1,s.count))).squareRoot() }

    func testEverySoundIsFiniteBoundedAndStartsAndEndsSilent() {
        for sound in all {
            let s=ToneRenderer.render(sound)
            XCTAssertFalse(s.isEmpty,sound.name)
            XCTAssertTrue(s.allSatisfy(\.isFinite),sound.name)
            XCTAssertLessThanOrEqual(s.map(abs).max() ?? 0,ToneRenderer.peak+1e-5,sound.name)
            XCTAssertLessThan(abs(s.first ?? 1),0.01,sound.name)
            XCTAssertLessThan(abs(s.last ?? 1),0.01,sound.name)
        }
    }
    func testCloserWarningsRepeatFasterAndOnePeriodIsRendered() {
        let lengths=WarningLevel.allCases.map { ToneRenderer.render(.warning($0)).count }
        XCTAssertEqual(lengths,lengths.sorted(by:>))
        for level in WarningLevel.allCases {
            XCTAssertEqual(ToneRenderer.render(.warning(level)).count,ToneRenderer.count(level.period))
        }
    }
    func testWarningIsMostlySilenceExceptAtCloseRange() {
        let far=ToneRenderer.render(.warning(.far)), pulse=ToneRenderer.count(ToneRenderer.warningPulse)
        XCTAssertGreaterThan(rms(far[..<pulse]),0.3)
        XCTAssertEqual(rms(far[pulse...]),0)
    }
    func testArrivalDecays() {
        let s=ToneRenderer.render(.arrival), window=ToneRenderer.count(0.1)
        XCTAssertLessThan(rms(s.suffix(window)),rms(s.prefix(window))*0.3)
    }
    func testBuzzPulsesAndHarmonicChangesTheSound() {
        let plain=ToneRenderer.render(.buzz(hertz:60,harmonic:false))
        // The 12 Hz pulse reaches silence between beats, at 0 and every 1/12 s.
        let trough=ToneRenderer.count(1/ToneRenderer.buzzRate)
        let crest=ToneRenderer.count(1.5/ToneRenderer.buzzRate)
        XCTAssertLessThan(rms(plain[(trough-20)..<(trough+20)]),rms(plain[(crest-400)..<(crest+400)])*0.2)
        XCTAssertNotEqual(plain,ToneRenderer.render(.buzz(hertz:60,harmonic:true)))
    }
    func testNamesAreDistinctForLogs() {
        XCTAssertEqual(Set(all.map(\.name)).count,all.count)
        XCTAssertEqual(SignalSound.buzz(hertz:40,harmonic:true).name,"buzz_40hz_harmonic")
    }
}
