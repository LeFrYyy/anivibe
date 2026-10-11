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

    public let id: ProviderID = AnilibriaProvider.providerID
    public let displayName = "Anilibria"
    public let capabilities: ProviderCapabilities = [.search, .episodeList, .availabilityCheck]

    private let baseURL: URL
    private let transport: HTTPTransport
    private let cacheTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let state = AnilibriaState()

    public init(baseURL: URL = AnilibriaProvider.defaultBaseURL, transport: HTTPTransport,
                cacheTTL: TimeInterval = 600, now: @escaping @Sendable () -> Date = { Date() }) {
        self.baseURL = baseURL
        self.transport = transport
        self.cacheTTL = cacheTTL
        self.now = now
    }

    // MARK: - DTO (формат anilibria.top/api/v1)

    struct NameDTO: Decodable {
        let main: String?
        let english: String?
        let alternative: String?
    }

    struct ReleaseSummaryDTO: Decodable {
        let id: Int
        let name: NameDTO?
        let year: Int?
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
        var components = URLComponents(url: baseURL.appendingPathComponent("app/search/releases"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components?.url else { throw VideoSourceError.invalidResponse("не удалось собрать URL поиска") }
        let data = try await get(url)
        let summaries: [ReleaseSummaryDTO]
        do { summaries = try JSONDecoder().decode([ReleaseSummaryDTO].self, from: data) } catch {
            throw VideoSourceError.invalidResponse("Anilibria: неожиданный ответ поиска")
        }
        return summaries.map { dto in
            var titles = [dto.name?.main, dto.name?.english, dto.name?.alternative].compactMap { $0?.nilIfBlank }
            var seen = Set<String>()
            titles = titles.filter { seen.insert($0.lowercased()).inserted }
            return ProviderTitle(id: String(dto.id), providerID: id, titles: titles, year: dto.year)
        }
    }

    /// Сопоставление с тайтлом каталога. Ищем по КАЖДОМУ известному названию
    /// (русское, ромадзи, английское, синонимы) — у Anilibria поиск по полному
    /// английскому названию часто ничего не находит. Порог ниже стандартного,
    /// т.к. у Anilibria свои варианты названий («Code Geass: Hangyaku no Lelouch R1»).
    public func match(anime: Anime) async throws -> ProviderTitle? {
        var candidates: [ProviderTitle] = []
        var seen = Set<String>()
        for title in anime.allTitles where !title.isEmpty {
            for candidate in try await search(title: title) where seen.insert(candidate.id).inserted {
                candidates.append(candidate)
            }
            if let best = TitleMatcher.bestMatch(for: anime.allTitles, among: candidates,
                                                 titlesOf: \.titles, threshold: 0.6) {
                return best
            }
        }
        // Запасной вариант: совпадение года (сезон в названии уже учтён в bestMatch выше,
        // а здесь сознательно берём первого кандидата того же года — лучше так,
        // чем честно признаться, что не нашли).
        if let year = anime.year, let byYear = candidates.first(where: { $0.year == year }) {
            return byYear
        }
        return nil
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
        let url = baseURL.appendingPathComponent("anime/releases/\(releaseID)")
        let data = try await get(url)
        let release: ReleaseDTO
        do { release = try JSONDecoder().decode(ReleaseDTO.self, from: data) } catch {
            throw VideoSourceError.invalidResponse("Anilibria: неожиданный ответ релиза")
        }
        await state.set(release, id: releaseID, until: current.addingTimeInterval(cacheTTL))
        return release
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(request)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) {
            throw VideoSourceError.from(error)
        }
        return data
    }
}

private actor AnilibriaState {
    private var releases: [String: (release: AnilibriaProvider.ReleaseDTO, until: Date)] = [:]

    func release(id: String, validAt date: Date) -> AnilibriaProvider.ReleaseDTO? {
        guard let entry = releases[id], date < entry.until else { return nil }
        return entry.release
    }

    func set(_ release: AnilibriaProvider.ReleaseDTO, id: String, until: Date) {
        releases[id] = (release, until)
    }
}
