import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// lib.social (бывшая MangaLib) — открытый API `api.lib.social/api` без ключа:
/// русский каталог, главы с ветками переводов и страницы на CDN `imglib`.
/// Сайт mangalib.me геоблокируется, но API-эндпоинт доступен напрямую.
public actor LibSocialService {
    public static let endpoint = URL(string: "https://api.lib.social/api")!
    /// Запасные хосты страниц, если `/api/constants` недоступен (проверено: отдают jpeg без Referer).
    private static let fallbackImageServers = ["https://img3.cdnrulib.link", "https://img3.cdnlibs.org"]
    private let transport: HTTPTransport
    private let cache: MetadataCache
    private let baseURL: URL
    private let limiter = RateLimiter(limit: 4, per: 1)
    private var imageServers: [String]?

    public init(transport: HTTPTransport, cache: MetadataCache, baseURL: URL = endpoint) {
        self.transport = transport
        self.cache = cache
        self.baseURL = baseURL
    }

    // MARK: - DTO

    struct Response<T: Decodable>: Decodable { let data: T? }

    struct MangaDTO: Decodable, Sendable {
        struct Cover: Decodable, Sendable { let `default`: String? }
        struct Kind: Decodable, Sendable { let label: String? }
        struct Rating: Decodable, Sendable { let average: String? }
        let id: Int
        let slug: String?
        let slug_url: String?
        let name: String?
        let rus_name: String?
        let eng_name: String?
        let cover: Cover?
        let type: Kind?
        let rating: Rating?

        var titles: [String] { [rus_name, eng_name, name].compactMap { $0?.nilIfBlank } }
        var coverURL: URL? { cover?.default.flatMap(URL.init) }
    }

    struct ChapterDTO: Decodable, Sendable {
        struct Branch: Decodable, Sendable {
            struct Team: Decodable, Sendable { let name: String? }
            let id: Int
            let branch_id: Int
            let teams: [Team]?
        }
        let id: Int
        let volume: String?
        let number: String?
        let name: String?
        let branches: [Branch]?
    }

    struct ChapterDetailDTO: Decodable, Sendable {
        struct Page: Decodable, Sendable { let url: String?; let slug: Int? }
        let pages: [Page]?
    }

    struct ConstantsDTO: Decodable, Sendable {
        struct Server: Decodable, Sendable { let id: String?; let url: String? }
        let imageServers: [Server]?
    }

    // MARK: - Привязка к записи Shikimori

    /// slug записи lib.social, соответствующей манге Shikimori: поиск по названиям
    /// (русское, английское, ромадзи, синонимы) с точным fold-совпадением. Кэшируется.
    public func slug(forMangaID mangaID: Int, titles: [String]) async -> String? {
        let cacheKey = "lib-map:\(mangaID)"
        if let data = await cache.data(for: cacheKey), let cached = String(data: data, encoding: .utf8), !cached.isEmpty {
            return cached == "-" ? nil : cached
        }
        let wanted = Set(titles.map(RussianTitleDictionary.fold))
        var found: String?
        for title in titles.filter({ !$0.isEmpty }).prefix(4) {
            let query = [URLQueryItem(name: "q", value: String(title.prefix(100))),
                         URLQueryItem(name: "site_id[]", value: "1")]
            guard let page: Response<[MangaDTO]> = try? await load(path: "manga", query: query),
                  let data = page.data, !data.isEmpty else { continue }
            if let match = data.first(where: { dto in dto.titles.contains { wanted.contains(RussianTitleDictionary.fold($0)) } }) {
                found = match.slug
                break
            }
        }
        await cache.store(Data((found ?? "-").utf8), for: cacheKey)
        return found
    }

    // MARK: - Главы

    /// Главы с русским переводом. У главы бывает несколько веток (команд перевода) —
    /// берём первую ветку; её id кодируется в id главы как `lib|<slug>|<volume>|<number>|<branch>`.
    public func chapters(slug: String) async throws -> [MangaChapter] {
        let page: Response<[ChapterDTO]> = try await load(path: "manga/\(slug)/chapters", query: [])
        let rows = (page.data ?? []).sorted { ($0.indexOrder) < ($1.indexOrder) }
        return rows.map { dto in
            let branch = dto.branches?.first
            let id = "lib|\(slug)|\(dto.volume ?? "")|\(dto.number ?? "")|\(branch?.branch_id ?? 0)"
            return MangaChapter(id: id,
                                number: dto.number.flatMap(Double.init),
                                volume: dto.volume.flatMap(Double.init),
                                title: dto.name?.nilIfBlank,
                                group: branch?.teams?.first?.name,
                                pageCount: 0)
        }
    }

    // MARK: - Страницы

    /// Страницы главы по закодированному в `chapters(slug:)` идентификатору `lib|...`.
    public func pageURLs(chapterID: String) async throws -> [URL] {
        let parts = chapterID.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5, parts[0] == "lib" else { return [] }
        let (slug, volume, number, branch) = (parts[1], parts[2], parts[3], parts[4])
        var query = [URLQueryItem(name: "number", value: number), URLQueryItem(name: "volume", value: volume)]
        if branch != "0" { query.append(URLQueryItem(name: "branch_id", value: branch)) }
        let dto: Response<ChapterDetailDTO> = try await load(path: "manga/\(slug)/chapter", query: query, cache: false)
        guard let pages = dto.data?.pages, !pages.isEmpty else { return [] }
        let hosts = await imageServerHosts()
        let host = hosts.first ?? Self.fallbackImageServers[0]
        return pages.sorted { ($0.slug ?? 0) < ($1.slug ?? 0) }.compactMap { page in
            guard let raw = page.url?.nilIfBlank else { return nil }
            // API отдаёт пути с ведущими «//manga/…» — нормализуем до одного слэша.
            let path = "/" + raw.drop(while: { $0 == "/" })
            return URL(string: host + path)
        }
    }

    /// Хосты страниц из `/api/constants` (кэш), фолбэк — проверенные CDN.
    private func imageServerHosts() async -> [String] {
        if let imageServers, !imageServers.isEmpty { return imageServers }
        var hosts = Self.fallbackImageServers
        if let dto: Response<ConstantsDTO> = try? await load(path: "constants", query: [URLQueryItem(name: "fields[]", value: "imageServers")]),
           let servers = dto.data?.imageServers {
            // «main» сейчас отдаёт 403 — берём остальные, затем запасные.
            let usable = servers.compactMap(\.url).filter { $0.contains("imglib") || $0.contains("cdn") }
            if !usable.isEmpty { hosts = usable + Self.fallbackImageServers }
        }
        imageServers = hosts
        return hosts
    }

    private func load<T: Decodable>(path: String, query: [URLQueryItem], cache storeCache: Bool = true) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        let url = components.url!
        let key = "lib:" + url.absoluteString
        if storeCache, let data = await cache.data(for: key), let cached = try? JSONDecoder().decode(T.self, from: data) { return cached }
        try await limiter.acquire()
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Anivibe/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Site-Id")
        let (data, response) = try await transport.send(request)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }
        let result = try JSONDecoder().decode(T.self, from: data)
        if storeCache { await cache.store(data, for: key) }
        return result
    }
}

private extension LibSocialService.ChapterDTO {
    /// Порядок в списке глав: по номеру, спешлы в конец.
    var indexOrder: Double { Double(number ?? "") ?? Double.greatestFiniteMagnitude }
}
