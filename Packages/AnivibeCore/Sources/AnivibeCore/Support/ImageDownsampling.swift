import Foundation

/// Bucketed *display* pixels, not the dimensions of the original download.
/// Buckets keep minor layout changes from creating a separate image/cache task.
public struct ImageDecodeSize: Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = min(1600, max(1, width))
        self.height = min(1600, max(1, height))
    }

    public static let full = ImageDecodeSize(width: 1600, height: 1600)
}

public enum ImageDownsampling {
    public static let maximumPixelSize = 1600
    private static let buckets = [64, 128, 192, 256, 384, 512, 768, 1024, 1600]

    public static func targetSize(width: Double, height: Double, scale: Double) -> ImageDecodeSize {
        let safeScale = scale.isFinite && scale > 0 ? min(scale, 4) : 1
        return ImageDecodeSize(width: bucket(width * safeScale), height: bucket(height * safeScale))
    }

    /// Aspect-fill math preserves enough pixels for crops, especially wide banners.
    /// Never upscale a small original, and retain the existing 1600 px safety cap.
    public static func thumbnailPixelSize(sourceWidth: Double, sourceHeight: Double,
                                          target: ImageDecodeSize) -> Int {
        guard sourceWidth.isFinite, sourceHeight.isFinite, sourceWidth > 0, sourceHeight > 0 else {
            return maximumPixelSize
        }
        let longestSide = max(sourceWidth, sourceHeight)
        let ratio = max(Double(target.width) / sourceWidth, Double(target.height) / sourceHeight)
        let requested = min(Double(maximumPixelSize), longestSide, ceil(longestSide * ratio))
        guard requested.isFinite else { return maximumPixelSize }
        return max(1, Int(requested))
    }

    private static func bucket(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else { return 64 }
        return buckets.first(where: { Double($0) >= value }) ?? maximumPixelSize
    }
}
