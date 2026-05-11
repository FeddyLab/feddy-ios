import Foundation

/// Display-name resolution for board keys. Mirrors the React Native
/// SDK's `localizedBoardName` precedence so the two SDKs render the
/// same board name for the same key on the same device locale.
///
/// Precedence:
///
/// 1. **SDK system key** (`features` / `bugs`) → bundled
///    `Localizable.xcstrings` catalog (`feddy.compose.board.<key>`).
///    Locked — host overrides are intentionally ignored to keep
///    first-party UI consistent across SDK platforms.
/// 2. **Host translation** for `key` at the current device locale,
///    set via ``Feddy/configure(apiKey:autoDetectSubscription:boardTranslations:)``.
/// 3. **`fallbackName`** — typically the server's `board.name`
///    (admin's dashboard input).
/// 4. Capitalized key as a last-ditch label so the picker is never
///    empty.
enum BoardLocalization {
    static let systemKeys: Set<String> = ["features", "bugs"]

    /// `app.feddy.boardTranslations.runtime` — runtime-only state
    /// holding the host's `boardTranslations` dictionary so view code
    /// can resolve names without threading the configuration through
    /// every helper. Written by ``Feddy/configure(...)``, cleared by
    /// ``Feddy/reset()``.
    private static let translations = Locked<BoardTranslations>([:])

    static func setHostTranslations(_ value: BoardTranslations) {
        translations.write { $0 = value }
    }

    static func clearHostTranslations() {
        translations.write { $0 = [:] }
    }

    /// Returns the current host-supplied translation for `key` at the
    /// current device locale, if any. Internal — exposed only for
    /// tests.
    static func hostTranslation(forKey key: String) -> String? {
        guard let entry = translations.read({ $0[key] }) else { return nil }
        for code in currentLocaleCodes() {
            if let value = entry[code], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func localizedName(
        _ key: String,
        fallbackName: String? = nil
    ) -> String {
        if systemKeys.contains(key) {
            return Localization.string("feddy.compose.board.\(key)")
        }
        if let host = hostTranslation(forKey: key) {
            return host
        }
        if let fallbackName, !fallbackName.isEmpty {
            return fallbackName
        }
        if key.isEmpty { return "" }
        return key.prefix(1).uppercased() + key.dropFirst()
    }

    /// Convenience wrapper that re-localizes a board's display name in
    /// place. Custom boards without host translations are returned
    /// untouched.
    static func localize(_ board: FeedbackBoard) -> FeedbackBoard {
        let resolved = localizedName(board.key, fallbackName: board.name)
        if resolved == board.name { return board }
        return FeedbackBoard(key: board.key, name: resolved)
    }

    /// Ordered list of locale keys to try when looking up host
    /// translations for the current device locale. Returns a single
    /// 2-letter code (`en` / `es` / `ja` / `de` / `fr`) for most
    /// languages, but for Chinese also resolves the script (`zh-Hans`
    /// / `zh-Hant`) and falls back to the base `zh` so hosts can
    /// supply either variant-specific or shared Chinese strings.
    private static func currentLocaleCodes() -> [String] {
        let language: String
        let script: String?
        let region: String?
        if #available(iOS 16.0, macOS 13.0, *) {
            let lang = Locale.current.language
            language = lang.languageCode?.identifier ?? "en"
            script = lang.script?.identifier
            region = lang.region?.identifier
        } else {
            language = Locale.current.languageCode ?? "en"
            script = nil
            region = (Locale.current as NSLocale).object(forKey: .countryCode) as? String
        }

        if language == "zh" {
            let variant: String
            if script == "Hans" {
                variant = "Hans"
            } else if script == "Hant" {
                variant = "Hant"
            } else if let r = region, ["CN", "SG"].contains(r) {
                variant = "Hans"
            } else if let r = region, ["TW", "HK", "MO"].contains(r) {
                variant = "Hant"
            } else {
                variant = "Hans"
            }
            return ["zh-\(variant)", "zh"]
        }

        return [language]
    }
}
