import Foundation
import AVFoundation
import UIKit

/// **시계 없이 — AirPods 소리로 주는 방향 신호**
///
/// Watch 진동과 같은 뜻(왼쪽으로·오른쪽으로·뒤로·도착·정지)을 소리로 낸다.
/// 문서 B4의 결론은 "AirPods는 보조"였지만, 소리 신호를 알아듣는지는 시계 없이도 잴 수 있다.
///
/// 두 가지로 낸다.
/// - **소리**: 짧은 음. 좌우는 **양쪽 귀에 내되 한쪽을 크게**, 그리고 **개수로도 가른다**
///   (왼쪽 = 삐삐 두 번, 오른쪽 = 삐 한 번 — 시계 진동의 왼쪽 2탭 · 오른쪽 1탭과 같은 문법).
///   처음엔 한쪽 귀에만 냈는데, AirPod 한쪽이 빠지면 그쪽 신호가 조용히 사라지는 것을 확인했다(3번 테스트, 2026-09-28).
///   침묵이 "잘 가고 있다"는 뜻인 설계에서 그건 가장 나쁜 실패라 바꿨다.
///   뒤는 낮은 음, 도착은 올라가는 세 음, 정지는 높낮이가 번갈아 빠르게 네 번(삐뽀삐뽀).
///   정지는 처음에 낮은 음 세 번이었는데, “뒤로(낮은 둥둥)”와 같은 낮은 소리라 바꿨다(사용자 요청, v3).
/// - **말**: "왼쪽" 같은 음성. 뜻은 가장 분명하지만 길다.
///
/// 문서 B2.6 — AirPods 가 빠지면 소리가 멈추거나 **폰 스피커로 샐 수 있다.** 경로 변화를 기록해 둔다.
@MainActor
final class AudioCuePlayer: ObservableObject {
    enum Style: String, CaseIterable, Identifiable {
        case tone = "소리", speech = "말"
        var id: String { rawValue }
    }

