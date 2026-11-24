import SwiftUI

func userMessage(for error: Error) -> String {
    if let e = error as? LocalizedError, let d = e.errorDescription { return d }
    return error.localizedDescription
}

func filmsText(_ n: Int) -> String {
    let m10 = n % 10, m100 = n % 100
    let word: String
    if (11...14).contains(m100) {
        word = "фильмов"
    } else if m10 == 1 {
        word = "фильм"
    } else if (2...4).contains(m10) {
        word = "фильма"
    } else {
        word = "фильмов"
    }
    return "\(n) \(word)"
}

// MARK: - Каталог в Environment

private struct CatalogKey: EnvironmentKey {
    static let defaultValue: any MovieCatalog = TMDBClient(apiKey: "")
}
extension EnvironmentValues {
    var catalog: any MovieCatalog {
        get { self[CatalogKey.self] }
        set { self[CatalogKey.self] = newValue }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Ошибка",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// Навигация к фильму, подборке и профилю — подключается один раз на NavigationStack.
    func appDestinations() -> some View {
        navigationDestination(for: Movie.self) { MovieDetailView(movie: $0) }
            .navigationDestination(for: MovieCollection.self) { CollectionDetailView(collection: $0) }
            .navigationDestination(for: UserAccount.self) { ProfileView(user: $0) }
    }
}

// MARK: - Изображения

struct PosterImage: View {
    let path: String?
    let title: String
    var size: TMDBImage.Size = .w342
    var ratio: CGFloat = 1.5  // высота / ширина

    var body: some View {
        Color(.secondarySystemBackground)
            .aspectRatio(1 / ratio, contentMode: .fit)
            .overlay {
                if let url = TMDBImage.url(path, size) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure: placeholder
                        default: ProgressView()
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Постер: \(title)")
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "film").font(.title2)
            Text(title).font(.caption).multilineTextAlignment(.center).padding(.horizontal, 6)
        }
        .foregroundStyle(.secondary)
    }
}

struct AvatarView: View {
    let name: String
    var size: CGFloat = 44

    private var hue: Double {
        Double(name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 }) / 360
    }

    var body: some View {
        Circle()
            .fill(Color(hue: hue, saturation: 0.45, brightness: 0.75))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

struct SkeletonGrid: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    private let ratios: [CGFloat] = [1.5, 1.65, 1.35]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<2, id: \.self) { col in
                VStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { row in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                            .aspectRatio(1 / ratios[(col + row * 2) % 3], contentMode: .fit)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .opacity(dim ? 0.5 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Загрузка")
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Не удалось загрузить", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Повторить", action: retry).buttonStyle(.borderedProminent)
        }
    }
}

struct TMDBAttribution: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(
                "Данные о фильмах предоставлены TMDB. Приложение использует API TMDB, но не одобрено и не сертифицировано TMDB."
            )
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            Link("themoviedb.org", destination: URL(string: "https://www.themoviedb.org")!)
                .font(.caption2)
        }
        .padding()
    }
}
