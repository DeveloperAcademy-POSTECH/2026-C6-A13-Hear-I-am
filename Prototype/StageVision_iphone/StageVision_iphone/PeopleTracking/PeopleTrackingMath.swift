import Foundation
import simd

nonisolated struct PersonMeasurement: Sendable {
    let position: SIMD3<Float>
    let depthSpread: Float
}

nonisolated struct TrackedPerson: Identifiable, Sendable {
    let id: Int
    var position: SIMD3<Float>
    var lastSeen: TimeInterval
    var depthSpread: Float
    var speed: Float = 0
    var moving = false
    var motionOrigin: SIMD3<Float>
    var motionTime: TimeInterval
    var motionReady = false
}

nonisolated enum PeopleTrackingMath {
    /// Vision coordinates (bottom left, oriented image) -> native sensor (top left).
    static func sensorPoint(_ p: SIMD2<Float>, quarterTurns: Int) -> SIMD2<Float> {
        switch quarterTurns {
        case 1: return SIMD2(1 - p.y, 1 - p.x) // right / portrait
        case 2: return SIMD2(1 - p.x, p.y)
        case 3: return SIMD2(p.y, p.x)
        default: return SIMD2(p.x, 1 - p.y)
        }
    }

    static func worldPoint(pixel: SIMD2<Float>, depth: Float, intrinsics: simd_float3x3,
                           camera: simd_float4x4) -> SIMD3<Float> {
        // Depth is camera Z, not radial distance. ARKit looks along negative Z.
        let x = (pixel.x - intrinsics[2].x) * depth / intrinsics[0].x
        let y = -(pixel.y - intrinsics[2].y) * depth / intrinsics[1].y
        let p = camera * SIMD4(x, y, -depth, 1)
        return SIMD3(p.x, p.y, p.z)
    }

    /// X right, Y above camera, Z horizontal forward; gravity aligned.
    static func relative(_ world: SIMD3<Float>, camera: simd_float4x4) -> SIMD3<Float>? {
        let forward = SIMD3(-camera[2].x, 0, -camera[2].z)
        guard simd_length(forward) > 0.15 else { return nil }
        let f = simd_normalize(forward)
        let right = simd_cross(f, SIMD3(0, 1, 0))
        let d = world - SIMD3(camera[3].x, camera[3].y, camera[3].z)
        return SIMD3(simd_dot(d, right), d.y, simd_dot(d, f))
    }

    static func robustDepth(_ samples: [Float]) -> (depth: Float, spread: Float)? {
        let values = samples.filter { $0.isFinite && $0 >= 0.2 && $0 <= 6 }.sorted()
        guard values.count >= 5 else { return nil }
        let median = values[values.count / 2]
        let deviation = values.map { abs($0 - median) }.sorted()[values.count / 2]
        guard deviation <= 0.12 else { return nil }
        return (median, deviation)
    }
}

nonisolated struct PersonTracker {
    private(set) var people: [TrackedPerson] = []
    private var nextID = 1

    mutating func update(_ measurements: [PersonMeasurement], time: TimeInterval) -> [TrackedPerson] {
        people.removeAll { time - $0.lastSeen > 0.65 }
        // Global nearest pairs, each detection/track can be consumed at most once.
        let pairs = people.indices.flatMap { i in
            measurements.indices.compactMap { j -> (Int, Int, Float)? in
                let distance = simd_distance(people[i].position, measurements[j].position)
                let gate = min(Float(0.9), 0.3 + Float(time - people[i].lastSeen) * 2)
                return distance < gate ? (i, j, distance) : nil
            }
        }.sorted { $0.2 < $1.2 }
        var usedTracks = Set<Int>(), usedDetections = Set<Int>()
        for (i, j, _) in pairs where !usedTracks.contains(i) && !usedDetections.contains(j) {
            usedTracks.insert(i); usedDetections.insert(j)
            let m = measurements[j]
            // Position smoothing has a small, explicit latency; speed uses a longer baseline.
            people[i].position = people[i].position * 0.25 + m.position * 0.75
            let elapsed = time - people[i].motionTime
            if elapsed >= 0.5 {
                let delta = m.position - people[i].motionOrigin
                let speed = simd_length(SIMD2(delta.x, delta.z)) / Float(elapsed)
                people[i].speed = people[i].motionReady ? people[i].speed * 0.35 + speed * 0.65 : speed
                people[i].moving = people[i].speed > (people[i].moving ? 0.14 : 0.25)
                people[i].motionReady = true
                people[i].motionOrigin = m.position
                people[i].motionTime = time
            }
            people[i].lastSeen = time
            people[i].depthSpread = m.depthSpread
        }
        for j in measurements.indices where !usedDetections.contains(j) {
            let m = measurements[j]
            people.append(TrackedPerson(id: nextID, position: m.position, lastSeen: time,
                                        depthSpread: m.depthSpread, motionOrigin: m.position, motionTime: time))
            nextID += 1
        }
        // Keep briefly missing tracks only for association, never show stale positions as live.
        return people.filter { time - $0.lastSeen < 0.01 }
    }
}


nonisolated struct PoseAnchor {
    var name: String
    var point: SIMD2<Float>
    var confidence: Float
}
nonisolated enum SinglePersonMath {
    static func acceptsDepthConfidence(_ value: Int, selected: Bool) -> Bool {
        value >= (selected ? 1 : 2) && value <= 2
    }
    static func torsoSamples(_ anchors: [PoseAnchor], selected: Bool) -> [SIMD2<Float>] {
        func p(_ name: String) -> SIMD2<Float>? {
            anchors.first { $0.name == name && $0.confidence > (selected ? 0.2 : 0.45)
                && $0.point.x.isFinite && $0.point.y.isFinite }?.point
        }
        var output: [SIMD2<Float>] = []
        if let root = p("root"), let neck = p("neck") { output.append((root + neck) / 2) }
        guard selected else { return output }
        if let left = p("leftHip"), let right = p("rightHip") { output.append((left + right) / 2) }
        if let left = p("leftShoulder"), let right = p("rightShoulder") { output.append((left + right) / 2) }
        if let root = p("root") { output.append(root) }
        if let neck = p("neck") { output.append(neck) }
        return output
    }
}
