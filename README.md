# Feddy Swift SDK

> **Beta Notice**: This SDK is currently in beta (v0.7.3). The API may change before the 1.0 release.

A Swift SDK for integrating [Feddy](https://feddy.app) feedback, roadmap, and changelog features into your iOS and macOS applications.

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/FeddyLab/feddy-ios", from: "0.7.3")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/FeddyLab/feddy-ios`
3. Click Add Package

## Quick Start

### 1. Setup

Initialize Feddy with your **Project ID** (a `fed_` followed by 12 alphanumeric characters, copied from your Feddy dashboard):

```swift
import Feddy

// In your AppDelegate or App struct
Feddy.configure(apiKey: "fed_xxxxxxxxxxxx")
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

// With avatar URL
Feddy.identify(
    userId: "user123",
    email: "user@example.com",
    displayName: "Alice Chen",
    avatarURL: URL(string: "https://example.com/avatar.jpg")
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
        Feddy.configure(apiKey: "fed_xxxxxxxxxxxx")
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
        Feddy.configure(apiKey: "fed_xxxxxxxxxxxx")
        return true
    }
}
```

## Submit Feedback

End users submit feature requests, bug reports, and general feedback through `Feddy.submitRequest(...)` or the bundled `RequestComposeView` SwiftUI sheet. Feddy never asks the end user to "log in" — submissions attribute to whichever identity you last passed to `Feddy.identify(...)`, falling back to a per-install anonymous token if you haven't called `identify` yet.

### SwiftUI Sheet

Drop `RequestComposeView` into your view hierarchy. It's a fully-localized form with title / description / category fields wired to the SDK:

```swift
import SwiftUI
import Feddy

struct ProfileView: View {
    @State private var showFeedback = false

    var body: some View {
        Button("Send Feedback") {
            showFeedback = true
        }
        .sheet(isPresented: $showFeedback) {
            // Default: shows the workspace's two system boards
            // (Feature, Bug), localized in 5 languages.
            RequestComposeView()
        }
    }
}
```

To surface custom boards (anything you added in
`dashboard.feddy.app/w/<ws>/boards`), pass them explicitly. You're
responsible for the display name's localization — the SDK does not
know about your custom boards:

```swift
.sheet(isPresented: $showFeedback) {
    RequestComposeView(boards: [
        .featureRequest,                       // SDK-localized "Feature"
        .bugReport,                            // SDK-localized "Bug"
        .init(
            key: "discussions",                // matches dashboard board.key
            name: NSLocalizedString("Discussions", comment: "")
        ),
    ])
}
```

### Programmatic Submit

If you have your own UI, call `Feddy.submitRequest(...)` directly. Like the rest of the API it's **synchronous, fire-and-forget, and never throws**:

```swift
// Lands in the workspace's primary board when boardKey is omitted.
Feddy.submitRequest(title: "Add dark mode")

// Pin to a specific board. The two system boards every workspace ships
// with are "features" and "bugs":
Feddy.submitRequest(
    title: "Crash on launch",
    description: "Happens after entering passcode on iPhone 15 Pro / iOS 17.4",
    boardKey: "bugs"
)

// Workspace-specific custom board (configure these in
// dashboard.feddy.app/w/<ws>/boards):
Feddy.submitRequest(
    title: "Confusing onboarding step 3",
    boardKey: "ux-research"
)
```

`boardKey` is the `key` of any board visible in your dashboard.

### Offline Retry Queue

Submissions that hit a network failure or 5xx server error are persisted to a local FIFO queue and replayed automatically on the next `Feddy.configure(...)` call. 4xx responses are not retried (replaying bad payloads would loop forever) and are dropped after a console log.

The queue is bounded (100 entries) and survives app restarts; the host app does not need to manage it.

## Show Roadmap

`RequestListView` is a drop-in roadmap viewer — paginated list, board picker, pull-to-refresh, inline upvote, and tap-to-detail navigation. No setup beyond `Feddy.configure(...)`.

### iOS Presentation

```swift
import SwiftUI
import Feddy

struct ContentView: View {
    @State private var showRoadmap = false

    var body: some View {
        Button("View Roadmap") { showRoadmap = true }
            .sheet(isPresented: $showRoadmap) {
                RequestListView()
            }
    }
}
```

To restrict to specific boards, pass the workspace's board keys:

```swift
RequestListView(boards: [
    .featureRequest,
    .init(key: "discussions", name: "Discussions"),
])
```

### Programmatic Read API

When you want a fully custom UI, fetch the same data programmatically:

```swift
let page = try await Feddy.fetchRequests(boardKey: "features", limit: 20)
for item in page.items {
    print(item.title, item.voteCount, item.attachments.count)
}

// Single request detail (with attachments + official reply)
let detail = try await Feddy.fetchRequest(id: "req_xyz")

// Toggle upvote — server is the source of truth, returns new state
let state = try await Feddy.upvote(requestId: "req_xyz")
print("voted=\(state.voted) total=\(state.voteCount)")

// Comments (oldest-first, paginated)
let thread = try await Feddy.fetchComments(requestId: "req_xyz", limit: 50)

// Append a comment
let posted = try await Feddy.addComment(requestId: "req_xyz", body: "Looking forward to this!")
```

All read methods are `async throws`; errors surface as `FeddyError.network` or `FeddyError.http(status:code:message:)` so the caller can switch on the server's `code` string for typed handling.

## Advanced Usage

### Anonymous Tracking

You can collect feedback **before** users sign in. When `identify` is omitted, Feddy persists a per-install anonymous token automatically and reconciles writes once you call `identify` with a real user ID:

```swift
// At app launch — user not signed in yet
Feddy.configure(apiKey: "fed_xxxxxxxxxxxx")

// Later, when the user signs in
Feddy.identify(userId: "user123", email: "user@example.com")
```

### Logout

Clear the configured client and any cached identity when the user logs out:

```swift
Feddy.reset()
```

After `reset`, subsequent calls become no-ops until you call `Feddy.configure` again.

### Subscription State

By default the SDK reads the host app's currently-active subscription from StoreKit 2 (`Transaction.currentEntitlements`) once at `configure(...)` and again on each `identify(...)`, so feedback rows in your dashboard carry up-to-date plan info with zero extra wiring.

```swift
Feddy.configure(apiKey: "fed_xxxxxxxxxxxx")
// Auto-detection runs in the background.
```

After a purchase, restore, or subscription state change, ask the SDK to re-read the entitlement so the next identify carries the freshest snapshot:

```swift
Feddy.refreshSubscription()
```

If your source-of-truth for paid state is RevenueCat, Adapty, or your own server, disable auto-detection and push the state explicitly:

```swift
Feddy.configure(
    apiKey: "fed_xxxxxxxxxxxx",
    autoDetectSubscription: false
)

Purchases.shared.getCustomerInfo { info, _ in
    guard let info else { return }
    let isPro = info.entitlements["pro"]?.isActive == true
    Feddy.setSubscription(
        isPro
            ? .init(isPaid: true, status: .active,
                    productId: info.activeSubscriptions.first,
                    expiresAt: info.expirationDate(forEntitlement: "pro"))
            : .init(isPaid: false, status: .none)
    )
}

// Pass nil to clear and let auto-detection take over again.
Feddy.setSubscription(nil)
```

Manual override always wins over the auto-detected snapshot. Both persist across launches; the next `Feddy.identify(...)` call attaches whichever takes precedence automatically.

### Custom Boards & i18n

The two SDK-shipped system boards (`features` / `bugs`) come pre-translated in 5 locales (en / es / ja / de / fr) and are picked automatically based on the device locale. The bundled views fetch the workspace's full board set from `GET /v1/boards` (1 h cached) so any custom board you create in the dashboard appears without redeploying the app:

```swift
RequestComposeView()    // boards fetched in the background
RequestListView()
RoadmapView()
```

For **custom boards**, supply per-locale display names via `boardTranslations` so each device locale renders the right label:

```swift
Feddy.configure(
    apiKey: "fed_xxxxxxxxxxxx",
    boardTranslations: [
        "roadmap-2026": [
            "en": "Roadmap 2026",
            "ja": "ロードマップ 2026",
            "es": "Hoja de ruta 2026",
        ],
        "design": ["ja": "デザインフィードバック"],
    ]
)
```

Resolution order for any custom board key:

1. `boardTranslations[key][deviceLocale]` if set
2. The server's `board.name` (whatever the admin typed in the dashboard)
3. Capitalized key as a last-ditch label

System keys (`features` / `bugs`) always use the SDK's bundled translations — they are intentionally not overridable so first-party UI stays consistent across SDK platforms.

If your app already has its own i18n system and you want to bypass `fetchBoards`, pass an explicit array — the views will skip the network call entirely:

```swift
RequestComposeView(boards: [
    .featureRequest,           // SDK-localized features board
    .bugReport,                // SDK-localized bugs board
    FeedbackBoard(key: "design", name: NSLocalizedString("Design", comment: "")),
])
```

```swift
let boards = try await Feddy.fetchBoards()    // for custom UIs
```

## Requirements

- iOS 15.0+ / macOS 10.15+
- Swift 5.5+
- Xcode 13.0+

## Features

- **Simple Integration**: Two method calls to get going — `Feddy.configure(apiKey:)` and `Feddy.identify(userId:)`
- **SwiftUI-First UI**: `RequestComposeView`, `RequestListView`, and `RequestDetailView` all ship as drop-in views — fully localized, no extra setup
- **Offline-Aware**: Failed submissions persist to a local retry queue and replay automatically when the network returns
- **Cross-Platform**: Native support for both iOS and macOS
- **Anonymous Fallback**: Collect feedback before users sign in via a per-install anonymous token — end users never need a Feddy account
- **Fire-and-Forget Writes**: `submitRequest` returns immediately — no `try` / `await` boilerplate; reads (`fetchRequests` / `fetchRequest` / `upvote` / `addComment`) are `async throws` for typed error handling
- **Localized**: Built-in `en` / `es` / `ja` / `de` / `fr` translations for end-user-facing strings
- **Open Source**: MIT licensed; no proprietary runtime dependencies

## License

MIT License — see `LICENSE` file for details.

## Support

For issues or questions, visit [Feddy](https://feddy.app) or open an issue on [GitHub](https://github.com/FeddyLab/feddy-ios/issues).
