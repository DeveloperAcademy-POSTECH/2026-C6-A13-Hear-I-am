import Foundation

public enum LabError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(s)=self { return s }; return nil }
}
