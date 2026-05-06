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
        let locale = currentLocaleCode()
        guard let entry = translations.read({ $0[key] }) else { return nil }
        if let value = entry[locale], !value.isEmpty {
            return value
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

    /// Current device locale's 2-letter language code (`en` / `es` /
    /// `ja` / `de` / `fr`). Falls back to `"en"` when the system can't
    /// resolve one.
    private static func currentLocaleCode() -> String {
        if #available(iOS 16.0, macOS 13.0, *) {
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        return Locale.current.languageCode ?? "en"
    }
}
