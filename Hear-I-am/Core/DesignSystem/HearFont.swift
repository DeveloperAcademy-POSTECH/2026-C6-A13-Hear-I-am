import CoreText
import SwiftUI

/// The design's typefaces, bundled in Resources/Fonts (both SIL Open Font License 1.1, licence files alongside):
/// Pretendard for Korean text and SUIT for the 「Hear I am」 wordmark. They are registered for the process at
/// launch instead of through Info.plist, because the Info.plist is generated from build settings.
enum HearFont {
    enum Pretendard: String {
        case regular="Pretendard-Regular", medium="Pretendard-Medium", semibold="Pretendard-SemiBold", bold="Pretendard-Bold"
    }
    static let suitExtraLight="SUIT-ExtraLight"

    static func pretendard(_ weight: Pretendard, size: CGFloat) -> Font {.custom(weight.rawValue,fixedSize:size)}
    static func suitExtraLight(size: CGFloat) -> Font {.custom(suitExtraLight,fixedSize:size)}

    static func registerBundled() {
        let urls=Bundle.main.urls(forResourcesWithExtension:"otf",subdirectory:nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray,.process,true,nil)
    }
}
