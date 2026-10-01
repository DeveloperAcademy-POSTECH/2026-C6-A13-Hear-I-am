import Foundation
import AVFoundation
import CoreMotion

/// **E7 엔진 — 공간 음향 방향 정위**
///
/// 문서에서 확인한 것 두 가지를 코드로 옮긴다.
/// 1. §B2.2 : 기본 렌더링은 **좌우 팬**이다. HRTF 를 명시해야 공간 음향이 된다.
/// 2. §B2.2 : **모노 입력만 공간화된다.** 그래서 버퍼를 1채널로 만든다.
///
/// 그리고 §B2.3 — 헤드폰이 주는 것은 **머리의 자세**이지 몸통 방향도 무대 좌표도 아니다.
@MainActor
final class SpatialEngine: ObservableObject {
    /// 무슨 소리로 방향을 줄까.
    /// - tone: 한 음(880Hz). 처음 판에 쓴 소리
    /// - noise: 넓은 대역 소리. 앞뒤를 가르는 단서는 귓바퀴가 만드는 높은 주파수 차이인데
    ///   한 음짜리 소리에는 그 정보가 거의 없다. 넓은 대역이면 앞뒤가 나아질 수 있다(가설)
    /// - code: 위치 대신 약속. 좌우는 귀(왼쪽·가운데·오른쪽), 앞뒤는 음높이(앞 높음 · 옆 중간 · 뒤 낮음).
    ///   공간 음향이 아니라 배워서 아는 신호다. 머리 방향을 따라가지 않는다(몸 기준)
    enum Stimulus: String, CaseIterable, Identifiable {
        case tone = "삐 (한 음)", noise = "쏴 (넓은 소리)", code = "높낮이 약속"
        var id: String { rawValue }
        var short: String {
            switch self {
            case .tone: return "삐"
            case .noise: return "쏴"
            case .code: return "높낮이"
            }
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var headYawDegrees: Double = 0
    @Published private(set) var headphonesConnected = false
    @Published private(set) var lastError: String?
    /// 머리 방향을 청취자 방향에 반영할지. 끄면 무대 고정 기준이 된다.
    @Published var followHead = true

    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let player = AVAudioPlayerNode()
    private let motion = CMHeadphoneMotionManager()
    private var buffer: AVAudioPCMBuffer?
    private var noiseBuffer: AVAudioPCMBuffer?
    private var codeBuffers: [Double: AVAudioPCMBuffer] = [:]
    @Published var stimulus: Stimulus = .tone
    private var yawOffset: Double = 0

    /// 문서가 권하는 대로 명시적으로 고른다. 기본값(equalPowerPanning)으로 두면 3D 가 아니다.
    var algorithm: AVAudio3DMixingRenderingAlgorithm = .HRTFHQ {
        didSet { player.renderingAlgorithm = algorithm }
    }

    func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // 같은 폰에서 Apple Music 을 틀어 둔 채 신호를 내야 한다(E3). 섞어서 내고, 음악을 끊지 않는다.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            buffer = Self.makeTone(format: format, seconds: 0.35, frequency: 880)
            noiseBuffer = Self.makeNoise(format: format, seconds: 0.35)
            for f in [330.0, 660.0, 1320.0] {
                codeBuffers[f] = Self.makeTone(format: format, seconds: 0.35, frequency: f)
            }

            engine.attach(player)
            engine.attach(environment)
            // 모노로 연결해야 공간화가 걸린다.
            engine.connect(player, to: environment, format: format)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)

            player.renderingAlgorithm = algorithm
            environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
            environment.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)

