import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Провайдер Anilibria (AniLiberty): публичный API `https://anilibria.top/api/v1`.
///
/// Отдаёт прямые HLS-ссылки, поэтому серии играют в родном AVPlayer-плеере
/// (прогресс, автопереход, PiP — всё работает). Ограничения источника:
/// озвучка одна (студия Anilibria), в поток могут вставляться рекламные метки,
/// каталог меньше AniList. Правовой статус контента студии — на совести
/// пользователя приложения; провайдер можно отключить в настройках.
public final class AnilibriaProvider: VideoSourceProvider, @unchecked Sendable {
    public static let providerID: ProviderID = "anilibria"
    public static let defaultBaseURL = URL(string: "https://anilibria.top/api/v1")!
    /// Зеркала того же API. Основной домен периодически отвечает Cloudflare 520
    /// (проверено 11.10.2026: anilibria.top — 520, api.anilibria.app — 200).
    public static let defaultBaseURLs: [URL] = [
        defaultBaseURL,
        URL(string: "https://api.anilibria.app/api/v1")!,
        URL(string: "https://aniliberty.top/api/v1")!
    ]

    public let id: ProviderID = AnilibriaProvider.providerID
    public let displayName = "Anilibria"
    public let capabilities: ProviderCapabilities = [.search, .episodeList, .availabilityCheck]

    private let baseURLs: [URL]
    private let transport: HTTPTransport
    private let cacheTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let state = AnilibriaState()

    public init(baseURLs: [URL] = AnilibriaProvider.defaultBaseURLs, transport: HTTPTransport,
                cacheTTL: TimeInterval = 600, now: @escaping @Sendable () -> Date = { Date() }) {
        self.baseURLs = baseURLs.isEmpty ? [AnilibriaProvider.defaultBaseURL] : baseURLs
        self.transport = transport
        self.cacheTTL = cacheTTL
        self.now = now
    }

    public convenience init(baseURL: URL, transport: HTTPTransport, cacheTTL: TimeInterval = 600,
                            now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(baseURLs: [baseURL], transport: transport, cacheTTL: cacheTTL, now: now)
    }

    // MARK: - DTO (формат anilibria.top/api/v1)

    struct NameDTO: Decodable {
        let main: String?
        let english: String?
        let alternative: String?
    }

    struct ExternalRefDTO: Decodable {
        let id: Int?
    }

    struct ReleaseSummaryDTO: Decodable {
        let id: Int
        let name: NameDTO?
        let year: Int?
        /// {"id": 1575, "url": "https://myanimelist.net/anime/1575", ...}; id бывает null.
        let mal: ExternalRefDTO?
        let shikimori: ExternalRefDTO?
    }

    struct ReleaseDTO: Decodable {
        let id: Int
        let name: NameDTO?
        let isBlockedByGeo: Bool?
        let isBlockedByCopyrights: Bool?
        let episodes: [EpisodeDTO]?

        enum CodingKeys: String, CodingKey {
            case id, name, episodes
            case isBlockedByGeo = "is_blocked_by_geo"
            case isBlockedByCopyrights = "is_blocked_by_copyrights"
        }
    }

    struct EpisodeDTO: Decodable {
        let ordinal: Double?
        let name: String?
        let hls480: String?
        let hls720: String?
        let hls1080: String?

        enum CodingKeys: String, CodingKey {
            case ordinal, name
            case hls480 = "hls_480"
            case hls720 = "hls_720"
            case hls1080 = "hls_1080"
        }
    }

    // MARK: - VideoSourceProvider

    public func search(title: String) async throws -> [ProviderTitle] {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let data = try await get(path: "app/search/releases", query: [URLQueryItem(name: "query", value: query)])
        let summaries: [ReleaseSummaryDTO]
        do { summaries = try JSONDecoder().decode([ReleaseSummaryDTO].self, from: data) } catch {
            throw VideoSourceError.invalidResponse("Anilibria: неожиданный ответ поиска")
        }
        return summaries.map { dto in
            var titles = [dto.name?.main, dto.name?.english, dto.name?.alternative].compactMap { $0?.nilIfBlank }
            var seen = Set<String>()
            titles = titles.filter { seen.insert($0.lowercased()).inserted }
            return ProviderTitle(id: String(dto.id), providerID: id, titles: titles, year: dto.year,
                                 malID: dto.mal?.id ?? dto.shikimori?.id)
        }
    }

    /// Сопоставление с тайтлом каталога.
    ///
    /// 1. Точное совпадение по ID MyAnimeList (AniList отдаёт `idMal`, Anilibria — `mal.id`).
    /// 2. Если ID нет — нечёткое сравнение названий (русское, ромадзи, английское,
    ///    синонимы) с учётом номера сезона. Кандидаты с ДРУГИМ MAL ID отбрасываются.
    /// 3. Иначе — `nil`. Никаких «первый тайтл того же года»: раньше так «Black Clover
    ///    2nd Season» (2026) превращался в «Чёрный факел» (тоже 2026).
    public func match(anime: Anime) async throws -> ProviderTitle? {
        var candidates: [ProviderTitle] = []
        var seen = Set<String>()
        for title in anime.allTitles where !title.isEmpty {
            for candidate in try await search(title: title) where seen.insert(candidate.id).inserted {
                candidates.append(candidate)
            }
            if let exact = Self.exactMatch(for: anime, among: candidates) { return exact }
        }
        return Self.fuzzyMatch(for: anime, among: candidates)
    }

