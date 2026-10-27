import Foundation

/// The tutorial describes the shipping signals; it never changes guidance preferences.
public enum SignalTutorialPlayback: Equatable, Sendable {
    case directionTick(toRight: Bool)
    case aligned
    case arrival
    case speech(String)
    /// The next point's side uses the louder direction voice in actual guidance.
    case nextSide(String)
    case completion
}

public struct SignalTutorialExample: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let playback: SignalTutorialPlayback

    public init(_ id: String, _ title: String, _ detail: String, symbol: String = "speaker.wave.2", playback: SignalTutorialPlayback) {
        self.id=id;self.title=title;self.detail=detail;self.symbol=symbol;self.playback=playback
    }
}

public struct SignalTutorialGroup: Identifiable, Sendable {
    public let title: String
    public let examples: [SignalTutorialExample]
    public var id: String { title }
}

/// All 23 previews from the develop tutorial are distributed across these five steps.
public enum SignalTutorialStep: Int, CaseIterable, Identifiable, Sendable {
    case preparation=1, direction, alignment, arrival, objects
    public var id: Int { rawValue }
    public var previous: Self? { Self(rawValue:rawValue-1) }
    public var next: Self? { Self(rawValue:rawValue+1) }

    public var title: String {
        switch self {
        case .preparation: return "듣기 준비"
        case .direction: return "방향 찾기"
        case .alignment: return "방향 맞춤과 거리"
        case .arrival: return "출발·도착·대기"
        case .objects: return "의자와 계단"
        }
    }
    public var subtitle: String {
        switch self {
        case .preparation: return "소리 출력과 음량 확인"
        case .direction: return "왼쪽과 오른쪽 신호"
        case .alignment: return "방향 맞음 신호와 남은 거리"
        case .arrival: return "지점 이름과 마지막 도착"
        case .objects: return "도착 후 바라볼 방향"
        }
    }
    public var question: String {
        switch self {
        case .preparation: return "소리가 잘 들리나요?"
        case .direction: return "어느 쪽으로 돌아야 할까요?"
        case .alignment: return "방향이 맞으면 무엇을 들을까요?"
        case .arrival: return "어디에 도착했을까요?"
        case .objects: return "도착한 뒤 어디를 볼까요?"
        }
    }
    public var explanation: String {
        switch self {
        case .preparation: return "연결된 이어폰이 있으면 이어폰으로, 없으면 iPhone 스피커로 들려요. 함께 듣고 싶다면 소리 출력에서 스피커를 선택하세요. 음량은 iPhone의 음량 버튼으로 조절해요."
        case .direction: return "낮은 톡 소리는 왼쪽, 높은 톡 소리는 오른쪽으로 몸을 돌리라는 뜻이에요. 목표 방향에 가까워질수록 톡 소리가 빨라지고, 방향이 맞으면 멈춰요."
        case .alignment: return "방향이 맞으면 확인 소리가 들려요. 이후 남은 거리를 듣고 이동해요. 방향 맞음은 지점에 도착했다는 뜻과 달라요."
        case .arrival: return "출발할 때는 출발, 중간 지점에 도착하면 피원이나 피투처럼 지점 이름을 말해요. 마지막에는 띵 소리 뒤에 마지막 지점 도착이라고 알려줘요."
        case .objects: return "의자나 계단으로 갈 때 기물 이름을 미리 알려줘요. 도착하면 의자일이나 계단일이라고 말하고, 바라볼 방향이 정해져 있으면 오른쪽 봐 또는 왼쪽 봐로 안내해요. 그 방향을 맞춘 뒤 다음 지점 안내가 이어져요."
        }
    }
    public var together: String {
        switch self {
        case .preparation: return "실제로 사용할 이어폰으로 들어보고 편안한 음량인지 함께 확인해보세요."
        case .direction: return "두 소리가 어떻게 다른지 이야기해보세요. 왼쪽과 오른쪽 음성도 각각 들어볼 수 있어요."
        case .alignment: return "방향 맞음과 지점 도착을 구분하고, 거리 안내가 어떻게 들리는지 확인해보세요."
        case .arrival: return "대기 시간이 설정된 중간 지점에서는 다음 안내가 잠시 쉬어요. 시간이 끝나면 이어지고, 일시정지 중에는 남은 시간이 유지돼요."
        case .objects: return "기물의 위치를 알리는 말과 도착 후 바라볼 방향을 알리는 말을 구분해보세요."
        }
    }
    public var groups: [SignalTutorialGroup] {
        switch self {
        case .preparation:
            return [.init(title:"출발 준비 완료 신호",examples:[
                .init("ready-ding","띵","출발 준비가 끝났을 때 들리는 소리",playback:.arrival)
            ])]
        case .direction:
            return [
                .init(title:"몸을 돌릴 방향",examples:[
                    .init("tick-left","왼쪽으로 돌기","낮은 톡 소리",symbol:"arrow.turn.up.left",playback:.directionTick(toRight:false)),
                    .init("tick-right","오른쪽으로 돌기","높은 톡 소리",symbol:"arrow.turn.up.right",playback:.directionTick(toRight:true))
                ]),
                .init(title:"다음 지점 방향",examples:[
                    .init("next-left",SignalCopy.left,"출발·지점 도착 직후 더 크게 알려줘요",playback:.nextSide(SignalCopy.left)),
                    .init("next-right",SignalCopy.right,"출발·지점 도착 직후 더 크게 알려줘요",playback:.nextSide(SignalCopy.right))
                ]),
                .init(title:"방향이 틀렸을 때",examples:[
                    .init("correct-left",SignalCopy.left,"톡 소리 시작 전에 한 번 알려줘요",playback:.speech(SignalCopy.left)),
                    .init("correct-right",SignalCopy.right,"톡 소리 시작 전에 한 번 알려줘요",playback:.speech(SignalCopy.right))
                ])
            ]
        case .alignment:
            return [
                .init(title:"방향 맞음",examples:[.init("aligned","방향 맞음 신호","실제 안내에서 사용하는 확인 소리",symbol:"checkmark",playback:.aligned)]),
                .init(title:"남은 거리",examples:[3.0,2,1,0.5].map { meters in
                    .init("distance-\(Int(meters*100))",SignalCopy.distance(meters),"목표 지점까지 남은 거리",playback:.speech(SignalCopy.distance(meters)))
                })
            ]
        case .arrival:
            return [
                .init(title:"출발",examples:[.init("start",SignalCopy.start,"안내가 시작될 때 들리는 말",playback:.speech(SignalCopy.start))]),
                .init(title:"중간 지점 도착",examples:[1,2].map { number in
                    .init("point-\(number)","P\(number) 도착",SignalCopy.point(number)+"라고 읽어요",playback:.speech(SignalCopy.point(number)))
                }),
                .init(title:"마지막 지점 도착",examples:[
                    .init("completion","띵 + 완료 안내","띵 소리 0.7초 뒤 마지막 지점 도착",playback:.completion),
                    .init("completed-voice",GuidanceCopy.completed,"완료 음성만 들어보기",playback:.speech(GuidanceCopy.completed))
                ])
            ]
        case .objects:
            return [
                .init(title:"기물 사전 안내",examples:[false,true].map { stairs in
                    .init(stairs ? "hint-stairs" : "hint-chair",SignalCopy.stepHint(stairs:stairs),"방향 맞음 후 거리 안내 전에 알려줘요",playback:.speech(SignalCopy.stepHint(stairs:stairs)))
                }),
                .init(title:"기물 지점 도착",examples:[false,true].map { stairs in
                    .init(stairs ? "point-stairs" : "point-chair",stairs ? "계단1 도착" : "의자1 도착",SignalCopy.stepPoint(stairs:stairs,number:1)+"이라고 읽어요",playback:.speech(SignalCopy.stepPoint(stairs:stairs,number:1)))
                }),
                .init(title:"도착 후 바라볼 방향",examples:[false,true].map { right in
                    .init(right ? "look-right" : "look-left",SignalCopy.look(toRight:right),"기물에 설정된 방향으로 몸을 돌려요",playback:.speech(SignalCopy.look(toRight:right)))
                })
            ]
        }
    }
}
