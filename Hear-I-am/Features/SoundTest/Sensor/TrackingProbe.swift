import ARKit

/// A bare world-tracking session that reports how much the phone position jitters.
/// Used to see whether waist vibration disturbs ARKit tracking. Keep the phone still while measuring.
@MainActor final class TrackingProbe: NSObject, ARSessionDelegate {
    private let session=ARSession()
    private var samples: [(time: Double, position: SIMD3<Float>)]=[]
    private(set) var running=false
    /// (tracking state, largest distance from the 1-second mean in cm)
    var onUpdate: ((String,Double?)->Void)?

    func start() {
        guard ARWorldTrackingConfiguration.isSupported, !running else { return }
        samples=[];running=true
        session.delegate=self
        session.run(ARWorldTrackingConfiguration(),options:[.resetTracking])
    }
    func stop() { session.pause();running=false;samples=[] }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let state=Self.describe(frame.camera.trackingState), time=frame.timestamp
        let t=frame.camera.transform.columns.3, position=SIMD3<Float>(t.x,t.y,t.z)
        Task { @MainActor in receive(state:state,time:time,position:position) }
    }
    private func receive(state: String, time: Double, position: SIMD3<Float>) {
        guard running else { return }
        samples.append((time,position));samples.removeAll { time-$0.time > 1 }
        let mean=samples.reduce(SIMD3<Float>()) { $0+$1.position }/Float(samples.count)
        let spread=samples.map { simd_distance($0.position,mean) }.max() ?? 0
        onUpdate?(state,samples.count > 10 ? Double(spread)*100 : nil)
    }
    nonisolated static func describe(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: return "정상"
        case .notAvailable: return "사용 불가"
        case .limited(let reason):
            switch reason {
            case .initializing: return "제한 · 준비 중"
            case .excessiveMotion: return "제한 · 너무 많이 움직임"
            case .insufficientFeatures: return "제한 · 특징점 부족"
            case .relocalizing: return "제한 · 위치 다시 찾는 중"
            @unknown default: return "제한"
            }
        }
    }
}
