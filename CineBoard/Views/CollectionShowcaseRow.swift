import SwiftUI

/// Подборка «витриной»: цветная карточка с переливающимся градиентом, стопкой обложек слева
/// (до пяти, каждая следующая меньше и выглядывает из-под предыдущей), названием, числом фильмов, лайков
/// и сохранений и описанием. Цвета подстраиваются под светлую и тёмную тему устройства.
struct CollectionShowcaseCard: View {
    let collection: MovieCollection
    let likes: Int
    var saves = 0
    var showsSave = false
    var isSaved = false
    var onToggleSave: () -> Void = {}

    private var theme: CollectionTheme { CollectionTheme.resolve(for: collection) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: collection) { card }
                .buttonStyle(.plain)
            if showsSave { saveButton }
        }
    }

    private var card: some View {
        // Обложки по центру карточки по вертикали, текст прижат к верху.
        HStack(alignment: .center, spacing: 16) {
            CoverStack(collection: collection)
            info
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background { AnimatedThemeBackground(theme: theme, seed: collection.id) }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: theme.bottom.opacity(0.3), radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(collection.title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                // Место под кнопку сохранения в углу.
                .padding(.trailing, showsSave ? 38 : 0)
            HStack(spacing: 6) {
                if !collection.isPublic { Image(systemName: "lock.fill") }
                Text("\(filmsText(collection.items.count)) · \(likesText(likes)) · \(savesText(saves))")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary.opacity(0.7))
            if !collection.details.isEmpty {
                MoreText(text: collection.details, lines: 4, color: .primary.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var saveButton: some View {
        Button(action: onToggleSave) {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(isSaved ? 0.2 : 0.1), in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .padding(12)
        .accessibilityLabel(isSaved ? "Remove from saved collections" : "Save collection")
    }
}

func savesText(_ n: Int) -> String { n == 1 ? "1 save" : "\(n) saves" }

/// Стопка обложек: главная целиком, остальные (до четырёх) меньше и выглядывают из-под неё вправо.
private struct CoverStack: View {
    let collection: MovieCollection
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
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 2, y: 3)
                    .offset(x: left(index, width: width), y: (mainHeight - height) / 2)
            }
        }
        // Фиксированный размер: стопка не «плывёт» вверх, даже если рядом много текста.
        .frame(width: totalWidth, height: mainHeight, alignment: .topLeading)
        .fixedSize()
        .accessibilityHidden(true)
    }

    /// Левый край обложки: следующая выглядывает вправо.
    private func left(_ index: Int, width: CGFloat) -> CGFloat {
        index == 0 ? 0 : mainWidth + peek * CGFloat(index) - width
    }
}

/// Фон карточки: градиент из двух цветов темы и несколько размытых пятен, плывущих — как в Apple Music.
struct AnimatedThemeBackground: View {
    let theme: CollectionTheme
    let seed: UUID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Скорость переливания (1 — исходная; 1.3 — на 30% быстрее).
    static let speed = 1.3

    var body: some View {
        let phase = Double(abs(seed.hashValue % 1000)) / 160
        let isDark = colorScheme == .dark
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate * Self.speed
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
                    .opacity(isDark ? 0.12 : 0.32)
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
