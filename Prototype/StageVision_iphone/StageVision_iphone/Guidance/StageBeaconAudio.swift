import Foundation
import AVFoundation
import CoreMotion
import Combine

/// Adapted from Hear-I-am / Prototype/HapticLab / Sources/iOS/StageView.swift
/// StageBeaconAudio, commit dc9bfbc597574065a52228296387a32cbafb01b8.
/// Keeps the mono noise, HRTFHQ, 600ms pulse and arrival chime. Adds stage-frame
/// calibration, one explicit distance gain, smoothing and fail-closed lifecycle handling.
@MainActor
final class StageBeaconAudio: ObservableObject {
    @Published private(set) var status = "AirPods를 연결한 뒤 소리를 준비하세요."
    @Published private(set) var outputStatus = "출력 확인 전"
    @Published private(set) var engineStatus = "엔진 정지"
    @Published private(set) var motionStatus = "머리 방향 수신 전"
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var prepared = false
    @Published private(set) var headReady = false
    @Published private(set) var outputGain = 0.0
    private(set) var headTimestamp = -Double.infinity
    private var rawYaw = 0.0
    private var yawOffset = 0.0
    private var initialHeading: MapPoint?
    private var engine: AVAudioEngine?
    private var environment: AVAudioEnvironmentNode?
    private var player: AVAudioPlayerNode?
    private var alertPlayer: AVAudioPlayerNode?
    private let motion = CMHeadphoneMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "StageVision.HeadphoneMotion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let speech = AVSpeechSynthesizer()
    private var ping: AVAudioPCMBuffer?
    private var chime: AVAudioPCMBuffer?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var arrivalTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryAttempts = 0
    private var engineStableSince = 0.0
    private var routeIdentity = ""
    private var motionReceivedAt = -Double.infinity
    private var motionAppliedAt = -Double.infinity
    private var motionDelayed = false
    private var preparing = false
    private var generation = UUID()
    private var packet: (cue: GuidanceCue, listener: MapPoint, source: MapPoint)?
    private var lastState: GuidanceCue.State = .paused
    private var lastGuidanceBlock: String?
    private var nextPing = 0.0
    private var lastTick = 0.0
    private var headphones: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let allowed: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones]
        return !outputs.isEmpty && outputs.allSatisfy { allowed.contains($0.portType) }
    }
    var heading: MapPoint? {
        guard prepared, recoveryTask == nil, engine?.isRunning == true, headReady, headphones, let initialHeading,
              BeaconMath.fresh(headTimestamp, now: ProcessInfo.processInfo.systemUptime) else { return nil }
        return BeaconMath.heading(initial: initialHeading, calibrationYaw: yawOffset, currentYaw: rawYaw)
    }
    var canCalibrate: Bool {
        prepared && recoveryTask == nil && engine?.isRunning == true && headReady && headphones && BeaconMath.fresh(headTimestamp, now: ProcessInfo.processInfo.systemUptime)
    }
    var waitingForFreshHead: Bool {
        prepared && recoveryTask == nil && engine?.isRunning == true && headphones && initialHeading != nil &&
        BeaconMath.retainsHeadCalibration(headTimestamp, now: ProcessInfo.processInfo.systemUptime)
    }

    func prepare() {
        shutdown()
        diagnostics = []
        refreshDiagnostics()
        record("소리 준비 요청")
        guard headphones else { status = "AirPods를 이 iPhone에 연결해주세요. 스피커로는 재생하지 않습니다."; return }
        guard motion.isDeviceMotionAvailable else { status = "머리 방향을 지원하는 AirPods가 필요합니다."; return }
        preparing = true
        defer { preparing = false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            guard headphones else { status = "이어폰 출력 연결을 확인해주세요."; return }
            let engine = AVAudioEngine()
            let environment = AVAudioEnvironmentNode()
            let player = AVAudioPlayerNode()
            let alerts = AVAudioPlayerNode()
            self.engine = engine; self.environment = environment
            self.player = player; self.alertPlayer = alerts
            let mono = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let stereo = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
            ping = Self.makeNoise(format: mono, seconds: 0.25)
            chime = Self.makeTones([(660, 0.14), (880, 0.14), (1320, 0.32)], format: stereo)
            guard ping != nil, chime != nil else { shutdown(); status = "안내 음원 생성 실패"; return }
            engine.attach(player); engine.attach(environment); engine.attach(alerts)
            engine.connect(player, to: environment, format: mono)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)
            engine.connect(alerts, to: engine.mainMixerNode, format: stereo)
            player.renderingAlgorithm = .HRTFHQ
            // Distance gain lives in BeaconMath. Do not attenuate a second time here.
            let attenuation = environment.distanceAttenuationParameters
            attenuation.distanceAttenuationModel = .inverse
            // Valid stage coordinates are within ±200m, hence all in-stage pairs are <566m.
            // Keep them inside the engine's unattenuated reference distance. Apple requires
            // rolloffFactor > 0; using zero to disable attenuation is unsupported.
            attenuation.referenceDistance = 1_000
            attenuation.maximumDistance = 10_000
            attenuation.rolloffFactor = 1
            player.volume = 0
            try engine.start()
            prepared = true
            routeIdentity = currentRouteIdentity
            recoveryAttempts = 0
            engineStableSince = ProcessInfo.processInfo.systemUptime
            refreshDiagnostics()
            record("엔진 시작 · 머리 방향 첫 샘플 대기")
            status = "AirPods 머리 방향을 기다리고 있습니다."
            let token = generation
            motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
                // Capture arrival before the main-actor hop; don't relabel old sensor data as fresh.
                let receivedAt = ProcessInfo.processInfo.systemUptime
                let yaw = data?.attitude.yaw
                let timestamp = data?.timestamp
                let failureText = error.map { error in
                    let failure = error as NSError
                    return "\(failure.domain)/\(failure.code) \(failure.localizedDescription)"
                }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.prepared else { return }
                    if let failureText {
                        self.record("머리 센서 오류: \(failureText)")
                        self.fail("AirPods 머리 방향 수신 오류 · 동작 및 피트니스 권한을 확인해주세요."); return
                    }
                    guard let yaw, yaw.isFinite, let timestamp, timestamp.isFinite,
                          timestamp > self.headTimestamp else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    // Also expire across a long gap when no watchdog tick ran during it.
                    if self.initialHeading != nil && !BeaconMath.retainsHeadCalibration(self.headTimestamp, now: now) {
                        self.silence(clearCalibration: true)
                        self.record("머리 방향 장기 지연 · 보정 해제")
                    }
                    if !self.motionReceivedAt.isFinite { self.record("머리 방향 첫 샘플 수신") }
                    self.motionReceivedAt = receivedAt
                    self.motionAppliedAt = now
                    self.rawYaw = yaw
                    self.headTimestamp = timestamp
                    self.headReady = BeaconMath.fresh(timestamp, now: now)
                    if self.motionDelayed && self.headReady {
                        self.record(String(format: "머리 방향 수신 복구 · 센서→수신 %.2f초 / 앱 반영 %.2f초", receivedAt - timestamp, now - receivedAt))
                        self.motionDelayed = false
                    }
                    if self.initialHeading == nil && self.headReady { self.status = "소리 준비됨 · 지도에서 P가 보는 방향을 지정하세요." }
                }
            }
            observe(AVAudioSession.routeChangeNotification, object: session, token: token)
            observe(AVAudioSession.interruptionNotification, object: session, token: token)
            observe(AVAudioSession.mediaServicesWereResetNotification, object: session, token: token)
            observe(.AVAudioEngineConfigurationChange, object: engine, token: token)
            lastTick = ProcessInfo.processInfo.systemUptime
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
        } catch { fail("소리 준비 실패: \(error.localizedDescription)") }
    }

    @discardableResult
    func calibrate(heading: MapPoint) -> Bool {
        guard canCalibrate, heading.length > 0.001 else { status = "AirPods 방향 측정을 먼저 확인해주세요."; return false }
        silence()
        initialHeading = heading
        yawOffset = rawYaw
        status = "무대 방향 보정 완료"
        return true
    }
    func update(_ guide: GuidanceState) {
        guard prepared else { return }
        let oldState = lastState
        lastState = guide.cue.state
        if guide.cue.state == .arrived {
            packet = nil
            player?.stop(); player?.volume = 0; outputGain = 0
            if oldState == .guiding && canCalibrate { announceArrival() }
            return
        }
        guard guide.active, guide.cue.state == .guiding,
              let listener = guide.position, let source = guide.target else {
            let reason = guide.active && guide.position == nil ? "P 위치 측정 대기 · \(guide.trackingMessage)" : guide.message
            if lastGuidanceBlock != reason {
                record("안내 무음: \(reason)")
                lastGuidanceBlock = reason
            }
            silence()
            status = "안내 무음 · \(reason)"
            return
        }
        if lastGuidanceBlock != nil {
            record("안내 재생 가능 · 위치/방향 데이터 확인")
            lastGuidanceBlock = nil
        }
        packet = (guide.cue, listener, source)
        tick()
    }
    /// Immediate stop clears queued audio, unlike only stopping future pings.
    func silence(clearCalibration: Bool = false) {
        packet = nil; nextPing = 0; outputGain = 0
        player?.volume = 0; player?.stop(); alertPlayer?.stop()
        arrivalTask?.cancel(); arrivalTask = nil
        speech.stopSpeaking(at: .immediate)
        if clearCalibration { initialHeading = nil }
    }
    func shutdown() {
        generation = UUID()
        silence(clearCalibration: true)
        recoveryTask?.cancel(); recoveryTask = nil
        timer?.invalidate(); timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        motion.stopDeviceMotionUpdates()
        engine?.stop()
        engine = nil; environment = nil; player = nil; alertPlayer = nil
        prepared = false; headReady = false; headTimestamp = -.infinity; lastState = .paused
        lastGuidanceBlock = nil
        motionReceivedAt = -.infinity
        motionAppliedAt = -.infinity; motionDelayed = false
        refreshDiagnostics()
        status = "소리 정지 · 다시 준비해주세요."
    }
    private func fail(_ message: String) {
        record(message)
        shutdown(); status = message
    }
    private var currentRouteIdentity: String {
        AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.uid }.sorted().joined(separator: "|")
    }
    private func record(_ message: String) {
        diagnostics.append("\(Date().formatted(date: .omitted, time: .standard)) · \(message)")
        if diagnostics.count > 30 { diagnostics.removeFirst(diagnostics.count - 30) }
    }
    private func refreshDiagnostics() {
        let session = AVAudioSession.sharedInstance()
        outputStatus = session.currentRoute.outputs.map { "\($0.portName) [\($0.portType.rawValue)]" }.joined(separator: ", ")
        if outputStatus.isEmpty { outputStatus = "출력 없음" }
        engineStatus = engine?.isRunning == true ? "실행 중 · \(Int(session.sampleRate))Hz" : "정지"
        let now = ProcessInfo.processInfo.systemUptime
        if headTimestamp.isFinite {
            motionStatus = String(format: "샘플 %.2f초 전 · 수신 %.2f초 전 · 앱 반영 지연 %.2f초 · yaw %+.0f°",
                                  now - headTimestamp, now - motionReceivedAt, motionAppliedAt - motionReceivedAt, rawYaw * 180 / .pi)
        } else {
            motionStatus = motion.isDeviceMotionAvailable ? "센서 지원 · 첫 샘플 대기" : "머리 센서 사용 불가"
        }
    }
    private func observe(_ name: Notification.Name, object: AnyObject, token: UUID) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] notification in
            // Extract scalar values before hopping off the notification callback.
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            let interruption = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.handleNotification(name, reason: reason, interruption: interruption)
            }
        })
    }
    private func handleNotification(_ name: Notification.Name, reason: UInt?, interruption: UInt?) {
        refreshDiagnostics()
        if name == AVAudioSession.routeChangeNotification {
            let value = reason.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            record("출력 이벤트 \(String(describing: value)) · \(outputStatus)")
            // categoryChange/newDeviceAvailable are NOT evidence of disconnection.
            switch BeaconAudioPolicy.routeAction(headphones: headphones, sameDevice: routeIdentity == currentRouteIdentity,
                                                 engineRunning: engine?.isRunning == true) {
            case .keep: break
            case .stop: fail("이어폰 출력이 사라졌습니다 · 현재 출력: \(outputStatus)")
            case .recover:
                routeIdentity = currentRouteIdentity
                recoverEngine("이어폰 출력 설정 변경")
            }
        } else if name == .AVAudioEngineConfigurationChange {
            record("엔진 구성 변경 · \(outputStatus) · \(engineStatus)")
            if engine?.isRunning != true { recoverEngine("샘플레이트/채널 설정 변경") }
        } else if name == AVAudioSession.interruptionNotification {
            record("오디오 interruption type=\(interruption.map(String.init) ?? "unknown")")
            if interruption != AVAudioSession.InterruptionType.ended.rawValue {
                fail("전화·시스템 오디오 중단 · 종료 후 소리를 다시 준비해주세요.")
            }
        } else {
            fail("오디오 서비스 재시작 · 소리를 다시 준비해주세요.")
        }
    }
    /// Route negotiation can stop the engine while headphones remain connected.
    /// Recover only the engine; never silently resume an old walking command.
    private func recoverEngine(_ reason: String) {
        guard prepared, headphones else { fail("이어폰 출력 없음 · 소리 준비 필요"); return }
        guard recoveryTask == nil else { return }
        guard recoveryAttempts < 3 else { fail("오디오 엔진 복구 실패 · 진단 기록을 확인해주세요."); return }
        silence(clearCalibration: true)
        status = "이어폰 연결 유지 · 오디오 엔진 재설정 중"
        record("엔진 복구 예약: \(reason)")
        let token = generation
        recoveryTask = Task { @MainActor [weak self] in
            // Give Bluetooth format negotiation a bounded settling interval.
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, self.generation == token else { return }
            self.recoveryTask = nil
            guard self.headphones, let engine = self.engine else {
                self.fail("이어폰 출력이 사라졌습니다 · 다시 연결해주세요."); return
            }
            self.recoveryAttempts += 1
            do {
                engine.prepare()
                try engine.start()
                self.engineStableSince = ProcessInfo.processInfo.systemUptime
                self.refreshDiagnostics()
                self.record("엔진 복구 성공 (\(self.recoveryAttempts)회)")
                self.status = "오디오 엔진 복구됨 · P가 보는 방향을 다시 지정하세요."
            } catch {
                self.record("엔진 복구 오류: \(error.localizedDescription)")
                self.recoverEngine("재시도")
            }
        }
    }
    /// A system permission sheet temporarily makes the scene inactive.
    /// Pause sound, but don't tear down the just-requested motion stream.
    func suspend() {
        silence(clearCalibration: true)
        if prepared && !preparing {
            record("앱 일시 비활성 · 안내만 정지")
            status = "안내 정지 · P가 보는 방향을 다시 지정하세요."
        }
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now - lastTick)); lastTick = now
        guard prepared else { return }
        refreshDiagnostics()
        guard headphones else { fail("이어폰 출력이 사라졌습니다 · 현재 출력: \(outputStatus)"); return }
        guard recoveryTask == nil else { return }
        guard engine?.isRunning == true else { recoverEngine("출력 장치는 연결됨, 엔진만 정지"); return }
        if now - engineStableSince > 2 { recoveryAttempts = 0 }
        headReady = BeaconMath.fresh(headTimestamp, now: now)
        guard headReady else {
            if !motionDelayed && motionReceivedAt.isFinite {
                record("머리 방향 데이터 지연 · \(motionStatus)")
                motionDelayed = true
            }
            let retain = BeaconMath.retainsHeadCalibration(headTimestamp, now: now)
            if !retain && initialHeading != nil { record("머리 방향 2초 초과 지연 · 보정 해제") }
            silence(clearCalibration: !retain)
            status = !motionReceivedAt.isFinite ? "이어폰 연결됨 · 머리 방향 첫 샘플 대기" :
                retain ? "머리 방향 수신 지연 · 무음, 보정 유지" : "머리 방향 2초 초과 지연 · 수신 확인 후 방향 재지정 필요"
            return
        }
        guard let packet else { return }
        guard BeaconMath.mayPlay(sample: packet.cue.sampleUptimeSeconds, head: headTimestamp, now: now,
                                  prepared: prepared, headphones: headphones, calibrated: initialHeading != nil),
              let heading, let player, let environment, let ping else {
            silence(); status = "위치 데이터 대기 · P 선택과 머리 방향 보정 유지"; return
        }
        environment.listenerPosition = AVAudio3DPoint(x: Float(packet.listener.x), y: 0, z: -Float(packet.listener.y))
        player.position = AVAudio3DPoint(x: Float(packet.source.x), y: 0, z: -Float(packet.source.y))
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: Float(heading.x), y: 0, z: -Float(heading.y)),
            up: AVAudio3DVector(x: 0, y: 1, z: 0))
        outputGain = BeaconMath.smoothGain(outputGain, target: packet.cue.gain, elapsed: dt)
        player.volume = Float(outputGain)
        if now >= nextPing {
            player.scheduleBuffer(ping, at: nil, options: [.interrupts])
            if !player.isPlaying { player.play() }
            nextPing = now + packet.cue.pulseIntervalSeconds
        }
        status = "공간음향 안내 중 · 가까우면 커지고 멀어지면 작아집니다."
    }
    private func announceArrival() {
        guard let chime, headphones else { return }
        alertPlayer?.scheduleBuffer(chime, at: nil, options: [.interrupts])
        alertPlayer?.play()
        let token = generation
        arrivalTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            guard let self, self.generation == token, self.prepared, self.headphones else { return }
            let utterance = AVSpeechUtterance(string: "도착")
            utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
            self.speech.speak(utterance)
        }
        status = "도착"
    }

    // Mono noise and the 10ms fade are carried over from HapticLab.
    private static func makeNoise(format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let fade = Int(format.sampleRate * 0.01)
        var seed: UInt32 = 777
        for i in 0..<Int(frames) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            var v = Double(seed) / Double(UInt32.max) * 2 - 1
            if i < fade { v *= Double(i) / Double(fade) }
            if i > Int(frames) - fade { v *= Double(Int(frames) - i) / Double(fade) }
            ch[i] = Float(v * 0.5)
        }
        return buffer
    }
    private static func makeTones(_ parts: [(Double, Double)], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let counts = parts.map { Int($0.1 * rate) }
        let total = counts.reduce(0, +)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let l = buffer.floatChannelData?[0], let r = buffer.floatChannelData?[1] else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)
        var i = 0
        for (part, n) in zip(parts, counts) {
            let fade = Int(rate * 0.005)
            for k in 0..<n {
                var v = sin(2 * .pi * part.0 * Double(k) / rate) * 0.5
                if k < fade { v *= Double(k) / Double(fade) }
                if k > n - fade { v *= Double(n - k) / Double(fade) }
                l[i] = Float(v); r[i] = Float(v); i += 1
            }
        }
        return buffer
    }
}
