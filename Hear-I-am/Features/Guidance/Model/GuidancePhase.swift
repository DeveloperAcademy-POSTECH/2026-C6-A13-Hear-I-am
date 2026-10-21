import Foundation

/// Portrait guidance flow: select → restore → checkpoint → wear → departure → guiding → completed.
enum GuidancePhase {
    case selection, restoring, checkpoint, wear, departure, starting, guiding, paused, interrupted, failed, finishing, completed

    /// Phases that show the live route camera under a compact header.
    var showsRouteCamera: Bool { [.starting,.guiding,.paused,.finishing,.completed].contains(self) }
    /// Phases that keep the camera visible behind a translucent instruction, so the saved route
    /// stays in sight after the checkpoint (field test 10/17: it looked like the route vanished).
    var showsCameraBehindInstruction: Bool { [.wear,.departure].contains(self) }
    /// Phases where the wearer aims the phone by hand.
    var isCameraStep: Bool { self == .restoring || self == .checkpoint }

    func stepLabel(targetName: String) -> String {
        switch self {
        case .selection:return "1 / 4 · 무대 선택"
        case .restoring,.checkpoint,.failed:return "2 / 4 · 현장 확인"
        case .wear:return "3 / 4 · 허리띠 착용"
        case .departure,.starting:return "4 / 4 · 출발 준비"
        case .guiding:return "안내 중 · \(targetName)"
        case .paused:return "안내 일시정지"
        case .interrupted:return "안내 중단 · 재확인 필요"
        case .finishing,.completed:return "안내 완료"
        }
    }
}
