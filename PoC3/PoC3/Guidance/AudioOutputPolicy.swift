import Foundation

enum AudioOutputMode: String, CaseIterable {
    case speaker, airPods
    var title: String { self == .speaker ? "스피커" : "에어팟" }
}

struct GuidanceAudioPort: Equatable {
    enum Kind { case speaker, bluetooth, other }
    let id: String
    let kind: Kind
}

enum AudioOutputPolicy {
    static func accepts(_ ports: [GuidanceAudioPort], mode: AudioOutputMode,
                        preparedIDs: Set<String>? = nil) -> Bool {
        guard !ports.isEmpty,
              ports.allSatisfy({ $0.kind == (mode == .speaker ? .speaker : .bluetooth) }) else { return false }
        return preparedIDs.map { $0 == Set(ports.map(\.id)) } ?? true
    }
}
