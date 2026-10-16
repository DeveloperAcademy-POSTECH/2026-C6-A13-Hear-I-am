import Foundation

public enum GuidanceCopy {
    public static let completed="마지막 지점에 도착했습니다. 안내를 종료합니다."
    public static func target(_ index: Int, last: Int) -> String {
        if index == last { return "마지막 지점" }
        let ordinals=["출발점","첫 번째 지점","두 번째 지점","세 번째 지점","네 번째 지점"]
        return ordinals.indices.contains(index) ? ordinals[index] : "\(index)번째 지점"
    }
}
