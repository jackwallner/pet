import ImageIO
import UIKit

/// A pet photo travels inside one synced record, so it stays small enough that CloudKit
/// carries it inline in the existing `payload` field and needs no schema change.
enum PetPhotoEncoder {
    static let maxBytes = 180_000
    private static let attempts: [(side: Int, quality: CGFloat)] = [(1000, 0.75), (800, 0.7), (600, 0.65), (400, 0.6)]

    /// Reads at thumbnail size so a 48 MP original is never decoded in full, and applies its orientation.
    static func jpeg(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        for attempt in attempts {
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                           kCGImageSourceCreateThumbnailWithTransform: true,
                           kCGImageSourceThumbnailMaxPixelSize: attempt.side] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
            if let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: attempt.quality), jpeg.count <= maxBytes { return jpeg }
        }
        return nil
    }

    #if DEBUG
    /// `-DemoPhoto`: a drawn stand-in, so screenshots and tests don't depend on the photo library.
    static func demo() -> Data? {
        let rect = CGRect(x: 0, y: 0, width: 600, height: 600)
        let image = UIGraphicsImageRenderer(bounds: rect).image { context in
            UIColor(red: 0.78, green: 0.62, blue: 0.44, alpha: 1).setFill()
            context.fill(rect)
            let symbol = UIImage(systemName: "dog.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 300))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            if let symbol { symbol.draw(at: CGPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2)) }
        }
        return image.jpegData(compressionQuality: 0.7)
    }
    #endif
}
