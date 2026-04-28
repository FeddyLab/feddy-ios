import Feddy
import SwiftUI

@main
struct FeddyTestAppApp: App {
    init() {
        // Canonical: configure once at launch, before any view runs.
        if !DemoConfig.isPlaceholder {
            Feddy.configure(apiKey: DemoConfig.apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // In your real app, call this from your auth
                    // handler with the user record you already have.
                    // Demo simulates with hardcoded values.
                    guard !DemoConfig.isPlaceholder else { return }
                    Feddy.identify(
                        userId: DemoUser.id,
                        email: DemoUser.email,
                        displayName: DemoUser.displayName
                    )
                }
        }
    }
}
