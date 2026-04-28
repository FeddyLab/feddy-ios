import Foundation

/// Lookup helper for strings in the SDK's `Localizable.xcstrings` catalog.
///
/// Use this from inside SDK UI components so the host app's locale is
/// honoured automatically. The catalog ships English source plus
/// `es / ja / de / fr` translations.
enum Localization {
    static let bundle: Bundle = .module

    /// Fetch a localized string by key. Returns the key itself as a
    /// last-resort fallback so missing translations are visible during
    /// development rather than silently rendering empty strings.
    static func string(_ key: String, comment: StaticString = "") -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
