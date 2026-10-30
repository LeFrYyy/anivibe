import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Каталог манги по публичному API Shikimori (`/api/mangas`): русские названия,
/// обложки, жанры, статус, тома/главы и связи с аниме (`/related` → Adaptation).
/// Только публичные данные; профиль/авторизация не используются.
public actor ShikimoriMangaService {
    public static let endpoint = URL(string: "https://shikimori.io/api")!
    private let transport: HTTPTransport
    private let cache: MetadataCache
    private let baseURL: URL
    private let limiter = RateLimiter(limit: 4, per: 1)

    public init(transport: HTTPTransport, cache: MetadataCache, baseURL: URL = endpoint) {
        self.transport = transport
        self.cache = cache
        self.baseURL = baseURL
    }

    struct ListItem: Decodable, Sendable {
        struct Image: Decodable, Sendable { let original: String?; let preview: String? }
        struct Genre: Decodable, Sendable { let name: String?; let russian: String?; let kind: String? }
        let id: Int
        let name: String?
        let russian: String?
        let image: Image?
        let kind: String?
        let status: String?
        let volumes: Int?
        let chapters: Int?
        let score: String?
        let aired_on: String?
        struct RateStat: Decodable, Sendable { let value: Int? }
        let genres: [Genre]?
        /// Детальный ответ `/mangas/{id}`: распределение оценок (сумма value = число голосов).
        let rates_scores_stats: [RateStat]?
        let synonyms: [String]?
        let english: [String]?
        let japanese: [String]?
        let description: String?

        var model: Manga {
            Manga(
                id: id,
                title: AnimeTitle(romaji: name?.nilIfBlank, english: english?.first?.nilIfBlank,
                                  native: japanese?.first?.nilIfBlank, russian: russian?.nilIfBlank,
                                  russianSource: russian?.nilIfBlank != nil ? .shikimori : nil),
                synonyms: (synonyms ?? []).compactMap { $0.nilIfBlank },
                synopsis: description.map { HTMLText.plainText($0).nilIfBlank } ?? nil,
                coverURL: image.flatMap { $0.original ?? $0.preview }.flatMap { URL(string: "https://shikimori.io" + $0) },
                year: aired_on.flatMap { Int($0.prefix(4)) },
                genres: (genres ?? []).compactMap { g in g.kind == "genre" ? (g.russian ?? g.name) : nil },
                status: status.map { MangaStatus(apiValue: $0) },
                format: kind.map { MangaFormat(apiValue: $0) },
                volumes: volumes,
                chapters: chapters,
                score: score.flatMap(Double.init),
                scoreVotes: rates_scores_stats?.compactMap(\.value).reduce(0, +)
            )
        }
    }

    /// Запись из `/api/mangas/{id}/related`: `anime` или `manga` + `relation` (англ.).
    struct RelationDTO: Decodable, Sendable {
        struct Ref: Decodable, Sendable { let id: Int }
        let relation: String
        let anime: Ref?
        let manga: Ref?
    }

    public func list(page: Int, limit: Int, query: String? = nil) async throws -> MangaPage {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(min(50, limit))),
            URLQueryItem(name: "censored", value: "true")
        ]
        if let text = query?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            items.append(URLQueryItem(name: "search", value: String(text.prefix(100))))
        } else {
            items.append(URLQueryItem(name: "order", value: "popularity"))
        }
        let list: [ListItem] = try await load(path: "mangas", query: items)
        return MangaPage(items: list.map(localize).filter { $0.id > 0 }, page: page, hasNextPage: list.count >= min(50, limit))
    }

    /// ID аниме-адаптаций манги (relation «Adaptation» = аниме снято по этой манге).
    public func adaptations(of malID: Int) async throws -> [Int] {
        let related: [RelationDTO] = try await load(path: "mangas/\(malID)/related", query: [])
        var seen = Set<Int>()
        return related.compactMap { entry in
            guard entry.relation.lowercased().contains("adaptation"), let anime = entry.anime else { return nil }
            return seen.insert(anime.id).inserted ? anime.id : nil
        }
    }

    public func details(id: Int) async throws -> Manga {
        var manga = localize(try await load(path: "mangas/\(id)", query: []) as ListItem)
        manga.animeMALIDs = (try? await adaptations(of: id)) ?? []
        return manga
    }

    /// Русское название из Shikimori → автоперевод/транскрипция, если его нет.
    private func localize(_ item: ListItem) -> Manga {
        var manga = item.model
        if manga.title.russian?.nilIfBlank == nil, let translated = RussianTitleTranslator.translate(manga.title) {
            manga.title.russian = translated
            manga.title.russianSource = .automatic
        }
        return manga
    }

    private func load<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        let url = components.url!
        let key = "shikimori-manga:" + url.absoluteString
        if let data = await cache.data(for: key), let cached = try? JSONDecoder().decode(T.self, from: data) { return cached }
        try await limiter.acquire()
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Anivibe/1.0 (iOS; public manga metadata)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(request)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }
        let result = try JSONDecoder().decode(T.self, from: data)
        await cache.store(data, for: key)
        return result
    }
}
