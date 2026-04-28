import Foundation

/// Stand-in for the user record the host app already has after its
/// own authentication flow. Feddy never authenticates end users —
/// the host app passes whatever identifier and traits it already
/// knows. Replace these constants with whatever your auth layer
/// returns at runtime.
enum DemoUser {
    static let id = "demo_user_alice"
    static let email = "alice@example.com"
    static let displayName = "Alice Chen"
}
