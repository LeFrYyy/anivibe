import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Провайдер «собственного манифеста»: JSON-файл со ссылками на видео,
/// права на распространение которых есть у ВАС (свой сервер, лицензированный CDN и т.п.).
///
/// Формат описан в `docs/stream-manifest.md`, пример — `docs/stream-manifest.example.json`.
/// URL манифеста задаётся в `Config/Secrets.xcconfig` (ANIVIBE_MANIFEST_URL).
public final class ManifestProvider: VideoSourceProvider, @unchecked Sendable {
    public struct Manifest: Codable, Sendable, Equatable {
        public struct Title: Codable, Sendable, Equatable {
            public let id: String
            public let anilistId: Int?
            public let titles: [String]
            public let episodes: [EpisodeEntry]
        }
        public struct EpisodeEntry: Codable, Sendable, Equatable {
            public let season: Int?
            public let number: Int
            public let title: String?
            public let url: URL
            public let expiresAt: Date?
        }
        public let version: Int
        public let providerName: String?
        public let titles: [Title]
    }

    public static let providerID: ProviderID = "manifest"
    public let id: ProviderID = ManifestProvider.providerID
    public let displayName: String
    public let capabilities: ProviderCapabilities = [.search, .episodeList, .audioTracksInfo, .subtitlesInfo, .availabilityCheck]

    private let manifestURL: URL
    private let transport: HTTPTransport
    private let cacheTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let state = ManifestState()

    public init(manifestURL: URL, displayName: String = "Мой источник", transport: HTTPTransport,
                cacheTTL: TimeInterval = 600, now: @escaping @Sendable () -> Date = { Date() }) {
        self.manifestURL = manifestURL
        self.displayName = displayName
        self.transport = transport
        self.cacheTTL = cacheTTL
        self.now = now
    }

    public func search(title: String) async throws -> [ProviderTitle] {
        let manifest = try await loadManifest()
        let all = manifest.titles.map { ProviderTitle(id: $0.id, providerID: id, titles: $0.titles, anilistID: $0.anilistId) }
        let q = title.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { t in TitleMatcher.matches(query: q, titles: t.titles) || t.titles.contains { TitleMatcher.similarity($0, q) >= 0.6 } }
    }

    public func match(anime: Anime) async throws -> ProviderTitle? {
        let manifest = try await loadManifest()
        let all = manifest.titles.map { ProviderTitle(id: $0.id, providerID: id, titles: $0.titles, anilistID: $0.anilistId) }
        if let byID = all.first(where: { $0.anilistID == anime.id }) { return byID }
        // Если у записи указан другой anilistId — это точно другой тайтл.
        return TitleMatcher.bestMatch(for: anime.allTitles, among: all.filter { $0.anilistID == nil }, titlesOf: \.titles)
    }

    public func episodes(for title: ProviderTitle) async throws -> [ProviderEpisode] {
        let manifest = try await loadManifest()
        guard let entry = manifest.titles.first(where: { $0.id == title.id }) else { throw VideoSourceError.titleNotFound }
        return entry.episodes.map {
            ProviderEpisode(providerID: id, titleID: entry.id, season: $0.season, number: $0.number, title: $0.title,
                            payload: $0.url.absoluteString)
        }
    }

    public func resolve(_ episode: ProviderEpisode) async throws -> PlaybackSource {
        let manifest = try await loadManifest()
        guard let entry = manifest.titles.first(where: { $0.id == episode.titleID })?.episodes
            .first(where: { $0.number == episode.number && $0.season == episode.season }) else {
            throw VideoSourceError.episodeNotFound(episode.number)
        }
        if let exp = entry.expiresAt, exp <= now() { throw VideoSourceError.linkExpired }
        guard entry.url.scheme == "https" else { throw VideoSourceError.unsupportedFormat("разрешены только https-ссылки") }
        let kind: StreamKind
        switch entry.url.pathExtension.lowercased() {
        case "m3u8": kind = .hls
        case "mp4", "m4v", "mov": kind = .progressiveFile
        default: throw VideoSourceError.unsupportedFormat(entry.url.pathExtension.isEmpty ? "без расширения" : entry.url.pathExtension)
        }
        var audio: [MediaTrackInfo] = [], subs: [MediaTrackInfo] = []
        if kind == .hls {
            var req = URLRequest(url: entry.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            req.httpMethod = "GET"
            let (data, response) = try await transport.send(req)
            guard (200..<300).contains(response.statusCode) else { throw VideoSourceError.unavailable("HTTP \(response.statusCode)") }
            let info = HLSManifestInspector.inspect(String(decoding: data.prefix(256 * 1024), as: UTF8.self))
            guard info.isValid else { throw VideoSourceError.unsupportedFormat("ответ не является плейлистом HLS") }
            audio = info.audio
            subs = info.subtitles
        } else {
            var req = URLRequest(url: entry.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            req.httpMethod = "HEAD"
            let (_, response) = try await transport.send(req)
            guard (200..<400).contains(response.statusCode) else { throw VideoSourceError.unavailable("HTTP \(response.statusCode)") }
        }
        return PlaybackSource(providerID: id, providerName: manifest.providerName ?? displayName, url: entry.url, kind: kind,
                              expiresAt: entry.expiresAt, audioTracks: audio, subtitleTracks: subs)
    }

    // MARK: - Manifest loading

    func loadManifest() async throws -> Manifest {
        let current = now()
        if let cached = await state.manifest(validAt: current) { return cached }
        var req = URLRequest(url: manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(req)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw VideoSourceError.from(error) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: Manifest
        do { manifest = try decoder.decode(Manifest.self, from: data) } catch {
            throw VideoSourceError.invalidResponse("манифест не соответствует формату (\(error.localizedDescription))")
        }
        guard manifest.version == 1 else { throw VideoSourceError.invalidResponse("неподдерживаемая версия манифеста \(manifest.version)") }
        // Не кэшируем дольше, чем живёт самая короткая временная ссылка.
        let soonest = manifest.titles.flatMap(\.episodes).compactMap(\.expiresAt).filter { $0 > current }.min()
        var until = current.addingTimeInterval(cacheTTL)
        if let soonest, soonest < until { until = soonest }
        await state.set(manifest, until: until)
        return manifest
    }
}

private actor ManifestState {
    private var manifest: ManifestProvider.Manifest?
    private var validUntil: Date = .distantPast

    func manifest(validAt date: Date) -> ManifestProvider.Manifest? {
        date < validUntil ? manifest : nil
    }

    func set(_ m: ManifestProvider.Manifest, until: Date) {
        manifest = m
        validUntil = until
    }
}
