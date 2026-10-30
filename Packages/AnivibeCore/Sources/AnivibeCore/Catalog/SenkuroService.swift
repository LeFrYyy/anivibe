import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Senkuro (`api.senkuro.com/graphql`) — открытый GraphQL API с русскими главами.
/// Покрывает тайтлы, которых нет на MangaLib (Берсерк, Ван-Пис, Тетрадь смерти).
/// Страницы — CDN `mirai.senkuro.org` (полный URL в ответе, Referer не нужен).
public actor SenkuroService {
    public static let endpoint = URL(string: "https://api.senkuro.com/graphql")!
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

    struct GQLResponse<T: Decodable>: Decodable { let data: T? }
    struct MangaData: Decodable, Sendable { let manga: MangaDTO? }
    struct MangaDTO: Decodable, Sendable {
        struct Title: Decodable, Sendable { let lang: String?; let content: String? }
        struct Branch: Decodable, Sendable { let id: String? }
        let slug: String?
        let titles: [Title]?
        let branches: [Branch]?
        var titleStrings: [String] { (titles ?? []).compactMap { $0.content?.nilIfBlank } }
        var branchID: String? { branches?.first?.id }
    }
    struct MangasData: Decodable, Sendable {
        struct Edge: Decodable, Sendable { let node: MangaDTO? }
        let edges: [Edge]?
    }
    struct ChaptersData: Decodable, Sendable {
        struct Connection: Decodable, Sendable {
            struct Edge: Decodable, Sendable {
                struct Node: Decodable, Sendable { let slug: String?; let number: String?; let name: String? }
                let node: Node?
            }
            let edges: [Edge]?
            let pageInfo: PageInfo?
            struct PageInfo: Decodable, Sendable { let hasNextPage: Bool?; let endCursor: String? }
        }
        let mangaChapters: Connection?
    }
    struct ChapterData: Decodable, Sendable {
        struct Chapter: Decodable, Sendable {
            struct Page: Decodable, Sendable {
                struct Image: Decodable, Sendable {
                    struct Size: Decodable, Sendable { let url: String? }
                    let original: Size?
                }
                let image: Image?
            }
            let pages: [Page]?
        }
        let mangaChapter: Chapter?
    }

    // MARK: - GraphQL

    private func gql<T: Decodable>(_ query: String, cache cacheable: Bool = true) async throws -> T {
        let key = "sen:" + query
        if cacheable, let data = await cache.data(for: key), let cached = try? JSONDecoder().decode(T.self, from: data) { return cached }
        try await limiter.acquire()
        let body = try JSONSerialization.data(withJSONObject: ["query": query])
        var request = URLRequest(url: baseURL, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Anivibe/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.send(request)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }
        let result = try JSONDecoder().decode(T.self, from: data)
        if cacheable { await cache.store(data, for: key) }
        return result
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Привязка к записи Shikimori

    /// Возвращает `slug|branchId` записи Senkuro для манги Shikimori. Кэшируется.
    /// 1) Проба slug по латинским названиям с верификацией по `titles` записи.
    /// 2) Поиск `mangas(search:)` с тем же скорингом, что и у lib.social.
    public func resolve(forMangaID mangaID: Int, titles: [String]) async -> (slug: String, branchID: String)? {
        let cacheKey = "sen-map:\(mangaID)"
        if let data = await cache.data(for: cacheKey), let cached = String(data: data, encoding: .utf8), !cached.isEmpty {
            if cached == "-" { return nil }
            let parts = cached.split(separator: "|").map(String.init)
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        let foldedWanted = Set(titles.map(RussianTitleDictionary.fold))
        var found: (String, String)?
        // Проба slug — главный путь: «berserk», «toukyou-kushu», «hagane-no-renkinjutsushi».
        var seen = Set<String>()
        for title in titles {
            guard let slug = LibSocialService.slugify(title), seen.insert(slug).inserted, seen.count <= 6 else { continue }
            let q = "{ manga(slug:\"\(slug)\"){ slug titles { lang content } branches { id } } }"
            guard let dto: GQLResponse<MangaData> = try? await gql(q),
                  let manga = dto.data?.manga, let branchID = manga.branchID else { continue }
            let matched = manga.titleStrings.contains { foldedWanted.contains(RussianTitleDictionary.fold($0)) }
            if matched { found = (manga.slug ?? slug, branchID); break }
        }
        // Поисковый фолбэк (латиницей — кириллицу их поиск не индексирует).
        if found == nil {
            for title in titles.filter({ !$0.isEmpty }).prefix(3) {
                guard LibSocialService.slugify(title) != nil else { continue }
                let q = "{ mangas(first:20, search:\"\(Self.esc(title))\"){ edges { node { slug titles { lang content } branches { id } } } } }"
                guard let dto: GQLResponse<MangasData> = try? await gql(q), let edges = dto.data?.edges else { continue }
                var best: (String, String, Double)?
                for edge in edges {
                    guard let node = edge.node, let slug = node.slug, let branchID = node.branchID else { continue }
                    let score = LibSocialService.matchScore(candidateTitles: node.titleStrings, wanted: titles)
                    if score > (best?.2 ?? 0) { best = (slug, branchID, score) }
                }
                if let best, best.2 >= 0.55 { found = (best.0, best.1); break }
            }
        }
        let stored = found.map { "\($0.0)|\($0.1)" } ?? "-"
        await cache.store(Data(stored.utf8), for: cacheKey)
        return found
    }

    // MARK: - Главы

    /// Главы ветки (перевода) в порядке возрастания номера; API отдаёт от новых к старым.
    public func chapters(branchID: String, slug: String) async throws -> [MangaChapter] {
        var result: [MangaChapter] = []
        var cursor: String? = nil
        // Сервер отдаёт максимум 100 глав за запрос независимо от `first` —
        // для больших тайтлов (Ван-Пис, 1204 главы) нужны все страницы.
        for _ in 0..<40 {
            let after = cursor.map { ", after:\"\($0)\"" } ?? ""
            let q = "{ mangaChapters(branchId:\"\(branchID)\", first:100\(after)){ edges { node { slug number name } } pageInfo { hasNextPage endCursor } } }"
            let dto: GQLResponse<ChaptersData> = try await gql(q)
            guard let conn = dto.data?.mangaChapters, let edges = conn.edges else { break }
            for edge in edges {
                guard let node = edge.node, let chapterSlug = node.slug else { continue }
                result.append(MangaChapter(id: "sen|\(chapterSlug)",
                                           number: node.number.flatMap(Double.init),
                                           volume: nil, title: node.name?.nilIfBlank,
                                           group: nil, pageCount: 0))
            }
            guard conn.pageInfo?.hasNextPage == true, let next = conn.pageInfo?.endCursor, !next.isEmpty else { break }
            cursor = next
        }
        return result.sorted { ($0.number ?? .greatestFiniteMagnitude) < ($1.number ?? .greatestFiniteMagnitude) }
    }

    // MARK: - Страницы

    /// Страницы главы по идентификатору `sen|<chapterSlug>`.
    public func pageURLs(chapterID: String) async throws -> [URL] {
        guard chapterID.hasPrefix("sen|") else { return [] }
        let chapterSlug = String(chapterID.dropFirst(4))
        let q = "{ mangaChapter(slug:\"\(chapterSlug)\"){ pages { image { original { url } } } } }"
        let dto: GQLResponse<ChapterData> = try await gql(q, cache: false)
        return (dto.data?.mangaChapter?.pages ?? []).compactMap { $0.image?.original?.url.flatMap(URL.init) }
    }
}
