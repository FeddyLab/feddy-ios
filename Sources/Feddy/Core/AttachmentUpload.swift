import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The limits the API enforces, mirrored here so a file is refused without a
/// round trip that was never going to accept it.
enum AttachmentLimits {
    static let maxBytes = 10 * 1024 * 1024
    static let maxPerMessage = 5
}

/// Why a picked image cannot be sent. The UI turns these into sentences.
enum AttachmentRejection {
    case tooLarge
    case tooMany
    case unreadable
}

/// Turns a picked image into something worth uploading, then puts it in the
/// bucket.
///
/// Downscaling happens on the device rather than on the server: a modern
/// phone screenshot is several megabytes, almost all of it detail nobody
/// reads at the size a support thread shows it. What leaves the device is a
/// JPEG whose long edge is capped — a screenshot is sent so that someone can
/// read the label on a button, so the ceiling is far above the 256px an
/// avatar gets.
enum AttachmentUpload {
    /// Long edge in pixels. Sized so a phone screenshot arrives at the size
    /// it was taken: the tallest of them is 2868 (16 Pro Max), and 2556 to
    /// 2752 covers everything else down to an iPad Pro. Capping at 2000, as
    /// this once did, shrank every single modern screenshot by a quarter and
    /// then re-encoded the result — and a screenshot is sent so someone can
    /// read a line of text in it.
    static let maxEdge = 3000
    /// Higher than a photo would need. JPEG spends its error budget on hard
    /// edges, which in a screenshot is all of the text.
    static let quality = 0.9

    /// Downscales and re-encodes as JPEG. Returns nil when the data is not a
    /// readable image, which is the only case worth refusing outright.
    ///
    /// ImageIO rather than UIKit: it decodes at the size asked for instead of
    /// building a full-resolution bitmap first, which on a large screenshot
    /// is the difference between a few megabytes of peak memory and tens.
    static func prepare(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                out, UTType.jpeg.identifier as CFString, 1, nil
            )
        else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }

    /// Compress, ask for a slot, PUT the bytes. Returns the descriptor the
    /// message write needs.
    static func send(
        _ data: Data,
        filename: String,
        api: APIClient
    ) async throws -> UploadedAttachment {
        guard let prepared = prepare(data) else {
            throw APIError(status: 0, message: "unreadable image")
        }
        guard prepared.count <= AttachmentLimits.maxBytes else {
            throw APIError(status: 0, message: "image too large")
        }
        let name = jpegName(for: filename)
        let slot = try await api.createUpload(
            filename: name, mimeType: "image/jpeg", sizeBytes: prepared.count
        )
        try await api.upload(data: prepared, to: slot.uploadUrl, mimeType: "image/jpeg")
        return UploadedAttachment(
            key: slot.key, filename: name, mimeType: "image/jpeg", sizeBytes: prepared.count
        )
    }

    /// Everything leaves as JPEG, so the name says so — otherwise a file
    /// downloaded later claims to be a PNG and is not one.
    static func jpegName(for filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        return (stem.isEmpty ? "image" : stem) + ".jpg"
    }
}
