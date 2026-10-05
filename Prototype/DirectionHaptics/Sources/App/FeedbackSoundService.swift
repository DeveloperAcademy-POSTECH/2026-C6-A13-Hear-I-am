import AVFAudio

@MainActor
final class FeedbackSoundService {
    private var successPlayer: AVAudioPlayer?
    private var incorrectPlayer: AVAudioPlayer?
    private var ownsSession = false

    func prepare() throws {
        guard successPlayer == nil || incorrectPlayer == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Eyes-closed feedback stays audible in silent mode without changing volume.
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
            ownsSession = true
            successPlayer = try makePlayer(resource: "success")
            incorrectPlayer = try makePlayer(resource: "incorrect")
        } catch {
            close()
            throw error
        }
    }
    private func makePlayer(resource: String) throws -> AVAudioPlayer {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav") else {
            throw NSError(domain: "FeedbackSound", code: 1, userInfo: [NSLocalizedDescriptionKey: "알림음 파일을 찾지 못했습니다."])
        }
        let player = try AVAudioPlayer(contentsOf: url)
        player.prepareToPlay()
        return player
    }
    func play(correct: Bool = true) throws {
        try prepare()
        stop()
        guard let player = correct ? successPlayer : incorrectPlayer else { return }
        player.currentTime = 0
        guard player.play() else {
            throw NSError(domain: "FeedbackSound", code: 2, userInfo: [NSLocalizedDescriptionKey: "알림음을 재생하지 못했습니다."])
        }
    }
    func stop() { successPlayer?.stop(); incorrectPlayer?.stop() }
    func close() {
        stop(); successPlayer = nil; incorrectPlayer = nil
        if ownsSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsSession = false
        }
    }
}
