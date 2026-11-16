import AVFoundation

/// A short two-note listening cue, separate from alignment/arrival signals.
@MainActor final class VoiceListeningChime {
    private var player: AVAudioPlayer?
    func play() {
        do {
            try HearAudioSession.activate()
            let player=try AVAudioPlayer(data:Self.wave())
            player.volume=0.28
            self.player=player
            player.prepareToPlay();player.play()
        } catch { /* The visible listening state remains available when output fails. */ }
    }
    func stop() { player?.stop();player=nil }
    private static func wave() -> Data {
        let rate=24_000, count=5_280
        var pcm=Data()
        for i in 0..<count {
            let t=Double(i)/Double(rate), duration=Double(count)/Double(rate)
            let attack=min(1,t/0.012), release=max(0,1-t/duration)
            let value=(sin(2 * .pi * 1046.5 * t)+0.35*sin(2 * .pi * 1568 * t))*attack*release*release*0.45
            var sample=Int16(max(-32767,min(32767,value*32767))).littleEndian
            withUnsafeBytes(of:&sample) {pcm.append(contentsOf:$0)}
        }
        var data=Data()
        func text(_ value:String) {data.append(contentsOf:value.utf8)}
        func integer<T:FixedWidthInteger>(_ value:T) {var n=value.littleEndian;withUnsafeBytes(of:&n) {data.append(contentsOf:$0)}}
        text("RIFF");integer(UInt32(36+pcm.count));text("WAVEfmt ");integer(UInt32(16))
        integer(UInt16(1));integer(UInt16(1));integer(UInt32(rate));integer(UInt32(rate*2))
        integer(UInt16(2));integer(UInt16(16));text("data");integer(UInt32(pcm.count));data.append(pcm)
        return data
    }
}
