import SwiftUI
import WayDetectCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: SessionController
    @StateObject private var guidance = GuidanceService()
    var body: some View {
        Form {
            Section("안내") {
                Toggle("음성 안내", isOn: $store.settings.voice)
                Toggle("진동 알림", isOn: $store.settings.haptics)
                Text("방향은 시계 방향으로 짧게 안내합니다. 진동은 출발·회전·정지를 구분합니다.").font(.footnote).foregroundStyle(.secondary)
            }.disabled(session.isActive)
            Section("안내 시험") {
                ForEach(HapticCue.allCases.filter { $0 != .none }, id: \.self) { cue in
                    Button {
                        guidance.speak(.init(cue.exampleSpeech, haptic: cue), voice: store.settings.voice, haptics: store.settings.haptics)
                    } label: {
                        HStack { Text(cue.title); Spacer(); Text(cue.patternDescription).foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("guidance-preview-\(cue.rawValue)")
                }
            }.disabled(session.isActive || (!store.settings.voice && !store.settings.haptics))
            Section("POC 사용 조건") {
                Text("iPhone · 배 앞 세로 착용 · 화면 바깥쪽 · 실내 · 앱을 켜 둔 상태")
                Text("목표 걸음 후 목표 방향으로 1.5초 정지하면 도착으로 처리합니다. 정면을 새 12시로 설정하고 다음 방향이 맞으면 자동 출발합니다.")
                Text("지도·카메라·자기장 보정 없이 상대 회전을 추적합니다. 자동 도착은 실제 위치 확인이 아닙니다.")
                Text("방향이 틀리면 ‘방향 재설정’을 누르고 정면을 본 채 1초 멈추세요. 걸음은 유지되며, ‘출발’ 또는 ‘계속 걷기’를 눌러 이동합니다.")
                Text("추정 걸음은 느린 보행이나 작은 움직임에서 누락될 수 있고 몸의 흔들림을 걸음으로 셀 수 있습니다. iOS 걸음은 지연될 수 있습니다.")
                Text("수신 끊김과 큰 방향 이탈은 감지합니다. 천천히 누적되는 오차와 벨트에서 폰이 돌아가는 현상은 센서만으로 확정할 수 없습니다.")
            }.font(.subheadline)
            Section("데이터") {
                Text("기록은 기기에만 저장됩니다. 이전 버전 파일은 그대로 보존하고 POC v2 기록은 별도 폴더에 저장합니다.")
                Text("WayDetect POC 2 · 실기기 정확도 검증 중").foregroundStyle(.secondary)
                LabeledContent("앱 빌드", value: Bundle.main.object(forInfoDictionaryKey: "WayDetectBuildIdentifier") as? String ?? "확인 불가")
            }.font(.footnote)
        }.navigationTitle("설정")
            .onChange(of: store.settings) { _, _ in store.saveSettings() }
            .onDisappear { guidance.stop() }
    }
}
