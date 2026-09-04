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

    /// Keeps the list fresh while the panel is open: without this a reply
    /// arriving mid-session only shows up on a manual refresh.
    func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            // A failed config fetch leaves the compose form without topics,
            // so keep retrying it alongside the list. Once loaded this is
            // a no-op.
            await FeddyCore.shared.loadConfig()
            await load()
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
    /// The user just closed this thread by rating an auto-reply helpful.
    /// Drives the wording under the composer; the server state is `status`.
    @Published var resolvedByUser = false
    @Published var isRating = false
    /// Shown briefly where the rating buttons were, after an answer.
    @Published var thanksSeq: Int?

    private var reportedSeq = 0
    private var pendingIdempotencyKey: String?

    init(conversationId: String) {
        self.conversationId = conversationId
    }

    var maxSeq: Int { parts.last?.seq ?? 0 }
    /// The email ask follows a person's reply, not the bot's: a bot answer
    /// gives no reason to expect mail worth being notified about.
    var hasTeammateReply: Bool { parts.contains { $0.authorType == "teammate" } }

    /// The auto-reply that can still be rated: the latest bot message, as
    /// long as nobody has rated it and no teammate has replied since. The
    /// user's own follow-ups leave the question standing.
    var feedbackTarget: Part? {
        guard let bot = parts.last(where: { $0.isFromBot }), bot.botFeedback == nil else {
            return nil
        }
        if parts.contains(where: { $0.seq > bot.seq && $0.authorType == "teammate" }) {
            return nil
        }
        return bot
    }

    func rate(seq: Int, helpful: Bool) async {
        guard let client = FeddyCore.shared.client, !isRating else { return }
        isRating = true
        defer { isRating = false }
        do {
            let result = try await client.sendBotFeedback(
                conversationId: conversationId, seq: seq, helpful: helpful
            )
            if let index = parts.firstIndex(where: { $0.seq == seq }) {
                parts[index].botFeedback = helpful ? "helpful" : "not_helpful"
            }
            thanksSeq = seq
            if result.status == "closed", status != "closed" {
                status = "closed"
                resolvedByUser = true
            }
            // A "no" is answered with the fallback message; the server holds
            // it back for a moment and the regular poll brings it in.
            _ = result.replySeq
        } catch {
            // Rated from another device already, or offline: the next poll
            // draws the truth, and there is nothing further to ask here.
            if let index = parts.firstIndex(where: { $0.seq == seq }) {
                parts[index].botFeedback = "unknown"
            }
        }
    }

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

    func send(_ text: String, tray: AttachmentTrayModel? = nil) async -> Bool {
        guard let client = FeddyCore.shared.client, !isSending else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isSending = true
        sendError = nil
        defer { isSending = false }
        let key = pendingIdempotencyKey ?? UUID().uuidString
        pendingIdempotencyKey = key
        do {
            // Uploaded before the message is written, and left in the tray if
            // it fails: the reply can then be retried whole rather than
            // costing the words that were typed with the screenshot.
            let files = try await tray?.upload(using: client) ?? []
            let result = try await client.appendPart(
                conversationId: conversationId, body: trimmed, attachments: files, idempotencyKey: key
            )
            pendingIdempotencyKey = nil
            tray?.clear()
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

    func submit(tray: AttachmentTrayModel? = nil) async {
        guard let client = FeddyCore.shared.client, !isSubmitting else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        let key = pendingIdempotencyKey ?? UUID().uuidString
        pendingIdempotencyKey = key
        do {
            let files = try await tray?.upload(using: client) ?? []
            let created = try await client.createConversation(
                body: trimmed, categoryCode: categoryCode, attachments: files, idempotencyKey: key
            )
            pendingIdempotencyKey = nil
            tray?.clear()
            createdConversationId = created.id
        } catch let error as APIError {
            submitError = error.isRateLimited ? Strings.rateLimited : Strings.errorGeneric
        } catch {
            submitError = Strings.errorGeneric
        }
    }
}
#endif
