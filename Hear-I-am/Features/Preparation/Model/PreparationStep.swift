import Foundation
import HearIAmCore

/// The five landscape preparation steps, in order. Scanning cannot be revisited once confirmed.
enum PreparationStep: Int, CaseIterable, Comparable {
    case scan, boundary, objects, route, checkpoint

    var title: String { [L("스캔하기"),L("무대 범위"),L("기물"),L("경로"),L("확인점")][rawValue] }
    var next: PreparationStep { PreparationStep(rawValue:min(rawValue+1,PreparationStep.checkpoint.rawValue))! }
    /// Corner names as seen from the audience, indexed like PreparationDraft.corners.
    static var cornerNames: [String] { [L("앞 왼쪽"),L("앞 오른쪽"),L("뒤 오른쪽"),L("뒤 왼쪽")] }

    static func < (a: PreparationStep, b: PreparationStep) -> Bool { a.rawValue < b.rawValue }
}

extension ObstacleKind {
    /// Name a new object starts with, and the kind label shown next to every object in the list.
    var defaultName: String {
        switch self {
        case .platform: return L("의자")
        case .stairs: return L("계단")
        case .box, .other: return L("기물")
        }
    }
}
