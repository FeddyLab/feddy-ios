import Foundation

#if canImport(UIKit)
import UIKit

/// Compresses a `UIImage` to JPEG bytes under `maxBytes`. Strategy:
///
/// 1. Downscale to `maxLongSide = 2048px` first — most attachments
///    come straight from the camera at 4032×3024 / 4MB+ which we
///    don't need to ship over a mobile network.
/// 2. Encode at quality 0.8 (sweet spot — visually lossless on
///    photos, ~70% smaller than 1.0).
/// 3. If still over budget, drop quality in 0.1 steps down to 0.3.
/// 4. Anything still failing returns `nil` — caller treats as
///    "this image cannot be uploaded" and skips it.
///
/// Returns `nil` when no encoding under `maxBytes` succeeded; this
/// is rare (a 100MP heavily-detailed image at very low quality is
/// the failure mode).
enum ImageCompression {
    static let maxLongSide: CGFloat = 2048
    static let qualitySteps: [CGFloat] = [0.8, 0.7, 0.6, 0.5, 0.4, 0.3]

    static func compressJPEG(_ image: UIImage, maxBytes: Int = 800_000) -> Data? {
        let resized = downscale(image, maxLongSide: maxLongSide)
        for quality in qualitySteps {
            guard let data = resized.jpegData(compressionQuality: quality) else {
                continue
            }
            if data.count <= maxBytes {
                return data
            }
        }
        return nil
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
