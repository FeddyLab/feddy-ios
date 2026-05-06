import Foundation

/// Display-name translations for **custom** board keys — anything beyond
/// the two SDK-shipped system boards (`features` / `bugs`). Keyed by
/// board key, then by 2-letter locale code (`en` / `es` / `ja` / `de`
/// / `fr`). Missing locales fall through to the server-supplied
/// `board.name` (whatever the admin typed in the dashboard).
///
/// ```swift
/// Feddy.configure(
///     apiKey: "fed_xxxxxxxxxxxx",
///     boardTranslations: [
///         "roadmap-2026": [
///             "en": "Roadmap 2026",
///             "ja": "ロードマップ 2026",
///             "es": "Hoja de ruta 2026",
///         ],
///         "design": ["ja": "デザインフィードバック"],
///     ]
/// )
/// ```
///
/// Has no effect on system keys: `features` / `bugs` are always pulled
/// from the SDK's bundled `Localizable.xcstrings` catalog so the
/// first-party UI stays consistent across SDK platforms.
public typealias BoardTranslations = [String: [String: String]]

extension Feddy {
    /// Fetch the workspace's public, non-archived boards from the server,
    /// with a 1 h `UserDefaults` cache. Stale-while-revalidate: returns
    /// cached value immediately on hit (even if stale), kicks a
    /// background refresh to update for the next call.
    ///
    /// Falls back to ``FeedbackBoard/systemDefaults`` (features + bugs,
    /// SDK-localized) when:
    /// - no cache exists and the server is unreachable
    /// - the response is empty
    /// - ``configure(apiKey:autoDetectSubscription:boardTranslations:)``
    ///   has not been called yet
    ///
    /// Use this when rendering a custom board picker outside the
    /// built-in modals. The bundled views call it automatically.
    @available(iOS 15.0, macOS 12.0, *)
    public static func fetchBoards() async -> [FeedbackBoard] {
        guard let client = currentClientIfReady() else {
            return FeedbackBoard.systemDefaults
        }

        if let cached = BoardsCache.currentBoards(), !cached.isEmpty {
            // Stale-while-revalidate: serve cache, nudge a refresh if past TTL.
            BoardsCache.refreshInBackground(client: client)
            return cached
        }

        // No cache — must hit the network. Fallback on any failure so the
        // picker is never empty.
        do {
            let fresh = try await BoardsCache.fetchOnce(client: client)
            return fresh.isEmpty ? FeedbackBoard.systemDefaults : fresh
        } catch {
            print(
                "[Feddy] boards fetch failed — using defaults: \(error.localizedDescription)"
            )
            return FeedbackBoard.systemDefaults
        }
    }
}
