#if canImport(UIKit)
import SwiftUI
import UIKit

/// Attachment pictures, decoded once and kept while the panel is open.
///
/// A thread carries an API path, not a picture, and the URL that path yields
/// is signed for sixty seconds. Two things follow from that, and both used
/// to be handled — badly — at the two places that drew an image.
///
/// A picture scrolled off screen and back was fetched again, and since every
/// answer is a different signature, nothing downstream could cache it
/// either: the same screenshot was downloaded once per look at it. And a URL
/// taken when the bubble first appeared is dead by the time someone has read
/// the reply and tapped the picture, which left the full screen spinning
/// over a 403 forever, because `AsyncImage`'s two-closure form has no
/// failure branch at all.
///
/// One place owns all of it: decoded images live in a cache keyed by
/// attachment id, and a request that comes back 403 is retried once against
/// a freshly signed URL before it counts as a failure.
final class AttachmentImageStore: @unchecked Sendable {
    static let shared = AttachmentImageStore()

    /// `NSCache` rather than a dictionary: it empties itself under memory
    /// pressure, which matters because these are full-size screenshots and
    /// the host app's own memory is not ours to spend.
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // Three or four full-size screenshots. Enough that scrolling a
        // thread back and forth never refetches; not enough to be worth
        // noticing.
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    /// What is already in hand, for the initial state of a view — so a
    /// picture that has been seen once comes back without a flash of
    /// placeholder.
    func cached(_ id: String) -> UIImage? {
        cache.object(forKey: id as NSString)
    }

    func image(for id: String) async throws -> UIImage {
        if let hit = cached(id) { return hit }
        guard let client = FeddyCore.shared.client else {
            throw APIError(status: 0, message: "not configured")
        }
        do {
            return try await fetch(id, client: client)
        } catch let error as APIError where error.status == 403 || error.status == 401 {
            // The signature aged out while the thread sat open. Nothing
            // else is retried: a second attempt at anything else fails the
            // same way and costs the user another download.
            client.forgetAttachmentURL(id: id)
            return try await fetch(id, client: client)
        }
    }

    private func fetch(_ id: String, client: APIClient) async throws -> UIImage {
        let signed = try await client.attachmentURL(id: id)
        let data = try await client.download(from: signed.url)
        guard let image = UIImage(data: data) else {
            throw APIError(status: 0, message: "undecodable attachment")
        }
        // Decode here rather than on the first draw: this is off the main
        // thread and a 3000px screenshot is not cheap to unpack.
        let ready = image.preparingForDisplay() ?? image
        cache.setObject(ready, forKey: id as NSString, cost: decodedBytes(ready))
        return ready
    }

    /// What the image actually occupies, not what it weighed on the wire —
    /// a 1 MB JPEG is fifteen times that once unpacked, and the wrong number
    /// here makes the limit meaningless.
    private func decodedBytes(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }
}

enum AttachmentImagePhase {
    case loading
    case loaded(Image)
    case failed
}

/// Draws one attachment through the store, handing the caller the phase so
/// the thumbnail and the full screen can disagree about what a failure looks
/// like.
struct AttachmentImageView<Content: View>: View {
    let id: String
    @ViewBuilder var content: (AttachmentImagePhase) -> Content
    @State private var phase: AttachmentImagePhase

    init(id: String, @ViewBuilder content: @escaping (AttachmentImagePhase) -> Content) {
        self.id = id
        self.content = content
        // Straight to `loaded` when it is already in the cache, so a picture
        // scrolled back into view does not blink.
        if let hit = AttachmentImageStore.shared.cached(id) {
            _phase = State(initialValue: .loaded(Image(uiImage: hit)))
        } else {
            _phase = State(initialValue: .loading)
        }
    }

    var body: some View {
        content(phase)
            .task(id: id) {
                do {
                    let image = try await AttachmentImageStore.shared.image(for: id)
                    phase = .loaded(Image(uiImage: image))
                } catch {
                    // Scrolling away cancels this. That is not a failure —
                    // leave it loading so coming back tries again, rather
                    // than making the picture vanish from the thread.
                    guard !Task.isCancelled else { return }
                    phase = .failed
                }
            }
    }
}
#endif
