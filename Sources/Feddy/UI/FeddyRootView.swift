#if canImport(UIKit)
import SwiftUI

struct FeddyRootView: View {
    let startInCompose: Bool

    @StateObject private var model = ConversationListModel()
    @State private var showCompose = false
    @State private var selectedConversationId: String?
    @State private var pendingOpenId: String?
    @Environment(\.presentationMode) private var presentationMode

    private var accent: Color { Theme.accent(FeddyCore.shared.config) }

    var body: some View {
        NavigationView {
            content
                .safeAreaInset(edge: .bottom, spacing: 0) { poweredBy }
                .navigationTitle(FeddyCore.shared.config?.brand.name ?? Strings.messages)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(Strings.close)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showCompose = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel(Strings.newMessage)
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
            await FeddyCore.shared.loadConfig()
            await model.load()
            // Nobody opens a support panel to admire an empty list: with no
            // thread to read, go straight to the compose form. A failed load
            // is not "empty" — dropping someone into a blank form would hide
            // the history they came back for.
            if startInCompose || (model.conversations.isEmpty && !model.loadFailed) {
                showCompose = true
            }
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
            Link(destination: URL(string: "https://feddy.app")!) {
                Text("Powered by Feddy")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.conversations.isEmpty {
            emptyState
        } else {
            conversationList
        }
    }

    private var conversationList: some View {
        List(model.conversations) { conversation in
            NavigationLink(tag: conversation.id, selection: $selectedConversationId) {
                ConversationDetailView(conversationId: conversation.id)
            } label: {
                ConversationRow(conversation: conversation, accent: accent)
            }
        }
        .listStyle(.plain)
        .refreshable { await model.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(Strings.emptyTitle)
                .font(.headline)
            Text(Strings.emptyBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(Strings.newMessage) { showCompose = true }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct ConversationRow: View {
    let conversation: ConversationSummary
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(conversation.hasUnread ? accent : Color.clear)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.subject ?? "…")
                        .font(.subheadline.weight(conversation.hasUnread ? .semibold : .regular))
                        .lineLimit(1)
                    if conversation.status == "closed" {
                        Text(Strings.statusClosed)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.surface)
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(Self.relativeFormatter.localizedString(for: conversation.lastMessageAt, relativeTo: Date()))
                        .foregroundStyle(.secondary)
                    if conversation.hasUnread {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(Strings.newReply)
                            .foregroundStyle(accent)
                    }
                }
                .font(.caption)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
#endif
