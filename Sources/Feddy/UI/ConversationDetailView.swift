#if canImport(UIKit)
import SwiftUI

struct ConversationDetailView: View {
    @StateObject private var model: ConversationDetailModel
    @State private var draft = ""
    /// Mirrors of state that lives in `UserDefaults`, which publishes
    /// nothing: without them a save or a skip would not redraw the view
    /// it happened in.
    @State private var emailBannerDismissed = false
    @State private var emailKnown = FeddyCore.shared.emailKnown
    @State private var showEmailSheet = false
    @FocusState private var replyFocused: Bool

    private var accent: Color { Theme.accent(FeddyCore.shared.config) }

    init(conversationId: String) {
        _model = StateObject(wrappedValue: ConversationDetailModel(conversationId: conversationId))
    }

    var body: some View {
        messageList
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .navigationTitle(FeddyCore.shared.config?.brand.name ?? Strings.messages)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Stays for as long as we have no email, whether the ask
                // was skipped or never shown: skipping is honoured for
                // good, so there has to be a way back to it.
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !emailKnown {
                        Button {
                            showEmailSheet = true
                        } label: {
                            Image(systemName: "envelope")
                        }
                        .accessibilityLabel(Strings.emailAdd)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(Strings.done) { replyFocused = false }
                }
            }
            .sheet(isPresented: $showEmailSheet) {
                EmailAskSheet(accent: accent) { emailKnown = true }
            }
            .task {
                await model.loadInitial()
                await model.pollLoop()
            }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(Array(model.parts.enumerated()), id: \.element.seq) { index, part in
                        MessageBubble(
                            part: part,
                            accent: accent,
                            startsRun: index == 0
                                || model.parts[index - 1].authorRunKey != part.authorRunKey
                        )
                        .id(part.seq)
                    }
                    // One view for both states rather than an if/else: a lazy
                    // stack caches its children by identity, and swapping two
                    // different views in and out at the same spot left the old
                    // row on screen with its props frozen.
                    if let state = feedbackState {
                        FeedbackRow(state: state, accent: accent) { seq, helpful in
                            Task { await model.rate(seq: seq, helpful: helpful) }
                        }
                    }
                    if showEmailBanner {
                        EmailCaptureBanner(
                            accent: accent,
                            onSkip: {
                                FeddyCore.shared.markEmailAskDismissed()
                                emailBannerDismissed = true
                            },
                            onSaved: {
                                emailKnown = true
                                emailBannerDismissed = true
                            }
                        )
                            .id(Self.emailBannerID)
                            .padding(.top, 2)
                            // Sits on the teammate's side rather than spanning
                            // both, the way every bubble around it does.
                            .padding(.trailing, 24)
                    }
                }
                .padding(16)
            }
            .background(
                Theme.page
                    .onTapGesture { replyFocused = false }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 12).onChanged { _ in replyFocused = false }
            )
            .onChange(of: model.parts.count) { _ in
                scrollToBottom(proxy, animated: true)
            }

            .onAppear { scrollToBottom(proxy, animated: false) }
        }
    }

    private static let emailBannerID = "feddy-email-ask"

    // The thank-you belongs to the message it answered: it stays where the
    // buttons were and goes with the next message, whoever sends it.
    private var feedbackState: FeedbackRow.State? {
        if let target = model.feedbackTarget {
            return .ask(seq: target.seq, disabled: model.isRating)
        }
        if let thanks = model.thanksSeq, thanks == model.parts.last?.seq {
            return .thanks
        }
        return nil
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let scroll = {
            if showEmailBanner {
                proxy.scrollTo(Self.emailBannerID, anchor: .bottom)
            } else if let last = model.parts.last {
                proxy.scrollTo(last.seq, anchor: .bottom)
            }
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2), scroll)
        } else {
            scroll()
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if model.status == "closed" {
                Text(model.resolvedByUser ? Strings.resolvedNotice : Strings.closedNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            if let error = model.sendError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }
            composer
        }
        .background(.bar)
    }

    private var showEmailBanner: Bool {
        !emailKnown && !emailBannerDismissed && !FeddyCore.shared.emailAskDismissed
            && model.hasTeammateReply
    }

    private var canSend: Bool {
        !model.isSending && !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            replyField
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button(action: send) {
                ZStack {
                    if model.isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(canSend ? accent : Color(.tertiaryLabel))
                    }
                }
                // Matches the field's single-line height (line + 12pt of
                // padding), so bottom alignment reads as centred on one line
                // and pins to the last line once the field grows.
                .frame(width: 26, height: 26)
                .padding(.vertical, 6)
            }
            .disabled(!canSend)
            .accessibilityLabel(Strings.send)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Grows with the reply instead of scrolling a single line sideways.
    @ViewBuilder
    private var replyField: some View {
        if #available(iOS 16.0, *) {
            TextField(Strings.replyPlaceholder, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($replyFocused)
        } else {
            TextField(Strings.replyPlaceholder, text: $draft)
                .submitLabel(.send)
                .onSubmit { send() }
                .focused($replyFocused)
        }
    }

    private func send() {
        let text = draft
        Task {
            // Clearing unconditionally would swallow anything typed while the
            // request was in flight; a failure leaves the draft alone so the
            // message is never lost.
            if await model.send(text), draft == text {
                draft = ""
            }
        }
    }
}