    static func exactMatch(for anime: Anime, among candidates: [ProviderTitle]) -> ProviderTitle? {
        guard let mal = anime.malID else { return nil }
        return candidates.first { $0.malID == mal }
    }

    static func fuzzyMatch(for anime: Anime, among candidates: [ProviderTitle]) -> ProviderTitle? {
        let compatible = candidates.filter { !TitleMatcher.idsConflict(anime.malID, $0.malID) }
        return TitleMatcher.bestMatch(for: anime.allTitles, among: compatible, titlesOf: \.titles, threshold: 0.6)
    }

    public func episodes(for title: ProviderTitle) async throws -> [ProviderEpisode] {
        let release = try await loadRelease(id: title.id)
        if release.isBlockedByGeo == true { throw VideoSourceError.unavailable("тайтл заблокирован по региону") }
        if release.isBlockedByCopyrights == true { throw VideoSourceError.unavailable("тайтл изъят по требованию правообладателя") }
        let episodes = (release.episodes ?? []).compactMap { ep -> ProviderEpisode? in
            // Пропускаем спецвыпуски с дробными номерами (PV, превью и т.п.).
            guard let ordinal = ep.ordinal, ordinal > 0, ordinal.rounded() == ordinal else { return nil }
            guard let url = Self.bestHLS(ep) else { return nil }
            return ProviderEpisode(providerID: id, titleID: title.id, season: nil,
                                   number: Int(ordinal), title: ep.name?.nilIfBlank, payload: url)
        }
        if episodes.isEmpty { throw VideoSourceError.unavailable("у Anilibria нет серий этого тайтла") }
        return episodes.sorted { $0.number < $1.number }
    }

    public func resolve(_ episode: ProviderEpisode) async throws -> PlaybackSource {
        guard let url = URL(string: episode.payload), let scheme = url.scheme,
              ["https", "http"].contains(scheme) else {
            throw VideoSourceError.invalidResponse("битая ссылка на поток")
        }
        // Проверяем, что плейлист живой и это действительно HLS.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw VideoSourceError.unavailable("HTTP \(response.statusCode)")
        }
        let info = HLSManifestInspector.inspect(String(decoding: data.prefix(256 * 1024), as: UTF8.self))
        guard info.isValid else { throw VideoSourceError.unavailable("ответ не является плейлистом HLS") }
        let audio = info.audio.isEmpty
            ? [MediaTrackInfo(name: "Озвучка Anilibria", language: "ru", isDefault: true)]
            : info.audio
        return PlaybackSource(providerID: id, providerName: displayName, url: url, kind: .hls,
                              audioTracks: audio, subtitleTracks: info.subtitles,
                              attribution: "Видео и озвучка: Anilibria (anilibria.top)")
    }

    // MARK: - Внутреннее

    static func bestHLS(_ ep: EpisodeDTO) -> String? {
        ep.hls1080?.nilIfBlank ?? ep.hls720?.nilIfBlank ?? ep.hls480?.nilIfBlank
    }

    private func loadRelease(id releaseID: String) async throws -> ReleaseDTO {
        let current = now()
        if let cached = await state.release(id: releaseID, validAt: current) { return cached }
        let data = try await get(path: "anime/releases/\(releaseID)")
        let release: ReleaseDTO
        do { release = try JSONDecoder().decode(ReleaseDTO.self, from: data) } catch {
            throw VideoSourceError.invalidResponse("Anilibria: неожиданный ответ релиза")
        }
        await state.set(release, id: releaseID, until: current.addingTimeInterval(cacheTTL))
        return release
    }

    /// GET с перебором зеркал: при сетевой ошибке или 5xx (в т.ч. Cloudflare 520)
    /// пробуем следующий домен и запоминаем рабочий. 4xx — ответ по существу, не перебираем.
    private func get(path: String, query: [URLQueryItem] = []) async throws -> Data {
        let preferred = await state.preferredMirror
        let order = ([preferred] + Array(baseURLs.indices).filter { $0 != preferred }).filter { baseURLs.indices.contains($0) }
        var lastError: Error = VideoSourceError.network("Anilibria недоступна")
        for index in order {
            var components = URLComponents(url: baseURLs[index].appendingPathComponent(path), resolvingAgainstBaseURL: false)
            if !query.isEmpty { components?.queryItems = query }
            guard let url = components?.url else { throw VideoSourceError.invalidResponse("не удалось собрать URL запроса") }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if case APIError.cancelled? = error as? APIError { throw error }
                lastError = error
                continue
            }
            if let error = APIError.from(status: response.statusCode, data: data, headers: response) {
                if case .server = error { lastError = VideoSourceError.from(error); continue }
                throw VideoSourceError.from(error)
            }
            await state.setPreferredMirror(index)
            return data
        }
        if lastError is APIError || lastError is VideoSourceError { throw VideoSourceError.from(lastError) }
        throw lastError
    }
}

private actor AnilibriaState {
    private(set) var preferredMirror = 0

    func setPreferredMirror(_ index: Int) { preferredMirror = index }

    private var releases: [String: (release: AnilibriaProvider.ReleaseDTO, until: Date)] = [:]

    func release(id: String, validAt date: Date) -> AnilibriaProvider.ReleaseDTO? {
        guard let entry = releases[id], date < entry.until else { return nil }
        return entry.release
    }

    func set(_ release: AnilibriaProvider.ReleaseDTO, id: String, until: Date) {
        releases[id] = (release, until)
    }
}
