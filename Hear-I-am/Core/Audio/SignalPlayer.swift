import AVFoundation
import UIKit
import os
import HearIAmCore

/// Plays signal tones mixed with speech. The warning loops on its own node, so a one-shot
/// tone (arrival, buzz) never cuts it off. Direction beeps have a node of their own too, so turning
/// right after arriving does not cut the ding. Every play, stop and failure is logged.
@MainActor final class SignalPlayer {
    /// (event, detail) for the experiment log. Guidance forwards these to its trial log.
    var onEvent: ((String,String)->Void)?
    var onError: ((String)->Void)?
    private(set) var warning: WarningLevel?
    /// Timbre for the warning; a running warning switches at once. The choice made in the sound test
    /// tab is saved, so guidance plays the same sound.
    private(set) var warningTone=SignalPlayer.savedWarningTone
    /// 「낮은 삑」 was chosen on 10/18 (#33). A new key, so a tone tried earlier in the test tab does not
    /// override that choice.
    static let toneKey="signal.warningTone.v2"
    static var savedWarningTone: WarningTone {
        UserDefaults.standard.string(forKey:toneKey).flatMap(WarningTone.init(rawValue:)) ?? .low
    }
    static let directionModeKey="signal.directionMode"
    /// How guidance gives the direction at each 45° landmark; chosen in the sound test tab (#33).
    static var directionMode: DirectionSignalMode {
        get { UserDefaults.standard.string(forKey:directionModeKey).flatMap(DirectionSignalMode.init(rawValue:)) ?? .both }
        set { UserDefaults.standard.set(newValue.rawValue,forKey:directionModeKey) }
    }
    private(set) var speechActive=false
    /// A long-running warning is softened so it does not drown the performance.
    private(set) var warningQuiet=false
    private let engine=AVAudioEngine()
    private let warningNode=AVAudioPlayerNode()
    private let shotNode=AVAudioPlayerNode()
    private let directionNode=AVAudioPlayerNode()
    private let format=AVAudioFormat(standardFormatWithSampleRate:ToneRenderer.sampleRate,channels:1)!
    private var buffers: [String:AVAudioPCMBuffer]=[:]
    private var shotVolume=SignalVolume.arrival
    private var observers: [NSObjectProtocol]=[]
    private let log=Logger(subsystem:Bundle.main.bundleIdentifier ?? "HearIAm",category:"Signal")

