import Feddy
import SwiftUI

struct ContentView: View {
    @State private var showFeedbackSheet = false
    @State private var showRoadmapSheet = false
    @State private var showFeedbackListSheet = false

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

            Section("Feedback") {
                Button {
                    showFeedbackSheet = true
                } label: {
                    Label("Send Feedback", systemImage: "bubble.left.and.bubble.right")
                }
                Button {
                    showFeedbackListSheet = true
                } label: {
                    Label("View Feedback", systemImage: "list.bullet")
                }
                Button {
                    showRoadmapSheet = true
                } label: {
                    Label("View Roadmap", systemImage: "list.bullet.rectangle")
                }
            }

            Section {
                Button {
                    Feddy.requestReviewIfAppropriate(boardKey: "bugs")
                } label: {
                    Label("Trigger Smart Review", systemImage: "star.bubble")
                }
                Button {
                    seedSmartReviewGatesForTesting()
                } label: {
                    Label("Seed gates as ready", systemImage: "calendar.badge.plus")
                }
                Button(role: .destructive) {
                    Feddy.resetSmartReviewState()
                } label: {
                    Label("Reset Smart Review state", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Debug — internal testing")
            } footer: {
                Text("Manipulating UserDefaults directly is for verifying the SDK during development. Don't copy this pattern into your own integration — production hosts should just call requestReviewIfAppropriate() at appropriate moments.")
            }

            Section {
                Text("Feddy.identify(…) ran in the host app on launch with the values above. Open dashboard.feddy.app to confirm this user appeared.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile")
        .sheet(isPresented: $showFeedbackSheet) {
            RequestComposeView()
        }
        .sheet(isPresented: $showFeedbackListSheet) {
            RequestListView()
        }
        .sheet(isPresented: $showRoadmapSheet) {
            RoadmapView()
        }
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

    /// Demo-only hack: writes UserDefaults keys that match the SDK's
    /// internal SmartReviewStore so the rule engine sees "8 days
    /// installed, 10 sessions, never shown" and lets the next
    /// requestReviewIfAppropriate() actually present the sheet.
    /// Real host apps must NOT replicate this — the SDK's storage
    /// keys are an implementation detail and may change.
    private func seedSmartReviewGatesForTesting() {
        let defaults = UserDefaults.standard
        let eightDaysAgo = Date().addingTimeInterval(-8 * 86_400)
        defaults.set(eightDaysAgo, forKey: "app.feddy.smartReview.installDate")
        defaults.set(10, forKey: "app.feddy.smartReview.sessionCount")
        defaults.removeObject(forKey: "app.feddy.smartReview.lastShownAt")
        defaults.removeObject(forKey: "app.feddy.smartReview.yearlyCount")
        defaults.removeObject(forKey: "app.feddy.smartReview.yearlyWindowStart")
    }
}

#Preview {
    ContentView()
}
