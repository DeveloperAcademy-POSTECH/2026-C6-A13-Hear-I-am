import Foundation
import HearIAmCore

/// Symbol, title and detail text shown for the current guidance phase.
struct GuidanceHeadline {
    let symbol: String
    let title: String
    let detail: String

    init(phase: GuidancePhase, targetName: String, hasStarted: Bool, departureReady: Bool, departureStatus: String,
         arrivedName: String?, cue: GuidanceCue?, message: String) {
        switch phase {
        case .guiding: symbol=cue?.symbol ?? "location.north"
        case .paused: symbol="pause.circle"
        case .interrupted,.failed: symbol="exclamationmark.circle"
        case .finishing,.completed: symbol="checkmark.circle"
        case .departure: symbol=departureReady ? "checkmark.circle" : "location.circle"
        default: symbol="speaker.wave.2"
        }
        switch phase {
        case .wear: title="휴대폰을 허리 앞에\n세로로 고정해주세요"
        case .countdown: title="천천히 착용해주세요"
        case .departure: title=departureReady ? "\(hasStarted ? "재개" : "출발") 준비가\n완료됐어요" : "\(hasStarted ? "저장한 동선 위에서" : "지정한 출발점에서")\n준비해주세요"
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
        case .wear: detail="후면 카메라는 몸 바깥쪽으로, 렌즈가 가려지지 않게 해주세요."
        case .countdown: detail="착용 시간이 끝나면 위치와 방향을 확인해요."
        case .departure: detail=departureReady ? "하단 버튼을 누르면 \(targetName)으로 안내해요." : departureStatus
        case .starting: detail="높은 비프는 왼쪽, 낮은 비프는 오른쪽이에요. 맞출수록 3·2·1번, 정렬되면 띠링 후 조용해져요."
        case .guiding: detail=cue.map {arrivedName != nil ? "다음 지점 · \($0.direction) " + String(format:"%.1f m",$0.distance) : String(format:"%.1f m",$0.distance)} ?? "위치 확인 중"
        default: detail=message
        }
    }
}
