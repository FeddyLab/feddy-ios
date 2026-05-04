import SwiftUI

/// Drop-in roadmap viewer — three horizontally-swipeable tabs grouped
/// by status (Planned / In Progress / Completed), each with its own
/// pagination. Mirrors the dashboard's kanban board on a phone-friendly
/// surface. Use this when the host wants to surface "what's coming /
/// happening / done"; for a flat all-feedback list with a board filter,
/// use ``RequestListView`` instead.
///
/// ```swift
/// .sheet(isPresented: $showRoadmap) {
///     RoadmapView()
/// }
/// ```
@available(iOS 15.0, macOS 12.0, *)
public struct RoadmapView: View {
    private let boards: [FeedbackBoard]

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Feddy.RoadmapStatus = .planned
    @State private var isComposing: Bool = false
    /// Bumps every time the compose sheet dismisses so each
    /// `RoadmapStatusPage` can `.task(id:)` on the change and reload.
    @State private var refreshToken: Int = 0

    public init(boards: [FeedbackBoard] = FeedbackBoard.systemDefaults) {
        self.boards = boards
    }

    public var body: some View {
        navigationContainer {
            VStack(spacing: 0) {
                statusPicker
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                tabContent
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PoweredByBadge()
            }
            .navigationTitle(Localization.string("feddy.roadmap.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
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
                    Button {
                        isComposing = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(Localization.string("feddy.compose.title"))
                }
            }
            .sheet(
                isPresented: $isComposing,
                onDismiss: {
                    // Each tab observes refreshToken via task(id:) and
                    // reloads. Server filters pending status, so a
                    // freshly-submitted item won't appear yet — the
                    // refresh is mostly for retry/cancel UX.
                    refreshToken &+= 1
                }
            ) {
                RequestComposeView(boards: boards)
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

    private var statusPicker: some View {
        // Empty `Picker("", ...)` would emit an empty-string entry into
        // the localization catalog. Use the label-closure form with
        // EmptyView so SwiftUI doesn't route an empty key through
        // localization extraction; segmented style hides the label
        // anyway.
        Picker(selection: $selectedTab) {
            ForEach(Feddy.RoadmapStatus.allCases, id: \.self) { status in
                Text(localizedStatusLabel(status.rawValue)).tag(status)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        // One independent page per status — using TabView with PageTabViewStyle
        // gives the host the dashboard-equivalent "swipe between columns"
        // affordance on top of the segmented picker tap target. Each page
        // owns its own pagination state via RoadmapStatusPage.
        if #available(iOS 16.0, macOS 13.0, *) {
            TabView(selection: $selectedTab) {
                ForEach(Feddy.RoadmapStatus.allCases, id: \.self) { status in
                    RoadmapStatusPage(
                        status: status,
                        boards: boards,
                        refreshToken: refreshToken
                    )
                    .tag(status)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
        } else {
            // Fallback for the iOS 15 / macOS 12 floor: render the active
            // page only (no horizontal swipe). The segmented picker still
            // switches between status pages — only the swipe gesture is
            // missing on older OSes.
            RoadmapStatusPage(
                status: selectedTab,
                boards: boards,
                refreshToken: refreshToken
            )
        }
    }
}

/// One status page inside ``RoadmapView``. Owns its own list of items,
/// cursor, and vote-overlay state so each tab paginates independently.
@available(iOS 15.0, macOS 12.0, *)
private struct RoadmapStatusPage: View {
    let status: Feddy.RoadmapStatus
    let boards: [FeedbackBoard]
    /// Parent's refresh-trigger counter — used as `task(id:)` so each
    /// page reloads after the compose sheet dismisses.
    let refreshToken: Int

    @State private var items: [Feddy.FeedbackRequest] = []
    @State private var nextCursor: String? = nil
    @State private var isInitialLoading = true
    @State private var isLoadingMore = false
    @State private var loadError: String? = nil
    @State private var votedIds: Set<String> = []
    @State private var voteOverlays: [String: Int] = [:]
    @State private var pendingVoteIds: Set<String> = []
    @State private var voteErrorMessage: String? = nil

    var body: some View {
        content
            .task(id: refreshToken) {
                // Initial load on first appear, plus reload whenever the
                // parent bumps refreshToken (compose sheet dismissed).
                if refreshToken == 0 && !items.isEmpty {
                    return
                }
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
                Text(emptyTitle)
                    .font(.headline)
                Text(Localization.string("feddy.roadmap.empty.body"))
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

    private var emptyTitle: String {
        // "No <Status> items yet" — lighter than the all-feedback empty
        // copy because this view's empty state is per tab.
        let label = localizedStatusLabel(status.rawValue)
        let template = Localization.string("feddy.roadmap.empty.titleFormat")
        return template.replacingOccurrences(of: "{status}", with: label)
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
                        // Status is implied by the tab — don't repeat it on
                        // every card.
                        showStatusChip: false,
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
                boardKey: nil,
                status: status,
                limit: 20,
                cursor: nil
            )
            items = page.items
            nextCursor = page.nextCursor
            votedIds = Set(page.items.filter(\.voted).map(\.id))
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
                boardKey: nil,
                status: status,
                limit: 20,
                cursor: cursor
            )
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
            for item in page.items where item.voted {
                votedIds.insert(item.id)
            }
        } catch {
            // Silently stop pagination on error.
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
