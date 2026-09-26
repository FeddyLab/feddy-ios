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
            VStack(alignment: .leading, spacing: 36) {
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
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .bounceOnlyWhenScrollable()
        .background(Theme.page)
    }

    /// The mark and the name say who you are writing to; the question is
    /// the headline. Nothing here is grey: it is the first thing read.
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                BrandMark(size: 44)
                if let name = config?.brand.name {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            Text(Strings.homeGreeting)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The one action on the screen, so it carries the brand colour; the
    /// reply time rides along underneath instead of on a line of its own.
    private var newMessageCard: some View {
        let onAccent = Theme.onAccent(config)
        return Button(action: onNewMessage) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Strings.sendUsAMessage)
                        .font(.body.weight(.semibold))
                    if let sla = config?.replySlaText, !sla.isEmpty {
                        Text(sla)
                            .font(.subheadline)
                            .opacity(0.85)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "paperplane.fill")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(onAccent)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            VStack(alignment: .leading, spacing: 12) {
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
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if conversation.id != recent.last?.id {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .background(Theme.ownBubble)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

private extension View {
    /// The home screen fits on one screen almost always; it scrolls only
    /// for large text or a small phone, and should not rubber-band as a
    /// whole otherwise. iOS 15 has no way to say so and keeps the bounce.
    @ViewBuilder
    func bounceOnlyWhenScrollable() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
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
