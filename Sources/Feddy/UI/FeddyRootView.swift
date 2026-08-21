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
            if startInCompose { showCompose = true }
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.subject ?? "…")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if conversation.status == "closed" {
                        Text(Strings.statusClosed)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(Self.relativeFormatter.localizedString(for: conversation.lastMessageAt, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if conversation.hasUnread {
                Circle()
                    .fill(accent)
                    .frame(width: 9, height: 9)
            }
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
