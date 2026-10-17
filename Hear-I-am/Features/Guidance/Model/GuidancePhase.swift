import Foundation

/// Portrait guidance flow: select → restore → checkpoint → wear → departure → guiding → completed.
enum GuidancePhase {
    case selection, restoring, checkpoint, wear, countdown, departure, starting, guiding, aligning, paused, interrupted, failed, finishing, completed

    /// Phases that show the live route camera under a compact header.
    var showsRouteCamera: Bool { [.starting,.guiding,.aligning,.paused,.finishing,.completed].contains(self) }
    /// Phases where the wearer aims the phone by hand.
    var isCameraStep: Bool { self == .restoring || self == .checkpoint }

    func stepLabel(targetName: String) -> String {
        switch self {
        case .selection:return "1 / 4 · 무대 선택"
        case .restoring,.checkpoint,.failed:return "2 / 4 · 현장 확인"
        case .wear,.countdown:return "3 / 4 · 허리띠 착용"
        case .departure,.starting:return "4 / 4 · 출발 준비"
        case .guiding:return "안내 중 · \(targetName)"
        case .paused:return "안내 일시정지"
        case .aligning:return "카메라 방향 교정 중"
        case .interrupted:return "안내 중단 · 재확인 필요"
        case .finishing,.completed:return "안내 완료"
        }
    }
}
