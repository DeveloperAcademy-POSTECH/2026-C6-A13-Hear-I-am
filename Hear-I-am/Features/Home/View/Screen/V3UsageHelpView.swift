import SwiftUI
import AVFoundation
import Speech
import CoreMotion

struct V3UsageHelpView: View {
    var body: some View {
        List {
            Section("몸에 맞춰 준비해요") {
                Label("iPhone을 허리 앞쪽에 단단히 고정해주세요.",systemImage:"iphone")
                Label("후면 카메라가 바깥쪽을 향하고 가려지지 않게 해주세요.",systemImage:"camera")
                Label("사용할 이어폰이나 스피커로 시험 소리를 들어주세요.",systemImage:"speaker.wave.2")
            }
            Section("연습과 실전") {
                Text("연습용은 저장한 공간을 제자리에서 둘러보며 찾고, 착용한 현재 위치에서 P1으로 안내해요.")
                Text("실전용은 조력자와 공간·확인점 두 곳·출발 위치를 확인한 뒤 안내를 시작해요.")
            }
            Section("착용 위치를 바꿨다면") {
                Text("먼저 안내를 일시정지하고, 휴대폰 고정과 현재 위치·몸 방향을 다시 확인해주세요.")
            }
            NavigationLink("소리 확인하기") {SoundOutputView()}
        }.navigationTitle("착용과 안내 준비").navigationBarTitleDisplayMode(.inline).v3Screen()
    }
}

struct V3VoiceHelpView: View {
    var body: some View {
        List {
            Section("부르고, 듣고, 말해요") {
                Label("“Hear I am”을 부르거나 홈의 흰 원을 눌러요.",systemImage:"mic")
                Text("공연 이름이나 공연장 이름을 한국어로 말해주세요. 준비 대화에서는 다시 부르지 않고 답할 수 있어요.")
            }
            Section("연습 중 요청") {
                Text("“Hear I am”을 부른 뒤 “잠깐 멈춰”, “계속”, “P1으로 돌아가”처럼 요청해요. 돌아갈 수 있는 지점은 이미 지나온 경로 안에서 확인해요.")
            }
            Section("실전에서는 마이크가 꺼져요") {
                Text("안내가 시작되면 호출어를 듣지 않아요. 화면의 일시정지 버튼을 사용해주세요.")
            }
            Section("음성 사용이 어려울 때") {
                Text("화면의 목록과 버튼으로 진행할 수 있어요. VoiceOver를 사용하면 항목을 선택한 뒤 두 번 탭해주세요.")
            }
        }.navigationTitle("음성으로 사용하기").navigationBarTitleDisplayMode(.inline).v3Screen()
    }
}

struct V3PermissionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var revision=0
    var body: some View {
        List {
            Section("필요한 권한을 확인해요") {
                permission("카메라",symbol:"camera",status:status(AVCaptureDevice.authorizationStatus(for:.video)),detail:"저장한 무대와 현재 공간을 맞춰요.")
                permission("마이크",symbol:"mic",status:status(AVCaptureDevice.authorizationStatus(for:.audio)),detail:"호출어와 요청을 들어요.")
                permission("음성 인식",symbol:"waveform",status:speechStatus,detail:"기기의 음성 인식으로 한국어 요청을 처리해요.")
                permission("움직임",symbol:"figure.walk",status:motionStatus,detail:"방향 찾기 연습에서 기기의 움직임을 사용해요.")
            }
            Section {
                Button("iPhone 설정 열기") {if let url=URL(string:UIApplication.openSettingsURLString) {openURL(url)}}
            } footer: {Text("마이크 권한이 없어도 조력자의 공연 관리와 버튼 조작은 사용할 수 있어요.")}
        }.id(revision).navigationTitle("권한 상태").navigationBarTitleDisplayMode(.inline).v3Screen()
            .onChange(of:scenePhase) {_,phase in if phase == .active {revision += 1}}
    }
    private func permission(_ title:String,symbol:String,status:String,detail:String) -> some View {
        Label {VStack(alignment:.leading,spacing:6) {Text("\(title) · \(status)").font(.headline);Text(detail).font(.subheadline).foregroundStyle(.secondary)}} icon: {Image(systemName:symbol)}.padding(.vertical,6)
    }
    private func status(_ value:AVAuthorizationStatus)->String {
        switch value {case .authorized:return "허용됨";case .notDetermined:return "사용할 때 요청";case .denied:return "허용 필요";case .restricted:return "사용 제한";@unknown default:return "확인 필요"}
    }
    private var speechStatus:String {
        switch SFSpeechRecognizer.authorizationStatus() {case .authorized:return "허용됨";case .notDetermined:return "사용할 때 요청";case .denied:return "허용 필요";case .restricted:return "사용 제한";@unknown default:return "확인 필요"}
    }
    private var motionStatus:String {
        switch CMMotionActivityManager.authorizationStatus() {case .authorized:return "허용됨";case .notDetermined:return "사용할 때 요청";case .denied:return "허용 필요";case .restricted:return "사용 제한";@unknown default:return "확인 필요"}
    }
}
