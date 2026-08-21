#if canImport(UIKit)
import Foundation

@MainActor
final class ConversationListModel: ObservableObject {
    @Published var conversations: [ConversationSummary] = []
    @Published var isLoading = false
    @Published var loadFailed = false

    private var hasLoaded = false

    func load() async {
        guard let client = FeddyCore.shared.client else { return }
        // Only the very first load swaps the whole screen for a spinner;
        // later refreshes update in place.
        if !hasLoaded { isLoading = true }
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            conversations = try await client.conversations().conversations
            loadFailed = false
        } catch {
            loadFailed = conversations.isEmpty
        }
    }

    /// Opening a thread clears its unread dot without waiting for the
    /// round trip; the detail view reports the read to the server.
    func markReadLocally(_ conversationId: String) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[index].seenSeq = conversations[index].lastSeq
    }
}

@MainActor
final class ConversationDetailModel: ObservableObject {
    @Published private(set) var conversationId: String
    @Published var parts: [Part] = []
    @Published var subject: String?
    @Published var status = "open"
    @Published var isSending = false
    @Published var sendError: String?

    private var reportedSeq = 0
    private var pendingIdempotencyKey: String?

    init(conversationId: String) {
        self.conversationId = conversationId
    }

    var maxSeq: Int { parts.last?.seq ?? 0 }
    var hasTeammateReply: Bool { parts.contains { !$0.isFromContact } }

    func loadInitial() async {
        guard let client = FeddyCore.shared.client else { return }
        guard let detail = try? await client.conversation(id: conversationId) else { return }
        parts = detail.parts
        subject = detail.subject
        status = detail.status
        await reportRead()
    }

    func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await pollOnce()
        }
    }

    func pollOnce() async {
        guard let client = FeddyCore.shared.client else { return }
        guard let fresh = try? await client.conversation(id: conversationId, sinceSeq: maxSeq)
        else { return }
        subject = fresh.subject ?? subject
        status = fresh.status
        guard !fresh.parts.isEmpty else { return }
        merge(fresh.parts)
        await reportRead()
    }

    func send(_ text: String) async -> Bool {
        guard let client = FeddyCore.shared.client, !isSending else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isSending = true
        sendError = nil
        defer { isSending = false }
        let key = pendingIdempotencyKey ?? UUID().uuidString
        pendingIdempotencyKey = key
        do {
            let result = try await client.appendPart(
                conversationId: conversationId, body: trimmed, idempotencyKey: key
            )
            pendingIdempotencyKey = nil
            if result.conversationId != conversationId {
                // Closed for 7+ days: the server started a fresh conversation.
                conversationId = result.conversationId
                parts = []
                reportedSeq = 0
                await loadInitial()
            } else {
                await pollOnce()
            }
            return true
        } catch let error as APIError {
            sendError = error.isRateLimited ? Strings.rateLimited : Strings.errorGeneric
            return false
        } catch {
            sendError = Strings.errorGeneric
            return false
        }
    }

    private func merge(_ incoming: [Part]) {
        var bySeq = Dictionary(uniqueKeysWithValues: parts.map { ($0.seq, $0) })
        for part in incoming { bySeq[part.seq] = part }
        parts = bySeq.values.sorted { $0.seq < $1.seq }
    }

    /// Having the thread on screen is what "read" means for the end
    /// user: report the highest rendered seq.
    private func reportRead() async {
        guard let client = FeddyCore.shared.client else { return }
        let seq = maxSeq
        guard seq > reportedSeq else { return }
        if (try? await client.markRead(conversationId: conversationId, seenSeq: seq)) != nil {
            reportedSeq = seq
            FeddyCore.shared.refresh()
        }
    }
}

@MainActor
final class ComposeModel: ObservableObject {
    @Published var text = ""
    @Published var categoryCode: String?
    @Published var isSubmitting = false
    @Published var submitError: String?
    @Published var createdConversationId: String?

    private var pendingIdempotencyKey: String?

    func submit() async {
        guard let client = FeddyCore.shared.client, !isSubmitting else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        let key = pendingIdempotencyKey ?? UUID().uuidString
        pendingIdempotencyKey = key
        do {
            let created = try await client.createConversation(
                body: trimmed, categoryCode: categoryCode, idempotencyKey: key
            )
            pendingIdempotencyKey = nil
            createdConversationId = created.id
            FeddyCore.shared.requestNotificationPermissionIfNeeded()
        } catch let error as APIError {
            submitError = error.isRateLimited ? Strings.rateLimited : Strings.errorGeneric
        } catch {
            submitError = Strings.errorGeneric
        }
    }
}
#endif
