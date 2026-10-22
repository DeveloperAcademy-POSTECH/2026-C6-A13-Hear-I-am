import XCTest
@testable import HearIAmCore

final class SignalSoundTests: XCTestCase {
    let all: [SignalSound]=WarningLevel.allCases.flatMap { level in WarningTone.allCases.map { .warning(level,tone:$0) } }+[.arrival]
        + AlignedTone.allCases.map { .aligned(tone:$0) }
        + [40,60,80].flatMap { [SignalSound.buzz(hertz:$0,harmonic:false),.buzz(hertz:$0,harmonic:true)] }
        + DirectionPattern.landmarks.map { SignalSound.direction(signedDegrees:$0) }
        + [.directionTick(toRight:false),.directionTick(toRight:true)]

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
        for tone in WarningTone.allCases {
            let lengths=WarningLevel.allCases.map { ToneRenderer.render(.warning($0,tone:tone)).count }
            XCTAssertEqual(lengths,lengths.sorted(by:>),tone.rawValue)
            for level in WarningLevel.allCases {
                XCTAssertEqual(ToneRenderer.render(.warning(level,tone:tone)).count,ToneRenderer.count(level.period),tone.rawValue)
                XCTAssertLessThanOrEqual(ToneRenderer.warningBeep(tone).count,ToneRenderer.count(WarningLevel.close.period),tone.rawValue)
            }
        }
    }
    func testWarningIsMostlySilenceExceptAtCloseRange() {
        for tone in WarningTone.allCases {
            let far=ToneRenderer.render(.warning(.far,tone:tone)), pulse=ToneRenderer.warningBeep(tone).count
            XCTAssertGreaterThan(rms(far[..<pulse]),0.1,tone.rawValue)
            XCTAssertEqual(rms(far[pulse...]),0,tone.rawValue)
        }
    }
    func testArrivalDecays() {
        let s=ToneRenderer.render(.arrival), window=ToneRenderer.count(0.1)
        XCTAssertLessThan(rms(s.suffix(window)),rms(s.prefix(window))*0.3)
    }
    /// Two notes, the second starting alignedStep after the first, both dying away (10/21, #62).
    func testAlignedChimeRisesAndDecays() {
        let window=ToneRenderer.count(0.02), second=ToneRenderer.count(ToneRenderer.alignedStep)
        for tone in [AlignedTone.warm,.fifth,.softBell] {
            let s=ToneRenderer.render(.aligned(tone:tone))
            XCTAssertEqual(s.count,ToneRenderer.count(ToneRenderer.alignedStep+ToneRenderer.alignedNote),tone.rawValue)
            XCTAssertEqual(s.first,0,tone.rawValue);XCTAssertEqual(s.last ?? 1,0,accuracy:1e-6,tone.rawValue)
            XCTAssertGreaterThan(rms(s[(second+window)..<(second+2*window)]),rms(s[(second-window)..<second]),tone.rawValue)
            XCTAssertLessThan(rms(s.suffix(window)),rms(s[second..<(second+window*2)])*0.3,tone.rawValue)
        }
        let chord=ToneRenderer.render(.aligned(tone:.chord))
        XCTAssertEqual(chord.count,ToneRenderer.count(ToneRenderer.alignedStep+ToneRenderer.alignedNote))
        XCTAssertLessThan(rms(chord.suffix(window)),rms(chord[window..<(window*3)])*0.3)
    }
    func testBuzzPulsesAndHarmonicChangesTheSound() {
        let plain=ToneRenderer.render(.buzz(hertz:60,harmonic:false))
        // The 12 Hz pulse reaches silence between beats, at 0 and every 1/12 s.
        let trough=ToneRenderer.count(1/ToneRenderer.buzzRate)
        let crest=ToneRenderer.count(1.5/ToneRenderer.buzzRate)
        XCTAssertLessThan(rms(plain[(trough-20)..<(trough+20)]),rms(plain[(crest-400)..<(crest+400)])*0.2)
        XCTAssertNotEqual(plain,ToneRenderer.render(.buzz(hertz:60,harmonic:true)))
    }
    func testDirectionBeepCountsAndPitches() {
        // Front once, back twice, sides once per 45°, all at PoC1 timings.
        for (degrees,hertz,count) in [(0,990.0,1),(180,990,2),(-180,990,2),(45,1320,1),(90,1320,2),(135,1320,3),(-45,660,1),(-90,660,2),(-135,660,3)] {
            let beep=try! XCTUnwrap(DirectionPattern.beep(signedDegrees:degrees))
            XCTAssertEqual(beep.hertz,hertz,"\(degrees)");XCTAssertEqual(beep.count,count,"\(degrees)")
            let length=Double(count)*DirectionPattern.beepLength+Double(count-1)*DirectionPattern.beepGap
            XCTAssertEqual(ToneRenderer.render(.direction(signedDegrees:degrees)).count,ToneRenderer.count(length),"\(degrees)")
        }
        for degrees in [30,60,-120,10] {
            XCTAssertNil(DirectionPattern.beep(signedDegrees:degrees));XCTAssertTrue(ToneRenderer.render(.direction(signedDegrees:degrees)).isEmpty)
        }
    }
    func testDirectionBeepIsSilentBetweenBeeps() {
        let s=ToneRenderer.render(.direction(signedDegrees:135))
        let on=ToneRenderer.count(DirectionPattern.beepLength), gap=ToneRenderer.count(DirectionPattern.beepGap)
        XCTAssertGreaterThan(rms(s[..<on]),0.3)
        XCTAssertEqual(rms(s[(on+5)..<(on+gap-5)]),0)
    }
    func testDirectionTickIsShortPercussiveAndDistinguishesLeftAndRight() {
        let left=ToneRenderer.render(.directionTick(toRight:false))
        let right=ToneRenderer.render(.directionTick(toRight:true))
        XCTAssertEqual(left.count,ToneRenderer.count(ToneRenderer.tickLength))
        XCTAssertEqual(right.count,ToneRenderer.count(ToneRenderer.tickLength))
        XCTAssertNotEqual(left,right)
        let window=ToneRenderer.count(0.01)
        XCTAssertLessThan(rms(left.suffix(window)),rms(left.prefix(window))*0.35)
    }
    /// No warning tone and not the arrival ding may share a pitch with a direction beep (#33).
    /// 「날카로운 삑」 (950 Hz, near the front beep) was dropped on 10/17 and is kept only for comparison.
    func testSignalsShareNoPitchWithDirectionBeeps() {
        let direction=[DirectionPattern.leftHertz,DirectionPattern.centerHertz,DirectionPattern.rightHertz]
        let pitches=WarningTone.allCases.filter { $0 != .sharp }.map { ($0.rawValue,$0.pitches[0]) }+[("arrival",ToneRenderer.arrivalHertz)]
        for (name,pitch) in pitches {
            XCTAssertTrue(direction.allSatisfy { abs($0-pitch)/pitch > 0.1 },"\(name) \(pitch) Hz")
        }
        for pitch in WarningTone.low.pitches {
            XCTAssertTrue(direction.allSatisfy { abs($0-pitch)/pitch > 0.1 },"low \(pitch) Hz")
        }
        XCTAssertEqual(DirectionSignalMode.allCases.map { [$0.vibrates,$0.beeps] },[[true,false],[false,true],[true,true]])
    }
    /// The aligned chime plays among ticks, warnings and the ding, so it shares no pitch with them (10/21, #62),
    /// and stays below 700 Hz so it never hurts the ears.
    func testAlignedChimeSharesNoPitchWithOtherGuidanceSounds() {
        let warnings=WarningTone.allCases.filter { $0 != .sharp }.flatMap(\.pitches)
        let others=[ToneRenderer.tickLeftHertz,ToneRenderer.tickRightHertz,ToneRenderer.arrivalHertz]+warnings
        for tone in AlignedTone.allCases {
            for pitch in tone.pitches {
                XCTAssertLessThan(pitch,700,"\(tone.rawValue) \(pitch) Hz")
                XCTAssertTrue(others.allSatisfy { abs($0-pitch)/pitch > 0.1 },"\(tone.rawValue) \(pitch) Hz")
            }
        }
    }
    func testNamesAreDistinctForLogs() {
        XCTAssertEqual(Set(all.map(\.name)).count,all.count)
        XCTAssertEqual(SignalSound.buzz(hertz:40,harmonic:true).name,"buzz_40hz_harmonic")
        XCTAssertEqual(SignalSound.direction(signedDegrees:-90).name,"direction_left_90")
        XCTAssertEqual(SignalSound.directionTick(toRight:false).name,"direction_tick_left")
        XCTAssertEqual(SignalSound.directionTick(toRight:true).name,"direction_tick_right")
        XCTAssertEqual(SignalSound.aligned().name,"aligned")
        XCTAssertEqual(SignalSound.aligned(tone:.fifth).name,"aligned_fifth")
    }
}
