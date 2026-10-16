import ARKit
import HearIAmCore

struct CameraSample {
    let time: Double
    let world: Point3
    let forward: Point3
    let normal: Bool
    let tracking: String
    let mapped: Bool
    let mapping: String
    let anchors: [String: Point3]
    init(_ frame: ARFrame) {
        time=frame.timestamp
        let t=frame.camera.transform
        world=Point3(SIMD3(t.columns.3.x,t.columns.3.y,t.columns.3.z))
        forward=Point3(-SIMD3(t.columns.2.x,t.columns.2.y,t.columns.2.z))
        switch frame.camera.trackingState {
        case .normal: normal=true; tracking="normal"
        case .notAvailable: normal=false; tracking="notAvailable"
        case .limited(let reason): normal=false; tracking="limited: \(reason)"
        }
        mapped=frame.worldMappingStatus == .mapped
        switch frame.worldMappingStatus {
        case .notAvailable: mapping="공간 인식 준비 중"
        case .limited: mapping="공간을 더 비춰주세요"
        case .extending: mapping="스캔 범위를 넓히고 있어요"
        case .mapped: mapping="공간 지도 안정됨"
        @unknown default: mapping="공간 확인 중"
        }
        anchors=Dictionary(frame.anchors.compactMap { anchor -> (String,Point3)? in
            guard let name=anchor.name, name.hasPrefix("PoC4.reference.") else { return nil }
            let p=anchor.transform.columns.3
            return (name,Point3(Double(p.x),Double(p.y),Double(p.z)))
        },uniquingKeysWith: {a,_ in a})
    }
}
