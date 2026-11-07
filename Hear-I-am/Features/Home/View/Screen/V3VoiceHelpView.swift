import SwiftUI

/// 「음성으로 사용하기」 (Figma 971:23463): how to call the app, what to say while practising, and the way
/// round it when speaking does not work.
struct V3VoiceHelpView: View {
    private let title = "음성으로 사용하기"
    private let sections = [
        SettingsInfo(title: "부르고, 듣고, 말해요", rows: [
            .init(icon: "mic", text: "“Hear I am”을 부르거나 홈의 흰 원을 눌러요."),
            .init(text: "공연 이름이나 공연장 이름을 한국어로 말해주세요. 준비 대화에서는 다시 부르지 않고 답할 수 있어요."),
        ]),
        SettingsInfo(title: "연습 중 요청", rows: [
            .init(text: "“Hear I am”을 부른 뒤 “잠깐 멈춰”, “계속”, “P1으로 돌아가”처럼 요청해요. 돌아갈 수 있는 지점은 이미 지나온 경로 안에서 확인해요."),
        ]),
        SettingsInfo(title: "실전에서는 마이크가 꺼져요", rows: [
            .init(text: "안내가 시작되면 호출어를 듣지 않아요. 화면의 일시정지 버튼을 사용해주세요."),
        ]),
        SettingsInfo(title: "음성 사용이 어려울 때", rows: [
            .init(text: "화면의 목록과 버튼으로 진행할 수 있어요. VoiceOver를 사용하면 항목을 선택한 뒤 두 번 탭해주세요."),
        ]),
    ]

    var body: some View {
        SettingsInfoPage(sections: sections) { EmptyView() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .settingsScreen()
            .accessibilityIdentifier("settings.help.voice")
            .readsAloud(title: title) { [title] + SettingsInfo.lines(sections) }
    }
}

#Preview {
    NavigationStack {
        V3VoiceHelpView()
    }
}
