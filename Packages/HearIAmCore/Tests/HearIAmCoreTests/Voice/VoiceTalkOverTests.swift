import XCTest
@testable import HearIAmCore

final class VoiceTalkOverTests: XCTestCase {
    private func rms(_ db: Double) -> Double { pow(10, db / 20) }

    /// The app alone at volume 0.45 on 11/13: output −12 dB, echo up to −23 dB. Not a person.
    func testAppEchoIsNotTalkOver() {
        var gate = VoiceTalkOver(); gate.volume = 0.45
        var heard = false
        for i in 0..<20 {
            let t = Double(i) * 0.1
            gate.output(rms: rms(-12), at: t)
            heard = gate.input(rms: rms(-23), at: t + 0.02) || heard
        }
        XCTAssertFalse(heard)
    }
    /// 「스캔」 over the greeting at volume 0.45: −9 dB against −13 dB output.
    func testPersonOverTheAppIsHeardOnSecondFrame() {
        var gate = VoiceTalkOver(); gate.volume = 0.45
        gate.output(rms: rms(-13), at: 0)
        XCTAssertFalse(gate.input(rms: rms(-9), at: 0.02))
        gate.output(rms: rms(-13), at: 0.1)
        XCTAssertTrue(gate.input(rms: rms(-9), at: 0.12))
        gate.output(rms: rms(-13), at: 0.2)
        XCTAssertFalse(gate.input(rms: rms(-9), at: 0.22), "reported once per burst")
    }
    /// One loud frame of echo is not enough.
    func testSingleLoudFrameIsIgnored() {
        var gate = VoiceTalkOver(); gate.volume = 0.45
        gate.output(rms: rms(-13), at: 0)
        XCTAssertFalse(gate.input(rms: rms(-9), at: 0.02))
        gate.output(rms: rms(-13), at: 0.1)
        XCTAssertFalse(gate.input(rms: rms(-30), at: 0.12))
        gate.output(rms: rms(-13), at: 0.2)
        XCTAssertFalse(gate.input(rms: rms(-9), at: 0.22))
    }
    /// The app is quiet: nothing to tell apart, so nothing is reported.
    func testNoOutputMeansNoTalkOver() {
        var gate = VoiceTalkOver()
        XCTAssertFalse(gate.input(rms: rms(-10), at: 0))
        XCTAssertFalse(gate.input(rms: rms(-10), at: 0.1))
        gate.output(rms: rms(-12), at: 1)
        XCTAssertFalse(gate.input(rms: rms(-10), at: 1.6), "output older than the window")
    }
    /// A louder phone sends back a louder echo; the same echo at a low volume is a person.
    func testVolumeIsTakenOut() {
        var loud = VoiceTalkOver(); loud.volume = 1
        var quiet = VoiceTalkOver(); quiet.volume = 0.1
        var l = false, q = false
        for i in 0..<3 {
            let t = Double(i) * 0.1
            loud.output(rms: rms(-12), at: t); quiet.output(rms: rms(-12), at: t)
            l = loud.input(rms: rms(-12), at: t + 0.02) || l
            q = quiet.input(rms: rms(-12), at: t + 0.02) || q
        }
        XCTAssertFalse(l); XCTAssertTrue(q)
    }

    /// 11/13 POS: the greeting's echo was written down before the person's word, and the greeting holds it too.
    func testOwnVoiceBeforeTalkOverIsTakenOff() {
        let greeting = "Yes, what would you like to do? Scan a stage, or practice with a saved performance?"
        XCTAssertEqual(VoiceEcho.withoutOwnVoice("Yes but would you like to do Practice", before: "Yes but would you like", lines: [greeting]), "Practice")
        // The final text dropped the echo the partial had: the person's word stays.
        XCTAssertEqual(VoiceEcho.withoutOwnVoice("스캔", before: "네,", lines: ["네, 무엇을 할까요?"]), "스캔")
        XCTAssertEqual(VoiceEcho.withoutOwnVoice("네 무엇을 스캔", before: "네 무엇을", lines: ["네, 무엇을 할까요?"]), "스캔")
        XCTAssertEqual(VoiceEcho.withoutOwnVoice("스캔", before: "", lines: ["네, 무엇을 할까요?"]), "스캔")
    }
}
