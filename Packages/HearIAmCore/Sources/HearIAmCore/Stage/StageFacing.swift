import Foundation

/// Stage-relative compass, not magnetic north. North faces the audience; east is the performer's right.
public enum StageFacing: String, Codable, CaseIterable, Sendable {
    case north, northEast, east, southEast, south, southWest, west, northWest
    public var headingDegrees: Double { Double(Self.allCases.firstIndex(of:self)!) * 45 }
    public var label: String {
        switch self {
        case .north: return "북 · 무대 앞"
        case .northEast: return "북동 · 오른쪽 앞"
        case .east: return "동 · 오른쪽"
        case .southEast: return "남동 · 오른쪽 뒤"
        case .south: return "남 · 무대 뒤"
        case .southWest: return "남서 · 왼쪽 뒤"
        case .west: return "서 · 왼쪽"
        case .northWest: return "북서 · 왼쪽 앞"
        }
    }
    public func bearing(headingDegrees: Double) -> Double {
        HeadingMath.wrapDegrees(self.headingDegrees-headingDegrees)
    }
}
