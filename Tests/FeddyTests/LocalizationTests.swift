import XCTest
@testable import Feddy

/// String Catalogs (`.xcstrings`) are compiled into `.lproj/Localizable.strings`
/// by Xcode's build system but **not** by `swift build` / `swift test` on the
/// macOS CLI — see Apple's SwiftPM source. Real iOS apps consuming Feddy via
/// SPM go through Xcode and therefore get full runtime localization.
///
/// To still keep these tests meaningful in `swift test`, we verify catalog
/// contents by parsing the `.xcstrings` JSON directly. That catches dropped
/// translations and missing locales, which are the realistic regressions.
final class LocalizationTests: XCTestCase {
    private static let expectedLocales: Set<String> = ["en", "zh-Hans", "zh-Hant", "es", "ja", "de", "fr"]

    func test_catalogShipsInResourceBundle() {
        XCTAssertNotNil(
            Localization.bundle.url(forResource: "Localizable", withExtension: "xcstrings"),
            "Localizable.xcstrings must be packaged in the Feddy resource bundle"
        )
    }

    func test_everyKeyHasAllExpectedLocales() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertFalse(strings.isEmpty, "catalog should not be empty")

        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any], "entry \(key) malformed")
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any],
                "entry \(key) missing localizations"
            )
            let actual = Set(localizations.keys)
            let missing = Self.expectedLocales.subtracting(actual)
            XCTAssertTrue(
                missing.isEmpty,
                "key '\(key)' is missing locales: \(missing.sorted().joined(separator: ", "))"
            )
        }
    }

    func test_translationsAreNonEmpty() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])

        for (key, rawEntry) in strings {
            let entry = rawEntry as? [String: Any] ?? [:]
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for (locale, rawLoc) in localizations {
                let loc = rawLoc as? [String: Any] ?? [:]
                let unit = loc["stringUnit"] as? [String: Any] ?? [:]
                let value = unit["value"] as? String ?? ""
                XCTAssertFalse(
                    value.isEmpty,
                    "key '\(key)' has empty value for locale '\(locale)'"
                )
            }
        }
    }

    // MARK: - helpers

    private func loadCatalog() throws -> [String: Any] {
        let url = try XCTUnwrap(
            Localization.bundle.url(forResource: "Localizable", withExtension: "xcstrings"),
            "Localizable.xcstrings missing from bundle"
        )
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