    init() {
        for node in [warningNode,shotNode,directionNode] {
            engine.attach(node);engine.connect(node,to:engine.mainMixerNode,format:format)
        }
        observers.append(NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.configurationChanged() }
        })
        // Not every output change reaches the engine: on 10/18 the earbud joined after the engine had
        // started on the speaker, and nothing was logged. The session reports each change.
        observers.append(NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] n in
            let reason=(n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            Task { @MainActor in self?.routeChanged(reason) }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Plays one sound once. A new one-shot replaces the previous one on its node (direction beeps
    /// replace direction beeps, other one-shots each other); the warning loop is untouched.
    @discardableResult func play(_ sound: SignalSound) -> Bool {
        guard prepare(sound.name), let buffer=buffer(sound) else { return false }
        let node: AVAudioPlayerNode
        switch sound {
        case .direction,.directionSweep,.directionAligned,.directionBuzz,.directionBuzzAligned: node=directionNode
        default: node=shotNode;shotVolume=volume(sound)
        }
        applyVolumes()
        node.scheduleBuffer(buffer,at:nil,options:.interrupts)
        if !node.isPlaying { node.play() }
        event("signal_play",sound.name)
        return true
    }
    /// Cancel the current direction glide or confirmation immediately; arrival has its own node.
    func stopDirection() { directionNode.stop() }
    /// Starts, changes or stops (nil) the looping obstacle warning.
    func setWarning(_ level: WarningLevel?) {
        guard level != warning else { return }
        let previous=warning;warning=level
        guard let level else {
            warningNode.stop();event("signal_warning",(previous?.name ?? "")+"->off");return
        }
        let sound=SignalSound.warning(level,tone:warningTone)
        guard prepare(sound.name), let buffer=buffer(sound) else { warning=nil;return }
        applyVolumes()
        warningNode.scheduleBuffer(buffer,at:nil,options:[.loops,.interrupts])
        if !warningNode.isPlaying { warningNode.play() }
        event("signal_warning",(previous?.name ?? "off")+"->"+level.name+" tone="+warningTone.rawValue)
    }
    func setWarningTone(_ tone: WarningTone) {
        guard tone != warningTone else { return }
        warningTone=tone;UserDefaults.standard.set(tone.rawValue,forKey:Self.toneKey)
        event("signal_warning_tone",tone.rawValue)
        guard let level=warning else { return }
        warning=nil;setWarning(level)
    }
    /// Lowers every tone while speech plays. Call with the speech's speaking state.
    func setSpeechActive(_ value: Bool) {
        guard value != speechActive else { return }
        speechActive=value;applyVolumes()
    }
    func setWarningQuiet(_ value: Bool) {
        guard value != warningQuiet else { return }
        warningQuiet=value;applyVolumes();event("signal_warning_quiet",value ? "on" : "off")
    }
    func stop() {
        let wasWarning=warning
        warning=nil;warningNode.stop();shotNode.stop();directionNode.stop()
        if wasWarning != nil { event("signal_warning",(wasWarning?.name ?? "")+"->off") }
    }
    /// Stops playback and the engine, e.g. when the screen closes or audio is interrupted.
    func shutdown() { stop();engine.stop();event("signal_engine","stopped") }

    private func prepare(_ name: String) -> Bool {
        do {
            try HearAudioSession.activate()
            guard AVAudioSession.sharedInstance().outputVolume > 0 else {
                onError?("소리가 꺼져 있어요. 휴대폰의 음량을 확인해주세요.");return false
            }
            if !engine.isRunning { try engine.start();event("signal_engine","started route="+HearAudioSession.route) }
            return true
        } catch {
            event("signal_error","\(name) \(error.localizedDescription)",level:.error)
            onError?("안내 신호를 재생할 수 없어요. 소리 출력을 확인해주세요.");return false
        }
    }
    private func buffer(_ sound: SignalSound) -> AVAudioPCMBuffer? {
        if let cached=buffers[sound.name] { return cached }
        let samples=ToneRenderer.render(sound)
        guard !samples.isEmpty, let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)),
              let channel=buffer.floatChannelData?[0] else {
            event("signal_error","\(sound.name) buffer",level:.error)
            onError?("안내 신호를 만들 수 없어요. 안내를 다시 시작해주세요.");return nil
        }
        buffer.frameLength=AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from:$0.baseAddress!,count:samples.count) }
        buffers[sound.name]=buffer;return buffer
    }
    private func volume(_ sound: SignalSound) -> Float {
        switch sound {
        case .warning: return SignalVolume.warning
        case .arrival: return SignalVolume.arrival
        case .direction,.directionSweep,.directionAligned,.directionBuzz,.directionBuzzAligned: return SignalVolume.direction
        case .buzz: return SignalVolume.buzz
        }
    }
    private func applyVolumes() {
        let share=speechActive ? SignalVolume.duckedShare : 1
        warningNode.volume=SignalVolume.warning*share*(warningQuiet ? SignalVolume.quietShare : 1);shotNode.volume=shotVolume*share
        directionNode.volume=SignalVolume.direction*share
    }
    private func routeChanged(_ reason: AVAudioSession.RouteChangeReason?) {
        event("signal_route",Self.name(reason)+" route="+HearAudioSession.route)
    }
    /// Route changes (earbud in/out) can stop the engine. A running warning is restarted on the new route.
    private func configurationChanged() {
        event("signal_engine","reconfigured route="+HearAudioSession.route)
        guard let level=warning else { return }
        warning=nil;setWarning(level)
    }
    private static func name(_ reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: return "device_added"
        case .oldDeviceUnavailable: return "device_removed"
        case .categoryChange: return "category"
        case .override: return "override"
        case .wakeFromSleep: return "wake"
        case .noSuitableRouteForCategory: return "no_route"
        case .routeConfigurationChange: return "configuration"
        default: return "unknown"
        }
    }
    private func event(_ name: String, _ detail: String, level: OSLogType = .info) {
        log.log(level:level,"\(name, privacy:.public) \(detail, privacy:.public)")
        onEvent?(name,detail)
    }
}

