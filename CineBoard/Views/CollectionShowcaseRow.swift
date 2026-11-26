import SwiftUI

/// Подборка «витриной»: цветная карточка с переливающимся градиентом, стопкой обложек слева
/// (до пяти, каждая следующая меньше и выглядывает из-под предыдущей), названием, числом фильмов и лайков
/// и описанием. В зеркальной карточке всё отражено: обложки справа, текст слева.
struct CollectionShowcaseCard: View {
    let collection: MovieCollection
    let likes: Int
    var mirrored = false
    var showsSave = false
    var isSaved = false
    var onToggleSave: () -> Void = {}

    private var theme: CollectionTheme { CollectionTheme.resolve(for: collection) }

    var body: some View {
        ZStack(alignment: mirrored ? .topLeading : .topTrailing) {
            NavigationLink(value: collection) { card }
                .buttonStyle(.plain)
            if showsSave { saveButton }
        }
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 16) {
            if mirrored {
                info
                CoverStack(collection: collection, mirrored: true)
            } else {
                CoverStack(collection: collection, mirrored: false)
                info
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background { AnimatedThemeBackground(theme: theme, seed: collection.id) }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: theme.bottom.opacity(0.35), radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var info: some View {
        VStack(alignment: mirrored ? .trailing : .leading, spacing: 8) {
            Text(collection.title)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(mirrored ? .trailing : .leading)
                // Место под кнопку сохранения в углу.
                .padding(mirrored ? .leading : .trailing, showsSave ? 38 : 0)
            HStack(spacing: 6) {
                if !collection.isPublic { Image(systemName: "lock.fill") }
                Text("\(filmsText(collection.items.count)) · \(likesText(likes))")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.78))
            if !collection.details.isEmpty {
                MoreText(text: collection.details, lines: 4, trailing: mirrored, color: .white.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity, alignment: mirrored ? .topTrailing : .topLeading)
    }

    private var saveButton: some View {
        Button(action: onToggleSave) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.white.opacity(isSaved ? 0.32 : 0.2), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel(isSaved ? "Remove from saved collections" : "Save collection")
    }
}

/// Стопка обложек: главная целиком, остальные (до четырёх) меньше и выглядывают из-под неё.
private struct CoverStack: View {
    let collection: MovieCollection
    let mirrored: Bool
    private let mainWidth: CGFloat = 96
    private let peek: CGFloat = 20
    private let shrink: CGFloat = 0.09
    static let maxCovers = 5

    /// Главная обложка и следующие уникальные постеры фильмов подборки.
    private var paths: [String?] {
        let main = collection.coverPath
        var result: [String?] = [main]
        for item in collection.sortedItems {
            guard result.count < Self.maxCovers, let path = item.posterPath, path != main,
                !result.contains(where: { $0 == path })
            else { continue }
            result.append(path)
        }
        return result
    }

    private var totalWidth: CGFloat { mainWidth + peek * CGFloat(paths.count - 1) }
    private var mainHeight: CGFloat { mainWidth * 1.5 }

    var body: some View {
        let list = paths
        ZStack(alignment: .topLeading) {
            // Сначала самые дальние (маленькие), главная — сверху.
            ForEach(Array(list.enumerated().reversed()), id: \.offset) { index, path in
                let scale = 1 - shrink * CGFloat(index)
                let width = mainWidth * scale
                let height = mainHeight * scale
                PosterImage(path: path, title: collection.title, size: .w185, ratio: 1.5)
                    .frame(width: width, height: height)
                    .shadow(color: .black.opacity(0.35), radius: 6, x: mirrored ? -2 : 2, y: 3)
                    .offset(x: left(index, width: width, count: list.count), y: (mainHeight - height) / 2)
            }
        }
        .frame(width: totalWidth, height: mainHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// Левый край обложки: следующая выглядывает вправо (в зеркальной карточке — влево).
    private func left(_ index: Int, width: CGFloat, count: Int) -> CGFloat {
        let normal = index == 0 ? 0 : mainWidth + peek * CGFloat(index) - width
        return mirrored ? totalWidth - (normal + width) : normal
    }
}

/// Фон карточки: градиент из двух цветов темы и несколько размытых пятен, медленно плывущих — как в Apple Music.
struct AnimatedThemeBackground: View {
    let theme: CollectionTheme
    let seed: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let phase = Double(abs(seed.hashValue % 1000)) / 160
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [theme.top, theme.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse()
                    .fill(theme.top)
                    .frame(width: 260, height: 190)
                    .blur(radius: 46)
                    .opacity(0.85)
                    .offset(x: 90 * sin(t * 0.33 + phase), y: -50 * cos(t * 0.27 + phase))
                Ellipse()
                    .fill(theme.bottom)
                    .frame(width: 280, height: 210)
                    .blur(radius: 52)
                    .opacity(0.9)
                    .offset(x: -80 * cos(t * 0.29 + phase), y: 60 * sin(t * 0.23 + phase * 1.3))
                Circle()
                    .fill(.white)
                    .frame(width: 150, height: 150)
                    .blur(radius: 44)
                    .opacity(0.16)
                    .offset(x: 70 * sin(t * 0.21 + phase * 2), y: 40 * cos(t * 0.31 + phase))
            }
            .drawingGroup()
        }
    }
}

/// Описание в несколько строк: если не помещается, последние слова затухают с многоточием и появляется «more».
struct MoreText: View {
    let text: String
    var lines = 4
    var trailing = false
    var color: Color = .secondary
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(color)
                .multilineTextAlignment(trailing ? .trailing : .leading)
                .lineLimit(lines)
                .background(
                    GeometryReader { Color.clear.preference(key: ShownHeightKey.self, value: $0.size.height) }
                )
                .background(alignment: .top) {
                    // Невидимая копия без ограничения строк — чтобы узнать полную высоту.
                    Text(text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(
                            GeometryReader { Color.clear.preference(key: FullHeightKey.self, value: $0.size.height) }
                        )
                }
                .mask {
                    if isTruncated {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.6),
                                .init(color: .black.opacity(0.1), location: 1),
                            ], startPoint: .top, endPoint: .bottom)
                    } else {
                        Color.black
                    }
                }
            if isTruncated {
                Text("more").font(.caption.weight(.semibold)).foregroundStyle(color)
            }
        }
        .onPreferenceChange(ShownHeightKey.self) { shownHeight = $0 }
        .onPreferenceChange(FullHeightKey.self) { fullHeight = $0 }
    }
}

private struct ShownHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FullHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
