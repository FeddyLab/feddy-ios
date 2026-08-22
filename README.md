# Feddy iOS SDK

In-app support for your users: submit feedback, get replies, done.
Swift Package, iOS 15+, zero third-party dependencies.

## Installation

Add the package in Xcode (**File → Add Package Dependencies…**) or in
`Package.swift`:

```swift
.package(url: "https://github.com/FeddyLab/feddy-ios", from: "0.2.3")
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
When `refresh()` (or a presented screen) pulls a new reply, it posts a
**local notification** so the banner and lock-screen behavior match a
push. Honest limitation: this only fires when the user opens your app
again — replies never wake the app from the outside.

**The SDK never asks for notification permission on its own.** If your
app already has permission, replies show up as notifications and nothing
else is needed. If it does not, the SDK stays quiet rather than spending
your one prompt — a refusal is permanent, and you may want that prompt
for something else. Hand it over only if you want the SDK to ask (once,
right after the user's first successful submission):

```swift
Feddy.configure(projectId: "fd_...", requestsNotificationPermission: true)
```

If the user leaves an email, replies also go out by email with the full
message content, which covers the time between app sessions.

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
