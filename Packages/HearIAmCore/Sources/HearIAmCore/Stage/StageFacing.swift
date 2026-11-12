import Foundation

/// Stage-relative compass, not magnetic north. North faces the audience; east is the performer's right.
public enum StageFacing: String, Codable, CaseIterable, Sendable {
    case north, northEast, east, southEast, south, southWest, west, northWest
    public var headingDegrees: Double { Double(Self.allCases.firstIndex(of:self)!) * 45 }
    public var label: String {
        switch self {
        case .north: return L("북 · 무대 앞")
        case .northEast: return L("북동 · 오른쪽 앞")
        case .east: return L("동 · 오른쪽")
        case .southEast: return L("남동 · 오른쪽 뒤")
        case .south: return L("남 · 무대 뒤")
        case .southWest: return L("남서 · 왼쪽 뒤")
        case .west: return L("서 · 왼쪽")
        case .northWest: return L("북서 · 왼쪽 앞")
        }
    }
    public func bearing(headingDegrees: Double) -> Double {
        HeadingMath.wrapDegrees(self.headingDegrees-headingDegrees)
    }
}
