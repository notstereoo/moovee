import SwiftUI

/// Запрос на кадрирование выбранного фото.
struct CropRequest: Identifiable {
    enum Kind { case avatar, banner }
    let id = UUID()
    let kind: Kind
    /// Уже с нормальной ориентацией (см. `ImageProcessing.normalized`).
    let image: UIImage
}

/// Выбор области фото: двигайте и масштабируйте фото под рамкой. Вне рамки затемнено — видно, что останется в профиле.
struct ImageCropView: View {
    let request: CropRequest
    let onCancel: () -> Void
    let onDone: (Data) -> Void

    @State private var cropSize: CGSize = .zero
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var isCircle: Bool { request.kind == .avatar }
    private var aspect: CGFloat { isCircle ? 1 : ImageProcessing.bannerAspect }
    private var outputSize: CGSize {
        isCircle ? CGSize(width: ImageProcessing.avatarSide, height: ImageProcessing.avatarSide) : ImageProcessing.bannerSize
    }
    private var geometry: CropGeometry { CropGeometry(imageSize: request.image.size, cropSize: cropSize) }

    var body: some View {
        GeometryReader { geo in
            cropArea(in: geo.size)
        }
        .background(Color.black)
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { controls }
        .preferredColorScheme(.dark)
    }

    // MARK: Область кадрирования

    private func cropArea(in area: CGSize) -> some View {
        let size = frameSize(in: area)
        let g = CropGeometry(imageSize: request.image.size, cropSize: size)
        let scale = g.baseScale * g.clampedZoom(zoom)
        let shown = g.clampedOffset(offset, zoom: zoom)
        let center = CGPoint(x: area.width / 2, y: area.height / 2)
        let frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)

        return ZStack {
            Image(uiImage: request.image)
                .resizable()
                .frame(width: request.image.size.width * scale, height: request.image.size.height * scale)
                .position(x: center.x + shown.width, y: center.y + shown.height)
                .frame(width: area.width, height: area.height)
                .clipped()
            overlay(frame: frame, in: area)
        }
        .frame(width: area.width, height: area.height)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .simultaneousGesture(zoomGesture)
        .onAppear { cropSize = size }
        .onChange(of: size) { _, new in
            cropSize = new
            offset = CropGeometry(imageSize: request.image.size, cropSize: new).clampedOffset(offset, zoom: zoom)
            lastOffset = offset
        }
        .accessibilityLabel(isCircle ? "Profile photo crop area" : "Banner crop area")
        .accessibilityHint("Drag to reposition. Use the slider to zoom.")
    }

    private func frameSize(in area: CGSize) -> CGSize {
        if isCircle {
            let side = max(120, min(area.width - 48, area.height - 32))
            return CGSize(width: side, height: side)
        }
        let width = area.width - 32
        let height = min(width / aspect, area.height - 32)
        return CGSize(width: height * aspect, height: height)
    }

    /// Затемнение вокруг рамки, контур и сетка третей.
    private func overlay(frame: CGRect, in area: CGSize) -> some View {
        let outline = isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        return ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: area))
                path.addPath(outline.path(in: frame))
            }
            .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))

            outline.path(in: frame).stroke(Color.white.opacity(0.9), lineWidth: 2)

            Path { path in
                for i in 1...2 {
                    let x = frame.minX + frame.width * CGFloat(i) / 3
                    let y = frame.minY + frame.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: frame.minY))
                    path.addLine(to: CGPoint(x: x, y: frame.maxY))
                    path.move(to: CGPoint(x: frame.minX, y: y))
                    path.addLine(to: CGPoint(x: frame.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.28), lineWidth: 0.5)
            .clipShape(outline.path(in: frame))
        }
        .allowsHitTesting(false)
    }

    // MARK: Жесты

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height)
                offset = geometry.clampedOffset(proposed, zoom: zoom)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = geometry.clampedZoom(lastZoom * value.magnification)
                offset = geometry.clampedOffset(offset, zoom: zoom)
            }
            .onEnded { _ in
                lastZoom = zoom
                lastOffset = offset
            }
    }

    // MARK: Панели

    private var topBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
            Spacer()
            Text(isCircle ? "Profile photo" : "Banner").font(.headline)
            Spacer()
            Button("Choose") { finish() }.fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Text(
                isCircle
                    ? "Move and zoom — the circle is what will be visible."
                    : "Move and zoom — the frame is what will be visible on your profile."
            )
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.white.opacity(0.7))
                Slider(
                    value: Binding(
                        get: { zoom },
                        set: { newValue in
                            zoom = geometry.clampedZoom(newValue)
                            lastZoom = zoom
                            offset = geometry.clampedOffset(offset, zoom: zoom)
                            lastOffset = offset
                        }), in: 1...CropGeometry.maxZoom
                )
                .accessibilityLabel("Zoom")
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black)
    }

    private func finish() {
        let rect = geometry.cropRect(zoom: zoom, offset: offset)
        guard let data = ImageProcessing.crop(request.image, rect: rect, outputSize: outputSize) else {
            onCancel()
            return
        }
        onDone(data)
    }
}
