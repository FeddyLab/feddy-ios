import Foundation

#if canImport(UIKit)
import UIKit

/// Compresses a `UIImage` to JPEG bytes under `maxBytes`. Strategy:
///
/// 1. Downscale to `maxLongSide = 1600px` first — most attachments
///    come straight from the camera at 4032×3024 / 4MB+ which we
///    don't need to ship over a mobile network. 1600px on the long
///    edge is enough detail for screenshots and feedback photos.
/// 2. Encode at quality 0.8 (sweet spot — visually lossless on
///    photos, ~70% smaller than 1.0).
/// 3. If still over budget, drop quality in 0.1 steps down to 0.2.
/// 4. If even quality 0.2 stays over budget (very rare — a complex
///    16MP screenshot full of high-frequency UI), still return that
///    lowest-quality encoding rather than dropping the attachment.
///    The server cap is 2MB, well above our 1.2MB target, so the
///    upload still succeeds.
enum ImageCompression {
    static let maxLongSide: CGFloat = 1600
    static let qualitySteps: [CGFloat] = [0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2]

    static func compressJPEG(_ image: UIImage, maxBytes: Int = 1_200_000) -> Data? {
        let resized = downscale(image, maxLongSide: maxLongSide)
        var lastEncoded: Data?
        for quality in qualitySteps {
            guard let data = resized.jpegData(compressionQuality: quality) else {
                continue
            }
            lastEncoded = data
            if data.count <= maxBytes {
                return data
            }
        }
        // Fallback: return the smallest encoding we managed even if
        // it's slightly over `maxBytes`. The server's hard cap is
        // 2MB, so this still uploads cleanly.
        return lastEncoded
    }

    private static func downscale(_ image: UIImage, maxLongSide: CGFloat) -> UIImage {
        let size = image.size
        let longSide = max(size.width, size.height)
        guard longSide > maxLongSide else { return image }
        let scale = maxLongSide / longSide
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
#endif
