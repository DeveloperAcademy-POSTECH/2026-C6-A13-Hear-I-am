import Foundation

@main
struct GuidanceCoreTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard value() else { fatalError("FAIL: \(label)") }
    }
    static func main() throws {
        let square = [MapPoint(-3, 0), MapPoint(3, 0), MapPoint(3, 6), MapPoint(-3, 6)]
        let p = MapPoint(0, 1), north = MapPoint(0, 1)
        let right = GuidanceMath.cue(position: p, target: MapPoint(2, 1), heading: north)
        check(abs(right.turnRadians - .pi / 2) < 1e-8 && right.pan == 1, "P facing back: east is right")
        let left = GuidanceMath.cue(position: p, target: MapPoint(-2, 1), heading: north)
        check(left.turnRadians < 0 && left.pan == -1, "west is left")
        check(GuidanceMath.cue(position: p, target: MapPoint(2, 1), heading: MapPoint(0, -1)).pan == -1, "P facing front reverses left/right")
        let far = GuidanceMath.cue(position: p, target: MapPoint(0, 5), heading: north)
        let near = GuidanceMath.cue(position: p, target: MapPoint(0, 2), heading: north)
        check(far.turnRadians == 0 && near.gain > far.gain && near.gain <= 0.6, "straight and increasing bounded gain")
        let arrival = GuidanceMath.cue(position: p, target: MapPoint(0, 1.2), heading: north)
        check(arrival.state == .arrived && arrival.gain == 0, "arrival mutes")
        check(GuidanceMath.routeInside(p, MapPoint(0, 5), polygon: square), "inside route")
        check(!GuidanceMath.routeInside(p, MapPoint(3, 5), polygon: square), "boundary target blocked")
        check(!GuidanceMath.routeInside(MapPoint(4, 2), p, polygon: square), "outside P blocked")
        let concave = [MapPoint(0, 0), MapPoint(4, 0), MapPoint(4, 4), MapPoint(3, 4), MapPoint(3, 1), MapPoint(1, 1), MapPoint(1, 4), MapPoint(0, 4)]
        check(!GuidanceMath.routeInside(MapPoint(0.5, 3), MapPoint(3.5, 3), polygon: concave), "concave exterior shortcut rejected")
        check(GuidanceMath.routeInside(p, p, polygon: square), "zero-length interior route")
        func ready(headTracking: Bool = false) -> GuidanceState {
            var s = GuidanceState(polygon: square, usesHeadTracking: headTracking)
            s.receive([GuidePerson(id: 1, point: p)], time: 10)
            s.select(1, time: 10)
            s.setTarget(MapPoint(0, 5))
            s.setHeading(toward: MapPoint(0, 3), time: 10)
            s.start(time: 10)
            return s
        }
        var s = ready()
        check(s.active && s.cue.state == .guiding, "operator starts")
        s.receive([], time: 10.2)
        check(s.selectedID == 1 && s.active && s.position == nil && s.cue.gain == 0, "occlusion keeps P and intent, immediately mutes stale position")
        s.receive([GuidePerson(id: 1, point: p)], time: 10.3)
        check(s.selectedID == 1 && s.active && s.cue.state == .guiding, "same sole person reappears without reselection")
        s = ready(); s.expire(time: 10.6)
        check(s.position == nil && s.selectedID == 1 && s.cue.state == .paused, "stale samples expire without deleting P")
        s = ready(); s.receive([GuidePerson(id: 2, point: p)], time: 10.2)
        check(s.selectedID == 1 && s.position == p && s.active, "single-person latch ignores detector ID churn")
        s = ready(); s.receive([GuidePerson(id: 1, point: p), GuidePerson(id: 2, point: MapPoint(1, 1))], time: 10.2)
        check(s.selectedID == 1 && s.active, "one-person mode consumes first candidate without multi-person logic")
        s = ready(); s.receive([GuidePerson(id: 1, point: MapPoint(0.3, 1))], time: 10.6)
        check(s.heading == MapPoint(1, 0) && s.cue.turnRadians < 0, "movement estimates heading and correction")
        s = ready()
        for i in 1...32 { s.receive([GuidePerson(id: 1, point: p)], time: 10 + Double(i) * 0.1) }
        check(!s.active && s.heading == nil && s.cue.gain == 0, "stationary after grace stops")
        s = ready(); s.receive([GuidePerson(id: 1, point: MapPoint(0, 4.8))], time: 10.2)
        check(!s.active && s.cue.state == .arrived && s.cue.gain == 0, "state machine arrival")
        s = ready(); s.setTarget(MapPoint(1, 4))
        check(!s.active && s.heading == nil, "new target requires alignment")
        s = ready(); s.invalidate("session interrupted")
        check(s.people.isEmpty && s.selectedID == nil && s.cue.gain == 0, "interruption clears output")
        let encoded = try JSONEncoder().encode(right)
        let decoded = try JSONDecoder().decode(GuidanceCue.self, from: encoded)
        check(decoded == right, "audio contract round trip")
        // Bidirectional distance gain: moving away, including beyond the old 5m/8m cap.
        let distances = [0.5, 0.75, 1, 2, 4, 5, 8, 12, 20]
        let gains = distances.map(BeaconMath.distanceGain)
        check(zip(gains, gains.dropFirst()).allSatisfy { $0 > $1 }, "farther always quieter")
        check(zip(gains.reversed(), gains.reversed().dropFirst()).allSatisfy { $0 < $1 }, "closer always louder")
        check(abs(BeaconMath.distanceGain(1) - 0.3) < 1e-8, "1m gain")
        check(abs(BeaconMath.distanceGain(2) - 0.15) < 1e-8, "2m gain")
        check(BeaconMath.distanceGain(0) == 0.6, "near-field gain capped")
        check(BeaconMath.distanceGain(.nan) == 0 && BeaconMath.distanceGain(-1) == 0, "invalid distance muted")
        let falling = BeaconMath.smoothGain(0.3, target: 0.1, elapsed: 0.05)
        let rising = BeaconMath.smoothGain(0.1, target: 0.3, elapsed: 0.05)
        check(falling < 0.3 && falling > 0.1, "smooth decrease without overshoot")
        check(rising > 0.1 && rising < 0.3, "smooth increase without overshoot")
        let h = BeaconMath.heading(initial: MapPoint(0, 1), calibrationYaw: 0.8, currentYaw: 0.8 - .pi / 2)
        check((h - MapPoint(1, 0)).length < 1e-8, "head turns right in arbitrary yaw reference")
        let front = BeaconMath.heading(initial: MapPoint(0, -1), calibrationYaw: 1.2, currentYaw: 1.2)
        check((front - MapPoint(0, -1)).length < 1e-8, "stage front calibration replaces fixed 180")
        let wrap = BeaconMath.heading(initial: MapPoint(0, 1), calibrationYaw: .pi - 0.01, currentYaw: -.pi + 0.01)
        check(abs(wrap.x + sin(0.02)) < 1e-8 && wrap.y > 0.99, "yaw wrap remains continuous")
        check(BeaconMath.mayPlay(sample: 10, head: 10, now: 10.2, prepared: true, headphones: true, calibrated: true), "fresh output allowed")
        check(!BeaconMath.mayPlay(sample: 10, head: 10.6, now: 10.6, prepared: true, headphones: true, calibrated: true), "position timeout mutes")
        check(!BeaconMath.mayPlay(sample: 10.6, head: 10, now: 10.6, prepared: true, headphones: true, calibrated: true), "head timeout mutes")
        check(!BeaconMath.mayPlay(sample: 10, head: 10, now: 10.2, prepared: true, headphones: false, calibrated: true), "speaker output rejected")
        check(!BeaconMath.mayPlay(sample: 10, head: 10, now: 10.2, prepared: true, headphones: true, calibrated: false), "uncalibrated output rejected")
        check(!BeaconMath.fresh(11, now: 10), "future timestamps rejected")
        s = ready(headTracking: true)
        for i in 1...40 {
            let time = 10 + Double(i) * 0.1
            s.receiveHeadHeading(MapPoint(0, 1), time: time)
            s.receive([GuidePerson(id: 1, point: p)], time: time)
        }
        check(s.active, "fresh head tracking permits stationary listening")
        s.receiveHeadHeading(MapPoint(1, 0), time: 14.1)
        s.receive([GuidePerson(id: 1, point: p)], time: 14.1)
        check(s.cue.turnRadians < -1.5, "head rotation changes direction while P stationary")
        s.receive([GuidePerson(id: 1, point: p)], time: 14.7)
        check(s.active && s.heading != nil && s.cue.state == .paused && s.cue.gain == 0,
              "brief head delay mutes guidance without discarding calibration or intent")
        s.receiveHeadHeading(MapPoint(1, 0), time: 14.8)
        s.receive([GuidePerson(id: 1, point: p)], time: 14.8)
        check(s.active && s.cue.state == .guiding, "fresh head and position resume after brief gap")
        s.receive([GuidePerson(id: 1, point: p)], time: 16.9)
        check(!s.active && s.heading == nil && s.cue.gain == 0, "long head gap requires explicit recalibration")
        s.receiveHeadHeading(MapPoint(1, 0), time: 17)
        s.receive([GuidePerson(id: 1, point: p)], time: 17)
        check(!s.active && s.heading == nil, "long gap cannot silently resume on next sample")
        check(BeaconMath.retainsHeadCalibration(10, now: 10.7) && !BeaconMath.fresh(10, now: 10.7),
              "retained calibration never makes stale head data playable")
        check(!BeaconMath.retainsHeadCalibration(10, now: 12.1) &&
              !BeaconMath.retainsHeadCalibration(11, now: 10) &&
              !BeaconMath.retainsHeadCalibration(-.infinity, now: 10), "invalid and long gaps cannot retain calibration")
        s = ready(headTracking: true)
        let startingGain = s.cue.gain
        s.receiveHeadHeading(MapPoint(0, 1), time: 10.2)
        s.receive([GuidePerson(id: 1, point: MapPoint(0, 0.6))], time: 10.2)
        check(s.cue.gain < startingGain && s.heading == MapPoint(0, 1), "walking backward decreases volume without overriding head yaw")
        s.receiveHeadHeading(MapPoint(0, 1), time: 10.4)
        s.receive([GuidePerson(id: 1, point: MapPoint(0, 2))], time: 10.4)
        check(s.cue.gain > startingGain, "reversing toward D increases volume again")
        s = ready(headTracking: true)
        s.receive([GuidePerson(id: 1, point: MapPoint(0, 4.8))], time: 10.7)
        check(s.cue.state == .paused, "stale head cannot trigger arrival")
        check(BeaconAudioPolicy.routeAction(headphones: true, sameDevice: true, engineRunning: true) == .keep,
              "same headphones category/config event keeps audio running")
        check(BeaconAudioPolicy.routeAction(headphones: true, sameDevice: true, engineRunning: false) == .recover,
              "stopped engine with connected headphones recovers, not disconnected")
        check(BeaconAudioPolicy.routeAction(headphones: true, sameDevice: false, engineRunning: true) == .recover,
              "different headphones require recovery and recalibration")
        check(BeaconAudioPolicy.routeAction(headphones: false, sameDevice: false, engineRunning: true) == .stop,
              "speaker route stops even if engine runs")
        check(BeaconAudioPolicy.routeAction(headphones: false, sameDevice: true, engineRunning: false) == .stop,
              "missing route cannot trigger automatic engine restart")
        s = ready(headTracking: true)
        s.receive([], time: 10.2, visualContact: true, detail: "몸 일부 보임")
        s.expire(time: 10.3)
        check(s.selectedID == 1 && s.heading != nil && s.active && s.position == p && s.cue.state == .guiding,
              "one visible depth miss preserves still-fresh position and pulse")
        check(s.cue.sampleUptimeSeconds == 10, "depth miss never refreshes position timestamp")
        for i in 1...40 {
            let time = 10.3 + Double(i) * 0.1
            s.receiveHeadHeading(MapPoint(0, 1), time: time)
            s.receive([], time: time, visualContact: true, detail: "부분 영상 추적")
            s.expire(time: time)
        }
        check(s.hasVisualContact && s.selectedID == 1 && s.cue.gain == 0 && s.active,
              "partial body without depth keeps P for seconds, but never guides from old position")
        s.receiveHeadHeading(MapPoint(0, 1), time: 14.4)
        s.receive([GuidePerson(id: 99, point: MapPoint(0, 2))], time: 14.4)
        check(s.selectedID == 1 && s.position == MapPoint(0, 2) && s.cue.state == .guiding,
              "fresh torso depth resumes same P with no reselection")
        s.receive([], time: 14.5, visualContact: false)
        s.pause()
        s.receive([GuidePerson(id: 123, point: MapPoint(0, 2))], time: 15)
        check(s.selectedID == 1 && !s.active && s.cue.gain == 0,
              "manual stop never resumes on reacquisition")
        s.clearSelection()
        check(s.selectedID == nil && !s.active, "operator can explicitly release P")
        s = GuidanceState(polygon: square, usesHeadTracking: true)
        s.receive([GuidePerson(id: 1, point: p)], time: 20)
        s.select(1, time: 20)
        s.setTarget(MapPoint(0, 5))
        check(s.setHeading(toward: MapPoint(2, 1), time: 20), "live map direction accepts manual tap without headphone samples")
        check(s.heading == MapPoint(1, 0) && !s.active, "manual preview stores arrow without starting guidance")
        s.expire(time: 20.1)
        check(s.heading == MapPoint(1, 0), "idle timer preserves manual arrow before audio calibration")
        s.receive([], time: 20.6, visualContact: true)
        check(!s.setHeading(toward: MapPoint(0, 3), time: 20.6) && s.message.contains("위치 측정 대기"),
              "partial visibility without location explains rejected direction tap")
        s.receive([GuidePerson(id: 8, point: p)], time: 20.7)
        check(s.setHeading(toward: MapPoint(0, 3), time: 20.7) && s.heading == north,
              "direction selection recovers with fresh position and same selected P")
        check(!s.setHeading(toward: p, time: 20.7) && s.heading == north,
              "tap on P rejects zero direction without replacing existing arrow")
        s = ready(headTracking: true)
        s.receiveHeadHeading(north, time: 10.4)
        s.receive([], time: 10.4, visualContact: true)
        s.expire(time: 10.51)
        check(s.position == nil && s.cue.gain == 0 && s.selectedID == 1,
              "visible depth dropout stops at original position expiry, not dropout time")
        print("Guidance core: \(checks) checks passed")
    }
}
