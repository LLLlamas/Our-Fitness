// Single shared helper for turning a captured/picked UIImage into bounded
// JPEG Data. Used by the Reminders photo step (≤1024px, stored on the
// reminder) and by WatchSyncService (≤120px thumbnail transferred to the
// watch) — one resize implementation instead of two near-duplicates.

import UIKit

public enum ImageDownscale {
    /// Resizes `image` so its longest side is at most `maxDimension` (no
    /// upscaling), then JPEG-encodes it. Returns nil only if JPEG encoding
    /// itself fails.
    public static func jpegData(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat = 0.7) -> Data? {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else {
            return image.jpegData(compressionQuality: quality)
        }
        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Convenience for re-downscaling already-stored JPEG Data (e.g. the
    /// reminder's full ≤1024px photo → a ≤120px watch thumbnail).
    public static func jpegData(from data: Data, maxDimension: CGFloat, quality: CGFloat = 0.6) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpegData(image, maxDimension: maxDimension, quality: quality)
    }
}
