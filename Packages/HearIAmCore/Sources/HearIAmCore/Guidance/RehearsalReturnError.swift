import Foundation

/// Rehearsal is allowed only on the already visited route and on valid, directed passages.
public enum RehearsalReturnError: Error, LocalizedError, Equatable, Sendable {
    case unavailable
    case trackingUnavailable
    case unvisitedDestination
    case positionUnsafe(GuidePauseReason)
    case blockedByObstacle(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "현재는 지점 복귀를 시작할 수 없어요. 진행 중인 복귀를 마치거나 안내 상태를 확인해주세요."
        case .trackingUnavailable:
            return "현재 위치와 방향을 확인할 수 없어요. 확인점을 다시 확인해주세요."
        case .unvisitedDestination:
            return "이미 도착했던 내부 지점으로만 돌아갈 수 있어요. 출발점과 마지막 도착점은 이번 실험에서 지원하지 않아요."
        case .positionUnsafe(.obstacleProximity):
            return "등록한 기물과 가까워 복귀를 시작할 수 없어요. 현재 위치와 동선을 확인해주세요."
        case .positionUnsafe:
            return "현재 위치가 확인된 동선 위에 있지 않아 복귀를 시작할 수 없어요. 위치를 다시 확인해주세요."
        case .blockedByObstacle(let name):
            return "\(name)의 통과 방향 또는 여유 공간 때문에 이 경로로 돌아갈 수 없어요. 조력자와 복귀 경로를 확인해주세요."
        }
    }
}
