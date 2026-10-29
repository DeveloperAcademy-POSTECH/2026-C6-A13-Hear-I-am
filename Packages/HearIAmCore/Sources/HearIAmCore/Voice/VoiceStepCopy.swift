/// What the voice agent says on reaching each step (#92): the screen's title, what to do there and the
/// word that moves on, the way VoiceOver reads a heading. Titles and words follow the performer screens of
/// the new IA (10/29): 공연 찾기 · 사용 방식 · 출발 준비 · 안내 중. Button-only guidance keeps its own lines.
public enum VoiceStepCopy {
    public static let stageList = "공연 찾기. 어떤 공연을 준비할까요? 공연 이름이나 번호를 말해주세요. 장소 이름으로 찾아 달라고 해도 돼요."

    public static func stageChosen(_ name: String) -> [String] {
        ["\(name), 선택했어요.", "사용 방식. ‘연습용’ 또는 ‘실전용’이라고 말해주세요. 취소라고 하면 공연 찾기로 돌아가요."]
    }

    public static let restoring = "현장 확인. 휴대폰을 손에 들고 주변을 천천히 비춰주세요. 공연장을 찾으면 알려 드릴게요."

    /// `number` is the checkpoint to aim at next, 1 or 2.
    public static func checkpoint(_ number: Int) -> [String] {
        [number == 1 ? "공연장을 찾았어요." : "확인점 1번을 확인했어요.",
         "확인점 \(number)번. 저장한 확인점 \(number)번에 조준점을 맞추고 ‘다음’이라고 말해주세요."]
    }

    public static let wear = ["두 확인점 보정을 마쳤어요.", "허리띠 착용.", GuidanceCopy.doNotDisturb,
                              "휴대폰을 허리 앞쪽에 세로로 고정해주세요. 후면 카메라는 몸 바깥쪽을 향하고 렌즈는 가리지 말아주세요.",
                              "다 차면 ‘착용 완료’라고 말해주세요."]

    public static func departure(started: Bool) -> [String] {
        ["출발 준비.", started ? "안내를 멈춘 동선 위에서 잠시 멈춰주세요." : "지정한 출발점에서 잠시 멈춰주세요. 몸이 향한 방향을 기준으로 안내해요."]
    }

    /// Once the start is held. Performance mode closes the microphone when guidance starts, so it says so.
    public static func departureReady(started: Bool, performance: Bool) -> [String] {
        if started { return ["재개 준비가 됐어요. ‘계속’이라고 말하면 이어서 안내해요."] }
        return ["준비가 되셨다면 ‘출발’이라고 말해주세요. 첫 번째 지점으로 안내해요.",
                performance ? "실전 중에는 호출어를 듣지 않고 이동 안내만 전달해요." : "안내 중에 다른 요청이 필요하면 ‘히얼아이엠’을 불러주세요."]
    }

    public static let paused = "안내를 일시정지했어요. ‘계속’이라고 말하면 이어서 안내해요."

    /// Guidance stopped by itself, off the route or near an obstacle.
    public static func autoPaused(_ reason: String) -> String {
        "잠시 멈춰주세요. \(reason) 동선 위로 돌아오면 ‘계속’이라고 말해주세요."
    }

    public static let interrupted = "위치 또는 소리를 확인할 수 없어 안내를 멈췄어요. 잠시 멈춰주세요. 확인점을 다시 확인하려면 휴대폰을 손에 들고 ‘계속’이라고 말해주세요."

    public static func failed(_ error: String) -> String {
        "공연장을 확인하지 못했어요. \(error) 다시 하려면 ‘계속’, 다른 공연으로 하려면 ‘무대 다시 선택’이라고 말해주세요."
    }
}
