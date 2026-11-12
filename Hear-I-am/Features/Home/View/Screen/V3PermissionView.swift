import SwiftUI
import HearIAmCore
import AVFoundation
import Speech
import CoreMotion

/// 「권한 상태」 (Figma 971:23466): each permission with its state and use, then 「iPhone 설정 열기」, which
/// opens this app's page in the Settings app (971:23465).
///
/// Under the permissions sits 「받아쓰기」 (#189). With the iPhone's dictation off every voice request fails at
/// once, and Home could only say so; this page shows whether it is on. It is a system switch, not a permission
/// of this app: an app can neither flip it nor open its page in Settings (only private URLs lead there), so the
/// row names the place in one line while it is off, and 「iPhone 설정 열기」 stays the way out to Settings.
struct V3PermissionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var permissions = AppPermission.readCurrent()
    @State private var dictation = DictationState.checking
    /// Bumped when the app comes back to the front, so dictation is checked again after a trip to Settings.
    @State private var dictationRound = 0
    private let title = L("권한 상태")
    private let note = L("마이크 권한이 없어도 조력자의 공연 관리와 버튼 조작은 사용할 수 있어요.")
    private var sections: [SettingsInfo] {
        [SettingsInfo(title: L("필요한 권한을 확인해요"), rows: permissions.map {
            .init(icon: $0.icon, text: "\($0.title) · \($0.status)", detail: $0.detail)
        }),
         SettingsInfo(title: L("받아쓰기를 확인해요"), rows: [
            .init(icon: "keyboard", text: "\(L("받아쓰기")) · \(dictation.status)", detail: dictation.detail)
         ])]
    }

    var body: some View {
        SettingsInfoPage(sections: sections) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: openAppSettings) {
                    SettingsPlainCapsuleLabel(title: L("iPhone 설정 열기"))
                }
                .buttonStyle(.plain)
                .readAloudTarget(L("아이폰 설정 열기 버튼"))
                .accessibilityHint(L("설정 앱에서 Hear I am의 접근 권한을 확인하고 변경해요"))
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
            [title] + SettingsInfo.lines(sections) + [L("아이폰 설정 열기 버튼"), note]
        }
        .onAppear(perform: refreshPermissions)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshPermissions()
                dictationRound += 1
            }
        }
        .task(id: dictationRound) {
            let checked = await DictationProbe().run(localeCode: HearLanguage.current.speechCode)
            if !Task.isCancelled { dictation = checked }
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
            AppPermission(id: "camera", icon: "camera", title: L("카메라"),
                          detail: L("저장한 무대와 현재 공간을 맞춰요."),
                          status: captureStatus(AVCaptureDevice.authorizationStatus(for: .video))),
            AppPermission(id: "microphone", icon: "mic", title: L("마이크"),
                          detail: L("호출어와 요청을 들어요."),
                          status: captureStatus(AVCaptureDevice.authorizationStatus(for: .audio))),
            AppPermission(id: "speech", icon: "waveform", title: L("음성 인식"),
                          detail: L("기기의 음성 인식으로 한국어 요청을 처리해요."),
                          status: speechStatus),
            AppPermission(id: "motion", icon: "figure.walk", title: L("움직임"),
                          detail: L("방향 찾기 연습에서 기기의 움직임을 사용해요."),
                          status: motionStatus)
        ]
    }

    private static func captureStatus(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return L("허용됨")
        case .notDetermined: return L("요청 전")
        case .denied: return L("허용 안 됨")
        case .restricted: return L("사용 제한")
        @unknown default: return L("확인 필요")
        }
    }

    private static var speechStatus: String {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return L("허용됨")
        case .notDetermined: return L("요청 전")
        case .denied: return L("허용 안 됨")
        case .restricted: return L("사용 제한")
        @unknown default: return L("확인 필요")
        }
    }

    private static var motionStatus: String {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: return L("허용됨")
        case .notDetermined: return L("요청 전")
        case .denied: return L("허용 안 됨")
        case .restricted: return L("사용 제한")
        @unknown default: return L("확인 필요")
        }
    }
}

/// Whether the iPhone's dictation (설정 > 일반 > 키보드 > 받아쓰기 활성화) is on, as far as the app can tell.
enum DictationState {
    case checking, on, off, unknown

    var status: String {
        switch self {
        case .checking: return L("확인 중")
        case .on: return L("켜짐")
        case .off: return L("꺼짐")
        case .unknown: return L("확인 필요")
        }
    }
    var detail: String {
        switch self {
        case .checking: return L("켜져 있는지 확인하고 있어요.")
        case .on: return L("음성 요청을 들을 수 있어요.")
        case .off: return L("꺼져 있어 음성 요청을 들을 수 없어요. 설정 앱의 일반 > 키보드에서 켤 수 있어요.")
        case .unknown: return L("켜져 있는지 확인하지 못했어요. 음성 요청은 받아쓰기가 켜져 있어야 들을 수 있어요.")
        }
    }
}

/// iOS has no setting to read for dictation. What tells is the recognizer itself: on-device recognition fails at
/// once with kLSRErrorDomain 201 when Siri and Dictation are off (16 Pro Max, 10/27), which is also how the
/// listener finds out. The probe gives it half a second of silence, so no microphone is opened and nothing is
/// asked of the user. With dictation on, the silence ends as "no speech" (kAFAssistantErrorDomain 1110, POS
/// 11/12); only that or a result counts as on, and any other failure is left as not known.
final class DictationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DictationState, Never>?
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?

    func run(localeCode: String) async -> DictationState {
        await withCheckedContinuation { continuation in
            lock.lock(); self.continuation = continuation; lock.unlock()
            // Creating a recognizer can wait on the speech service; kept off the main thread.
            DispatchQueue.global(qos: .userInitiated).async { self.begin(localeCode) }
        }
    }

    private func begin(_ localeCode: String) {
        // Not allowed yet: recognition would fail for that reason, and asking here would raise the system prompt.
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { finish(.unknown, "not_authorized"); return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeCode)),
              recognizer.supportsOnDeviceRecognition else { finish(.unknown, "no_on_device \(localeCode)"); return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        let format = request.nativeAudioFormat
        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate / 2)) else {
            finish(.unknown, "no_buffer"); return
        }
        silence.frameLength = silence.frameCapacity
        for buffer in UnsafeMutableAudioBufferListPointer(silence.mutableAudioBufferList) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        let task = recognizer.recognitionTask(with: request) { [self] result, error in
            if let error = error as NSError? {
                let off = error.domain == "kLSRErrorDomain" && error.code == 201
                let heardNothing = error.domain == "kAFAssistantErrorDomain" && error.code == 1110
                finish(off ? .off : heardNothing ? .on : .unknown, "\(error.domain) \(error.code)")
            } else if result?.isFinal == true {
                finish(.on, "final")
            }
        }
        lock.lock(); self.recognizer = recognizer; self.task = task; lock.unlock()
        request.append(silence)
        request.endAudio()
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { self.finish(.unknown, "timeout") }
    }

    private func finish(_ state: DictationState, _ reason: String) {
        lock.lock()
        let waiting = continuation; continuation = nil
        let running = task; task = nil; recognizer = nil
        lock.unlock()
        guard let waiting else { return }
        running?.cancel()
        VoiceLog.write("dictation_check", "\(state) \(reason)", screen: "settings")
        waiting.resume(returning: state)
    }
}