private struct MessageBubble: View {
    let part: Part
    let accent: Color
    let startsRun: Bool

    private var authorLabel: String? {
        guard !part.isFromContact, startsRun else { return nil }
        return part.authorName ?? FeddyCore.shared.config?.brand.name
    }

    var body: some View {
        VStack(alignment: part.isFromContact ? .trailing : .leading, spacing: 3) {
            if let authorLabel {
                Text(authorLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 34)
            }
            HStack(alignment: .top, spacing: 8) {
                if !part.isFromContact {
                    avatar
                }
                Text(part.body)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(part.isFromContact ? Theme.ownBubble : Theme.surface)
                    .foregroundStyle(Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text(Self.timeFormatter.string(from: part.createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, part.isFromContact ? 0 : 34)
        }
        .frame(
            maxWidth: .infinity,
            alignment: part.isFromContact ? .trailing : .leading
        )
        .padding(part.isFromContact ? .leading : .trailing, 48)
    }

    @ViewBuilder
    private var avatar: some View {
        if startsRun {
            if let urlString = part.authorAvatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsCircle
                }
                .frame(width: 26, height: 26)
                .clipShape(Circle())
            } else {
                initialsCircle
            }
        } else {
            Color.clear.frame(width: 26, height: 26)
        }
    }

    // A bot with no picture gets a spark, not an initial: an automatic
    // answer must never read as a person called "A".
    private var initialsCircle: some View {
        BotOrInitialCircle(
            isBot: part.isFromBot,
            name: part.authorName ?? FeddyCore.shared.config?.brand.name ?? "?",
            accent: accent
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}

private struct BotOrInitialCircle: View {
    let isBot: Bool
    let name: String
    let accent: Color

    var body: some View {
        Circle()
            .fill(accent)
            .frame(width: 26, height: 26)
            .overlay(
                Group {
                    if isBot {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.caption2.weight(.bold))
                    }
                }
                .foregroundStyle(Theme.onAccent(FeddyCore.shared.config))
            )
    }
}

/// "Was this helpful?" under the latest auto-reply, then a thank-you once
/// answered. The row goes away as soon as a person on the team replies.
private struct FeedbackRow: View {
    enum State: Equatable {
        case ask(seq: Int, disabled: Bool)
        case thanks
    }

    let state: State
    let accent: Color
    let onAnswer: (Int, Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch state {
            case let .ask(seq, _):
                Text(Strings.feedbackPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(Strings.feedbackYes) { onAnswer(seq, true) }
                Button(Strings.feedbackNo) { onAnswer(seq, false) }
            case .thanks:
                Text(Strings.feedbackThanks)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .tint(accent)
        .controlSize(.mini)
        .disabled(isDisabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 34)
        .padding(.trailing, 48)
    }

    private var isDisabled: Bool {
        if case let .ask(_, disabled) = state { return disabled }
        return false
    }
}

/// Second-chance email ask (spec flow): a teammate replied but we have
/// no email for this contact yet.
private struct EmailCaptureBanner: View {
    let accent: Color
    let onSkip: () -> Void
    let onSaved: () -> Void

    @State private var email = ""
    @State private var error: String?
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Strings.emailPromptTitle)
                .font(.subheadline.weight(.semibold))
            // A line of its own: side by side with the buttons it was just
            // another field competing with the reply box below it.
            TextField(Strings.emailPlaceholder, text: $email)
                .textFieldStyle(.plain)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.page)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color(.systemRed))
            }
            // Trailing, with the primary action last: the leading corner is
            // where the system puts what you are meant to skip past.
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(Strings.emailSkip, action: onSkip)
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                Button(Strings.emailSave) { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(saved ? 0 : 1)
    }

    private func save() {
        Task {
            let message = await EmailCapture.save(email)
            guard message == nil else {
                error = message
                return
            }
            error = nil
            saved = true
            onSaved()
        }
    }
}

#endif
