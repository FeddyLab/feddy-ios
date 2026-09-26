#if canImport(UIKit)
import SwiftUI

/// The blocks the home screen stacks, top to bottom. A list rather than a
/// fixed layout so the server can one day choose and order them (a help
/// centre slots in under `newMessage`) without the other blocks changing.
enum HomeSection: Hashable {
    case greeting
    case newMessage
    case recentConversations

    static let defaultOrder: [HomeSection] = [.greeting, .newMessage, .recentConversations]
}

/// What `Feddy.present()` opens on: who you are writing to, the one way to
/// start, and the last few threads.
struct HomeView: View {
    @ObservedObject var model: ConversationListModel
    @Binding var selectedConversationId: String?
    let onNewMessage: () -> Void

    /// Enough to pick a thread back up without pushing whatever comes
    /// after the list off the first screen; the rest is one tap away.
    static let recentLimit = 3

    private var config: FeddyConfig? { FeddyCore.shared.config }
    private var accent: Color { Theme.accent(config) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(HomeSection.defaultOrder, id: \.self) { section in
                    switch section {
                    case .greeting:
                        greeting
                    case .newMessage:
                        newMessageCard
                    case .recentConversations:
                        recentConversations
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.page)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandMark(size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(config?.brand.name ?? Strings.messages)
                    .font(.title.weight(.bold))
                Text(Strings.homeGreeting)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var newMessageCard: some View {
        Button(action: onNewMessage) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Strings.sendUsAMessage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let sla = config?.replySlaText, !sla.isEmpty {
                        Text(sla)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "paperplane.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
    }

    /// Absent until there is something to show: no empty-state block, the
    /// new-message card above already says what to do.
    @ViewBuilder
    private var recentConversations: some View {
        if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if !model.conversations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Strings.yourMessages)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if model.conversations.count > Self.recentLimit {
                        NavigationLink {
                            ConversationListView(model: model)
                        } label: {
                            Text(Strings.seeAll)
                                .font(.subheadline)
                                .foregroundStyle(accent)
                        }
                    }
                }
                VStack(spacing: 0) {
                    let recent = Array(model.conversations.prefix(Self.recentLimit))
                    ForEach(recent) { conversation in
                        NavigationLink(tag: conversation.id, selection: $selectedConversationId) {
                            ConversationDetailView(conversationId: conversation.id)
                        } label: {
                            ConversationRow(conversation: conversation, accent: accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if conversation.id != recent.last?.id {
                            Divider().padding(.leading, 62)
                        }
                    }
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else if model.loadFailed {
            Text(Strings.errorGeneric)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every conversation, for when there are more than the home screen shows.
struct ConversationListView: View {
    @ObservedObject var model: ConversationListModel
    @State private var selectedConversationId: String?

    private var accent: Color { Theme.accent(FeddyCore.shared.config) }

    var body: some View {
        List(model.conversations) { conversation in
            NavigationLink(tag: conversation.id, selection: $selectedConversationId) {
                ConversationDetailView(conversationId: conversation.id)
            } label: {
                ConversationRow(conversation: conversation, accent: accent)
            }
        }
        .listStyle(.plain)
        .refreshable { await model.load() }
        .navigationTitle(Strings.yourMessages)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedConversationId) { id in
            if let id {
                model.markReadLocally(id)
            } else {
                Task { await model.load() }
            }
        }
    }
}

/// A filled card dims a little under the finger, the way system rows do.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
#endif
