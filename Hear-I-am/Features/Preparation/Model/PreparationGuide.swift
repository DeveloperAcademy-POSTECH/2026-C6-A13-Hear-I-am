import Foundation
import HearIAmCore

/// Title and description of the collapsible guide card for the current step.
struct PreparationGuide {
    let title: String
    let description: String

    init(step: PreparationStep, draft: PreparationDraft, nextCorner: Int?, objectEditing: Bool, pendingVertexCount: Int) {
        let names=PreparationStep.cornerNames
        switch step {
        case .scan:
            title="공간을 천천히 둘러보세요"
            description="휴대폰을 양손으로 잡고 공연장과 백스테이지까지 충분히 담아주세요."
        case .boundary:
            title=nextCorner.map {"무대 \(names[$0])을 지정해주세요"} ?? "네 모서리가 연결됐어요"
            if nextCorner == 2, draft.corners[0] != nil, draft.corners[1] != nil, draft.corners[3] != nil {
                description="청록색 점선은 뒤 왼쪽에서 뒤 오른쪽으로 향하는 임시 가이드예요. 실제 바닥의 뒤 오른쪽 모서리를 직접 찍어주세요."
            } else {
                description="객석 기준 앞 오른쪽 → 앞 왼쪽 → 뒤 왼쪽 → 뒤 오른쪽 순서예요. 점선은 임시 방향 가이드이며 네 모서리는 직접 찍어주세요."
            }
        case .objects:
            title=objectEditing ? "기물의 바닥 둘레를 지정해주세요" : "장애물과 의자을 등록하세요"
            description=objectEditing ? "스캔 면 위에서 십자선을 물체 주변 바닥 모서리에 맞추고 ‘둘레 점 추가’를 누르세요. 한 방향으로 3~8점을 찍고 등록하면 자동으로 닫힙니다. 현재 \(pendingVertexCount)/8점 · 윗면은 찍지 않아요." : "‘기물 추가’ 후 바닥 둘레를 직접 찍어요. 사각형은 네 모서리를 순서대로 지정하세요. 기물이 없으면 건너뛰세요."
        case .route:
            title=draft.routeFinished ? "경로가 연결됐어요" : (draft.route.isEmpty ? "출발점을 지정해주세요" : "다음 위치를 지정해주세요")
            description="출발·도착은 같은 높이의 무대 밖도 가능해요. 내부 지점은 무대 안 바닥 또는 등록한 의자·계단 윗면에 지정하세요. 승하강은 허용한 변으로만 가능해요. 빨간 영역은 장애물에서 \(Int((draft.effectiveObstacleClearance*100).rounded()))cm 여유라 지나갈 수 없어요. \(draft.route.count)/6점"
        case .checkpoint:
            title=draft.checkpoint == nil ? "확인점 한 개를 지정해주세요" : "확인점을 지정했어요"
            description="특징적인 바닥이나 고정된 기물이 바닥과 만나는 경계를 선택하세요. 둘레 오차는 안쪽 5cm까지 허용해요. 무대 모서리에서 0.5m 이상 떨어져야 해요."
        }
    }
}
