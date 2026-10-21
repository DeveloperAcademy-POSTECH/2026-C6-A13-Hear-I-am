import SceneKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A native skinned figure sampled from recorded distance, never from SceneKit's wall clock.
@MainActor final class ReplayWalkingFigure {
    let node = SCNNode()
    private(set) var isRigged = false
    private var modelRoot: SCNNode?
    private var modelBaseHeight: Float = 0
    private var clip: Clip?
    private struct Binding {
        let bone: SCNNode
        let track: Track
        let sourceRest: SIMD4<Float>
        var rest: SIMD4<Float>
        let bindRotation: simd_quatf
    }
    private var bindings = [Binding]()

    private struct Clip: Decodable {
        let version: Int
        let loopStart: Float
        let loopEnd: Float
        let strideMeters: Float
        let rootName: String
        let rootPosition: [Float]
        let tracks: [Track]
    }
    private struct Track: Decodable {
        let node: String
        let path: String
        let interpolation: String
        let times: [Float]
        let values: [[Float]]

        func value(_ index: Int) -> SIMD4<Float> {
            let v = values[index]
            return SIMD4(v[0], v[1], v[2], v.count == 4 ? v[3] : 0)
        }
        func blend(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
            path == "rotation" ? simd_slerp(simd_quatf(vector: a), simd_quatf(vector: b), t).vector : a + (b - a) * t
        }
        func sample(_ time: Float) -> SIMD4<Float> {
            var low = 0, high = times.count
            while low < high {
                let middle = (low + high) / 2
                if times[middle] <= time { low = middle + 1 } else { high = middle }
            }
            let a = max(0, low - 1), b = min(a + 1, times.count - 1)
            guard a != b, interpolation != "STEP" else { return value(a) }
            return blend(value(a), value(b), max(0, min(1, (time - times[a]) / (times[b] - times[a]))))
        }
        /// Average a complete gait cycle into an arms-down resting pose (the bind pose is a T pose).
        func resting(start: Float, end: Float) -> SIMD4<Float> {
            let reference = sample(start)
            var sum = SIMD4<Float>.zero
            for i in 0..<32 {
                var v = sample(start + (end - start) * Float(i) / 32)
                if path == "rotation", simd_dot(reference, v) < 0 { v = -v }
                sum += v
            }
            return path == "rotation" ? simd_normalize(sum) : sum / 32
        }
    }

    init(directory: URL? = nil) {
        let directory = directory ?? Bundle.main.url(forResource: "ReplayWalker", withExtension: "scn", subdirectory: "ReplayModels.scnassets")?.deletingLastPathComponent()
        if let directory {
            do {
                let data = try Data(contentsOf: directory.appendingPathComponent("ReplayWalker.animation.json"))
                let clip = try JSONDecoder().decode(Clip.self, from: data)
                guard clip.version == 1, clip.loopEnd > clip.loopStart, clip.strideMeters > 0,
                      clip.rootPosition.count == 3, !clip.tracks.isEmpty else { throw AssetError.invalid }
                // Fresh scene per player: cached node clones can retain references to another figure's bones.
                let scene = try SCNScene(url: directory.appendingPathComponent("ReplayWalker.scn"), options: [.checkConsistency: true])
                var bound = [Binding]()
                for track in clip.tracks {
                    guard !track.times.isEmpty, track.times.count == track.values.count,
                          track.values.allSatisfy({ $0.count == (track.path == "rotation" ? 4 : 3) && $0.allSatisfy(\.isFinite) }),
                          track.times.allSatisfy(\.isFinite),
                          zip(track.times, track.times.dropFirst()).allSatisfy({ $0 < $1 }),
                          ["rotation", "translation", "scale"].contains(track.path),
                          ["LINEAR", "STEP"].contains(track.interpolation),
                          let bone = scene.rootNode.childNode(withName: track.node, recursively: true) else { throw AssetError.invalid }
                    let rest = track.resting(start: clip.loopStart, end: clip.loopEnd)
                    bound.append(Binding(bone: bone, track: track, sourceRest: rest, rest: rest, bindRotation: bone.simdOrientation))
                }
                var skinCount = 0
                scene.rootNode.enumerateChildNodes { n, _ in if n.skinner != nil { skinCount += 1 } }
                guard skinCount > 0 else { throw AssetError.invalid }
                #if canImport(UIKit)
                let texture = UIImage(contentsOfFile: directory.appendingPathComponent("ReplayWalker.jpg").path)
                #else
                let texture = NSImage(contentsOf: directory.appendingPathComponent("ReplayWalker.jpg"))
                #endif
                guard let texture else { throw AssetError.invalid }
                scene.rootNode.enumerateChildNodes { n, _ in
                    for material in n.geometry?.materials ?? [] {
                        material.diffuse.contents = texture
                        material.roughness.contents = 0.85; material.metalness.contents = 0
                        material.lightingModel = .physicallyBased
                    }
                }
                for child in scene.rootNode.childNodes { node.addChildNode(child) }
                self.clip = clip; bindings = bound; isRigged = true
                modelRoot = node.childNode(withName: "ReplayWalker", recursively: true)
                modelBaseHeight = modelRoot?.simdPosition.y ?? 0
                relaxUpperBody()
                show(distance: 0, blend: 0)
                return
            } catch {
                #if DEBUG
                print("Replay walker unavailable: \(error)")
                #endif
            }
        }
        #if canImport(UIKit)
        node.addChildNode(ReplayModelFactory.cleanPerson())
        #endif
    }

