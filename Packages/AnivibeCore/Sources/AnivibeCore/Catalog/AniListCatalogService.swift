import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Каталог на основе публичного AniList GraphQL API.
/// Документация: https://docs.anilist.co — ключ не нужен для чтения публичных данных.
/// Ограничения: 90 запросов/мин (сейчас временно 30/мин), см. README.
public final class AniListCatalogService: CatalogService, @unchecked Sendable {
    public static let endpoint = URL(string: "https://graphql.anilist.co")!

    public let name = "AniList"
    public let isDemo = false
    private let transport: HTTPTransport
    private let limiter: RateLimiter
    private let cache: MetadataCache
    private let endpoint: URL
    private let now: @Sendable () -> Date

    public init(transport: HTTPTransport, cache: MetadataCache,
                limiter: RateLimiter = RateLimiter(limit: 25, per: 60),
                endpoint: URL = AniListCatalogService.endpoint,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.cache = cache
        self.limiter = limiter
        self.endpoint = endpoint
        self.now = now
    }

    public func search(_ query: CatalogQuery) async throws -> CatalogPage {
        let q = query.validated()
        var vars: [String: JSONValue] = [
            "page": .int(q.page),
            "perPage": .int(q.perPage),
            "sort": .array([.string(q.effectiveSort.rawValue)])
        ]
        if !q.trimmedSearch.isEmpty { vars["search"] = .string(q.trimmedSearch) }
        if !q.genres.isEmpty { vars["genres"] = .array(q.genres.sorted().map { .string($0) }) }
        if let y = q.year { vars["year"] = .int(y) }
        if let s = q.season { vars["season"] = .string(s.rawValue) }
        if let st = q.status { vars["status"] = .string(st.rawValue) }
        if !q.formats.isEmpty { vars["formats"] = .array(q.formats.map(\.rawValue).sorted().map { .string($0) }) }

        let dto: SearchResponseDTO = try await perform(query: AniListQueries.search, variables: vars, cacheTTLKey: "search")
        let page = dto.Page
        let items = (page?.media ?? []).compactMap { $0 }.filter { $0.isAdult != true }.map(\.model)
        return CatalogPage(items: items, page: page?.pageInfo?.currentPage ?? q.page, hasNextPage: page?.pageInfo?.hasNextPage ?? false)
    }

    public func details(id: Int) async throws -> AnimeDetails {
        guard id > 0 else { throw APIError.badRequest("Некорректный идентификатор") }
        let dto: DetailsResponseDTO = try await perform(query: AniListQueries.details, variables: ["id": .int(id)], cacheTTLKey: "details")
        guard let media = dto.Media else { throw APIError.notFound }
        return media.detailsModel
    }

    public func homeFeed() async throws -> HomeFeed {
        let current = AnimeSeason.current(for: now())
        let vars: [String: JSONValue] = ["season": .string(current.season.rawValue), "seasonYear": .int(current.year), "perPage": .int(20)]
        let dto: HomeResponseDTO = try await perform(query: AniListQueries.home, variables: vars, cacheTTLKey: "home")
        func list(_ p: MediaPageDTO?) -> [Anime] { (p?.media ?? []).compactMap { $0 }.filter { $0.isAdult != true }.map(\.model) }
        return HomeFeed(popular: list(dto.popular), seasonal: list(dto.seasonal), trending: list(dto.trending),
                        recentlyAdded: list(dto.recent), seasonLabel: "\(current.season.localizedName) \(current.year)")
    }

    public func genres() async throws -> [String] {
        let dto: GenresResponseDTO = try await perform(query: AniListQueries.genres, variables: [:], cacheTTLKey: "genres")
        // «Hentai» исключаем: каталог работает с isAdult: false.
        return (dto.GenreCollection ?? []).filter { $0 != "Hentai" }
    }

    // MARK: - Transport

    private func perform<T: Decodable>(query: String, variables: [String: JSONValue], cacheTTLKey: String) async throws -> T {
        let body = try JSONEncoder.sorted.encode(GraphQLRequestBody(query: query, variables: variables))
        let cacheKey = "anilist:\(cacheTTLKey):" + (String(data: body, encoding: .utf8) ?? "")
        if let cached = await cache.data(for: cacheKey), let decoded = try? decode(T.self, from: cached) {
            return decoded
        }
        try await limiter.acquire()
        let request = URLRequest.json(url: endpoint, body: body)
        let (data, response) = try await transport.send(request)
        if response.statusCode == 429 {
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 60
            await limiter.block(for: retry)
            throw APIError.rateLimited(retryAfter: retry)
        }
        // AniList на 400/404 возвращает JSON с массивом errors — достаём понятное сообщение.
        if !(200..<300).contains(response.statusCode) {
            if response.statusCode == 404, (try? JSONDecoder().decode(GraphQLResponse<T>.self, from: data))?.errors != nil {
                throw APIError.notFound
            }
            if let gql = try? JSONDecoder().decode(GraphQLResponse<T>.self, from: data), let errs = gql.errors, !errs.isEmpty,
               response.statusCode == 400 {
                throw APIError.graphQL(errs.map(\.message))
            }
            throw APIError.from(status: response.statusCode, data: data, headers: response) ?? .invalidResponse("HTTP \(response.statusCode)")
        }
        let decoded = try decode(T.self, from: data)
        await cache.store(data, for: cacheKey)
        return decoded
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope: GraphQLResponse<T>
        do { envelope = try JSONDecoder().decode(GraphQLResponse<T>.self, from: data) } catch {
            throw APIError.decoding(String(describing: error))
        }
        if let payload = envelope.data { return payload }
        if let errs = envelope.errors, !errs.isEmpty {
            if errs.contains(where: { $0.status == 429 }) { throw APIError.rateLimited(retryAfter: 60) }
            if errs.contains(where: { $0.status == 404 }) { throw APIError.notFound }
            throw APIError.graphQL(errs.map(\.message))
        }
        throw APIError.invalidResponse("Пустой ответ")
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
