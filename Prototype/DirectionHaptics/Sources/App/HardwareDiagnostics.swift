#if DEBUG
import CoreMotion
import Foundation

/// Explicit developer launch argument only; no recordings or user data are saved.
@MainActor
enum HardwareDiagnostics {
    static func run(haptics: HapticService) async {
        print("HARDWARE BEGIN supportsHaptics=\(haptics.supportsHaptics) preview=\(haptics.isPreview)")
        let manager = CMMotionManager()
        manager.deviceMotionUpdateInterval = 0.02
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        for index in 0..<5 {
            try? await Task.sleep(for: .seconds(1))
            if let sample = manager.deviceMotion {
                print("HARDWARE MOTION \(index) timestamp=\(sample.timestamp) uptime=\(ProcessInfo.processInfo.systemUptime) delta=\(ProcessInfo.processInfo.systemUptime - sample.timestamp) gravity=\(sample.gravity) yaw=\(sample.attitude.yaw)")
            } else { print("HARDWARE MOTION \(index) missing available=\(manager.isDeviceMotionAvailable) active=\(manager.isDeviceMotionActive)") }
        }
        manager.stopDeviceMotionUpdates()
        for set in Presets.all {
            do {
                try await haptics.play(set.pattern(for: .front))
                print("HARDWARE HAPTIC \(set.code) completed")
            } catch { print("HARDWARE HAPTIC \(set.code) failed=\(error)") }
        }
        let interrupted = Task { try await haptics.play(.init(steps: [.buzz(1.5)])) }
        try? await Task.sleep(for: .milliseconds(250))
        haptics.stop(interrupted: true)
        do { try await interrupted.value; print("HARDWARE CANCEL unexpected completion") }
        catch { print("HARDWARE CANCEL returned=\(error)") }
        do {
            try await haptics.play(Presets.all[0].pattern(for: .front))
            print("HARDWARE RETRY completed")
        } catch { print("HARDWARE RETRY failed=\(error)") }
        let sound = FeedbackSoundService()
        do { try sound.prepare(); try sound.play(); print("HARDWARE SOUND started") }
        catch { print("HARDWARE SOUND failed=\(error)") }
        try? await Task.sleep(for: .seconds(1))
        sound.close()
        var preferences = AppPreferences(); preferences.preparationSeconds = 3
        let runner = RandomPracticeRunner(set: Presets.all[0], preferences: preferences, haptics: haptics)
        runner.start()
        for _ in 0..<12 {
            try? await Task.sleep(for: .seconds(1))
            print("HARDWARE RUNNER phase=\(runner.phase) issue=\(runner.issue ?? "none") faceUp=\(runner.faceUp) angle=\(runner.relativeDegrees) count=\(runner.completed)")
        }
        runner.close()
        print("HARDWARE END")
    }
}
#endif
