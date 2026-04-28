import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            if DemoConfig.isPlaceholder {
                missingKeyView
            } else {
                profileView
            }
        }
    }

    private var missingKeyView: some View {
        ContentUnavailableView(
            String(localized: "Set FEDDY_API_KEY to run the demo"),
            systemImage: "key.slash",
            description: Text("Edit DemoConfig.swift or set the FEDDY_API_KEY env var on the Run scheme.")
        )
    }

    private var profileView: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    avatarBubble
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DemoUser.displayName)
                            .font(.headline)
                        Text(DemoUser.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("Identity sent to Feddy") {
                LabeledContent("External user ID") {
                    Text(DemoUser.id)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Email", value: DemoUser.email)
                LabeledContent("Display name", value: DemoUser.displayName)
            }

            Section {
                Text("Feddy.identify(…) ran in the host app on launch with the values above. Open dashboard.feddy.app to confirm this user appeared.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile")
    }

    private var avatarBubble: some View {
        Circle()
            .fill(.tint)
            .frame(width: 56, height: 56)
            .overlay {
                Text(String(DemoUser.displayName.prefix(1)))
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
    }
}

#Preview {
    ContentView()
}
