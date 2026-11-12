import Foundation
import HearIAmCore

/// Symbol, title and detail text shown for the current guidance phase.
struct GuidanceHeadline {
    let symbol: String
    let title: String
    let detail: String

    init(title: String, detail: String, symbol: String) {
        self.title=title;self.detail=detail;self.symbol=symbol
    }
    init(facing: StageFacing, pointName: String) {
        symbol="arrow.triangle.turn.up.right.circle"
        title=L("%@ · 바라볼 방향 맞추기", pointName)
        detail=L("그 자리에서 %@ 방향을 바라봐주세요.", facing.label)
    }
    init(holdingSeconds: Double, pointName: String) {
        symbol="speaker.slash"
        title=L("%@ · 공연 대기 중", pointName)
        detail=L("다음 지점 안내까지 %@초", Int(ceil(holdingSeconds)))
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
        case .wear: title=L("휴대폰을 허리 앞에\n세로로 고정해주세요")
        case .departure: title=departureReady ? (hasStarted ? L("재개 준비가\n완료됐어요") : L("출발 준비가\n완료됐어요")) : (hasStarted ? L("저장한 동선 위에서\n준비해주세요") : L("지정한 출발점에서\n준비해주세요"))
        case .approaching: title=L("출발점으로 이동해요")
        case .starting: title=L("안내를 시작할게요")
        case .guiding: title=arrivedName.map {L("%@에 도착했어요", $0)} ?? cue?.direction ?? L("%@으로 이동해요", targetName)
        case .paused: title=L("안내를\n일시정지했어요")
        case .interrupted: title=L("잠시 멈춰주세요")
        case .failed: title=L("공연장을\n확인하지 못했어요")
        case .finishing: title=L("마지막 지점에\n도착했어요")
        case .completed: title=L("모든 동선을\n완료했어요")
        default: title=""
        }
        switch phase {
        case .wear: detail=L("고정하기 전에 방해 금지 모드를 켜주세요. 후면 카메라는 몸 바깥쪽으로, 렌즈가 가려지지 않게 해주세요.")
        case .departure: detail=departureReady ? L("하단 버튼을 누르면 %@으로 안내해요.", targetName) : departureStatus
        case .approaching: detail=cue.map {"\($0.direction) · " + String(format:"%.1f m",$0.distance)} ?? L("현재 위치를 확인 중이에요.")
        case .starting: detail=L("시작 음성이 끝나면 소리로 방향을 알려드려요.")
        case .guiding: detail=cue.map {arrivedName != nil ? L("다음 지점 · %@ ", $0.direction) + String(format:"%.1f m",$0.distance) : String(format:"%.1f m",$0.distance)} ?? L("위치 확인 중")
        default: detail=message
        }
    }
}
