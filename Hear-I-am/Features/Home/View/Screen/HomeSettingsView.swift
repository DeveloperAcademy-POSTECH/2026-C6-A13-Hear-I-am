import SwiftUI
import HearIAmCore

struct HomeSettingsView: View {
    @AppStorage(HearAudioSession.speakerKey) private var forcesSpeaker=false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("폰 스피커로 듣기",isOn:$forcesSpeaker)
                } header: { Text("소리 출력") }
                footer: {
                    Text("켜면 에어팟이 연결돼 있어도 신호음과 음성이 폰 스피커로 나와요. 끄면 연결된 에어팟으로, 에어팟이 없으면 폰 스피커로 나와요.")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("완료") {dismiss()} } }
        }
    }
}
