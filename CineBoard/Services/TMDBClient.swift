import Foundation

protocol MovieCatalog: Sendable {
    var isConfigured: Bool { get }
    func trending(page: Int) async throws -> MoviePage
    func search(query: String, page: Int) async throws -> MoviePage
    func details(id: Int) async throws -> Movie
}

enum TMDBError: LocalizedError, Equatable {
    case missingKey, invalidKey, offline, rateLimited, server(Int), badResponse, decoding

    var errorDescription: String? {
        switch self {
        case .missingKey: String(localized: "TMDB key is not set. Add it to Config/Secrets.xcconfig (see README).")
        case .invalidKey: String(localized: "The TMDB key was rejected. Check the value in Config/Secrets.xcconfig.")
        case .offline: String(localized: "No internet connection. Check your network and try again.")
        case .rateLimited: String(localized: "The catalog has temporarily limited requests. Wait a moment and try again.")
        case .server(let code): String(localized: "The catalog is temporarily unavailable (code \(code)). Please try later.")
        case .badResponse, .decoding: String(localized: "Could not read the catalog response. Please try later.")
        }
    }
}

extension TMDBError {
    /// Временные сбои, при которых можно показать сохранённые данные.
    var allowsCachedFallback: Bool {
        switch self {
        case .offline, .rateLimited, .server: true
        case .missingKey, .invalidKey, .badResponse, .decoding: false
        }
    }
}

enum TMDBImage {
    enum Size: String { case w185, w342, w500, w780 }
    static func url(_ path: String?, _ size: Size) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(path)")
    }
}

struct TMDBClient: MovieCatalog {
    let apiKey: String
    var session: URLSession = .shared

    init(
        apiKey: String = (Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String) ?? "",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    var isConfigured: Bool { !apiKey.isEmpty && !apiKey.hasPrefix("$(") && apiKey != "ВАШ_КЛЮЧ" }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func trending(page: Int) async throws -> MoviePage {
        try await get("/trending/movie/week", [URLQueryItem(name: "page", value: String(page))])
    }

    func search(query: String, page: Int) async throws -> MoviePage {
        try await get(
            "/search/movie",
            [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "include_adult", value: "false"),
            ])
    }

    func details(id: Int) async throws -> Movie { try await get("/movie/\(id)") }

    private func get<T: Decodable>(_ path: String, _ items: [URLQueryItem] = []) async throws -> T {
        guard isConfigured else { throw TMDBError.missingKey }
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3\(path)") else {
            throw TMDBError.badResponse
        }
        var query = items + [URLQueryItem(name: "language", value: "en-US")]
        let useBearer = apiKey.hasPrefix("eyJ")  // v4 Read Access Token — JWT
        if !useBearer { query.append(URLQueryItem(name: "api_key", value: apiKey)) }
        comps.queryItems = query
        guard let url = comps.url else { throw TMDBError.badResponse }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if useBearer { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw TMDBError.badResponse }
            switch http.statusCode {
            case 200..<300: break
            case 401: throw TMDBError.invalidKey
            case 429: throw TMDBError.rateLimited
            default: throw TMDBError.server(http.statusCode)
            }
            do { return try Self.decoder.decode(T.self, from: data) } catch { throw TMDBError.decoding }
        } catch let error as TMDBError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw TMDBError.offline
        }
    }
}
