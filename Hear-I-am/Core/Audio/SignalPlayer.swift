import AVFoundation
import os
import HearIAmCore

/// Plays signal tones mixed with speech. The warning loops on its own node, so a one-shot
/// tone (arrival, buzz) never cuts it off. Direction beeps have a node of their own too, so turning
/// right after arriving does not cut the ding. Every play, stop and failure is logged.
@MainActor final class SignalPlayer {
    /// (event, detail) for the experiment log. Guidance forwards these to its trial log.
    var onEvent: ((String,String)->Void)?
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
    private var observer: NSObjectProtocol?
    private let log=Logger(subsystem:Bundle.main.bundleIdentifier ?? "HearIAm",category:"Signal")

    init() {
        for node in [warningNode,shotNode,directionNode] {
            engine.attach(node);engine.connect(node,to:engine.mainMixerNode,format:format)
        }
        observer=NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.configurationChanged() }
        }
    }
    deinit { observer.map(NotificationCenter.default.removeObserver) }

    /// Plays one sound once. A new one-shot replaces the previous one on its node (direction beeps
    /// replace direction beeps, other one-shots each other); the warning loop is untouched.
    func play(_ sound: SignalSound) {
        guard prepare(sound.name), let buffer=buffer(sound) else { return }
        let node: AVAudioPlayerNode
        if case .direction=sound { node=directionNode } else { node=shotNode;shotVolume=volume(sound) }
        applyVolumes()
        node.scheduleBuffer(buffer,at:nil,options:.interrupts)
        if !node.isPlaying { node.play() }
        event("signal_play",sound.name)
    }
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
            if !engine.isRunning { try engine.start();event("signal_engine","started route="+HearAudioSession.route) }
            return true
        } catch {
            event("signal_error","\(name) \(error.localizedDescription)",level:.error);return false
        }
    }
    private func buffer(_ sound: SignalSound) -> AVAudioPCMBuffer? {
        if let cached=buffers[sound.name] { return cached }
        let samples=ToneRenderer.render(sound)
        guard !samples.isEmpty, let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)),
              let channel=buffer.floatChannelData?[0] else {
            event("signal_error","\(sound.name) buffer",level:.error);return nil
        }
        buffer.frameLength=AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from:$0.baseAddress!,count:samples.count) }
        buffers[sound.name]=buffer;return buffer
    }
    private func volume(_ sound: SignalSound) -> Float {
        switch sound {
        case .warning: return SignalVolume.warning
        case .arrival: return SignalVolume.arrival
        case .direction: return SignalVolume.direction
        case .buzz: return SignalVolume.buzz
        }
    }
    private func applyVolumes() {
        let share=speechActive ? SignalVolume.duckedShare : 1
        warningNode.volume=SignalVolume.warning*share*(warningQuiet ? SignalVolume.quietShare : 1);shotNode.volume=shotVolume*share
        directionNode.volume=SignalVolume.direction*share
    }
    /// Route changes (earbud in/out) stop the engine. A running warning is restarted on the new route.
    private func configurationChanged() {
        event("signal_route","changed route="+HearAudioSession.route)
        guard let level=warning else { return }
        warning=nil;setWarning(level)
    }
    private func event(_ name: String, _ detail: String, level: OSLogType = .info) {
        log.log(level:level,"\(name, privacy:.public) \(detail, privacy:.public)")
        onEvent?(name,detail)
    }
}
