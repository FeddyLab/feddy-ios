# Feddy iOS SDK

In-app support for your users: submit feedback, get replies, done.
Swift Package, iOS 15+, zero third-party dependencies.

## Installation

Add the package in Xcode (**File → Add Package Dependencies…**) or in
`Package.swift`:

```swift
.package(url: "https://github.com/FeddyLab/feddy-ios", from: "0.1.1")
```

## Quick start

Configure once at launch, then present the support UI from anywhere:

```swift
import Feddy

// SwiftUI
@main
struct MyApp: App {
    init() {
        Feddy.configure(apiKey: "fd_live_...")
    }
    var body: some Scene { WindowGroup { ContentView() } }
}

// UIKit
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Feddy.configure(apiKey: "fd_live_...")
    return true
}
```

```swift
Feddy.present()                    // conversation list
Feddy.presentNewConversation()     // straight into the compose form
```

Both calls work from UIKit and SwiftUI hosts — the UI is presented
modally over whatever is currently on screen.

## Identify your user (optional)

```swift
Feddy.identify(
    userId: "u_123",
    email: "user@example.com",
    attributes: [
        "plan": "pro",
        "is_member": true,
        "trial_ends_at": Date(),
        "credits_left": 42,
    ]
)
```

Attribute values may be `String`, `Bool`, numbers, or `Date`; anything
else is dropped. Anonymous users work fine without `identify` — their
identity is a generated id stored in the Keychain, so history survives
reinstalls.

## Unread badge

```swift
Feddy.unreadCount { count in badge.isHidden = count == 0 }
Feddy.onUnreadCountChanged = { count in badge.isHidden = count == 0 }
Feddy.refresh()   // call when your app enters the foreground
```

## Reply notifications

The SDK does not use remote push. When `refresh()` (or a presented
screen) pulls a new reply, it posts a **local notification** so the
banner and lock-screen behavior match a push. Honest limitation: this
only fires when the user opens your app again — replies never wake the
app from the outside. Notification permission is requested once, right
after the user's first successful submission.

If the user leaves an email, replies also go out by email with the full
message content, which covers the time between app sessions.

## Privacy

The package ships a `PrivacyInfo.xcprivacy` declaring only what the SDK
needs to function: the user's email (optional), a user identifier, and
the feedback content itself. Nothing is used for tracking and there are
no analytics.

## Example app

Open `Example/FeddyExample.xcodeproj`, paste a project API key into
`FeddyExampleApp.swift`, and run. Point `apiURL` at your own deployment
or `http://localhost:3000` for local development.
