import Foundation

/// One `identify` call's arguments, captured at call time.
struct IdentityPayload: @unchecked Sendable {
    let externalId: String
    var email: String? = nil
    var name: String? = nil
    var avatarUrl: String? = nil
    var attributes: [String: Any] = [:]
}

/// Sends `identify` payloads one at a time, in call order.
///
/// The server replaces the whole attribute set on every identify, so the
/// last request to arrive wins. Firing each call as its own request let two
/// calls made milliseconds apart (a placeholder value at launch, then the
/// real one) land in either order, and the stale one could overwrite the
/// real one. Here only one request is in flight, and calls made meanwhile
/// collapse into the newest, which goes out next.
///
/// `submit` records the payload synchronously under a lock rather than
/// hopping onto an actor: unstructured tasks reach an actor in no promised
/// order, which would reintroduce the race one step earlier.
///
/// A payload that fails on a transient error (network, rate limit, 5xx) is
/// kept and resent on the next `flush()`, unless a newer call replaced it.
/// Client errors (4xx) are dropped: resending the same payload cannot fix
/// them.
final class IdentityQueue: @unchecked Sendable {
    typealias Send = @Sendable (IdentityPayload) async throws -> Void

    private let send: Send
    private let lock = NSLock()
    private var pending: IdentityPayload?
    private var sending = false

    init(send: @escaping Send) {
        self.send = send
    }

    var isSending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sending
    }

    func submit(_ payload: IdentityPayload) {
        lock.lock()
        pending = payload
        let start = claimSender()
        lock.unlock()
        if start { Task { await drain() } }
    }

    /// Starts sending whatever is pending. Safe to call at any time; a no-op
    /// while a request is in flight or when nothing is waiting.
    func flush() {
        lock.lock()
        let start = claimSender()
        lock.unlock()
        if start { Task { await drain() } }
    }

    /// Caller holds the lock.
    private func claimSender() -> Bool {
        guard !sending, pending != nil else { return false }
        sending = true
        return true
    }

    private func takeNext() -> IdentityPayload? {
        lock.lock()
        defer { lock.unlock() }
        guard let payload = pending else {
            sending = false
            return nil
        }
        pending = nil
        return payload
    }

    /// Returns true when the failed payload was kept and sending stopped.
    private func keepForRetry(_ payload: IdentityPayload, after error: Error) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // A newer call made while this one was in flight supersedes it.
        guard pending == nil, Self.isRetryable(error) else { return false }
        pending = payload
        sending = false
        return true
    }

    private func drain() async {
        while let payload = takeNext() {
            do {
                try await send(payload)
            } catch {
                if keepForRetry(payload, after: error) { return }
            }
        }
    }

    static func isRetryable(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return true }
        return apiError.isRateLimited || apiError.status >= 500
    }
}