    @Published var style: Style = .tone
    /// 기록에 남기는 소리 이름. 소리를 바꾸면 버전을 올려 옛 결과와 섞이지 않게 한다.
    /// v1(이름 "소리"): 좌우를 한쪽 귀에만, 둘 다 삐삐 · v2: 양쪽 귀 + 개수(왼쪽 2번 · 오른쪽 1번)
    /// v3: 정지를 낮은 음 세 번 → 삐뽀삐뽀
    static let toneVersion = "소리 v3"
    var recordName: String { style == .tone ? Self.toneVersion : style.rawValue }
    @Published private(set) var repeating: GuideSignal?
    @Published private(set) var outputName = "—"
    @Published private(set) var isHeadphones = false
    @Published private(set) var isSpeaker = false
    @Published private(set) var routeLog: [String] = []
    @Published private(set) var lastError: String?
    /// 이어폰이 빠지면 멈추고 스피커로 다시 켜지 않는다(3번 테스트에서 스피커로 새는 것을 확인했다).
    /// 3번 화면만 비교용으로 끈다.
    var safetyStop = true
    /// 이어폰이 빠져서 멈춘 상태. 운영자가 확인하고 풀 때까지 소리를 내지 않는다.
    @Published private(set) var headphonesLost = false

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let speech = AVSpeechSynthesizer()
    private var buffers: [GuideSignal: AVAudioPCMBuffer] = [:]
    private var durations: [GuideSignal: Double] = [:]
    private var task: Task<Void, Never>?
    private var prepared = false
    private var format: AVAudioFormat?
    /// 이어폰이 빠진 시각. 다시 연결돼도 운영자가 볼 수 있게 남긴다.
    @Published private(set) var lastLossAt: Date?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in self?.routeChanged(raw) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                            object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.note("오디오 엔진이 멈춤 (출력 장치가 바뀜)") }
        })
        updateRoute()
    }

    // MARK: 재생

    /// 한 번 울린다.
    func play(_ signal: GuideSignal) {
        // 이어폰이 아닌 곳(폰 스피커)으로는 안내음을 내지 않는다 — 객석으로 샌다
        if safetyStop, headphonesLost || !isHeadphones { return }
        guard prepare() else { return }
        if style == .speech, signal != .heartbeat {
            speech.stopSpeaking(at: .immediate)
            let u = AVSpeechUtterance(string: word(signal))
            u.voice = AVSpeechSynthesisVoice(language: "ko-KR")
            u.rate = 0.55
            speech.speak(u)
        } else if let buffer = buffers[signal] {
            node.scheduleBuffer(buffer, at: nil, options: [.interrupts])
            if !node.isPlaying { node.play() }
        }
    }

    /// 벗어난 정도에 따라 반복한다. `stop()` 을 부를 때까지 — 침묵이 "잘 가고 있다"는 뜻이다.
    func startRepeating(_ signal: GuideSignal, every deviation: Deviation) {
        task?.cancel()
        repeating = signal
        let cueSec = style == .speech ? 0.7 : (durations[signal] ?? 0.3)
        let period = UInt64((cueSec + Double(deviation.repeatMs) / 1000) * 1_000_000_000)
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.play(signal)
                try? await Task.sleep(nanoseconds: period)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        repeating = nil
        speech.stopSpeaking(at: .immediate)
        node.stop()
    }

    func word(_ s: GuideSignal) -> String {
        switch s {
        case .left: return "왼쪽"
        case .right: return "오른쪽"
        case .back: return "뒤로"
        case .arrive: return "도착"
        case .stop: return "정지"
        case .heartbeat: return ""
        }
    }

    /// 소리 신호가 어떻게 들리는지. 화면에 그대로 보여 준다.
    func sound(_ s: GuideSignal) -> String {
        switch s {
        case .left: return "삐삐 두 번 · 왼쪽이 크게"
        case .right: return "삐 한 번 · 오른쪽이 크게"
        case .back: return "양쪽 귀에 낮은 둥둥"
        case .arrive: return "올라가는 세 음"
        case .stop: return "삐뽀삐뽀 (높낮이 번갈아 빠르게)"
        case .heartbeat: return "아주 작은 톡"
        }
    }

    // MARK: 준비

    /// 처음 쓸 때, 그리고 출력 장치가 바뀌어 엔진이 멈춘 뒤에 다시 켠다.
    /// 다시 켜면 새 출력(예: 폰 스피커)으로 나간다 — 그게 E9 에서 보려는 사고다.
    @discardableResult
    private func prepare() -> Bool {
        do {
            if !prepared {
                let session = AVAudioSession.sharedInstance()
                // 같은 폰에서 Apple Music 을 틀어 둔 채 신호를 내야 한다(E3). 섞어서 내고, 음악을 끊지 않는다.
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
                self.format = format
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
                for s in GuideSignal.allCases {
                    let (buf, sec) = Self.makeCue(s, format: format)
                    buffers[s] = buf
                    durations[s] = sec
                }
                prepared = true
            }
            if !engine.isRunning {
                // 출력 장치가 바뀌면 엔진이 멈추고 연결이 풀릴 수 있다. 다시 잇고 켠다.
                if let format { engine.connect(node, to: engine.mainMixerNode, format: format) }
                try engine.start()
                node.play()
            }
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: 출력 경로

    private func updateRoute() {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        outputName = outs.map(\.portName).joined(separator: ", ")
        if outputName.isEmpty { outputName = "—" }
        let headphoneTypes: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones]
        isHeadphones = outs.contains { headphoneTypes.contains($0.portType) }
        isSpeaker = outs.contains { $0.portType == .builtInSpeaker }
    }

    private func routeChanged(_ raw: UInt?) {
        updateRoute()
        let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        let text: String
        switch reason {
        case .newDeviceAvailable: text = "새 장치 연결"
        case .oldDeviceUnavailable: text = "장치 빠짐"
        case .categoryChange: text = "오디오 설정 바뀜"
        case .override: text = "출력 강제 변경"
        default: text = "경로 바뀜"
        }
        note("\(text) → \(outputName)")
        if headphonesLost, isHeadphones {
            // 다시 끼웠다. 이어폰으로만 나가므로 자동으로 풀어도 스피커로 새지 않는다.
            headphonesLost = false
            note("AirPods 다시 연결 — 안내음 다시 가능")
        }
        if safetyStop, reason == .oldDeviceUnavailable, !isHeadphones {
            stop()
            headphonesLost = true
            lastLossAt = Date()
            note("안내음 멈춤 (이어폰 빠짐)")
            // 운영자는 화면이 아니라 무용수를 보고 있다 — 손에 든 폰을 떨게 해서 알린다
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func note(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        routeLog.append("\(f.string(from: Date())) \(text)")
    }

    func clearLog() { routeLog.removeAll() }

    /// 자동으로 안 풀렸을 때 쓰는 수동 버튼. 이어폰이 연결돼 있을 때만 풀린다.
    func resumeAfterLoss() {
        updateRoute()
        if isHeadphones { headphonesLost = false }
    }

    // MARK: 소리 만들기

    /// (주파수, 길이 ms) 목록. 주파수가 nil 이면 쉼.
    private static func segments(_ s: GuideSignal) -> (parts: [(Double?, Double)], left: Float, right: Float, gain: Float) {
        switch s {
        case .left:      return ([(880, 90), (nil, 110), (880, 90)], 1, 0.35, 0.5)
        case .right:     return ([(880, 120)], 0.35, 1, 0.5)
        case .back:      return ([(330, 160), (nil, 120), (330, 160)], 1, 1, 0.55)
        case .arrive:    return ([(660, 110), (880, 110), (1175, 220)], 1, 1, 0.45)
        case .stop:      return ([(1100, 110), (550, 110), (1100, 110), (550, 110)], 1, 1, 0.55)
        case .heartbeat: return ([(1320, 30)], 1, 1, 0.12)
        }
    }

    private static func makeCue(_ s: GuideSignal, format: AVAudioFormat) -> (AVAudioPCMBuffer, Double) {
        let spec = segments(s)
        let rate = format.sampleRate
        var mono: [Float] = []
        for (freq, ms) in spec.parts {
            let n = Int(rate * ms / 1000)
            let fade = min(Int(rate * 0.005), n / 2)
            for i in 0..<n {
                guard let freq else { mono.append(0); continue }
                var env: Float = 1
                if i < fade { env = Float(i) / Float(fade) }
                if i > n - fade { env = Float(n - i) / Float(fade) }
                mono.append(Float(sin(2 * .pi * freq * Double(i) / rate)) * env * spec.gain)
            }
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mono.count))!
        buffer.frameLength = AVAudioFrameCount(mono.count)
        let l = buffer.floatChannelData![0], r = buffer.floatChannelData![1]
        for i in mono.indices {
            l[i] = mono[i] * spec.left
            r[i] = mono[i] * spec.right
        }
        return (buffer, Double(mono.count) / rate)
    }
}
