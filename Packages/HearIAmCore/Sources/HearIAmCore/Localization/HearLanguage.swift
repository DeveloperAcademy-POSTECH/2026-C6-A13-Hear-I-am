import Foundation
import Observation

/// The language the app shows and speaks in (#183). Korean is the source text; English comes from the app's
/// `Localizable.xcstrings`. The choice is the app's own, set in Settings, so it switches without a restart and
/// without changing the phone's language.
public enum HearLanguage: String, CaseIterable, Sendable {
    case korean = "ko"
    case english = "en"

    public static let storageKey = "app.language"

    /// The saved choice, or the phone's language the first time (Korean unless the phone prefers another language).
    /// Read inside a SwiftUI body, it makes that view redraw when the language changes.
    public static var current: HearLanguage { HearLanguageStore.shared.language }

    /// Saves the choice and redraws every view that showed translated text. The phone's own language list for
    /// this app follows too, so permission prompts and Siri phrases, which iOS reads itself, match after the
    /// next launch.
    public static func choose(_ language: HearLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        HearLanguageStore.shared.language = language
    }

    static var saved: HearLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey), let saved = HearLanguage(rawValue: raw) { return saved }
        // Without an English table (unit tests, a build that lost it) the app can only be Korean.
        guard let first = Locale.preferredLanguages.first, HearText.hasEnglish else { return .korean }
        return first.hasPrefix("ko") ? .korean : .english
    }

    public var isEnglish: Bool { self == .english }
    /// For dates and numbers on screen.
    public var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "ko_KR") }
    /// For speech recognition and the speaking voice.
    public var speechCode: String { isEnglish ? "en-US" : "ko-KR" }
    /// The name shown on the switch, always in its own language.
    public var nativeName: String { isEnglish ? "English" : "한국어" }
}

/// Translated text for `key`, the Korean source sentence. `%@` and `%1$@`… in it are filled with `args` in order.
/// Korean returns the key itself; English looks it up in the app's English table and falls back to Korean when a
/// sentence has no translation yet.
public func L(_ key: String, _ args: Any...) -> String {
    HearText.fill(HearText.translate(key), args)
}

public enum HearText {
    private static let tables = HearTextTables()
    static var hasEnglish: Bool { tables.bundle(for: HearLanguage.english.rawValue) != nil }

    public static func translate(_ key: String, in language: HearLanguage = .current) -> String {
        guard language.isEnglish, let bundle = tables.bundle(for: language.rawValue) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    /// Fills `%@` (in order) and `%n$@` (by position). Other `%` sequences are left for `String(format:)`.
    public static func fill(_ format: String, _ args: [Any]) -> String {
        guard !args.isEmpty, format.contains("%") else { return format }
        let values = args.map { String(describing: $0) }
        var out = ""
        var next = 0
        var i = format.startIndex
        while i < format.endIndex {
            let c = format[i]
            guard c == "%" else { out.append(c); i = format.index(after: i); continue }
            let rest = format[format.index(after: i)...]
            if rest.hasPrefix("@") {
                out += next < values.count ? values[next] : ""
                next += 1
                i = format.index(i, offsetBy: 2)
                continue
            }
            let digits = rest.prefix { $0.isNumber }
            if !digits.isEmpty, rest.dropFirst(digits.count).hasPrefix("$@"), let n = Int(digits) {
                out += n >= 1 && n <= values.count ? values[n - 1] : ""
                i = format.index(i, offsetBy: 1 + digits.count + 2)
                continue
            }
            out.append(c)
            i = format.index(after: i)
        }
        return out
    }
}

private final class HearTextTables: @unchecked Sendable {
    private let lock = NSLock()
    private var bundles: [String: Bundle] = [:]
    func bundle(for code: String) -> Bundle? {
        lock.lock(); defer { lock.unlock() }
        if let cached = bundles[code] { return cached }
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        bundles[code] = bundle
        return bundle
    }
}

/// Holds the language so that SwiftUI views reading it (through `L`) redraw when it changes. It is read from
/// any thread: guidance and speech code ask for text off the main thread.
public final class HearLanguageStore: Observable, @unchecked Sendable {
    public static let shared = HearLanguageStore()
    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var value = HearLanguage.saved

    public var language: HearLanguage {
        get {
            registrar.access(self, keyPath: \.language)
            lock.lock(); defer { lock.unlock() }
            return value
        }
        set {
            registrar.withMutation(of: self, keyPath: \.language) {
                lock.lock(); value = newValue; lock.unlock()
            }
        }
    }
}
