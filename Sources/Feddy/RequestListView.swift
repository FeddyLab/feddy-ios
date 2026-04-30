import SwiftUI

/// Drop-in roadmap viewer: paginated list of public-roadmap requests
/// with a board picker, pull-to-refresh, infinite scroll, and an
/// inline upvote button on each row. Tapping a row pushes
/// ``RequestDetailView``.
///
/// Present this as a sheet or push it onto a navigation stack:
///
/// ```swift
/// .sheet(isPresented: $showRoadmap) {
///     RequestListView()
/// }
/// ```
///
/// To restrict to specific boards, pass the workspace's board keys
/// (matches what you see in `dashboard.feddy.app/w/<ws>/boards`):
///
/// ```swift
/// RequestListView(boards: [
///     .featureRequest,
///     .init(key: "discussions", name: "Discussions"),
/// ])
/// ```
@available(iOS 15.0, macOS 12.0, *)
public struct RequestListView: View {
    private let boards: [FeedbackBoard]

    @State private var selectedBoardKey: String?
    @State private var items: [Feddy.FeedbackRequest] = []
    @State private var nextCursor: String? = nil
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String? = nil
    @State private var votedIds: Set<String> = []
    @State private var voteOverlays: [String: Int] = [:]
    @State private var pendingVoteIds: Set<String> = []
    @State private var voteErrorMessage: String? = nil

    public init(boards: [FeedbackBoard] = FeedbackBoard.systemDefaults) {
        self.boards = boards
        // Default to the first board if any were provided. nil means
        // "all boards in the workspace" (server defaults the union).
        _selectedBoardKey = State(initialValue: boards.first?.key)
    }

    public var body: some View {
        navigationContainer {
            VStack(spacing: 0) {
                if boards.count > 1 {
                    boardPicker
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
                content
            }
                .navigationTitle(Localization.string("feddy.list.title"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .task(id: selectedBoardKey) {
                    await loadInitial()
                }
                .refreshable {
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
        }
    }

    /// Use NavigationStack on iOS 16+/macOS 13+; fall back to
    /// NavigationView on the iOS 15 / macOS 12 floor declared by
    /// Package.swift. Same pattern as RequestComposeView.
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

    private var boardPicker: some View {
        Picker(
            Localization.string("feddy.compose.board.label"),
            selection: Binding<String?>(
                get: { selectedBoardKey },
                set: { selectedBoardKey = $0 }
            )
        ) {
            ForEach(boards) { board in
                Text(board.name).tag(Optional(board.key))
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
    }

    private var list: some View {
        List {
            ForEach(items) { item in
                // Inline-destination NavigationLink (works on both
                // NavigationView and NavigationStack); the value-based
                // .navigationDestination(for:) is iOS 16+ only.
                NavigationLink(destination: RequestDetailView(requestId: item.id)) {
                    RequestRow(
                        request: item,
                        voteOverlay: voteOverlays[item.id],
                        voted: votedIds.contains(item.id),
                        votePending: pendingVoteIds.contains(item.id),
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

    @MainActor
    private func loadInitial() async {
        isInitialLoading = true
        loadError = nil
        nextCursor = nil
        do {
            let page = try await Feddy.fetchRequests(
                boardKey: selectedBoardKey,
                limit: 20,
                cursor: nil
            )
            items = page.items
            nextCursor = page.nextCursor
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
                limit: 20,
                cursor: cursor
            )
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
        } catch {
            // Silently stop pagination on error; pull-to-refresh recovers.
        }
    }

    @MainActor
    private func handleVoteTap(for item: Feddy.FeedbackRequest) {
        guard !pendingVoteIds.contains(item.id) else { return }
        let wasVoted = votedIds.contains(item.id)
        let baseline = voteOverlays[item.id] ?? item.voteCount
        // Optimistic toggle.
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
                    // Rollback to the prior state.
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

@available(iOS 15.0, macOS 12.0, *)
private struct RequestRow: View {
    let request: Feddy.FeedbackRequest
    let voteOverlay: Int?
    let voted: Bool
    let votePending: Bool
    let onVoteTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Button(action: onVoteTap) {
                    Image(systemName: voted ? "chevron.up.circle.fill" : "chevron.up.circle")
                        .font(.title3)
                        .foregroundStyle(voted ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    voted
                        ? Localization.string("feddy.action.upvoted")
                        : Localization.string("feddy.action.upvote")
                )
                .disabled(votePending)
                Text("\(voteOverlay ?? request.voteCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

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
                    statusChip
                    if !request.attachments.isEmpty {
                        Label(
                            "\(request.attachments.count)",
                            systemImage: "paperclip"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var statusChip: some View {
        Text(localizedStatus(request.status))
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                statusColor(request.status).opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(statusColor(request.status))
    }
}

@available(iOS 15.0, macOS 12.0, *)
private func localizedStatus(_ status: String) -> String {
    let key = "feddy.status.\(status)"
    let value = Localization.string(key)
    // Fallback to the raw key if no translation matches (e.g. a future
    // status string the SDK doesn't know about yet).
    return value == key ? status.capitalized : value
}

@available(iOS 15.0, macOS 12.0, *)
private func statusColor(_ status: String) -> Color {
    switch status {
    case "completed": return .green
    case "in_progress": return .blue
    case "planned": return .orange
    case "rejected", "duplicate": return .gray
    default: return .secondary
    }
}
