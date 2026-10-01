import ARKit
import Vision
import ImageIO
import QuartzCore

/// One-person PoC only. The operator's selection outlives missing joints/depth.
/// Visual presence and a fresh, measured 3D position are intentionally separate.
nonisolated final class SinglePersonVisionTracker {
    var selected = false
    private var sequence = VNSequenceRequestHandler()
    private var objectRequest: VNTrackObjectRequest?
    private var previousTurns: Int?
    private var filteredPosition: SIMD3<Float>?
    private var lastPositionTime = -Double.infinity

    func process(_ frame: ARFrame, orientation: CGImagePropertyOrientation, turns: Int) -> PeopleFrame {
        func result(_ status: String, visible: Bool = false, people: [TrackedPerson] = []) -> PeopleFrame {
            PeopleFrame(people: people, camera: frame.camera.transform, status: status,
                        timestamp: frame.timestamp, personVisible: visible)
        }
        guard case .normal = frame.camera.trackingState else {
            return result("공간 추적 안정화 대기 · P 지정 유지")
        }
        if previousTurns != turns {
            objectRequest = nil; sequence = VNSequenceRequestHandler(); previousTurns = turns
        }
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: orientation)
            let pose = VNDetectHumanBodyPoseRequest()
            try handler.perform([pose])
            // Only one participant is in scope. Choose the largest body observation.
            let candidates = (pose.results ?? []).compactMap { try? $0.recognizedPoints(.all) }
            let points = candidates.max { box($0).area < box($1).area } ?? [:]
            let goodJoints = points.values.filter { $0.confidence >= (selected ? 0.2 : 0.45) }
            var visible = goodJoints.count >= 2
            let poseBox = box(points)
            if goodJoints.count >= 4, poseBox.area > 0.003 {
                try seed(poseBox, frame: frame, orientation: orientation)
            } else if selected, let request = objectRequest {
                try sequence.perform([request], on: frame.capturedImage, orientation: orientation)
                if let observation = request.results?.first as? VNDetectedObjectObservation, observation.confidence >= 0.25,
                   hasPersonPixels(in: observation.boundingBox, mask: frame.segmentationBuffer, turns: turns) {
                    visible = true
                    request.inputObservation = observation
                } else { objectRequest = nil }
            }
            if selected && !visible {
                // Reacquire the only person, including an upper body without the hips.
                let human = VNDetectHumanRectanglesRequest()
                human.upperBodyOnly = true
                try handler.perform([human])
                if let observation = human.results?.filter({ $0.confidence >= 0.3 }).max(by: { $0.boundingBox.area < $1.boundingBox.area }) {
                    visible = true
                    try seed(observation.boundingBox, frame: frame, orientation: orientation)
                }
            }
            let keys: [(String, VNHumanBodyPoseObservation.JointName)] = [
                ("root", .root), ("neck", .neck), ("leftShoulder", .leftShoulder),
                ("rightShoulder", .rightShoulder), ("leftHip", .leftHip), ("rightHip", .rightHip)
            ]
            let anchors = keys.compactMap { name, key -> PoseAnchor? in
                guard let value = points[key] else { return nil }
                return PoseAnchor(name: name, point: SIMD2(Float(value.location.x), Float(value.location.y)), confidence: value.confidence)
            }
            // A lone hand/foot indicates visual presence, not a fresh torso position.
            let samples = SinglePersonMath.torsoSamples(anchors, selected: selected)
            for center in samples {
                let uv = PeopleTrackingMath.sensorPoint(center, quarterTurns: turns)
                guard let depth = depthSample(uv, frame: frame, relaxed: selected) else { continue }
                let resolution = frame.camera.imageResolution
                let world = PeopleTrackingMath.worldPoint(pixel: uv * SIMD2(Float(resolution.width), Float(resolution.height)),
                    depth: depth.depth, intrinsics: frame.camera.intrinsics, camera: frame.camera.transform)
                guard CACurrentMediaTime() - frame.timestamp <= 0.5 else {
                    return result("처리 지연 · P 지정 유지", visible: visible)
                }
                // Do not smooth across an occlusion using an old position.
                let p: SIMD3<Float>
                if let old = filteredPosition, frame.timestamp - lastPositionTime <= 0.5 {
                    p = old * 0.25 + world * 0.75
                } else { p = world }
                filteredPosition = p; lastPositionTime = frame.timestamp
                let person = TrackedPerson(id: 1, position: p, lastSeen: frame.timestamp,
                    depthSpread: depth.spread, motionOrigin: p, motionTime: frame.timestamp)
                return result(selected ? "P 지정 유지 · 몸통/부분 자세 + 깊이 측정" : "사람 발견 · P로 선택하세요", visible: true, people: [person])
            }
            return result(visible ? "P 영상 유지 · 몸통/깊이 측정 대기 (소리 일시 중지)" : "P 화면 밖/영상 추적 대기 · 선택 유지", visible: visible)
        } catch {
            objectRequest = nil
            return result("영상 처리 일시 실패 · P 지정 유지")
        }
    }

    private func box(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> CGRect {
        let usable = points.values.filter { $0.confidence >= 0.2 }.map(\.location)
        guard usable.count >= 2 else { return .zero }
        let xs = usable.map(\.x), ys = usable.map(\.y)
        let rect = CGRect(x: xs.min()! - 0.04, y: ys.min()! - 0.04,
                          width: xs.max()! - xs.min()! + 0.08, height: ys.max()! - ys.min()! + 0.08)
        return rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    private func seed(_ box: CGRect, frame: ARFrame, orientation: CGImagePropertyOrientation) throws {
        sequence = VNSequenceRequestHandler()
        let request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: box))
        request.trackingLevel = .accurate
        // Prime on the actual seed image, not the next frame.
        try sequence.perform([request], on: frame.capturedImage, orientation: orientation)
        if let observation = request.results?.first as? VNDetectedObjectObservation { request.inputObservation = observation }
        objectRequest = request
    }
    private func hasPersonPixels(in box: CGRect, mask: CVPixelBuffer?, turns: Int) -> Bool {
        guard let mask else { return false }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return false }
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        var count = 0
        for row in 0..<7 {
            for col in 0..<7 {
                let p = SIMD2(Float(box.minX + box.width * (Double(col) + 0.5) / 7),
                              Float(box.minY + box.height * (Double(row) + 0.5) / 7))
                let uv = PeopleTrackingMath.sensorPoint(p, quarterTurns: turns)
                let x = Int(uv.x * Float(w)), y = Int(uv.y * Float(h))
                guard x >= 0, x < w, y >= 0, y < h else { continue }
                if base.advanced(by: y * CVPixelBufferGetBytesPerRow(mask)).assumingMemoryBound(to: UInt8.self)[x] > 127 { count += 1 }
            }
        }
        return count >= 2
    }
    private func depthSample(_ uv: SIMD2<Float>, frame: ARFrame, relaxed: Bool) -> (depth: Float, spread: Float)? {
        guard let data = frame.sceneDepth, let confidence = data.confidenceMap,
              let mask = frame.segmentationBuffer else { return nil }
        let depth = data.depthMap
        for buffer in [depth, confidence, mask] { CVPixelBufferLockBaseAddress(buffer, .readOnly) }
        defer { for buffer in [depth, confidence, mask] { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) } }
        guard let db = CVPixelBufferGetBaseAddress(depth), let cb = CVPixelBufferGetBaseAddress(confidence),
              let mb = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let w = CVPixelBufferGetWidth(depth), h = CVPixelBufferGetHeight(depth)
        guard CVPixelBufferGetWidth(confidence) == w, CVPixelBufferGetHeight(confidence) == h else { return nil }
        let mw = CVPixelBufferGetWidth(mask), mh = CVPixelBufferGetHeight(mask)
        let x = Int(uv.x * Float(w)), y = Int(uv.y * Float(h))
        let radius = relaxed ? 3 : 2
        var values: [Float] = []
        for dy in -radius...radius {
            for dx in -radius...radius {
                let px = x + dx, py = y + dy
                guard px >= 0, px < w, py >= 0, py < h else { continue }
                let quality = cb.advanced(by: py * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)[px]
                guard SinglePersonMath.acceptsDepthConfidence(Int(quality), selected: relaxed) else { continue }
                let mx = min(mw - 1, px * mw / w), my = min(mh - 1, py * mh / h)
                guard mb.advanced(by: my * CVPixelBufferGetBytesPerRow(mask)).assumingMemoryBound(to: UInt8.self)[mx] > 127 else { continue }
                values.append(db.advanced(by: py * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float.self)[px])
            }
        }
        return PeopleTrackingMath.robustDepth(values)
    }
}

private extension CGRect {
    nonisolated var area: CGFloat { isNull ? 0 : width * height }
}
