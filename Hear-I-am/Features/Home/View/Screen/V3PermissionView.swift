import SwiftUI
import AVFoundation
import Speech
import CoreMotion

struct V3PermissionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var headingSize: CGFloat = 22
    @State private var permissions = AppPermission.readCurrent()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("사용 중인 권한을 확인해요")
                    .font(.system(size: headingSize, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                SettingsGroup {
                    ForEach(Array(permissions.enumerated()), id: \.element.id) { index, permission in
                        permissionRow(permission)
                        if index < permissions.count - 1 {
                            SettingsDivider()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("권한은 iPhone 설정에서 변경할 수 있어요.")
                        .font(.subheadline)
                        .foregroundStyle(SettingsStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: openAppSettings) {
                        Text("iPhone 설정 열기")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SettingsStyle.darkText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, minHeight: SettingsStyle.buttonHeight)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("설정 앱에서 Hear I am의 접근 권한을 확인하고 변경해요")
                    .accessibilityIdentifier("settings.permissions.openSettings")

                    Text("마이크와 음성 인식은 말로 요청할 때 사용해요.")
                        .font(.footnote)
                        .foregroundStyle(SettingsStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .navigationTitle("앱 접근 권한")
        .navigationBarTitleDisplayMode(.inline)
        .settingsScreen()
        .readsAloud {
            ["앱 접근 권한", "사용 중인 권한을 확인해요"]
            + permissions.map { "\($0.title), \($0.status). \($0.detail)." }
            + ["권한은 아이폰 설정에서 변경할 수 있어요.",
               "아이폰 설정 열기 버튼",
               "마이크와 음성 인식은 말로 요청할 때 사용해요."]
        }
        .onAppear(perform: refreshPermissions)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshPermissions()
            }
        }
    }

    private func permissionRow(_ permission: AppPermission) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(permission.title)
                    .font(.body)
                    .foregroundStyle(.white)
                Text(permission.detail)
                    .font(.footnote)
                    .foregroundStyle(SettingsStyle.secondary)
                if dynamicTypeSize.isAccessibilitySize {
                    Text(permission.status)
                        .font(.body)
                        .foregroundStyle(SettingsStyle.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                Text(permission.status)
                    .font(.body)
                    .foregroundStyle(SettingsStyle.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, SettingsStyle.rowInset)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(permission.title), \(permission.detail)")
        .accessibilityValue(permission.status)
        .accessibilityIdentifier("settings.permissions.\(permission.id)")
    }

    private func refreshPermissions() {
        permissions = AppPermission.readCurrent()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct AppPermission: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: String

    // Reading authorization statuses does not present system permission requests.
    static func readCurrent() -> [AppPermission] {
        [
            AppPermission(id: "camera", title: "카메라",
                          detail: "무대 스캔과 위치 확인",
                          status: captureStatus(AVCaptureDevice.authorizationStatus(for: .video))),
            AppPermission(id: "microphone", title: "마이크",
                          detail: "음성 요청 듣기",
                          status: captureStatus(AVCaptureDevice.authorizationStatus(for: .audio))),
            AppPermission(id: "speech", title: "음성 인식",
                          detail: "말한 내용을 명령으로 이해하기",
                          status: speechStatus),
            AppPermission(id: "motion", title: "동작 및 피트니스",
                          detail: "기기의 움직임 확인",
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
