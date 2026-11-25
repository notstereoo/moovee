import UIKit

/// Приведение выбранных фото к компактным JPEG для аватара и баннера.
enum ImageProcessing {
    static let avatarSide: CGFloat = 512
    /// Баннер 2:1 — примерно такую область видно в профиле на телефоне.
    static let bannerAspect: CGFloat = 2
    static let bannerSize = CGSize(width: 1500, height: 750)

    /// Квадрат по центру, `avatarSide` × `avatarSide` (если пользователь не выбирал область вручную).
    static func avatarJPEG(from data: Data) -> Data? {
        render(data, to: CGSize(width: avatarSide, height: avatarSide))
    }

    /// Баннер 2:1, обрезка по центру.
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

    // MARK: Ручное кадрирование

    /// Копия изображения в пикселях с нормальной ориентацией (без EXIF-поворота), чтобы считать область точно.
    static func normalized(_ image: UIImage, maxSide: CGFloat = 3000) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let k = min(1, maxSide / max(pixels.width, pixels.height))
        let target = CGSize(width: (pixels.width * k).rounded(), height: (pixels.height * k).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Вырезает `rect` (в координатах изображения) и масштабирует до `outputSize`.
    static func crop(_ image: UIImage, rect: CGRect, outputSize: CGSize) -> Data? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let k = outputSize.width / rect.width
        let drawRect = CGRect(
            x: -rect.minX * k, y: -rect.minY * k, width: image.size.width * k, height: image.size.height * k)
        return UIGraphicsImageRenderer(size: outputSize, format: format)
            .jpegData(withCompressionQuality: 0.82) { _ in
                image.draw(in: drawRect)
            }
    }
}

/// Математика окна кадрирования: изображение всегда полностью закрывает рамку.
struct CropGeometry: Equatable {
    var imageSize: CGSize
    var cropSize: CGSize

    static let maxZoom: CGFloat = 5

    /// Масштаб, при котором изображение ровно закрывает рамку (zoom = 1).
    var baseScale: CGFloat { max(cropSize.width / imageSize.width, cropSize.height / imageSize.height) }

    func clampedZoom(_ zoom: CGFloat) -> CGFloat { min(max(zoom, 1), Self.maxZoom) }

    /// Ограничивает сдвиг так, чтобы рамка не выходила за края изображения.
    func clampedOffset(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let s = baseScale * clampedZoom(zoom)
        let maxX = max(0, (imageSize.width * s - cropSize.width) / 2)
        let maxY = max(0, (imageSize.height * s - cropSize.height) / 2)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    /// Область изображения (в его координатах), попавшая в рамку.
    func cropRect(zoom: CGFloat, offset: CGSize) -> CGRect {
        let s = baseScale * clampedZoom(zoom)
        let o = clampedOffset(offset, zoom: zoom)
        let width = cropSize.width / s
        let height = cropSize.height / s
        return CGRect(
            x: imageSize.width / 2 - o.width / s - width / 2,
            y: imageSize.height / 2 - o.height / s - height / 2,
            width: width, height: height)
    }
}
