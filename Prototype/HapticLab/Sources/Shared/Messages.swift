import Foundation

/// iPhone → Watch 로 보내는 지시.
/// 문서 §A5.2 — 늦게 도착한 지시는 틀린 지시다. 그래서 유효 시간을 함께 보낸다.
struct GuideCommand: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var signal: GuideSignal
    var deviation: Deviation?
    /// 보낸 쪽 시계 기준 전송 시각
    var sentAt: Date = Date()
    /// 이 시간이 지나면 **재생하지 않고 버린다**
    var validForMs: Int = 700
    /// 지연 측정(E8)용 표식
    var isProbe: Bool = false
    /// 반복 중인 방향 신호를 멈춘다 — "잘 가고 있다"는 뜻의 침묵으로 돌아간다
    var silence: Bool?

    var dictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    init(signal: GuideSignal, deviation: Deviation? = nil, validForMs: Int = 700,
         isProbe: Bool = false, silence: Bool? = nil) {
        self.silence = silence
        self.signal = signal
        self.deviation = deviation
        self.validForMs = validForMs
        self.isProbe = isProbe
    }

    init?(dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let decoded = try? JSONDecoder().decode(GuideCommand.self, from: data)
        else { return nil }
        self = decoded
    }
}

/// Watch → iPhone 회신.
/// iPhone 과 Watch 의 시계는 서로 다르므로 **편도 지연을 직접 잴 수 없다.**
/// 그래서 왕복 시간(iPhone 시계만으로 잰다)과 Watch 안에서의 처리 시간을 따로 보낸다.
struct GuideAck: Codable, Sendable {
    var commandId: UUID
    /// Watch 가 받은 순간부터 햅틱을 실제로 호출하기까지 걸린 시간(ms) — Watch 로컬 시계
    var onWatchMs: Double
    /// 유효 시간이 지나 버린 지시인가
    var wasDropped: Bool
    /// 앞선 신호가 울리는 중이라 우선순위에 밀려 버려졌는가(§A5.2)
    var wasPreempted: Bool

    var dictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    init(commandId: UUID, onWatchMs: Double, wasDropped: Bool, wasPreempted: Bool) {
        self.commandId = commandId
        self.onWatchMs = onWatchMs
        self.wasDropped = wasDropped
        self.wasPreempted = wasPreempted
    }

    init?(dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let decoded = try? JSONDecoder().decode(GuideAck.self, from: data)
        else { return nil }
        self = decoded
    }
}
