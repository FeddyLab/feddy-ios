#if canImport(UIKit)
import SwiftUI

struct FeddyRootView: View {
    let startInCompose: Bool

    @StateObject private var model = ConversationListModel()
    @State private var showCompose = false
    @State private var selectedConversationId: String?
    @State private var pendingOpenId: String?
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            HomeView(
                model: model,
                selectedConversationId: $selectedConversationId,
                onNewMessage: { showCompose = true }
            )
            .safeAreaInset(edge: .bottom, spacing: 0) { poweredBy }
            // The greeting is the title; a bar title would say it twice.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Strings.close)
                }
            }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showCompose, onDismiss: openPendingConversation) {
            NewConversationView { conversationId in
                pendingOpenId = conversationId
                showCompose = false
            }
        }
        .task {
            if startInCompose { showCompose = true }
            await FeddyCore.shared.loadConfig()
            await model.load()
            await model.pollLoop()
        }
        .onChange(of: selectedConversationId) { id in
            if let id {
                // Clear the row's dot immediately; the detail view reports
                // the read to the server as soon as the thread is on screen.
                model.markReadLocally(id)
            } else {
                // Back from a thread: pick up read state and any new replies.
                Task { await model.load() }
            }
        }
        .onDisappear { FeddyCore.shared.refresh() }
    }

    /// The line the free and Pro plans carry; Business turns it off through
    /// the config. Re-evaluated on every render, so it disappears the
    /// moment the config lands.
    @ViewBuilder
    private var poweredBy: some View {
        if FeddyCore.shared.brandingEnabled {
            // Plain text on the page, no bar: it is a footnote, not a toolbar.
            Link(destination: URL(string: "https://feddy.app/?utm_source=ios-sdk&utm_medium=powered-by")!) {
                Text("Powered by Feddy")
                    .font(.caption2)
            }
            .tint(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.page)
        }
    }

    /// Opening the new thread waits for the compose sheet to finish
    /// dismissing, so the push animates instead of being swallowed, and
    /// waits for the reload so the row the link binds to exists.
    @MainActor
    private func openPendingConversation() {
        guard let id = pendingOpenId else { return }
        pendingOpenId = nil
        Task {
            await model.load()
            selectedConversationId = id
        }
    }
}
#endif
