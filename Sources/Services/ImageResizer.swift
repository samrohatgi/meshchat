import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Downscales a picked photo into a small JPEG thumbnail before it's stored
/// or sent over the mesh - profile pictures ride inside ordinary JSON
/// packets, so keeping them tiny (a few KB) matters a lot more here than it
/// would for a normal image picker.
enum ImageResizer {
    static func thumbnail(from data: Data, maxDimension: CGFloat = 160, quality: CGFloat = 0.5) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
        #else
        return data
        #endif
    }
}
