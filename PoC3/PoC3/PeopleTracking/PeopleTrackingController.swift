import ARKit
import AVFoundation
import Combine
import ImageIO
import QuartzCore
import UIKit
import Vision

nonisolated struct PeopleFrame: Sendable {
    var people: [TrackedPerson] = []
    var camera = matrix_identity_float4x4
    var status: String
    var rejected = 0
    var requiresRestart = false
    var timestamp: TimeInterval = 0
    var personVisible = false
}

/// All Vision, depth reads, and identity association stay on one serial delegate queue.
nonisolated final class PeopleFrameProcessor: NSObject, ARSessionDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "stagevision.people", qos: .userInitiated)
    var deliver: (@Sendable (PeopleFrame) -> Void)?
    private var orientation: CGImagePropertyOrientation = .right
    private var turns = 1
    private var lastFrame: TimeInterval = -1
    private var tracker = PersonTracker()
    private let singlePersonMode: Bool
    private let singleTracker = SinglePersonVisionTracker()
    init(singlePersonMode: Bool = false) { self.singlePersonMode = singlePersonMode; super.init() }
    func setPersonSelected(_ value: Bool) {
        queue.async { self.singleTracker.selected = value }
    }

    func setOrientation(_ value: CGImagePropertyOrientation, turns: Int) {
        queue.async { self.orientation = value; self.turns = turns }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        process(frame)
    }

    func process(_ frame: ARFrame) {
        guard CACurrentMediaTime() - frame.timestamp < 0.3 else { return }
        guard frame.timestamp - lastFrame >= 0.12 else { return }
        lastFrame = frame.timestamp
        if singlePersonMode {
            deliver?(singleTracker.process(frame, orientation: orientation, turns: turns))
            return
        }
        guard case .normal = frame.camera.trackingState else {
            tracker = PersonTracker()
            deliver?(PeopleFrame(status: "공간 추적 준비 중 · 주변을 천천히 비춰주세요"))
            return
        }
        guard PeopleTrackingMath.relative(.zero, camera: frame.camera.transform) != nil else {
            deliver?(PeopleFrame(status: "휴대폰을 수평 전방으로 향해주세요"))
            return
        }
        guard let depth = frame.sceneDepth, let confidence = depth.confidenceMap,
              let mask = frame.segmentationBuffer else {
            deliver?(PeopleFrame(status: "LiDAR 깊이와 사람 영역을 준비하고 있습니다"))
            return
        }
        let request = VNDetectHumanBodyPoseRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: orientation).perform([request])
            let observations = request.results ?? []
            let buffer = depth.depthMap
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            CVPixelBufferLockBaseAddress(mask, .readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
                CVPixelBufferUnlockBaseAddress(mask, .readOnly)
            }
            var measurements: [PersonMeasurement] = []
            for observation in observations {
                guard let points = try? observation.recognizedPoints(.all),
                      let root = points[.root], root.confidence > 0.45,
                      let neck = points[.neck], neck.confidence > 0.45 else { continue }
                // An interior torso point avoids arm/leg boundaries and clothing edges.
                let center = SIMD2(Float((root.location.x + neck.location.x) / 2),
                                   Float((root.location.y + neck.location.y) / 2))
                let uv = PeopleTrackingMath.sensorPoint(center, quarterTurns: turns)
                guard let sample = sampleDepth(uv, depth: buffer, confidence: confidence, mask: mask) else { continue }
                let resolution = frame.camera.imageResolution
                let pixel = uv * SIMD2(Float(resolution.width), Float(resolution.height))
                let position = PeopleTrackingMath.worldPoint(pixel: pixel, depth: sample.depth,
                    intrinsics: frame.camera.intrinsics, camera: frame.camera.transform)
                measurements.append(PersonMeasurement(position: position, depthSpread: sample.spread))
            }
            guard CACurrentMediaTime() - frame.timestamp < 0.7 else {
                deliver?(PeopleFrame(status: "처리 지연 · 오래된 측정값을 제외했습니다"))
                return
            }
            let people = tracker.update(measurements, time: frame.timestamp)
            deliver?(PeopleFrame(people: people, camera: frame.camera.transform,
                                 status: "LiDAR 실시간 측정", rejected: observations.count - measurements.count, timestamp: frame.timestamp))
        } catch {
            tracker = PersonTracker()
            deliver?(PeopleFrame(status: "사람 인식 처리 실패 · 다시 시작해주세요", requiresRestart: true))
        }
    }

    private func sampleDepth(_ uv: SIMD2<Float>, depth: CVPixelBuffer,
                             confidence: CVPixelBuffer, mask: CVPixelBuffer) -> (depth: Float, spread: Float)? {
        guard uv.x > 0, uv.x < 1, uv.y > 0, uv.y < 1,
              let dBase = CVPixelBufferGetBaseAddress(depth),
              let cBase = CVPixelBufferGetBaseAddress(confidence),
              let mBase = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
        guard CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height else { return nil }
        let mw = CVPixelBufferGetWidth(mask), mh = CVPixelBufferGetHeight(mask)
        let x = Int(uv.x * Float(width)), y = Int(uv.y * Float(height))
        var values: [Float] = []
        for dy in -2...2 {
            for dx in -2...2 {
                let px = x + dx, py = y + dy
                guard px >= 0, px < width, py >= 0, py < height else { continue }
                let confidenceValue = cBase.advanced(by: py * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)[px]
                guard confidenceValue == ARConfidenceLevel.high.rawValue else { continue }
                let mx = min(mw - 1, px * mw / width), my = min(mh - 1, py * mh / height)
                let person = mBase.advanced(by: my * CVPixelBufferGetBytesPerRow(mask)).assumingMemoryBound(to: UInt8.self)[mx]
                guard person > 127 else { continue }
                values.append(dBase.advanced(by: py * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float32.self)[px])
            }
        }
        return PeopleTrackingMath.robustDepth(values)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        tracker = PersonTracker()
        deliver?(PeopleFrame(status: "센서가 중단되었습니다 · 다시 시작해주세요", requiresRestart: true))
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        tracker = PersonTracker()
        deliver?(PeopleFrame(status: "센서 중단 종료 · 다시 시작해주세요", requiresRestart: true))
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        deliver?(PeopleFrame(status: "센서 오류 · 다시 시작해주세요", requiresRestart: true))
    }
}

@MainActor
enum PeopleTrackingController {
    static let semantics: ARConfiguration.FrameSemantics = [.sceneDepth, .personSegmentation]
}
