import SwiftUI

/// Подборка «витриной»: обложка с мягким свечением и рядом название, число фильмов и лайков, описание.
/// В зеркальной строке обложка справа, а текст слева и прижат к обложке.
struct CollectionShowcaseRow: View {
    let collection: MovieCollection
    let likes: Int
    var mirrored = false
    private let coverWidth: CGFloat = 132

    var body: some View {
        NavigationLink(value: collection) {
            HStack(alignment: .center, spacing: 18) {
                if mirrored {
                    info
                    cover
                } else {
                    cover
                    info
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var cover: some View {
        ZStack {
            // Свечение: размытая копия обложки того же цвета.
            PosterImage(path: collection.coverPath, title: collection.title, size: .w185, ratio: 1.4)
                .blur(radius: 26)
                .opacity(0.42)
                .scaleEffect(1.12)
                .accessibilityHidden(true)
            PosterImage(path: collection.coverPath, title: collection.title, size: .w342, ratio: 1.4)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .frame(width: coverWidth)
    }

    private var info: some View {
        VStack(alignment: mirrored ? .trailing : .leading, spacing: 6) {
            Text(collection.title)
                .font(.title3.bold())
                .lineLimit(2)
                .multilineTextAlignment(mirrored ? .trailing : .leading)
            HStack(spacing: 6) {
                if !collection.isPublic { Image(systemName: "lock.fill") }
                Text("\(filmsText(collection.items.count)) · \(likesText(likes))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !collection.details.isEmpty {
                MoreText(text: collection.details, lines: 4, trailing: mirrored)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: mirrored ? .trailing : .leading)
    }
}

/// Описание в несколько строк: если не помещается, последние слова затухают с многоточием и появляется «more».
struct MoreText: View {
    let text: String
    var lines = 4
    var trailing = false
    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    private var isTruncated: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                Text("more").font(.caption.weight(.semibold)).foregroundStyle(.primary.opacity(0.7))
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
