import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// MangaDex (api.mangadex.org) — бесплатный открытый API: главы с русским переводом,
/// страницы для чтения (`at-home`), обложки и привязка к MAL/AniList через `links`.
/// Лимит ~5 запросов/с; страницы CDN живут ~15 минут, поэтому их запрашиваем при чтении.
public actor MangaDexService {
    public static let endpoint = URL(string: "https://api.mangadex.org")!
    private let transport: HTTPTransport
    private let cache: MetadataCache
    private let baseURL: URL
    private let limiter = RateLimiter(limit: 4, per: 1)

    public init(transport: HTTPTransport, cache: MetadataCache, baseURL: URL = endpoint) {
        self.transport = transport
        self.cache = cache
        self.baseURL = baseURL
    }

    // MARK: - DTO

    struct Response<T: Decodable>: Decodable { let data: [T]?; let total: Int? }
    struct Single<T: Decodable>: Decodable { let data: T? }

    struct MangaDTO: Decodable, Sendable {
        struct Attributes: Decodable, Sendable {
            let title: [String: String]?
            let altTitles: [[String: String]]?
            let description: [String: String]?
            let year: Int?
            let status: String?
            let links: [String: String]?
        }
        struct Relationship: Decodable, Sendable {
            struct CoverAttributes: Decodable, Sendable { let fileName: String? }
            let type: String
            let attributes: CoverAttributes?
        }
        let id: String
        let attributes: Attributes
        let relationships: [Relationship]?

        var malID: Int? { attributes.links?["mal"].flatMap { Int($0) } }
        var coverFileName: String? { relationships?.first { $0.type == "cover_art" }?.attributes?.fileName }

        var coverURL: URL? {
            coverFileName.flatMap { URL(string: "https://uploads.mangadex.org/covers/\(id)/\($0).512.jpg") }
        }

        /// Названия для проверки совпадения с записью Shikimori.
        var allTitles: [String] {
            var names = Array((attributes.title ?? [:]).values)
            for alt in attributes.altTitles ?? [] { names += alt.values }
            return names
        }
    }

    struct ChapterDTO: Decodable, Sendable {
        struct Attributes: Decodable, Sendable {
            let chapter: String?
            let volume: String?
            let title: String?
            let translatedLanguage: String?
            let pages: Int?
            let externalUrl: String?
            let publishAt: String?
        }
        struct Relationship: Decodable, Sendable {
            struct GroupAttributes: Decodable, Sendable { let name: String? }
            let type: String
            let attributes: GroupAttributes?
        }
        let id: String
        let attributes: Attributes
        let relationships: [Relationship]?

        var model: MangaChapter {
            MangaChapter(id: id, number: attributes.chapter.flatMap(Double.init),
                         volume: attributes.volume.flatMap(Double.init),
                         title: attributes.title?.nilIfBlank,
                         group: relationships?.first { $0.type == "scanlation_group" }?.attributes?.name,
                         pageCount: attributes.pages ?? 0,
                         externalURL: attributes.externalUrl.flatMap(URL.init))
        }
    }

    struct AtHomeDTO: Decodable, Sendable {
        struct ChapterData: Decodable, Sendable { let hash: String; let data: [String]?; let dataSaver: [String]? }
        let baseUrl: String
        let chapter: ChapterData
    }

    // MARK: - Привязка к MAL/Shikimori ID

    /// MangaDex ID манги по её MAL ID: поиск по названию с проверкой `links.mal`.
    /// Результат кэшируется («mal:23390» → UUID).
    public func mangadexID(forMALID malID: Int, titles: [String]) async -> String? {
        let cacheKey = "mangadex-map:\(malID)"
        if let data = await cache.data(for: cacheKey), let cached = String(data: data, encoding: .utf8), !cached.isEmpty {
            return cached == "-" ? nil : cached
        }
        var found: String?
        for title in titles.filter({ !$0.isEmpty }).prefix(4) {
            var query = [URLQueryItem(name: "title", value: title),
                         URLQueryItem(name: "limit", value: "10"),
                         URLQueryItem(name: "contentRating[]", value: "safe"),
                         // Только записи, где есть перевод на русский.
                         URLQueryItem(name: "availableTranslatedLanguage[]", value: "ru"),
                         // Самая популярная запись обычно и есть основная манга (додзинси ниже).
                         URLQueryItem(name: "order[followedCount]", value: "desc"),
                         URLQueryItem(name: "includes[]", value: "cover_art")]
            query.append(contentsOf: ["suggestive", "erotica"].map { URLQueryItem(name: "contentRating[]", value: $0) })
            guard let page: Response<MangaDTO> = try? await load(path: "manga", query: query),
                  let data = page.data, !data.isEmpty else { continue }
            if let exact = data.first(where: { $0.malID == malID }) { found = exact.id; break }
            let folded = Set(titles.map(RussianTitleDictionary.fold))
            if let named = data.first(where: { dto in dto.allTitles.contains { folded.contains(RussianTitleDictionary.fold($0)) } }) {
                found = named.id
                break
            }
            if found == nil, let first = data.first, folded.contains(RussianTitleDictionary.fold(title)) { found = first.id }
        }
        await cache.store(Data((found ?? "-").utf8), for: cacheKey)
        return found
    }

    // MARK: - Главы на русском

    public func chapters(mangadexID: String, language: String = "ru") async throws -> [MangaChapter] {
        var chapters: [MangaChapter] = []
        var offset = 0
        while offset < 1000 {
            let query = [
                URLQueryItem(name: "translatedLanguage[]", value: language),
                URLQueryItem(name: "order[chapter]", value: "asc"),
                URLQueryItem(name: "order[volume]", value: "asc"),
                URLQueryItem(name: "limit", value: "200"),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "includes[]", value: "scanlation_group"),
                URLQueryItem(name: "includeExternalUrl", value: "0"),
                URLQueryItem(name: "includeEmptyPages", value: "0"),
                URLQueryItem(name: "includeFutureUpdates", value: "0"),
                URLQueryItem(name: "contentRating[]", value: "safe"),
                URLQueryItem(name: "contentRating[]", value: "suggestive"),
                URLQueryItem(name: "contentRating[]", value: "erotica")
            ]
            let page: Response<ChapterDTO> = try await load(path: "manga/\(mangadexID)/feed", query: query)
            guard let data = page.data, !data.isEmpty else { break }
            chapters += data.map(\.model)
            offset += data.count
            if data.count < 200 || offset >= (page.total ?? 0) { break }
        }
        return Self.dedupe(chapters)
    }

    /// По одному переводу на главу: самый свежий релиз на номер главы (остальные — дубли групп).
    static func dedupe(_ chapters: [MangaChapter]) -> [MangaChapter] {
        var byNumber: [String: MangaChapter] = [:]
        var order: [String] = []
        for chapter in chapters {
            let key = chapter.number.map { String($0) } ?? ("external:" + chapter.id)
            if byNumber[key] == nil { order.append(key); byNumber[key] = chapter }
            else if let current = byNumber[key], chapter.pageCount > current.pageCount { byNumber[key] = chapter }
        }
        return order.compactMap { byNumber[$0] }.sorted {
            switch ($0.number, $1.number) {
            case let (a?, b?): return a != b ? a < b : ($0.volume ?? 0) < ($1.volume ?? 0)
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.id < $1.id
            }
        }
    }

    // MARK: - Страницы главы

    /// URL страниц полной читалки. `dataSaver` — ужатые jpeg (экономия трафика).
    public func pageURLs(chapterID: String, dataSaver: Bool = false) async throws -> [URL] {
        let dto: AtHomeDTO = try await load(path: "at-home/server/\(chapterID)", query: [], cache: false)
        let files = dataSaver ? (dto.chapter.dataSaver ?? dto.chapter.data ?? []) : (dto.chapter.data ?? [])
        let kind = dataSaver ? "data-saver" : "data"
        return files.compactMap { URL(string: "\(dto.baseUrl)/\(kind)/\(dto.chapter.hash)/\($0)") }
    }

    /// Обложка записи MangaDex по её ID (запасной источник постеров).
    public func coverURL(mangadexID: String) async -> URL? {
        let key = "mangadex-cover:\(mangadexID)"
        if let data = await cache.data(for: key), let url = URL(string: String(data: data, encoding: .utf8) ?? "") { return url }
        guard let dto: Single<MangaDTO> = try? await load(path: "manga/\(mangadexID)", query: [URLQueryItem(name: "includes[]", value: "cover_art")]),
              let url = dto.data?.coverURL else { return nil }
        await cache.store(Data(url.absoluteString.utf8), for: key)
        return url
    }

    private func load<T: Decodable>(path: String, query: [URLQueryItem], cache storeCache: Bool = true) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        let url = components.url!
        let key = "mangadex:" + url.absoluteString
        if storeCache, let data = await cache.data(for: key), let cached = try? JSONDecoder().decode(T.self, from: data) { return cached }
        try await limiter.acquire()
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Anivibe/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(request)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }
        let result = try JSONDecoder().decode(T.self, from: data)
        if storeCache { await cache.store(data, for: key) }
        return result
    }
}
