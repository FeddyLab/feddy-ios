import SwiftUI

/// Detail page for one roadmap request — title, description,
/// official-reply callout, attachment grid, and the comment thread
/// with an inline composer at the bottom. Reachable from
/// ``RequestListView`` (via push) or as a standalone screen:
///
/// ```swift
/// NavigationStack {
///     RequestDetailView(requestId: "req_xyz")
/// }
/// ```
@available(iOS 15.0, macOS 12.0, *)
public struct RequestDetailView: View {
    private let requestId: String

    @State private var detail: Feddy.FeedbackRequest? = nil
    @State private var comments: [Feddy.FeedbackComment] = []
    @State private var commentsCursor: String? = nil
    @State private var isLoadingDetail = true
    @State private var isLoadingMoreComments = false
    @State private var loadError: String? = nil
    @State private var voted: Bool = false
    @State private var voteCountOverride: Int? = nil
    @State private var votePending: Bool = false
    @State private var voteErrorMessage: String? = nil
    @State private var commentDraft: String = ""
    @State private var isPostingComment: Bool = false
    @State private var commentErrorMessage: String? = nil
    @State private var lightboxAttachment: LightboxAttachment? = nil

    public init(requestId: String) {
        self.requestId = requestId
    }

    private struct LightboxAttachment: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    public var body: some View {
        contentView
            .navigationTitle(detail?.title ?? "")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await loadInitial()
            }
            .alert(
                Localization.string("feddy.detail.vote.failed"),
                isPresented: Binding(
                    get: { voteErrorMessage != nil },
                    set: { if !$0 { voteErrorMessage = nil } }
                )
            ) {
                Button(Localization.string("feddy.action.cancel"), role: .cancel) {
                    voteErrorMessage = nil
                }
            }
            .alert(
                Localization.string("feddy.detail.comment.send.failed"),
                isPresented: Binding(
                    get: { commentErrorMessage != nil },
                    set: { if !$0 { commentErrorMessage = nil } }
                )
            ) {
                Button(Localization.string("feddy.action.cancel"), role: .cancel) {
                    commentErrorMessage = nil
                }
            }
            .sheet(item: $lightboxAttachment) { attachment in
                AttachmentLightboxView(url: attachment.url) {
                    lightboxAttachment = nil
                }
            }
    }

    @ViewBuilder
    private var contentView: some View {
        if isLoadingDetail && detail == nil {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, detail == nil {
            VStack(spacing: 12) {
                Text(loadError)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(Localization.string("feddy.action.retry")) {
                    Task { await loadInitial() }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detail {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(detail)
                        if !detail.description.isEmpty {
                            Text(detail.description)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let reply = detail.officialReply, !reply.isEmpty {
                            officialReply(reply)
                        }
                        if !detail.attachments.isEmpty {
                            attachmentsSection(detail.attachments)
                        }
                        Divider()
                        commentsSection
                        PoweredByBadge()
                    }
                    .padding()
                }
                composer
            }
        }
    }

    private func header(_ detail: Feddy.FeedbackRequest) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    statusChip(detail.status)
                    Text(detail.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            voteButton(currentCount: detail.voteCount)
        }
    }

    private func voteButton(currentCount: Int) -> some View {
        Button(action: handleVoteTap) {
            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                Text(verbatim: "\(voteCountOverride ?? currentCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(voted ? Color.white : Color.primary)
            .frame(width: 48, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        voted ? Color.orange : Color.secondary.opacity(0.12)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        voted ? Color.clear : Color.secondary.opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(votePending)
        .accessibilityLabel(
            voted
                ? Localization.string("feddy.action.upvoted")
                : Localization.string("feddy.action.upvote")
        )
    }

    private func officialReply(_ reply: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Localization.string("feddy.detail.officialReply"))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(reply)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func attachmentsSection(_ attachments: [Feddy.Attachment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Localization.string("feddy.detail.attachments"))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 8)],
                spacing: 8
            ) {
                ForEach(attachments, id: \.key) { attachment in
                    Button {
                        lightboxAttachment = LightboxAttachment(url: attachment.assetURL)
                    } label: {
                        AsyncImage(url: attachment.assetURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            @unknown default:
                                Color.gray.opacity(0.1)
                            }
                        }
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Localization.string("feddy.detail.comments"))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if comments.isEmpty {
                Text(Localization.string("feddy.detail.comments.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(comments) { comment in
                    CommentRow(comment: comment)
                }
                if commentsCursor != nil {
                    Button {
                        Task { await loadMoreComments() }
                    } label: {
                        if isLoadingMoreComments {
                            ProgressView()
                        } else {
                            Text(Localization.string("feddy.list.loadingMore"))
                                .font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: 8) {
                // Single-line composer keeps us on the iOS 15 / macOS 12
                // floor — the multi-line `axis: .vertical` variant is
                // iOS 16 / macOS 13. End users typing more than one line
                // is rare for roadmap comments; we revisit if telemetry
                // shows otherwise.
                TextField(
                    Localization.string("feddy.detail.comment.placeholder"),
                    text: $commentDraft
                )
                .textFieldStyle(.roundedBorder)
                .disabled(isPostingComment)
                Button(action: handleCommentSend) {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPostingComment)
                .accessibilityLabel(Localization.string("feddy.action.send"))
            }
            .padding()
        }
        #if os(iOS)
        .background(Color(.secondarySystemBackground))
        #endif
    }

    @MainActor
    private func loadInitial() async {
        isLoadingDetail = true
        loadError = nil
        do {
            async let detailTask = Feddy.fetchRequest(id: requestId)
            async let commentsTask = Feddy.fetchComments(requestId: requestId, limit: 20, cursor: nil)
            let (loadedDetail, loadedComments) = try await (detailTask, commentsTask)
            detail = loadedDetail
            // Seed local state from the server-supplied voted flag so
            // returning to the detail view shows the persisted vote.
            voted = loadedDetail.voted
            voteCountOverride = nil
            comments = loadedComments.items
            commentsCursor = loadedComments.nextCursor
        } catch {
            loadError = Localization.string("feddy.list.error.body")
        }
        isLoadingDetail = false
    }

    @MainActor
    private func loadMoreComments() async {
        guard !isLoadingMoreComments, let cursor = commentsCursor else { return }
        isLoadingMoreComments = true
        defer { isLoadingMoreComments = false }
        do {
            let page = try await Feddy.fetchComments(
                requestId: requestId,
                limit: 20,
                cursor: cursor
            )
            comments.append(contentsOf: page.items)
            commentsCursor = page.nextCursor
        } catch {
            // Silently stop pagination on error.
        }
    }

    @MainActor
    private func handleVoteTap() {
        guard !votePending, let detail else { return }
        let wasVoted = voted
        let baseline = voteCountOverride ?? detail.voteCount
        if wasVoted {
            voted = false
            voteCountOverride = max(baseline - 1, 0)
        } else {
            voted = true
            voteCountOverride = baseline + 1
        }
        votePending = true
        Task {
            do {
                let state = try await Feddy.upvote(requestId: requestId)
                await MainActor.run {
                    voted = state.voted
                    voteCountOverride = state.voteCount
                    votePending = false
                }
            } catch {
                await MainActor.run {
                    voted = wasVoted
                    voteCountOverride = baseline
                    votePending = false
                    voteErrorMessage = Localization.string("feddy.detail.vote.failed")
                }
            }
        }
    }

    @MainActor
    private func handleCommentSend() {
        let body = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isPostingComment else { return }
        isPostingComment = true
        Task {
            do {
                let posted = try await Feddy.addComment(requestId: requestId, body: body)
                await MainActor.run {
                    comments.append(posted)
                    commentDraft = ""
                    isPostingComment = false
                }
            } catch {
                await MainActor.run {
                    isPostingComment = false
                    commentErrorMessage = Localization.string("feddy.detail.comment.send.failed")
                }
            }
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct AttachmentLightboxView: View {
    let url: URL
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView().tint(.white)
                case .success(let img):
                    img
                        .resizable()
                        .scaledToFit()
                case .failure:
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.white)
                @unknown default:
                    Color.clear
                }
            }
            .padding()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.5), in: Circle())
            }
            .padding()
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct CommentRow: View {
    let comment: Feddy.FeedbackComment

    private var isAdmin: Bool { comment.authorKind == .admin }
    private var isSelf: Bool { comment.isSelf }

    private var accent: Color {
        if isAdmin { return .blue }
        if isSelf { return .orange }
        return .secondary
    }

    private var fillColor: Color {
        if isAdmin { return Color.blue.opacity(0.08) }
        if isSelf { return Color.orange.opacity(0.10) }
        return Color.clear
    }

    private var borderColor: Color {
        if isAdmin { return Color.blue.opacity(0.35) }
        if isSelf { return Color.orange.opacity(0.5) }
        return Color.secondary.opacity(0.3)
    }

    private var label: String {
        if isSelf {
            return Localization.string("feddy.detail.comment.you")
        }
        let display = comment.authorDisplayName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if isAdmin {
            if let display, !display.isEmpty { return display }
            return Localization.string("feddy.detail.comment.team")
        }
        if let display, !display.isEmpty { return display }
        return Localization.string("feddy.detail.comment.anonymous")
    }

    /// Snapshot of the comment's age, computed once per render.
    /// `Text(date, style: .relative)` would re-tick every minute and
    /// distract a reader who's just trying to read the thread.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
    private var relativeTime: String {
        Self.relativeFormatter.localizedString(
            for: comment.createdAt,
            relativeTo: Date(),
        )
    }

    var body: some View {
        HStack(alignment: .top) {
            if isSelf { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if isAdmin {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(accent)
                    }
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                Text(comment.content)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            )
            if !isSelf { Spacer(minLength: 24) }
        }
        .padding(.vertical, 4)
    }
}

@available(iOS 15.0, macOS 12.0, *)
private func statusChip(_ status: String) -> some View {
    Text(detailStatusLabel(status))
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            detailStatusColor(status).opacity(0.15),
            in: Capsule()
        )
        .foregroundStyle(detailStatusColor(status))
}

@available(iOS 15.0, macOS 12.0, *)
private func detailStatusLabel(_ status: String) -> String {
    let key = "feddy.status.\(status)"
    let value = Localization.string(key)
    return value == key ? status.capitalized : value
}

@available(iOS 15.0, macOS 12.0, *)
private func detailStatusColor(_ status: String) -> Color {
    switch status {
    case "completed": return .green
    case "in_progress": return .blue
    case "planned": return .orange
    case "rejected", "duplicate": return .gray
    default: return .secondary
    }
}
