import SwiftUI

func userMessage(for error: Error) -> String {
    if let e = error as? LocalizedError, let d = e.errorDescription { return d }
    return error.localizedDescription
}

func filmsText(_ n: Int) -> String { n == 1 ? "1 film" : "\(n) films" }

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
            "Error",
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
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .favorites(let user): FavoritesView(user: user)
                case .followList(let user, let kind): FollowListView(user: user, kind: kind)
                }
            }
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
            .accessibilityLabel("Poster: \(title)")
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
    var imageData: Data?
    var size: CGFloat = 44

    init(name: String, imageData: Data? = nil, size: CGFloat = 44) {
        self.name = name
        self.imageData = imageData
        self.size = size
    }

    init(user: UserAccount, size: CGFloat = 44) {
        self.init(name: user.shownName, imageData: user.avatarData, size: size)
    }

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle()
                    .fill(ProfileColors.color(for: name))
                    .overlay(
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.45, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Цвета-заглушки для профиля без фото: стабильно зависят от имени.
enum ProfileColors {
    static func hue(for name: String) -> Double {
        Double(name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 360 }) / 360
    }

    static func color(for name: String, brightness: Double = 0.75, shift: Double = 0) -> Color {
        Color(hue: (hue(for: name) + shift).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: brightness)
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
        .accessibilityLabel("Loading")
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Could not load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry).buttonStyle(.borderedProminent)
        }
    }
}

struct TMDBAttribution: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(
                "Movie data provided by TMDB. This app uses the TMDB API but is not endorsed or certified by TMDB."
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

/// Экраны, открываемые из профиля.
enum ProfileRoute: Hashable {
    case favorites(UserAccount)
    case followList(UserAccount, FollowListViewModel.Kind)
}

/// Баннер профиля. Картинка лежит поверх прозрачной подложки, поэтому не раздувает раскладку.
/// С `stretches` при оттягивании списка вниз баннер приближается (как в X), а не уезжает вниз.
struct ProfileBanner: View {
    let imageData: Data?
    let seed: String
    var height: CGFloat = 200
    var stretches = false
    static let scrollSpace = "profileScroll"

    var body: some View {
        if stretches {
            GeometryReader { geo in
                let pulled = max(0, geo.frame(in: .named(Self.scrollSpace)).minY)
                artwork
                    .frame(width: geo.size.width, height: height + pulled)
                    .clipped()
                    .offset(y: -pulled)
            }
            .frame(height: height)
            .accessibilityHidden(true)
        } else {
            artwork
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .accessibilityHidden(true)
        }
    }

    private var artwork: some View {
        Color.clear
            .overlay {
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(
                        colors: [
                            ProfileColors.color(for: seed, brightness: 0.55),
                            ProfileColors.color(for: seed, brightness: 0.35, shift: 0.08),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipped()
    }
}

func likesText(_ n: Int) -> String { n == 1 ? "1 like" : "\(n) likes" }

/// Мягкий верх экрана: вместо резкой границы под заголовком контент плавно уходит в размытие.
struct SoftTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.7), location: 0.35),
                                .init(color: .black.opacity(0.25), location: 0.7),
                                .init(color: .clear, location: 1),
                            ], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 150)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
            .modifier(NativeSoftScrollEdge())
    }
}

/// На iOS 26+ системный край прокрутки тоже делаем мягким.
private struct NativeSoftScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

extension View {
    func softTopEdge() -> some View { modifier(SoftTopEdge()) }
}
