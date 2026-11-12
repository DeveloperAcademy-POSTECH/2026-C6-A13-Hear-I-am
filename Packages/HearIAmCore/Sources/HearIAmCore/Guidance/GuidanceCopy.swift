import Foundation

public enum GuidanceCopy {
    public static var completed: String { L("마지막 지점 도착") }
    /// Read before the phone goes on the belt: iOS gives apps no way to turn Do Not Disturb on (#65).
    public static var doNotDisturb: String { L("방해 금지 모드를 켜주세요. 안내 중에 알림이 오면 소리가 끊길 수 있습니다.") }
    public static func target(_ index: Int, last: Int) -> String {
        if index == last { return L("마지막 지점") }
        let ordinals=[L("출발점"),L("첫 번째 지점"),L("두 번째 지점"),L("세 번째 지점"),L("네 번째 지점")]
        return ordinals.indices.contains(index) ? ordinals[index] : L("%@번째 지점", index)
    }
}