    func show(distance: Double, blend: Double, strideScale: Double = 1) {
        guard let clip, distance.isFinite, blend.isFinite, strideScale.isFinite else { return }
        let phase = Float(max(0, distance).truncatingRemainder(dividingBy: Double(clip.strideMeters)) / Double(clip.strideMeters))
        let time = clip.loopStart + phase * (clip.loopEnd - clip.loopStart)
        let amount = Float(max(0, min(1, blend)))
        let stride = Float(max(0.15, min(1, strideScale))), legAmount = amount * stride
        // Small asset-specific sole clearance, including the averaged resting pose's straighter legs.
        modelRoot?.simdPosition.y = modelBaseHeight + 0.015 + (1 - legAmount) * 0.032
        // The chosen endpoints already match closely. Close the remaining small seam over the final 0.10 s.
        let seam = max(0, min(1, (time - (clip.loopEnd - 0.10)) / 0.10))
        let smoothSeam = seam * seam * (3 - 2 * seam)
        for binding in bindings {
            let bone = binding.bone, track = binding.track, rest = binding.rest
            var walking = track.blend(track.sample(time), track.sample(clip.loopStart), smoothSeam)
            if track.path == "rotation", let weight = upperBodyWeight(track.node) {
                let delta = simd_quatf(vector: binding.sourceRest).inverse * simd_quatf(vector: walking)
                walking = (simd_quatf(vector: rest) * simd_slerp(simd_quatf(), delta, weight * (0.5 + stride * 0.5))).vector
            }
            let lowerBody = track.node.contains("Leg") || track.node.contains("Foot") || track.node.contains("Toe") || (track.node == clip.rootName && track.path == "translation")
            var value = track.blend(rest, walking, lowerBody ? legAmount : amount)
            if track.node == clip.rootName && track.path == "translation" {
                // Keep vertical hip motion. The outer node owns all recorded travel and heading.
                value.x = clip.rootPosition[0]; value.z = clip.rootPosition[2]
            }
            switch track.path {
            case "rotation": bone.simdOrientation = simd_quatf(vector: value)
            case "translation": bone.simdPosition = SIMD3(value.x, value.y, value.z)
            case "scale": bone.simdScale = SIMD3(value.x, value.y, value.z)
            default: break
            }
        }
    }
    /// The supplied "swagger" clip lifts its hands to the chest. Retain its timing but relax the upper body.
    private func upperBodyWeight(_ name: String) -> Float? {
        switch name.replacingOccurrences(of: "mixamorig:", with: "") {
        case "LeftArm", "RightArm": return 0.55
        case "LeftForeArm", "RightForeArm", "LeftHand", "RightHand": return 0.25
        case "Hips", "Spine", "Spine1", "Spine2", "LeftShoulder", "RightShoulder": return 0.40
        case "Head", "Neck": return 0.15
        default: return name.contains("Hand") ? 0.15 : nil
        }
    }
    private func relaxUpperBody() {
        for i in bindings.indices {
            let binding = bindings[i]
            guard binding.track.path == "rotation", upperBodyWeight(binding.track.node) != nil else { continue }
            let relaxedWeight: Float = binding.track.node.contains("Hand") ? 0.40 : 0.12
            bindings[i].rest = simd_slerp(binding.bindRotation, simd_quatf(vector: binding.sourceRest), relaxedWeight).vector
        }
        show(distance: 0, blend: 0)
        // Aim each upper arm mostly down, with a small clearance from the torso. Preserve the original bone roll.
        for name in ["mixamorig:LeftArm", "mixamorig:RightArm"] {
            guard let i = bindings.firstIndex(where: { $0.track.node == name && $0.track.path == "rotation" }),
                  let parent = bindings[i].bone.parent, let child = bindings[i].bone.childNodes.first else { continue }
            let bone = bindings[i].bone
            let current = simd_normalize(child.simdWorldPosition - bone.simdWorldPosition)
            let desired = simd_normalize(SIMD3<Float>(name.contains("Left") ? 0.16 : -0.16, -1, 0.02))
            let correction = simd_quatf(from: current, to: desired)
            bindings[i].rest = (parent.simdWorldOrientation.inverse * correction * bone.simdWorldOrientation).vector
        }
    }
    private enum AssetError: Error { case invalid }
}
