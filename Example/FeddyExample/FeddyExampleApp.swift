import SwiftUI
import Feddy

// Paste your project ID from the dashboard. For local development,
// point apiURL at your API dev server; the default below is production.
private let projectId = "fd_replace_me"
private let apiURL = URL(string: "https://core.feddy.app")!

@main
struct FeddyExampleApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Feddy.configure(projectId: projectId, apiURL: apiURL)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Feddy.refresh() }
        }
    }
}

struct ContentView: View {
    @State private var unread = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Feddy Example")
                .font(.title2.bold())

            Button("Open support") { Feddy.present() }
                .buttonStyle(.borderedProminent)

            Button("New conversation") { Feddy.presentNewConversation() }
                .buttonStyle(.bordered)

            Button("Identify demo user") {
                Feddy.identify(
                    userId: "demo-user-1",
                    email: nil,
                    attributes: ["plan": "pro", "is_member": true]
                )
            }
            .buttonStyle(.bordered)

            Label("Unread: \(unread)", systemImage: unread > 0 ? "bell.badge" : "bell")
                .foregroundStyle(unread > 0 ? .red : .secondary)
        }
        .onAppear {
            Feddy.onUnreadCountChanged = { unread = $0 }
            Feddy.refresh()
        }
    }
}
