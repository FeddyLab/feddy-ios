import SwiftUI

/// Drop-in feedback list — every public-roadmap request in the
/// workspace, paginated, with an inline upvote button and tap-to-detail
/// navigation. The board axis is exposed as a top-bar filter menu (with
/// an "All" entry); status is shown as a per-card chip rather than a
/// filter, since this view is positioned as the "everything" surface.
/// For a status-grouped, kanban-style presentation, use
/// ``RoadmapView`` instead.
///
/// Present as a sheet or push onto a navigation stack:
///
/// ```swift
/// .sheet(isPresented: $showFeedback) {
///     RequestListView()
/// }
/// ```
///
/// Pass the workspace's board catalog if you have custom boards; the
/// menu pulls display names from these entries. When omitted, only the
/// two system boards (`features` / `bugs`) appear in the filter.
///
/// ```swift
/// RequestListView(boards: [
///     .featureRequest,
///     .bugReport,
///     .init(key: "discussions", name: "Discussions"),
/// ])
/// ```
@available(iOS 15.0, macOS 12.0, *)
public struct RequestListView: View {
    private let boards: [FeedbackBoard]

    @Environment(\.dismiss) private var dismiss

    @State private var selectedBoardKey: String? = nil  // nil = All boards
    @State private var items: [Feddy.FeedbackRequest] = []
    @State private var nextCursor: String? = nil
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String? = nil
    @State private var votedIds: Set<String> = []
    @State private var voteOverlays: [String: Int] = [:]
    @State private var pendingVoteIds: Set<String> = []
    @State private var voteErrorMessage: String? = nil
    @State private var isComposing: Bool = false

    public init(boards: [FeedbackBoard] = FeedbackBoard.systemDefaults) {
        self.boards = boards
    }

