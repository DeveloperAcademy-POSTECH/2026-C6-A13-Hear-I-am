import SwiftUI

struct V3VoiceHelpView: View {
    @ScaledMetric(relativeTo: .title2) private var headingSize: CGFloat = 24

    private let title = "음성으로 앱 사용하기"
    private let preparationHeading = "안내를 시작하기 전에"
    private let preparationDescription = "‘Hear I am’을 부른 뒤 원하는 내용을 말해주세요."
    private let examples = ["저장된 공연 알려줘", "라이온 킹 공연 찾아줘"]
    private let guidanceHeading = "안내가 진행 중일 때"
    private let guidanceDescription = "실전 안내 중에는 마이크가 꺼져요. 안내를 시작하기 전 준비 상태에서는 말로 요청할 수 있어요."
    private let permissionHeading = "음성 인식이 안 되나요?"
    private let permissionDescription = "마이크와 음성 인식 권한을 확인해주세요."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(preparationHeading)
                        .font(.system(size: headingSize, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(preparationDescription)
                        .font(.body)
                        .lineSpacing(4)
                    SettingsGroup {
                        ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                            if index > 0 { SettingsDivider() }
                            SettingsRowLabel(title: example, accessory: .none, adaptsToDynamicType: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(guidanceHeading)
                        .font(.title3.weight(.medium))
                        .accessibilityAddTraits(.isHeader)
                    SettingsGroup {
                        Text(guidanceDescription)
                            .font(.body)
                            .lineSpacing(4)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(permissionHeading)
                        .font(.title3.weight(.medium))
                        .accessibilityAddTraits(.isHeader)
                    Text(permissionDescription)
                        .font(.body)
                        .lineSpacing(4)
                    SettingsGroup {
                        NavigationLink {
                            V3PermissionView()
                        } label: {
                            SettingsRowLabel(title: "앱 접근 권한 확인", adaptsToDynamicType: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.help.voice.permissions")
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsScreen()
        .accessibilityIdentifier("settings.help.voice")
        .readsAloud {
            [title, preparationHeading,
             preparationDescription.replacingOccurrences(of: "Hear I am", with: "히어 아이 엠")]
            + examples
            + [guidanceHeading, guidanceDescription,
               permissionHeading, permissionDescription, "앱 접근 권한 확인 버튼"]
        }
    }
}

#Preview {
    NavigationStack {
        V3VoiceHelpView()
    }
}
