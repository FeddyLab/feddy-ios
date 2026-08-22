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
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Button(action: { Feddy.present() }) {
                        row("Feedback & Support")
                    }
                    .buttonStyle(.plain)
                    // The system's own list badge, kept current by the SDK.
                    // Nothing to observe, nothing to hide at zero.
                    .feddyUnreadBadge()

                    Button(action: { Feddy.presentNewConversation() }) {
                        row("New conversation")
                    }
                    .buttonStyle(.plain)

                } header: {
                    Text("Support")
                }

                Section {
                    CustomUnreadRow()
                } header: {
                    Text("Your own indicator")
                } footer: {
                    Text("Observe FeddyUnread.shared when the count has to appear somewhere a list badge cannot go.")
                }

                Section {
                    Button("Identify demo user") {
                        Feddy.identify(
                            userId: "demo-user-1",
                            attributes: ["plan": "pro", "is_member": true]
                        )
                    }
                    Button("Refresh now") { Feddy.refresh() }
                } header: {
                    Text("Demo")
                }
            }
            .navigationTitle("Feddy Example")
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

/// The same count, drawn by hand — a red pill rather than the system's
/// grey text. Both are on screen at once so the difference is visible.
private struct CustomUnreadRow: View {
    @ObservedObject private var unread = FeddyUnread.shared

    var body: some View {
        HStack {
            Text("Unread replies")
            Spacer()
            if unread.count > 0 {
                Text("\(unread.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemRed), in: Capsule())
            } else {
                Text("None")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
