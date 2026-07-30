import UIKit

/// Doc 08 « Avatars » — recadrage carré, 512 px, JPEG qualité 0,8.
enum AvatarPhotoProcessor {
    static func process(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let side = min(image.size.width, image.size.height)
        let cropRectInPoints = CGRect(
            x: (image.size.width - side) / 2,
            y: (image.size.height - side) / 2,
            width: side,
            height: side
        )
        let cropRectInPixels = cropRectInPoints.applying(CGAffineTransform(scaleX: image.scale, y: image.scale))
        guard let cgImage = image.cgImage?.cropping(to: cropRectInPixels) else { return nil }
        let cropped = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)

        let targetSize = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
