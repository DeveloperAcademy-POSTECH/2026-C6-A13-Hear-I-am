import SwiftUI

/// 「착용과 안내 준비」 (Figma 971:23464): three cards of short steps, then 「소리 확인하기」.
struct V3UsageHelpView: View {
    private let title = "착용과 안내 준비"
    private let sections = [
        SettingsInfo(title: "몸에 맞춰 준비해요", rows: [
            .init(icon: "iphone", text: "iPhone을 허리 앞쪽에 단단히 고정해주세요."),
            .init(icon: "camera", text: "후면 카메라가 바깥쪽을 향하고 가려지지 않게 해주세요."),
            .init(icon: "speaker.wave.2", text: "사용할 이어폰이나 스피커로 시험 소리를 들어주세요."),
        ]),
        SettingsInfo(title: "연습과 실전", rows: [
            .init(text: "연습용은 저장한 공간을 제자리에서 둘러보며 찾고, 착용한 현재 위치에서 P1으로 안내해요."),
            .init(text: "실전용은 조력자와 공간·확인점 두 곳·출발 위치를 확인한 뒤 안내를 시작해요."),
        ]),
        SettingsInfo(title: "착용 위치를 바꿨다면", rows: [
            .init(text: "먼저 안내를 일시정지하고, 휴대폰 고정과 현재 위치·몸 방향을 다시 확인해주세요."),
        ]),
    ]

    var body: some View {
        SettingsInfoPage(sections: sections) {
            NavigationLink {
                SoundOutputView()
            } label: {
                SettingsPlainCapsuleLabel(title: "소리 확인하기", chevron: true)
            }
            .buttonStyle(.plain)
            .readAloudTarget("소리 확인하기 버튼")
            .accessibilityIdentifier("settings.help.wearing.sound")
            .padding(.top, 8)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsScreen()
        .accessibilityIdentifier("settings.help.wearing")
        .readsAloud(title: title) {
            [title] + SettingsInfo.lines(sections) + ["소리 확인하기 버튼"]
        }
    }
}

// MARK: - Shared parts of the help pages (971:23464 · 23463 · 23466)

/// One captioned card of a help page. Each row may carry a symbol on its left.
struct SettingsInfo: Identifiable {
    struct Row: Identifiable {
        var icon: String? = nil
        let text: String
        /// A second, dimmer line under the text (the permission rows).
        var detail: String? = nil
        var id: String { text }
        /// What the read-aloud voice says for this row; 「Hear I am」 is spelled out so it is not read letter by letter.
        var spoken: String {
            ([text] + [detail].compactMap { $0 }).joined(separator: ". ")
                .replacingOccurrences(of: "Hear I am", with: "히어 아이 엠")
        }
    }
    let title: String
    let rows: [Row]
    var id: String { title }
    /// The read-aloud lines of these sections, in the order they are drawn.
    static func lines(_ sections: [SettingsInfo]) -> [String] {
        sections.flatMap { [$0.title] + $0.rows.map(\.spoken) }
    }
}

/// A help page: 17pt semibold captions over dark cards, 28pt apart, then whatever comes after them.
struct SettingsInfoPage<Footer: View>: View {
    let sections: [SettingsInfo]
    @ViewBuilder let footer: Footer
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .readAloudTarget(section.title)
                            .padding(.leading, 16)
                            .accessibilityAddTraits(.isHeader)
                        SettingsGroup {
                            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 {
                                    SettingsInfoDivider(leading: row.icon == nil && section.rows[index - 1].icon == nil ? 16 : 57)
                                }
                                SettingsInfoRow(row: row)
                            }
                        }
                    }
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
}

/// Text at 17pt, 16pt in from the card; with a symbol, the symbol sits in a 24pt column and the text 57pt in.
struct SettingsInfoRow: View {
    let row: SettingsInfo.Row
    var body: some View {
        HStack(alignment: .center, spacing: 17) {
            if let icon = row.icon {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(row.text)
                    .font(.system(size: 17, weight: row.detail == nil ? .regular : .semibold))
                    .lineSpacing(3)
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 15))
                        .foregroundStyle(SettingsStyle.secondary)
                        .lineSpacing(2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, row.detail == nil ? 15 : 22)
        .readAloudTarget(row.spoken)
        .accessibilityElement(children: .combine)
    }
}

/// The hairline between rows, from where the row's text starts to 16pt short of the card's edge.
struct SettingsInfoDivider: View {
    let leading: CGFloat
    var body: some View {
        Rectangle().fill(SettingsStyle.separator).frame(height: 1 / UIScreen.main.scale * 2)
            .padding(.leading, leading).padding(.trailing, 16).accessibilityHidden(true)
    }
}

/// A 52pt dark capsule holding one plain line, as 「소리 확인하기」 and 「iPhone 설정 열기」.
struct SettingsPlainCapsuleLabel: View {
    let title: String
    var chevron = false
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(chevron ? .white.opacity(0.85) : .white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsStyle.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(SettingsStyle.group, in: Capsule())
        .contentShape(Capsule())
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