/// Test-only continuous mono oscillator. One render stream, no replayed audio clips.
@MainActor final class ContinuousTonePlayer {
    var onUnavailable: ((String)->Void)?
    private let engine=AVAudioEngine()
    private let state=ContinuousToneRenderState()
    private var observers: [NSObjectProtocol]=[]
    private var active=false
    init() {
        let state=self.state
        let format=AVAudioFormat(standardFormatWithSampleRate:ToneRenderer.sampleRate,channels:1)!
        let source=AVAudioSourceNode(format:format) { _,_,frames,buffers in
            state.render(frames:Int(frames),buffers:buffers)
            return noErr
        }
        engine.attach(source);engine.connect(source,to:engine.mainMixerNode,format:format)
        for name in [AVAudioSession.interruptionNotification,AVAudioSession.routeChangeNotification,
                     UIApplication.willResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] note in
                if note.name == AVAudioSession.routeChangeNotification,
                   let raw=note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   AVAudioSession.RouteChangeReason(rawValue:raw) == .categoryChange { return }
                let interruption=note.name == AVAudioSession.interruptionNotification
                Task { @MainActor in
                    guard let self, self.active else { return }
                    self.stop()
                    if interruption { HearAudioSession.interrupted() }
                    self.onUnavailable?(interruption ? "오디오 중단" : "출력 변경 또는 화면 비활성화")
                }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    @discardableResult func start() -> Bool {
        do {
            try HearAudioSession.activate()
            guard AVAudioSession.sharedInstance().outputVolume > 0 else { onUnavailable?("휴대폰 음량을 확인해주세요.");return false }
            state.command.withLock { $0=ContinuousToneCommand(hertz:nil,updatedAt:ProcessInfo.processInfo.systemUptime) }
            if !engine.isRunning { try engine.start() }
            active=true;return true
        } catch { stop();onUnavailable?("지속음을 시작할 수 없어요: "+error.localizedDescription);return false }
    }
    func setHertz(_ hertz: Double?) {
        state.command.withLock { $0=ContinuousToneCommand(hertz:hertz,updatedAt:ProcessInfo.processInfo.systemUptime) }
    }
    func stop() { active=false;setHertz(nil);engine.stop() }
}

/// Main writes one small command; the render thread never waits on its lock or allocates samples.
private final class ContinuousToneRenderState: @unchecked Sendable {
    let command=OSAllocatedUnfairLock(initialState:ContinuousToneCommand(hertz:nil,updatedAt:0))
    private var latest=ContinuousToneCommand(hertz:nil,updatedAt:0)
    private var oscillator=ContinuousSineOscillator()
    func render(frames: Int, buffers: UnsafeMutablePointer<AudioBufferList>) {
        if let next=command.withLockIfAvailable({ $0 }) { latest=next }
        let target=latest.activeHertz(at:ProcessInfo.processInfo.systemUptime)
        // The source format is mono non-interleaved Float32.
        guard let data=buffers.pointee.mBuffers.mData else { return }
        oscillator.render(into:UnsafeMutableBufferPointer(start:data.assumingMemoryBound(to:Float.self),count:frames),
                          targetHertz:target,sampleRate:ToneRenderer.sampleRate)
    }
}