            try engine.start()
            isRunning = true
            lastError = nil
            startHeadTracking()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        motion.stopDeviceMotionUpdates()
        isRunning = false
    }

    /// 정면을 맞춘 뒤 머리가 얼마나 돌았나(°). 화면 확인용.
    var relativeYawDegrees: Double { headYawDegrees - yawOffset }

    /// 지금 머리가 향한 쪽을 "무대 정면"으로 삼는다. §B2.3 의 기준 맞추기.
    /// `headYawDegrees` 는 보정 전 값이므로 그대로 기준으로 쓴다.
    /// (이전 코드는 기존 기준에 더해서, 두 번 누르면 기준이 틀어졌다.)
    func calibrateFront() { yawOffset = headYawDegrees }

    /// 무대 평면의 한 방위에 소리를 놓고 한 번 울린다.
    /// - Parameter bearing: 0° 가 정면, 시계 방향으로 커진다.
    func play(bearing: Double, distance: Float = 2.0) {
        guard isRunning else { return }
        let radians = bearing * .pi / 180
        let chosen: AVAudioPCMBuffer?
        switch stimulus {
        case .code:
            // 좌우: 오른쪽 반(0~180 사이)이면 오른쪽 귀, 왼쪽 반이면 왼쪽 귀, 정면·정후면은 가운데
            let side = sin(radians)
            let x: Float = abs(side) < 0.01 ? 0 : (side > 0 ? distance : -distance)
            player.position = AVAudio3DPoint(x: x, y: 0, z: -0.01)
            // 앞뒤: 앞쪽 높은 음, 옆 중간 음, 뒤쪽 낮은 음
            let front = cos(radians)
            chosen = codeBuffers[front > 0.1 ? 1320 : (front < -0.1 ? 330 : 660)]
        case .tone, .noise:
            // AVAudio3D 좌표: +x 오른쪽, -z 앞
            player.position = AVAudio3DPoint(x: Float(sin(radians)) * distance,
                                             y: 0,
                                             z: -Float(cos(radians)) * distance)
            chosen = stimulus == .noise ? noiseBuffer : buffer
        }
        guard let chosen else { return }
        player.scheduleBuffer(chosen, at: nil, options: [.interrupts])
        if !player.isPlaying { player.play() }
    }

    private func startHeadTracking() {
        guard motion.isDeviceMotionAvailable else {
            lastError = "이 기기·헤드폰에서는 머리 방향을 받을 수 없다"
            return
        }
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            guard let self else { return }
            if let error { self.lastError = error.localizedDescription; return }
            guard let data else { return }
            let yaw = data.attitude.yaw * 180 / .pi
            self.headphonesConnected = true
            self.headYawDegrees = yaw
            if self.followHead {
                // CMAttitude 의 yaw 는 고개를 오른쪽으로 돌리면 음수가 된다(실기기: 오른쪽 90° → −92.5°).
                // AVAudio3D 청취자 yaw 는 반대로, 양수가 오른쪽을 보는 쪽이다(실기기 확인, 2026-09-29).
                // 그래서 부호를 뒤집어 넣는다. 09-28 에 추론만으로 이 부호를 없앴다가
                // 고개를 오른쪽으로 돌리면 왼쪽 소리가 앞에서 들리는 것을 자동 확인에서 찾아 되돌렸다.
                self.environment.listenerAngularOrientation =
                    AVAudio3DAngularOrientation(yaw: Float(-(yaw - self.yawOffset)), pitch: 0, roll: 0)
            } else {
                self.environment.listenerAngularOrientation =
                    AVAudio3DAngularOrientation(yaw: 0, pitch: 0, roll: 0)
            }
        }
    }

    /// 넓은 대역 소리(백색 잡음). 시작과 끝을 부드럽게 깎는다. 매번 같은 소리가 나도록 시드를 고정한다.
    private static func makeNoise(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let fade = Int(format.sampleRate * 0.01)
        var seed: UInt32 = 12345
        for i in 0..<Int(frames) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            var sample = Double(seed) / Double(UInt32.max) * 2 - 1
            if i < fade { sample *= Double(i) / Double(fade) }
            if i > Int(frames) - fade { sample *= Double(Int(frames) - i) / Double(fade) }
            channel[i] = Float(sample * 0.35)
        }
        return buffer
    }

    /// 짧은 모노 톤. 시작과 끝을 부드럽게 깎아 클릭 잡음을 없앤다.
    private static func makeTone(format: AVAudioFormat, seconds: Double, frequency: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let fade = Int(format.sampleRate * 0.01)
        for i in 0..<Int(frames) {
            let t = Double(i) / format.sampleRate
            var sample = sin(2 * .pi * frequency * t)
            if i < fade { sample *= Double(i) / Double(fade) }
            if i > Int(frames) - fade { sample *= Double(Int(frames) - i) / Double(fade) }
            channel[i] = Float(sample * 0.6)
        }
        return buffer
    }
}

extension AVAudio3DMixingRenderingAlgorithm {
    var korean: String {
        switch self {
        case .equalPowerPanning: return "좌우 팬 (기본값)"
        case .sphericalHead:     return "구형 머리"
        case .HRTF:              return "HRTF"
        case .HRTFHQ:            return "HRTF 고품질"
        case .auto:              return "자동"
        default:                 return "기타"
        }
    }
}
