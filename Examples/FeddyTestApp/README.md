# FeddyTestApp

Public **integration showcase** for the `Feddy` SDK. Open it to see a
fake host app's Profile screen with `Feddy.identify(...)` already
wired up — exactly the shape your own app's integration will take.

> Feddy never authenticates end users. Your host app already knows
> who the user is from your own auth system; the SDK just receives
> that identity through `Feddy.identify(externalUserId:email:displayName:)`.
> The demo simulates this by hardcoding a demo user in `DemoUser.swift`
> — in your real app those values come from your auth handler.

## Run

1. Open `FeddyTestApp.xcodeproj` in Xcode.
2. The local `Feddy` package is wired up via a relative path (`../..`).
3. Set your `fed_pk_…` API key (see "API key" below) and ⌘R on an
   iOS 17+ simulator.

## API key

Set one of:

1. **Scheme env var** (recommended for local dev) — Edit Scheme → Run →
   Arguments → Environment Variables → `FEDDY_API_KEY = fed_pk_…`
2. **`DemoConfig.swift`** — replace `defaultApiKey` with your own
   `fed_pk_*`. Best for screen-recordings.

If neither is set, the app shows a "Set FEDDY_API_KEY to run the demo"
state instead of crashing.

> Each project has exactly one key (no test/live split). Get yours from
> `dashboard.feddy.app` → Project → Settings → API Keys.

## What this demo teaches (v0.1)

Two integration call sites — read the source side-by-side:

### `FeddyTestAppApp.swift` — configure once at launch

```swift
@main
struct FeddyTestAppApp: App {
    init() {
        Feddy.configure(apiKey: DemoConfig.apiKey)
    }
    // …
}
```

### `FeddyTestAppApp.swift` — identify after your auth ran

```swift
.task {
    Feddy.identify(
        userId: yourUser.id,
        email: yourUser.email,
        displayName: yourUser.displayName
    )
}
```

In the demo, `yourUser` is the hardcoded `DemoUser` enum (simulating
the user record your auth layer already produced). In your real app,
move this `Feddy.identify(...)` call into your sign-in handler or
wherever your auth completes.

Both calls are synchronous and fire-and-forget — no `try` / `await`
boilerplate at the integration site. Errors (invalid key, network
failure) are logged to the console; in debug builds an invalid key
also trips an `assertionFailure` so integration mistakes surface
immediately.

The Profile screen then displays the same values that were forwarded —
useful as a visual sanity check, since you can compare them against
the user record on `dashboard.feddy.app`.

## What's coming

- **v0.2** ships `Feddy.RequestComposeView` (native SwiftUI feedback
  form). The demo will gain a "Send Feedback" row that opens it as a
  sheet — the canonical mainstream-SaaS integration shape.
- **v0.3** ships `Feddy.RequestListView` (wish list + voting).
- **v0.4** ships Smart Review Prompt.

## i18n

The demo localizes its own UI strings via `Localizable.xcstrings`:
`en` (base) · `es` · `ja` · `de` · `fr`. Switch locales at runtime
with **Edit Scheme → Run → Options → App Language** to verify
translations.

## Troubleshooting

- **Stuck on "Set FEDDY_API_KEY to run the demo"** — neither the
  scheme env var nor `DemoConfig.swift` was updated.
- **HTTP 401** in the dashboard — the key is rejected by the server.
  Check that it isn't revoked and that its scopes include
  `identify:write`.
- **Configuration error: Secret keys (fed_sk_*)…** — you pasted a
  secret key. Switch to your project's `fed_pk_*` publishable key.
