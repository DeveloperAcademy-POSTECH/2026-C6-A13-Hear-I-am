import SwiftUI

struct V3SoundHelpView: View {
    @ScaledMetric(relativeTo: .title2) private var headingSize: CGFloat = 24

    private let title = "소리가 들리지 않을 때"
    private let heading = "어떤 문제가 있나요?"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(heading)
                    .font(.system(size: headingSize, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                ForEach(SoundHelpQuestion.all) { question in
                    SettingsGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(question.title)
                                .font(.body.weight(.medium))
                                .accessibilityAddTraits(.isHeader)

                            Rectangle()
                                .fill(SettingsStyle.separator)
                                .frame(height: 0.5)
                                .accessibilityHidden(true)

                            Text(question.answer)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineSpacing(4)

                            if question.opensSoundOutput {
                                NavigationLink {
                                    SoundOutputView()
                                } label: {
                                    SettingsRowLabel(title: "소리 출력 열기", adaptsToDynamicType: true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("출력 기기와 음량을 확인해요")
                                .accessibilityIdentifier("settings.help.sound.output.\(question.id)")
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsScreen()
        .accessibilityIdentifier("settings.help.sound")
        .readsAloud {
            [title, heading] + SoundHelpQuestion.all.flatMap { question in
                [question.title, question.answer]
                    .map { $0.replacingOccurrences(of: "VoiceOver", with: "보이스오버") }
                + (question.opensSoundOutput ? ["소리 출력 열기 버튼"] : [])
            }
        }
    }
}

private struct SoundHelpQuestion: Identifiable {
    let id: Int
    let title: String
    let answer: String
    var opensSoundOutput = false

    static let all: [SoundHelpQuestion] = [
        .init(
            id: 1,
            title: "소리가 전혀 들리지 않아요",
            answer: "소리가 나오는 기기를 확인해주세요. 원하는 기기로 연결한 뒤, 음량을 높이고 테스트 소리를 들어보세요.",
            opensSoundOutput: true
        ),
        .init(
            id: 2,
            title: "이어폰을 연결했는데 휴대폰에서 소리가 나요",
            answer: "이어폰 연결 상태를 확인해주세요. 재생 방식이 ‘항상 iPhone 스피커’라면 ‘연결된 기기로 자동’으로 바꿔주세요.",
            opensSoundOutput: true
        ),
        .init(
            id: 3,
            title: "소리가 너무 작아요",
            answer: "사용할 출력 기기를 연결한 상태에서 테스트 소리를 들으며 음량을 조절해주세요.",
            opensSoundOutput: true
        ),
        .init(
            id: 4,
            title: "테스트 소리는 들리는데 이동 안내가 나오지 않아요",
            answer: "사용할 공연과 장면을 선택하고 안내를 시작했는지 확인해주세요. 안내가 멈춰 있다면 준비 상태와 현재 위치를 확인해주세요."
        ),
        .init(
            id: 5,
            title: "잘 들리다가 갑자기 소리가 나오지 않아요",
            answer: "이동 중이라면 먼저 멈춰주세요. 이어폰의 연결과 배터리, 현재 출력 기기를 확인한 뒤 테스트 소리를 다시 들어보세요.",
            opensSoundOutput: true
        ),
        .init(
            id: 6,
            title: "안내 음성과 VoiceOver가 겹쳐 들려요",
            answer: "이동 중이라면 먼저 제자리에 멈춰주세요. 화면을 두 손가락으로 한 번 탭하면 VoiceOver 읽기를 잠시 멈출 수 있어요. 한 번 더 탭하면 읽기를 이어갈 수 있어요."
        ),
        .init(
            id: 7,
            title: "이동 안내를 놓쳤어요",
            answer: "먼저 제자리에 멈추고 안내를 일시정지해주세요. 이동 방향이 확실하지 않다면 조력자와 현재 위치와 다음 이동 방향을 확인해주세요.\n\n준비가 되면 안내를 재개해주세요. ‘공간 다시 찾기’나 ‘확인점 다시 확인’을 진행하면 중단한 지점부터 안내를 이어서 받을 수 있어요."
        )
    ]
}

#Preview {
    NavigationStack {
        V3SoundHelpView()
    }
}
