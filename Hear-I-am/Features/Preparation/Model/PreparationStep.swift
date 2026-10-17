import Foundation
import HearIAmCore

/// The five landscape preparation steps, in order. Scanning cannot be revisited once confirmed.
enum PreparationStep: Int, CaseIterable, Comparable {
    case scan, boundary, objects, route, checkpoint

    var title: String { ["스캔","무대 범위","장애물","경로","확인점"][rawValue] }
    var next: PreparationStep { PreparationStep(rawValue:min(rawValue+1,PreparationStep.checkpoint.rawValue))! }
    /// Corner names as seen from the audience, indexed like PreparationDraft.corners.
    static let cornerNames=["앞 왼쪽","앞 오른쪽","뒤 오른쪽","뒤 왼쪽"]

    static func < (a: PreparationStep, b: PreparationStep) -> Bool { a.rawValue < b.rawValue }
}

extension ObstacleKind {
    /// Name a new object starts with, and the kind label shown next to every object in the list.
    var defaultName: String {
        switch self {
        case .platform: return "단상"
        case .stairs: return "계단"
        case .box, .other: return "장애물"
        }
    }
}
