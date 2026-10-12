import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Провайдер ЛЕГАЛЬНЫХ ТЕСТОВЫХ потоков для проверки плеера.
/// Это НЕ серии аниме: интерфейс явно помечает такие источники как тестовые.
///
/// Потоки:
/// - Apple «BipBop» — официальные примеры HLS от Apple для разработчиков
///   (developer.apple.com/streaming/examples). Две аудиодорожки и несколько субтитров.
/// - «Big Buck Bunny» © Blender Foundation, CC BY 3.0, HLS-версия из публичных тестовых потоков Mux.
public struct TestStreamProvider: VideoSourceProvider {
    public struct Stream: Sendable, Hashable {
        public let name: String
        public let url: URL
        public let attribution: String
    }

    public static let providerID: ProviderID = "test-streams"
    public static let streams: [Stream] = [
        Stream(name: "Apple BipBop (2 аудио, субтитры)",
               url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8")!,
               attribution: "Тестовый поток Apple (HLS examples)"),
        Stream(name: "Big Buck Bunny",
               url: URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!,
               attribution: "© Blender Foundation, CC BY 3.0 · тестовый поток Mux")
    ]

    public let id: ProviderID = TestStreamProvider.providerID
    public let displayName = "Тестовый поток (не серия аниме)"
    public let capabilities: ProviderCapabilities = [.episodeList, .audioTracksInfo, .subtitlesInfo, .availabilityCheck]
    public let providesTestContent = true
    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    public func search(title: String) async throws -> [ProviderTitle] {
        [ProviderTitle(id: "test", providerID: id, titles: ["Test streams"])]
    }

    /// Тестовый поток доступен для любого тайтла — но он всегда помечен как тест.
    public func match(anime: Anime) async throws -> ProviderTitle? {
        ProviderTitle(id: "test-\(anime.id)", providerID: id, titles: anime.allTitles, anilistID: anime.id)
    }

    public func episodes(for title: ProviderTitle) async throws -> [ProviderEpisode] {
        // Номер серии → поток по кругу. Без сезона (сквозная нумерация).
        (1...500).map { n in
            ProviderEpisode(providerID: id, titleID: title.id, season: nil, number: n,
                            title: Self.streams[(n - 1) % Self.streams.count].name,
                            payload: String((n - 1) % Self.streams.count))
        }
    }

    public func resolve(_ episode: ProviderEpisode) async throws -> PlaybackSource {
        guard let index = Int(episode.payload), Self.streams.indices.contains(index) else {
            throw VideoSourceError.episodeNotFound(episode.number)
        }
        let stream = Self.streams[index]
        var request = URLRequest(url: stream.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw VideoSourceError.unavailable("сервер вернул HTTP \(response.statusCode)")
        }
        let info = HLSManifestInspector.inspect(String(decoding: data.prefix(256 * 1024), as: UTF8.self))
        guard info.isValid else { throw VideoSourceError.unsupportedFormat("ответ не является плейлистом HLS") }
        return PlaybackSource(providerID: id, providerName: displayName, url: stream.url, kind: .hls,
                              audioTracks: info.audio, subtitleTracks: info.subtitles,
                              isTestContent: true, attribution: stream.attribution)
    }
}
