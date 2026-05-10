import Foundation

enum AppLocalization {
    private static let languageKey = "settings.appLanguage"

    static var languageId: String {
        let stored = UserDefaults.standard.string(forKey: languageKey) ?? "en"
        return stored == "uk" ? "uk" : "en"
    }

    static var isUkrainian: Bool {
        languageId == "uk"
    }

    static func t(_ uk: String, _ en: String) -> String {
        isUkrainian ? uk : en
    }
}

