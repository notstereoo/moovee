import UIKit

/// Приведение выбранных фото к компактным JPEG для аватара и баннера.
enum ImageProcessing {
    static let avatarSide: CGFloat = 512
    static let bannerSize = CGSize(width: 1500, height: 500)

    /// Квадрат по центру, `avatarSide` × `avatarSide`.
    static func avatarJPEG(from data: Data) -> Data? {
        render(data, to: CGSize(width: avatarSide, height: avatarSide))
    }

    /// Баннер 3:1, обрезка по центру.
    static func bannerJPEG(from data: Data) -> Data? {
        render(data, to: bannerSize)
    }

    private static func render(_ data: Data, to size: CGSize) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
        return UIGraphicsImageRenderer(size: size, format: format)
            .jpegData(withCompressionQuality: 0.82) { _ in
                image.draw(in: CGRect(origin: origin, size: drawSize))
            }
    }
}
