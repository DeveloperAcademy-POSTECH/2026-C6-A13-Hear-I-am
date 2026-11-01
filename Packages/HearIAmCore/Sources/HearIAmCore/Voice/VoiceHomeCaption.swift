/// Display-only captions for Home. Partial recognition never becomes an accepted command here.
public struct VoiceHomeCaption: Equatable, Sendable {
    public private(set) var transcript = ""
    public private(set) var narration = ""

    public init() {}

    /// Narration can overlap a request without replacing what the user has said.
    public mutating func updateNarration(_ text: String) {
        narration = text
    }

    /// Recognizers revise the entire partial result; each update replaces the previous caption.
    public mutating func receivePartial(
        _ text: String,
        isAwake: Bool,
        isEnglish: Bool,
        overlappingNarration: Bool,
        spokenLines: [String]
    ) {
        guard isAwake, !isEnglish else { return }
        transcript = overlappingNarration
            ? VoiceEcho.strippingLeadingEcho(text, of: spokenLines)
            : text
    }

    public mutating func clearRequest() {
        transcript = ""
    }

    public mutating func reset() {
        transcript = ""
        narration = ""
    }
}
