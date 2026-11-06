import SwiftUI

/// Public support and privacy links, reached through Settings → App Info.
struct AppInfoView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
    private let privacyURL = URL(string: "https://xrpjwk8.github.io/heariam-help/privacy/")!
    private let supportURL = URL(string: "https://xrpjwk8.github.io/heariam-help/support/")!

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SettingsSectionHeader(title: "Hear I am")
                SettingsGroup {
                    SettingsRowLabel(title: "버전", value: version, accessory: .none)
                    SettingsDivider()
                    SettingsRowLabel(title: "운영 주체", value: "Hear I am", accessory: .none)
                }.padding(.bottom, 24)

                SettingsSectionHeader(title: "개인정보 및 고객지원")
                SettingsGroup {
                    Link(destination: privacyURL) {
                        SettingsRowLabel(title: "개인정보처리방침")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("웹 브라우저에서 개인정보처리방침을 엽니다.")
                    .accessibilityIdentifier("appInfo.privacy")
                    SettingsDivider()
                    Link(destination: supportURL) {
                        SettingsRowLabel(title: "고객지원")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("웹 브라우저에서 도움말과 문의 페이지를 엽니다.")
                    .accessibilityIdentifier("appInfo.support")
                }
                Text("링크를 누르면 웹 브라우저가 열립니다.")
                    .font(.footnote)
                    .foregroundStyle(SettingsStyle.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .settingsScreen()
        .navigationTitle("앱 정보")
        .navigationBarTitleDisplayMode(.inline)
        .readsAloud {
            ["앱 정보", "Hear I am", "버전, \(version)", "운영 주체, Hear I am",
             "개인정보 및 고객지원", "개인정보처리방침 링크", "고객지원 링크",
             "링크를 누르면 웹 브라우저가 열립니다."]
        }
    }
}
