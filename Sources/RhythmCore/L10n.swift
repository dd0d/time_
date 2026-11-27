import Foundation

public enum L10n {
    public static let languagePreference = "interfaceLanguage"
    // Read once so AppKit menus, notifications and SwiftUI agree until relaunch.
    public static let language = UserDefaults.standard.string(forKey: languagePreference) == "ru" ? "ru" : "en"
    public static let locale = Locale(identifier: language)
    private static let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))

    public static func text(_ value: String.LocalizationValue) -> String {
        String(localized: value, bundle: bundle, locale: locale)
    }

    public static func label(_ key: String) -> String {
        bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }
}
