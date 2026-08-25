# Feddy iOS SDK

In-app support for your users: submit feedback, get replies, done.
Swift Package, iOS 15+, zero third-party dependencies.

## Installation

Add the package in Xcode (**File → Add Package Dependencies…**) or in
`Package.swift`:

```swift
.package(url: "https://github.com/FeddyLab/feddy-ios", from: "0.3.2")
```

## Quick start

Copy your project's ID from the Feddy dashboard (**Settings → Project ID**).
It ships inside your binary, so it is public by design — checking it into
source control is fine.

Configure once at launch, then present the support UI from anywhere:

```swift
import Feddy

// SwiftUI
@main
struct MyApp: App {
    init() {
        Feddy.configure(projectId: "fd_...")
    }
    var body: some Scene { WindowGroup { ContentView() } }
}

// UIKit
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Feddy.configure(projectId: "fd_...")
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

In SwiftUI, mark the row with the system's own badge — the one it puts
on rows in Settings — and the SDK keeps it current:

```swift
Form {
    Button(action: { Feddy.present() }) { Text("Support") }
        .feddyUnreadBadge()
}
```

A badge is placed at the very end of the row, so the row must not draw a
trailing chevron of its own — the badge would land outside it and read
backwards. Leave the trailing edge to the system (a plain row, or a
`NavigationLink`, which the system badges in front of the chevron).

`List`, `Form`, and `TabView` render badges. For a row that draws its own
chevron — or anywhere a red marker suits better than grey text — use the
marker instead, which you can put wherever the row wants it:

```swift
HStack {
    Text("Support")
    Spacer()
    FeddyUnreadDot()                    // or FeddyUnreadDot(showsCount: true)
    Image(systemName: "chevron.forward")
}
```

Both stay current on their own. To place the count somewhere neither
fits, observe it:

```swift
@ObservedObject private var unread = FeddyUnread.shared
```

From UIKit, or to drive something outside a view hierarchy:

```swift
Feddy.unreadCount { count in badge.isHidden = count == 0 }
Feddy.onUnreadCountChanged = { count in badge.isHidden = count == 0 }
```

Call `Feddy.refresh()` when your app enters the foreground.

## Reply notifications

The SDK does not use remote push, so there is no APNs key to configure.
**The SDK posts no notifications and asks for no notification
permission.** A reply reaches the user two ways:

- **In the app** — `unreadCount`, `onUnreadCountChanged`, and the
  `FeddyUnreadDot` / `.feddyUnreadBadge()` views mark your entry point,
  refreshed by a foreground poll and by `refresh()`.
- **Away from the app** — if the user left an email address, the reply is
  emailed to them in full. The panel asks for one after the first message
  is sent, and again when a teammate replies. Someone who skips is not
  asked again; the envelope button in the panel's toolbar stays as the way
  back for as long as no address is on file.

Local notifications were tried and removed in 0.3.0: they can only be
posted while the app is in the foreground, and iOS does not present a
foreground notification unless the host app implements
`UNUserNotificationCenterDelegate`. Claiming the delegate would take it
away from your app, and the one case worth notifying about — a reply
arriving while the app is closed — is unreachable either way.

## Localization

The panel follows the device language and ships in ten: English, 简体中文,
繁體中文, 日本語, 한국어, Deutsch, Français, Español, Português (Brasil),
and Русский. Anything else falls back to English.

The four topics every project starts with — Bug, Feature request,
Question, Other — are translated by the SDK. Topics you add in the
dashboard appear exactly as you typed them, since their labels live in
your project rather than in the package.

## Privacy

The package ships a `PrivacyInfo.xcprivacy` declaring only what the SDK
needs to function: the user's email (optional), a user identifier, and
the feedback content itself. Nothing is used for tracking and there are
no analytics.

## Example app

Open `Example/FeddyExample.xcodeproj`, paste a project ID into
`FeddyExampleApp.swift`, and run. Point `apiURL` at your own deployment
or `http://localhost:3000` for local development.
