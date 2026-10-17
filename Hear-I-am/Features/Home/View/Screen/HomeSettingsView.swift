import SwiftUI
import HearIAmCore

struct HomeSettingsView: View {
    @AppStorage(GuidanceInteractionSettings.advanceDuringSpeechKey) private var advanceDuringSpeech=false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("음성 안내 중 다음 단계 진행",isOn:$advanceDuringSpeech)
                } header: { Text("음성 안내") }
                footer: {
                    Text("켜면 설명이 끝나기 전에도 다음 단계 버튼을 누를 수 있어요. 넘어가면 이전 설명은 멈춥니다. 위치와 확인점 검증은 그대로 필요하며, 착용 카운트다운과 마지막 종료 안내는 끝까지 진행됩니다.")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.confirmationAction) { Button("완료") {dismiss()} } }
        }
    }
}
