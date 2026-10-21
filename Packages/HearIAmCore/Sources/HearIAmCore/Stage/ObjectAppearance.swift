import Foundation

/// Display only. Never changes the obstacle footprint or passage policy.
public struct ObjectAppearance: Codable, Equatable, Sendable {
    public enum Model: String, Codable, CaseIterable, Sendable {
        case generic, chair, table, musicStand, microphone, speaker, monitor
        public var title: String {
            switch self {
            case .generic: return "기본 입체"
            case .chair: return "의자"
            case .table: return "테이블"
            case .musicStand: return "보면대"
            case .microphone: return "마이크"
            case .speaker: return "스피커"
            case .monitor: return "바닥 모니터"
            }
        }
        public var defaultHeight: Double {
            switch self {
            case .generic: return 0.5
            case .chair: return 0.85
            case .table: return 0.75
            case .musicStand: return 1.2
            case .microphone: return 1.5
            case .speaker: return 1.0
            case .monitor: return 0.35
            }
        }
        public init(from decoder: Decoder) throws {
            let value=try decoder.singleValueContainer().decode(String.self)
            self=Self(rawValue:value) ?? .generic
        }
    }
    public var model: Model
    /// 0 faces the audience; 90 faces stage right. Relative to the registered stage.
    public var headingDegrees: Double
    public init(model: Model = .generic, headingDegrees: Double = 0) {
        self.model=model; self.headingDegrees=headingDegrees
    }
    public func validate() throws {
        guard headingDegrees.isFinite else { throw LabError.invalid("기물 표시 방향이 올바르지 않습니다.") }
    }
}

/// Dimensions for a replaceable visual, independent of the authoritative collision polygon.
public struct ObjectPlacement: Equatable, Sendable {
    public let center: FloorPoint
    public let width: Double
    public let depth: Double
    public let height: Double
    public let measuredHeight: Bool
    public let appearance: ObjectAppearance
    public init(_ object: StageObstacle) {
        appearance=object.appearance ?? ObjectAppearance()
        let xs=object.vertices.map(\.x), ys=object.vertices.map(\.y)
        center=FloorPoint(((xs.min() ?? 0)+(xs.max() ?? 0))/2,((ys.min() ?? 0)+(ys.max() ?? 0))/2)
        let center=self.center
        let a=appearance.headingDegrees * .pi/180, c=cos(a), s=sin(a)
        // Convert stage floor (+back) to model coordinates (+front), then inverse yaw.
        let points=object.vertices.map { p -> FloorPoint in
            let x=p.x-center.x, z = -(p.y-center.y)
            return FloorPoint(c*x-s*z,s*x+c*z)
        }
        width=max(0.05,(points.map(\.x).max() ?? 0)-(points.map(\.x).min() ?? 0))
        depth=max(0.05,(points.map(\.y).max() ?? 0)-(points.map(\.y).min() ?? 0))
        measuredHeight=object.height.map { $0.isFinite && $0 > 0 } ?? false
        height=measuredHeight ? object.height! : (object.kind == .platform || object.kind == .stairs ? 0.2 : appearance.model.defaultHeight)
    }
}
