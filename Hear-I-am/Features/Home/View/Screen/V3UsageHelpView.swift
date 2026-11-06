import SwiftUI

struct V3UsageHelpView: View {
    @ScaledMetric(relativeTo: .title2) private var headingSize: CGFloat = 24

    private let title = "착용과 안내준비"
    private let heading = "몸 앞에 안정적으로 고정해요"
    private let beltDescription = "러닝밴드를 허리에 착용하고, 휴대폰을 몸 앞쪽에 세로로 단단히 고정해주세요."
    private let handheldDescription = "임시로 배꼽 앞에 휴대폰을 세로로 들고, 위치와 방향을 일정하게 유지해주세요."
    private let cameraHeading = "후면 카메라는 몸이 향한 방향으로"
    private let cameraDescription = "카메라가 밴드나 옷에 가려지지 않게 해주세요."
    private let positionDescription = "착용 위치를 바꿨다면 안내를 멈추고 위치와 방향을 다시 확인해주세요."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(heading)
                    .font(.system(size: headingSize, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                WearingHelpCard(
                    title: "러닝밴드가 있어요",
                    image: "WearingBeltPortrait",
                    description: beltDescription
                )

                WearingHelpCard(
                    title: "러닝밴드가 없어요",
                    image: "WearingHandheldPortrait",
                    description: handheldDescription
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(cameraHeading)
                        .font(.body.weight(.medium))
                        .accessibilityAddTraits(.isHeader)
                    Text(cameraDescription)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .fixedSize(horizontal: false, vertical: true)

                Text(positionDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink {
                    SoundOutputView()
                } label: {
                    SettingsHelpCapsuleLabel(title: "소리 확인하기")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.help.wearing.sound")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsScreen()
        .accessibilityIdentifier("settings.help.wearing")
        .readsAloud {
            [title, heading,
             "러닝밴드가 있어요", beltDescription,
             "러닝밴드가 없어요", handheldDescription,
             cameraHeading, cameraDescription, positionDescription,
             "소리 확인하기 버튼"]
        }
    }
}

private struct WearingHelpCard: View {
    let title: String
    let image: String
    let description: String
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 18

    var body: some View {
        SettingsGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: titleSize, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Color.clear
                    .aspectRatio(330.0 / 230.0, contentMode: .fit)
                    .overlay {
                        Image(image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .accessibilityHidden(true)

                Text(description)
                    .font(.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A settings capsule that grows with the help page’s text size.
struct SettingsHelpCapsuleLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(SettingsStyle.darkText)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: SettingsStyle.buttonHeight)
            .background(.white, in: Capsule())
            .contentShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        V3UsageHelpView()
    }
}
