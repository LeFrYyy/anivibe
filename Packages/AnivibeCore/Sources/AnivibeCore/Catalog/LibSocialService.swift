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

    /// Маркеры спешлов/артбуков в названиях — такие записи не должны побеждать основную мангу.
    private static let spinOffMarkers = ["спец", "special", "артбук", "artbook", "пилот", "pilot",
        "prototype", "colored", "цветн", "oneshot", "спецвыпуск", "memorial", "doujinshi",
        "додзинси", "кроссовер", "crossover", "веб", "web", "издание", "альтернативн"]

    /// slug записи lib.social, соответствующей манге Shikimori. Кэшируется.
    /// 1) Угадывание slug по латинским названиям: основные записи часто скрыты из поиска
    ///    (лицензия), но главы отдаются по slug напрямую — «death-note», «vinland-saga».
    /// 2) Поиск `q=` со скорингом совпадения и штрафом спешлам.
    public func slug(forMangaID mangaID: Int, titles: [String]) async -> String? {
        let cacheKey = "lib-map:\(mangaID)"
        if let data = await cache.data(for: cacheKey), let cached = String(data: data, encoding: .utf8), !cached.isEmpty {
            return cached == "-" ? nil : cached
        }
        var found = await slugByGuess(titles)
        if found == nil { found = await slugBySearch(titles) }
        await cache.store(Data((found ?? "-").utf8), for: cacheKey)
        return found
    }

    /// slug-формат MangaLib: латиница в нижнем регистре через дефисы («Shingeki no Kyojin» → «shingeki-no-kyojin»).
    static func slugify(_ title: String) -> String? {
        var folded = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        folded = folded.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return folded.count >= 2 ? folded : nil
    }

    /// Проба slug напрямую: `manga/<slug>/chapters` 200 с непустым data → запись существует.
    private func slugByGuess(_ titles: [String]) async -> String? {
        var seen = Set<String>()
        for title in titles {
            guard let slug = Self.slugify(title), seen.insert(slug).inserted else { continue }
            if seen.count > 6 { break }
            let query = [URLQueryItem(name: "per_page", value: "1")]
            guard let page: Response<[ChapterDTO]> = try? await load(path: "manga/\(slug)/chapters", query: query) else { continue }
            if !(page.data ?? []).isEmpty { return slug }
        }
        return nil
    }

    /// Скоринг кандидата поиска: точное fold-равенство — 1.0; покрытие токенов — доля
    /// совпавших слов; спешл-маркеры, которых нет в искомом названии, сильно штрафуют.
    static func matchScore(candidateTitles: [String], wanted: [String]) -> Double {
        var best = 0.0
        for want in wanted {
            let w = RussianTitleDictionary.fold(want)
            let wTokens = Set(w.split(separator: " ").map(String.init))
            guard !wTokens.isEmpty else { continue }
            for candTitle in candidateTitles {
                let c = RussianTitleDictionary.fold(candTitle)
                let cTokens = Set(c.split(separator: " ").map(String.init))
                guard !cTokens.isEmpty else { continue }
                var score: Double
                if c == w {
                    score = 1.0
                } else {
                    let shared = wTokens.intersection(cTokens).count
                    guard shared > 0 else { continue }
                    // требуем покрытия всех слов меньшего названия («ван пис» ⊂ «ван пис эпизод а»)
                    let small = min(wTokens.count, cTokens.count)
                    let big = max(wTokens.count, cTokens.count)
                    guard shared >= small, Double(shared) / Double(big) >= 0.5 else { continue }
                    score = Double(shared) / Double(big) * 0.8
                }
                let extras = cTokens.subtracting(wTokens)
                let hasSpinOff = extras.contains { tok in
                    Self.spinOffMarkers.contains { tok.hasPrefix($0) }
                }
                if hasSpinOff { score *= 0.2 }
                best = max(best, score)
            }
        }
        return best
    }

    private func slugBySearch(_ titles: [String]) async -> String? {
        var best: (slug: String, score: Double)?
        for title in titles.filter({ !$0.isEmpty }).prefix(4) {
            let query = [URLQueryItem(name: "q", value: String(title.prefix(100))),
                         URLQueryItem(name: "site_id[]", value: "1"),
                         URLQueryItem(name: "limit", value: "20")]
            guard let page: Response<[MangaDTO]> = try? await load(path: "manga", query: query),
                  let data = page.data, !data.isEmpty else { continue }
            for dto in data {
                guard let slug = dto.slug else { continue }
                let score = Self.matchScore(candidateTitles: dto.titles, wanted: titles)
                if score > (best?.score ?? 0) { best = (slug, score) }
            }
            if (best?.score ?? 0) >= 1.0 { break }
        }
        guard let best, best.score >= 0.55 else { return nil }
        return best.slug
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
