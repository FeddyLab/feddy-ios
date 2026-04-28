# Feddy Swift SDK

> **Beta Notice**: This SDK is currently in beta (v0.1.0). The API may change before the 1.0 release.

A Swift SDK for integrating [Feddy](https://feddy.app) feedback, roadmap, and changelog features into your iOS and macOS applications.

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/FeddyLab/feddy-ios", from: "0.1.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/FeddyLab/feddy-ios`
3. Click Add Package

## Quick Start

### 1. Setup

Initialize Feddy with your project's publishable API key (found in your Feddy dashboard, prefixed with `fed_pk_`):

```swift
import Feddy

// In your AppDelegate or App struct
Feddy.configure(apiKey: "fed_pk_your_project_key")
```

### 2. Identify Users

Identify users to enable personalized feedback tracking:

```swift
// Minimal identification (only userId required)
Feddy.identify(userId: "user123")

// With email
Feddy.identify(
    userId: "user123",
    email: "user@example.com"
)

// With display name
Feddy.identify(
    userId: "user123",
    email: "user@example.com",
    displayName: "Alice Chen"
)

// With avatar URL and custom traits
Feddy.identify(
    userId: "user123",
    email: "user@example.com",
    displayName: "Alice Chen",
    avatarURL: URL(string: "https://example.com/avatar.jpg"),
    profile: [
        "plan": .string("pro"),
        "seats": .int(5),
    ]
)
```

Both `Feddy.configure` and `Feddy.identify` are **synchronous, fire-and-forget, and never throw**. Errors (invalid key, network failure) are logged to the console; the call site never has to deal with `try` or `await`.

### 3. SwiftUI App Lifecycle

```swift
import SwiftUI
import Feddy

@main
struct MyApp: App {
    init() {
        Feddy.configure(apiKey: "fed_pk_your_project_key")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 4. UIKit App Lifecycle

```swift
import UIKit
import Feddy

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Feddy.configure(apiKey: "fed_pk_your_project_key")
        return true
    }
}
```

## Advanced Usage

### Anonymous Tracking

You can collect feedback **before** users sign in. When `identify` is omitted, Feddy persists a per-install anonymous token automatically and reconciles writes once you call `identify` with a real user ID:

```swift
// At app launch — user not signed in yet
Feddy.configure(apiKey: "fed_pk_…")

// Later, when the user signs in
Feddy.identify(userId: "user123", email: "user@example.com")
```

### Logout

Clear the configured client and any cached identity when the user logs out:

```swift
Feddy.reset()
```

After `reset`, subsequent calls become no-ops until you call `Feddy.configure` again.

### Profile Traits

The `profile` dictionary accepts string, int, double, and bool values. Use it for any custom attributes you want to filter or sort feedback by in the dashboard:

```swift
Feddy.identify(
    userId: "user123",
    profile: [
        "plan": .string("pro"),
        "trial_days_left": .int(7),
        "is_paying": .bool(true),
        "ltv_usd": .double(199.99),
    ]
)
```

## Requirements

- iOS 15.0+ / macOS 10.15+
- Swift 5.5+
- Xcode 13.0+

## Features

- **Simple Integration**: Two method calls to get started — `Feddy.configure(apiKey:)` and `Feddy.identify(userId:)`
- **Cross-Platform**: Native support for both iOS and macOS
- **Anonymous Fallback**: Collect feedback before users sign in via a per-install anonymous token
- **Fire-and-Forget API**: No `try` / `await` boilerplate at the call site — the SDK handles retries and logging internally
- **Type-Safe**: Full Swift type safety with explicit `ProfileValue` cases for custom traits
- **Localized**: Built-in `en` / `es` / `ja` / `de` / `fr` translations for end-user-facing strings
- **Open Source**: MIT licensed; no proprietary runtime dependencies

## License

MIT License — see `LICENSE` file for details.

## Support

For issues or questions, visit [Feddy](https://feddy.app) or open an issue on [GitHub](https://github.com/FeddyLab/feddy-ios/issues).