    public var body: some View {
        navigationContainer {
            content
                .navigationTitle(Localization.string("feddy.list.title"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    // Sheet-friendly close affordance — `dismiss` is
                    // context-aware (closes a sheet / pops a navigation
                    // push) so this works whether the host presents the
                    // view as a sheet or pushes it onto an existing
                    // stack.
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(
                            Localization.string("feddy.action.cancel")
                        )
                    }
                    ToolbarItem(placement: .primaryAction) {
                        filterMenu
                    }
                    ToolbarItem(placement: .primaryAction) {
                        composeButton
                    }
                }
                .task(id: selectedBoardKey) {
                    await loadInitial()
                }
                .refreshable {
                    await loadInitial()
                }
                .sheet(
                    isPresented: $isComposing,
                    onDismiss: {
                        // Refresh after compose dismiss so a successful
                        // submission with status `pending` doesn't appear
                        // (server filters internal statuses) but the UI
                        // still feels reactive on retry / cancel.
                        Task { await loadInitial() }
                    }
                ) {
                    RequestComposeView(boards: boards)
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
        }
    }

    @ViewBuilder
    private func navigationContainer<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isInitialLoading && items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, items.isEmpty {
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
        } else if items.isEmpty {
            VStack(spacing: 8) {
                Text(Localization.string("feddy.list.empty.title"))
                    .font(.headline)
                Text(Localization.string("feddy.list.empty.body"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list
        }
    }

    /// Toolbar shortcut to open ``RequestComposeView`` so end users can
    /// post new feedback directly from the list rather than the host
    /// app having to wire up its own entry point. Mirrors the
    /// "compose" affordance every mainstream feedback / inbox app
    /// (GitHub, Linear, Mail) puts in the same spot.
    private var composeButton: some View {
        Button {
            isComposing = true
        } label: {
            Image(systemName: "square.and.pencil")
        }
        .accessibilityLabel(Localization.string("feddy.compose.title"))
    }

    private var filterMenu: some View {
        Menu {
            menuRow(
                title: Localization.string("feddy.filter.allBoards"),
                isSelected: selectedBoardKey == nil
            ) {
                selectedBoardKey = nil
            }
            ForEach(boards) { board in
                menuRow(
                    title: board.name,
                    isSelected: selectedBoardKey == board.key
                ) {
                    selectedBoardKey = board.key
                }
            }
        } label: {
            Label(
                Localization.string("feddy.action.filter"),
                systemImage: "line.3.horizontal.decrease.circle"
            )
        }
    }

    /// Render a menu entry that shows a checkmark only when selected.
    /// Passing `systemImage: ""` to `Label` would log a runtime warning
    /// for every unselected entry every time the menu opens, which
    /// floods the console once a workspace has more than a couple of
    /// boards.
    @ViewBuilder
    private func menuRow(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(items) { item in
                NavigationLink(destination: RequestDetailView(requestId: item.id)) {
                    RequestRow(
                        request: item,
                        boardName: boardDisplayName(for: item.boardKey),
                        voteOverlay: voteOverlays[item.id],
                        voted: votedIds.contains(item.id),
                        votePending: pendingVoteIds.contains(item.id),
                        showStatusChip: true,
                        onVoteTap: { handleVoteTap(for: item) }
                    )
                }
                .onAppear {
                    if item.id == items.last?.id {
                        Task { await loadMoreIfNeeded() }
                    }
                }
            }
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Text(Localization.string("feddy.list.loadingMore"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
    }

    private func boardDisplayName(for key: String) -> String {
        boards.first(where: { $0.key == key })?.name ?? key.capitalized
    }

    @MainActor
    private func loadInitial() async {
        isInitialLoading = true
        loadError = nil
        nextCursor = nil
        do {
            let page = try await Feddy.fetchRequests(
                boardKey: selectedBoardKey,
                status: nil,
                limit: 20,
                cursor: nil
            )
            items = page.items
            nextCursor = page.nextCursor
            // Seed votedIds from the server-supplied flag so the
            // voted-state highlight survives view reopens — without
            // this, only this-session taps would show as voted.
            votedIds = Set(page.items.filter(\.voted).map(\.id))
            // Drop stale overlays that no longer match a fetched item;
            // server is authoritative for vote_count on initial load.
            voteOverlays.removeAll()
        } catch {
            loadError = Localization.string("feddy.list.error.body")
        }
        isInitialLoading = false
    }

    @MainActor
    private func loadMoreIfNeeded() async {
        guard !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await Feddy.fetchRequests(
                boardKey: selectedBoardKey,
                status: nil,
                limit: 20,
                cursor: cursor
            )
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            // Merge new page's voted flags into the existing set.
            for item in page.items where item.voted {
                votedIds.insert(item.id)
            }
        } catch {
            // Silently stop pagination on error; pull-to-refresh recovers.
        }
    }

    @MainActor
    private func handleVoteTap(for item: Feddy.FeedbackRequest) {
        guard !pendingVoteIds.contains(item.id) else { return }
        let wasVoted = votedIds.contains(item.id)
        let baseline = voteOverlays[item.id] ?? item.voteCount
        if wasVoted {
            votedIds.remove(item.id)
            voteOverlays[item.id] = max(baseline - 1, 0)
        } else {
            votedIds.insert(item.id)
            voteOverlays[item.id] = baseline + 1
        }
        pendingVoteIds.insert(item.id)
        Task {
            do {
                let state = try await Feddy.upvote(requestId: item.id)
                await MainActor.run {
                    voteOverlays[item.id] = state.voteCount
                    if state.voted {
                        votedIds.insert(item.id)
                    } else {
                        votedIds.remove(item.id)
                    }
                    pendingVoteIds.remove(item.id)
                }
            } catch {
                await MainActor.run {
                    if wasVoted {
                        votedIds.insert(item.id)
                    } else {
                        votedIds.remove(item.id)
                    }
                    voteOverlays[item.id] = baseline
                    pendingVoteIds.remove(item.id)
                    voteErrorMessage = Localization.string("feddy.detail.vote.failed")
                }
            }
        }
    }
}

/// Shared row for both ``RequestListView`` and ``RoadmapView``. The
/// `showStatusChip` flag lets the host hide the status chip when the
/// containing view already groups by status (RoadmapView's tabs).
@available(iOS 15.0, macOS 12.0, *)
struct RequestRow: View {
    let request: Feddy.FeedbackRequest
    let boardName: String
    let voteOverlay: Int?
    let voted: Bool
    let votePending: Bool
    let showStatusChip: Bool
    let onVoteTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            voteButton

            VStack(alignment: .leading, spacing: 6) {
                Text(request.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if !request.description.isEmpty {
                    Text(request.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    boardChip
                    if showStatusChip {
                        statusChip
                    }
                    if !request.attachments.isEmpty {
                        // Use the title-closure form so the count isn't
                        // routed through SwiftUI's localization extractor
                        // (which would otherwise generate a `%lld` key).
                        Label {
                            Text(verbatim: "\(request.attachments.count)")
                        } icon: {
                            Image(systemName: "paperclip")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    /// Reddit / Featurebase style upvote pill: vertical chip with the
    /// ↑ icon over the count, framed by a rounded background that
    /// changes color when the current user has voted. The accentColor
    /// fill makes the voted state unmistakable at a glance even when
    /// scrolling a long list.
    private var voteButton: some View {
        Button(action: onVoteTap) {
            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .semibold))
                Text(verbatim: "\(voteOverlay ?? request.voteCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(voted ? Color.white : Color.primary)
            .frame(width: 44, height: 48)
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
        .accessibilityLabel(
            voted
                ? Localization.string("feddy.action.upvoted")
                : Localization.string("feddy.action.upvote")
        )
        .disabled(votePending)
    }

    private var boardChip: some View {
        Text(boardName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var statusChip: some View {
        Text(localizedStatusLabel(request.status))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                statusChipColor(request.status).opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(statusChipColor(request.status))
    }
}

@available(iOS 15.0, macOS 12.0, *)
func localizedStatusLabel(_ status: String) -> String {
    let key = "feddy.status.\(status)"
    let value = Localization.string(key)
    return value == key ? status.capitalized : value
}

@available(iOS 15.0, macOS 12.0, *)
func statusChipColor(_ status: String) -> Color {
    switch status {
    case "completed": return .green
    case "in_progress": return .blue
    case "planned": return .orange
    case "rejected", "duplicate": return .gray
    default: return .secondary
    }
}
