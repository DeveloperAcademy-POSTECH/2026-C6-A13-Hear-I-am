import SwiftUI
import AVFoundation
import Speech
import CoreMotion

/// 「권한 상태」 (Figma 971:23466): each permission with its state and use, then 「iPhone 설정 열기」, which
/// opens this app's page in the Settings app (971:23465).
struct V3PermissionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var permissions = AppPermission.readCurrent()
    private let title = "권한 상태"
    private let note = "마이크 권한이 없어도 조력자의 공연 관리와 버튼 조작은 사용할 수 있어요."
    private var sections: [SettingsInfo] {
        [SettingsInfo(title: "필요한 권한을 확인해요", rows: permissions.map {
            .init(icon: $0.icon, text: "\($0.title) · \($0.status)", detail: $0.detail)
        })]
    }

    var body: some View {
        SettingsInfoPage(sections: sections) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: openAppSettings) {
                    SettingsPlainCapsuleLabel(title: "iPhone 설정 열기")
                }
                .buttonStyle(.plain)
                .readAloudTarget("아이폰 설정 열기 버튼")
                .accessibilityHint("설정 앱에서 Hear I am의 접근 권한을 확인하고 변경해요")
                .accessibilityIdentifier("settings.permissions.openSettings")
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .readAloudTarget(note)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 8)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .settingsScreen()
        .readsAloud(title: title) {
            [title] + SettingsInfo.lines(sections) + ["아이폰 설정 열기 버튼", note]
        }
        .onAppear(perform: refreshPermissions)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshPermissions()
            }
        }
    }

    private func refreshPermissions() {
        permissions = AppPermission.readCurrent()
    }

    /// The app's own page in the Settings app, where each permission can be turned on or off.
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct AppPermission: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let status: String

    // Reading authorization statuses does not present system permission requests.
    static func readCurrent() -> [AppPermission] {
        [
            AppPermission(id: "camera", icon: "camera", title: "카메라",
                          detail: "저장한 무대와 현재 공간을 맞춰요.",
                          status: captureStatus(AVCaptureDevice.authorizationStatus(for: .video))),
            AppPermission(id: "microphone", icon: "mic", title: "마이크",
                          detail: "호출어와 요청을 들어요.",
                          status: captureStatus(AVCaptureDevice.authorizationStatus(for: .audio))),
            AppPermission(id: "speech", icon: "waveform", title: "음성 인식",
                          detail: "기기의 음성 인식으로 한국어 요청을 처리해요.",
                          status: speechStatus),
            AppPermission(id: "motion", icon: "figure.walk", title: "움직임",
                          detail: "방향 찾기 연습에서 기기의 움직임을 사용해요.",
                          status: motionStatus)
        ]
    }

    private static func captureStatus(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "허용됨"
        case .notDetermined: return "요청 전"
        case .denied: return "허용 안 됨"
        case .restricted: return "사용 제한"
        @unknown default: return "확인 필요"
        }
    }

    private static var speechStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return "허용됨"
        case .notDetermined: return "요청 전"
        case .denied: return "허용 안 됨"
        case .restricted: return "사용 제한"
        @unknown default: return "확인 필요"
        }
    }

    private static var motionStatus: String {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: return "허용됨"
        case .notDetermined: return "요청 전"
        case .denied: return "허용 안 됨"
        case .restricted: return "사용 제한"
        @unknown default: return "확인 필요"
        }
    }
}
