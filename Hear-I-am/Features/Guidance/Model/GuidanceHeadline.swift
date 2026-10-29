import Foundation
import HearIAmCore

/// Symbol, title and detail text shown for the current guidance phase.
struct GuidanceHeadline {
    let symbol: String
    let title: String
    let detail: String

    init(startAlignment: StartAlignment) {
        symbol=startAlignment.state == .waiting ? "timer" : "location.north"
        title=startAlignment.state == .waiting ? "출발점 · 자동 시작 대기" : "출발점 · 첫 경로점 방향 맞추기"
        detail=startAlignment.state == .waiting ? "\(Int(ceil(startAlignment.remaining)))초 후 안내 시작" : "그 자리에서 좌우 안내에 따라 몸을 돌려주세요."
    }
    init(facing: StageFacing, pointName: String) {
        symbol="arrow.triangle.turn.up.right.circle"
        title="\(pointName) · 바라볼 방향 맞추기"
        detail="그 자리에서 \(facing.label) 방향을 바라봐주세요."
    }
    init(holdingSeconds: Double, pointName: String) {
        symbol="speaker.slash"
        title="\(pointName) · 공연 대기 중"
        detail="다음 지점 안내까지 \(Int(ceil(holdingSeconds)))초"
    }
    init(phase: GuidancePhase, targetName: String, hasStarted: Bool, departureReady: Bool, departureStatus: String,
         arrivedName: String?, cue: GuidanceCue?, message: String) {
        switch phase {
        case .approaching,.guiding: symbol=cue?.symbol ?? "location.north"
        case .paused: symbol="pause.circle"
        case .interrupted,.failed: symbol="exclamationmark.circle"
        case .finishing,.completed: symbol="checkmark.circle"
        case .departure: symbol=departureReady ? "checkmark.circle" : "location.circle"
        default: symbol="speaker.wave.2"
        }
        switch phase {
        case .wear: title="휴대폰을 허리 앞에\n세로로 고정해주세요"
        case .departure: title=departureReady ? "\(hasStarted ? "재개" : "출발") 준비가\n완료됐어요" : "\(hasStarted ? "저장한 동선 위에서" : "지정한 출발점에서")\n준비해주세요"
        case .approaching: title="출발점으로 이동해요"
        case .starting: title="안내를 시작할게요"
        case .guiding: title=arrivedName.map {"\($0)에 도착했어요"} ?? cue?.direction ?? "\(targetName)으로 이동해요"
        case .paused: title="안내를\n일시정지했어요"
        case .interrupted: title="잠시 멈춰주세요"
        case .failed: title="공연장을\n확인하지 못했어요"
        case .finishing: title="마지막 지점에\n도착했어요"
        case .completed: title="모든 동선을\n완료했어요"
        default: title=""
        }
        switch phase {
        case .wear: detail="고정하기 전에 방해 금지 모드를 켜주세요. 후면 카메라는 몸 바깥쪽으로, 렌즈가 가려지지 않게 해주세요."
        case .departure: detail=departureReady ? "하단 버튼을 누르면 \(targetName)으로 안내해요." : departureStatus
        case .approaching: detail=cue.map {"\($0.direction) · " + String(format:"%.1f m",$0.distance)} ?? "현재 위치를 확인 중이에요."
        case .starting: detail="시작 음성이 끝나면 소리로 방향을 알려드려요."
        case .guiding: detail=cue.map {arrivedName != nil ? "다음 지점 · \($0.direction) " + String(format:"%.1f m",$0.distance) : String(format:"%.1f m",$0.distance)} ?? "위치 확인 중"
        default: detail=message
        }
    }
}
