import Foundation
import simd

@main
struct PeopleTrackingCoreTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        checks += 1
        guard value() else { fatalError("FAIL: \(label)") }
    }
    static func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ label: String) {
        check(simd_distance(a, b) < 0.0001, label)
    }
    static func main() {
        let p = SIMD2<Float>(0.2, 0.7)
        let expected: [SIMD2<Float>] = [SIMD2(0.2, 0.3), SIMD2(0.3, 0.8), SIMD2(0.8, 0.7), SIMD2(0.7, 0.2)]
        for i in 0...3 { check(simd_distance(PeopleTrackingMath.sensorPoint(p, quarterTurns: i), expected[i]) < 0.0001, "orientation \(i)") }
        let k = simd_float3x3(SIMD3(100, 0, 0), SIMD3(0, 100, 0), SIMD3(50, 50, 1))
        near(PeopleTrackingMath.worldPoint(pixel: SIMD2(50, 50), depth: 2, intrinsics: k, camera: matrix_identity_float4x4), SIMD3(0, 0, -2), "center projects forward")
        let offAxis = PeopleTrackingMath.worldPoint(pixel: SIMD2(100, 25), depth: 2, intrinsics: k, camera: matrix_identity_float4x4)
        near(offAxis, SIMD3(1, 0.5, -2), "off-axis unprojection")
        check(simd_length(offAxis) > 2, "axial depth differs from radial distance")
        var camera = matrix_identity_float4x4
        camera[3] = SIMD4(3, 1, 4, 1)
        near(PeopleTrackingMath.worldPoint(pixel: SIMD2(50, 50), depth: 2, intrinsics: k, camera: camera), SIMD3(3, 1, 2), "camera translation")
        near(PeopleTrackingMath.relative(SIMD3(4, 0.5, 1), camera: camera)!, SIMD3(1, -0.5, 3), "camera relative coordinates")
        let rotation = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)))
        near(PeopleTrackingMath.relative(SIMD3(-3, 0, -1), camera: rotation)!, SIMD3(1, 0, 3), "rotated camera heading")
        let vertical = simd_float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)))
        check(PeopleTrackingMath.relative(.zero, camera: vertical) == nil, "vertical heading rejected")
        check(PeopleTrackingMath.robustDepth([.nan, .infinity, -1, 0, 9]) == nil, "invalid depth rejected")
        check(PeopleTrackingMath.robustDepth([1, 1, 1, 1]) == nil, "insufficient depth rejected")
        check(PeopleTrackingMath.robustDepth([1, 1.4, 1.8, 2.2, 2.6]) == nil, "incoherent patch rejected")
        check(abs(PeopleTrackingMath.robustDepth([2, 2.01, 2, 1.99, 5])!.depth - 2) < 0.001, "outlier rejection")
        func sample(_ x: Float, _ z: Float = -2) -> PersonMeasurement { PersonMeasurement(position: SIMD3(x, 0, z), depthSpread: 0.01) }
        var tracker = PersonTracker()
        let initial = tracker.update([sample(-1), sample(1)], time: 0)
        check(initial.map(\.id) == [1, 2], "multiple identities")
        let reversed = tracker.update([sample(1.04), sample(-0.98)], time: 0.12)
        check(reversed.first { $0.id == 1 }!.position.x < 0, "order independent IDs")
        check(Set(reversed.map(\.id)).count == 2, "unique assignment")
        check(tracker.update([], time: 0.24).isEmpty, "missing detections hidden immediately")
        check(tracker.update([sample(-0.97)], time: 0.36).first!.id == 1, "brief occlusion reacquisition")
        check(tracker.update([sample(-0.97)], time: 1.2).first!.id == 3, "expired track gets new ID")
        var still = PersonTracker()
        for i in 0...12 { _ = still.update([sample(i % 2 == 0 ? 0.01 : -0.01)], time: Double(i) * 0.12) }
        check(still.people[0].motionReady && !still.people[0].moving, "stationary noise")
        var walking = PersonTracker()
        for i in 0...12 { _ = walking.update([sample(Float(i) * 0.08)], time: Double(i) * 0.12) }
        check(walking.people.count == 1 && walking.people[0].moving, "walking association and speed")
        check(abs(walking.people[0].speed - 0.667) < 0.02, "world-space speed")
        let neck = PoseAnchor(name: "neck", point: SIMD2(0.5, 0.8), confidence: 0.8)
        let root = PoseAnchor(name: "root", point: SIMD2(0.5, 0.4), confidence: 0.8)
        check(SinglePersonMath.torsoSamples([neck], selected: false).isEmpty, "initial P needs neck and root")
        check(!SinglePersonMath.torsoSamples([neck, root], selected: false).isEmpty, "initial torso recognized")
        check(SinglePersonMath.torsoSamples([neck], selected: true) == [neck.point], "selected P allows neck-only torso fallback")
        let shoulders = [PoseAnchor(name: "leftShoulder", point: SIMD2(0.3, 0.7), confidence: 0.3),
                         PoseAnchor(name: "rightShoulder", point: SIMD2(0.7, 0.7), confidence: 0.3)]
        check(SinglePersonMath.torsoSamples(shoulders, selected: true) == [SIMD2(0.5, 0.7)], "partial shoulders allow torso depth sampling")
        check(SinglePersonMath.torsoSamples(shoulders, selected: false).isEmpty, "relaxation only after selection")
        check(SinglePersonMath.torsoSamples([PoseAnchor(name: "wrist", point: SIMD2(0.1, 0.4), confidence: 0.9)], selected: true).isEmpty,
              "hand-only observation cannot invent a body position")
        check(SinglePersonMath.acceptsDepthConfidence(1, selected: true), "selected P accepts medium depth confidence")
        check(!SinglePersonMath.acceptsDepthConfidence(1, selected: false), "initial detection still requires high depth confidence")
        check(!SinglePersonMath.acceptsDepthConfidence(0, selected: true), "low depth confidence remains rejected")
        print("People tracking: \(checks) checks passed")
    }
}
