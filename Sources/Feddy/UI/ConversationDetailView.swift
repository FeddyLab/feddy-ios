#if canImport(UIKit)
import SwiftUI

struct ConversationDetailView: View {
    @StateObject private var model: ConversationDetailModel
    @StateObject private var tray = AttachmentTrayModel()
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
                // good, so there has to be a way back to it. Gone entirely
                // when the project cannot email replies.
                ToolbarItem(placement: .navigationBarTrailing) {
                    if FeddyCore.shared.emailCaptureEnabled && !emailKnown {
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
            AttachmentArea(model: tray, disabled: model.isSending)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            composer
        }
        .background(.bar)
    }

    private var showEmailBanner: Bool {
        FeddyCore.shared.emailCaptureEnabled
            && !emailKnown && !emailBannerDismissed && !FeddyCore.shared.emailAskDismissed
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
            if await model.send(text, tray: tray), draft == text {
                draft = ""
            }
        }
    }
}

/// One image on a message. The thread carries an API path, not a picture:
/// asking for it proves this contact owns the attachment and yields a URL
/// good for a minute. Requested when the bubble appears rather than when the
/// thread loads, so nothing long-lived is held — see `AttachmentImageStore`,
/// which owns the signing, the retry and the cache.
/// However many pictures came with one message, laid out so the bubble can
/// never grow wider than the screen.
///
/// A single image keeps its shape — that is the common case and cropping it
/// would hide what the sender was pointing at. Several become a grid of
/// equal tiles: ragged heights read as a mistake, and an unbounded row is
/// what pushed the message text off the right edge entirely. Cropping is
/// confined to the grid, and tapping any tile opens the picture whole.
private struct AttachmentRow: View {
    let attachments: [Attachment]
    let alignment: HorizontalAlignment

    private let tile: CGFloat = 84
    private let spacing: CGFloat = 6
    private let perRow = 3

    private var rows: [[Attachment]] {
        stride(from: 0, to: attachments.count, by: perRow).map {
            Array(attachments[$0..<min($0 + perRow, attachments.count)])
        }
    }

    var body: some View {
        if attachments.count == 1, let only = attachments.first {
            AttachmentThumbnail(attachment: only, tile: nil)
        } else {
            VStack(alignment: alignment, spacing: spacing) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: spacing) {
                        ForEach(rows[index]) { file in
                            AttachmentThumbnail(attachment: file, tile: tile)
                        }
                    }
                }
            }
        }
    }
}

private struct AttachmentThumbnail: View {
    let attachment: Attachment
    /// Side length when this is one tile of a grid; nil when it is the only
    /// picture and may keep its own proportions.
    let tile: CGFloat?
    @State private var showFullScreen = false

    // Capped, not framed square. A lone screenshot cropped to a tile loses
    // the very thing it was sent to show.
    private let maxWidth: CGFloat = 200
    private let maxHeight: CGFloat = 260

    var body: some View {
        AttachmentImageView(id: attachment.id) { phase in
            switch phase {
            case .loaded(let image):
                Button {
                    showFullScreen = true
                } label: {
                    sized(image)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .fullScreenCover(isPresented: $showFullScreen) {
                    AttachmentFullScreen(attachment: attachment)
                }
            case .loading:
                placeholder
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            case .failed:
                // A picture that will not load is not worth a broken-image
                // icon in the middle of a conversation. Scrolling it out of
                // view and back rebuilds this and tries again.
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func sized(_ image: Image) -> some View {
        if let tile {
            image.resizable().scaledToFill().frame(width: tile, height: tile)
        } else {
            image.resizable().scaledToFit().frame(maxWidth: maxWidth, maxHeight: maxHeight)
        }
    }

    // Exactly the size the loaded picture will take, so nothing reflows when
    // it arrives — the placeholders being larger than the images is what
    // made the first paint push the text off screen.
    private var placeholder: some View {
        Theme.surface
            .frame(width: tile ?? maxWidth, height: tile ?? maxWidth)
            .overlay(ProgressView().controlSize(.small))
    }
}

/// The picture on its own, over black. Nothing else on screen: whatever the
/// person is trying to read in the screenshot is the only thing that matters
/// here.
///
/// No zoom. What was here magnified but could not pan, so anything the
/// magnification brought within reading distance was pushed off the edges —
/// half a gesture is worse than none. A portrait screenshot fills a portrait
/// screen at its own proportions anyway, and it arrives at the size it was
/// taken (`AttachmentUpload.maxEdge`), so there is nothing to zoom towards.
private struct AttachmentFullScreen: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AttachmentImageView(id: attachment.id) { phase in
                switch phase {
                case .loaded(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .loading:
                    ProgressView().tint(.white)
                case .failed:
                    // Said out loud rather than spun forever. This is where
                    // an expired signature used to land, and the whole
                    // screen was black with a turning spinner on it.
                    VStack(spacing: 10) {
                        Image(systemName: "photo")
                            .font(.system(size: 30))
                        Text(Strings.errorGeneric)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(32)
                }
            }
            .accessibilityLabel(attachment.filename)
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .padding(16)
            .accessibilityLabel(Strings.close)
        }
        // A tap anywhere is the gesture people try first.
        .onTapGesture { dismiss() }
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
            if let attachments = part.attachments, !attachments.isEmpty {
                AttachmentRow(
                    attachments: attachments,
                    // Follows the message, not a fixed side: a last row that
                    // is not full has to hug the same edge the bubble does,
                    // or it hangs off the far side of its own block.
                    alignment: part.isFromContact ? .trailing : .leading
                )
                .padding(.leading, part.isFromContact ? 0 : 34)
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
