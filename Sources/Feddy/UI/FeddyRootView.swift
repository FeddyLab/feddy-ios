#if canImport(UIKit)
import SwiftUI

struct FeddyRootView: View {
    let startInCompose: Bool

    @StateObject private var model = ConversationListModel()
    @State private var showCompose = false
    @State private var pushedConversationId: String?
    @Environment(\.presentationMode) private var presentationMode

    private var accent: Color { Theme.accent(FeddyCore.shared.config) }

    var body: some View {
        NavigationView {
            content
                .navigationTitle(FeddyCore.shared.config?.brand.name ?? Strings.messages)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(Strings.close) { presentationMode.wrappedValue.dismiss() }
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
                .background(navigationLinks)
        }
        .navigationViewStyle(.stack)
        .accentColor(accent)
        .sheet(isPresented: $showCompose) {
            NewConversationView { conversationId in
                showCompose = false
                pushedConversationId = conversationId
                Task { await model.load() }
            }
        }
        .task {
            await FeddyCore.shared.loadConfig()
            await model.load()
            if startInCompose { showCompose = true }
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
            Button {
                pushedConversationId = conversation.id
            } label: {
                ConversationRow(conversation: conversation, accent: accent)
            }
            .buttonStyle(.plain)
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

    /// Single programmatic push target: rows and the compose flow both
    /// navigate by setting pushedConversationId.
    @ViewBuilder
    private var navigationLinks: some View {
        if let id = pushedConversationId {
            NavigationLink(
                isActive: Binding(
                    get: { pushedConversationId != nil },
                    set: { active in
                        if !active { pushedConversationId = nil }
                    }
                )
            ) {
                ConversationDetailView(conversationId: id)
            } label: {
                EmptyView()
            }
            .hidden()
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
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
#endif
