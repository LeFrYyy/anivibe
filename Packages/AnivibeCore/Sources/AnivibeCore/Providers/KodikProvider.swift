import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Kodik как обычный видеоисточник: кнопка «Смотреть» и плеер приложения работают через него.
///
/// * Сопоставление — по Shikimori ID (= idMal из AniList), затем по названиям.
/// * Для каждой серии запоминаются все озвучки, где она есть; играет предпочитаемая
///   (последняя выбранная пользователем), иначе — самая полная.
/// * Потоки — прямые HLS разных качеств (см. `KodikStreamResolver`).
public struct KodikProvider: VideoSourceProvider {
    public static let providerID: ProviderID = "kodik"
    public let id: ProviderID = KodikProvider.providerID
    public let displayName = "Kodik"
    public let capabilities: ProviderCapabilities = [.search, .episodeList, .audioTracksInfo]

    private let client: KodikClient
    private let preferredVoice: @Sendable () -> String?
    private let preferredQuality: @Sendable () -> Int?
    private let cache = MatchCache()

    public init(client: KodikClient,
                preferredVoice: @escaping @Sendable () -> String? = { nil },
                preferredQuality: @escaping @Sendable () -> Int? = { nil }) {
        self.client = client
        self.preferredVoice = preferredVoice
        self.preferredQuality = preferredQuality
    }

    // MARK: - VideoSourceProvider

    public func search(title: String) async throws -> [ProviderTitle] {
        guard let match = try await client.search(titles: [title]) else { return [] }
        let key = "title:\(title.lowercased())"
        await cache.store(match, for: key)
        return [ProviderTitle(id: key, providerID: id, titles: [match.matchedTitle], year: match.year)]
    }

    public func match(anime: Anime) async throws -> ProviderTitle? {
        let key = "anime:\(anime.id)"
        if await cache.match(for: key) == nil {
            guard let match = try await client.search(titles: anime.allTitles, year: anime.year, shikimoriID: anime.malID) else {
                return nil
            }
            await cache.store(match, for: key)
        }
        guard let match = await cache.match(for: key) else { return nil }
        return ProviderTitle(id: key, providerID: id, titles: [match.matchedTitle], year: match.year, malID: anime.malID)
    }

    public func episodes(for title: ProviderTitle) async throws -> [ProviderEpisode] {
        guard let match = await cache.match(for: title.id) else { throw VideoSourceError.titleNotFound }
        return Self.makeEpisodes(match: match, titleID: title.id, preferredVoice: preferredVoice())
    }

    public func resolve(_ episode: ProviderEpisode) async throws -> PlaybackSource {
        guard let payload = Payload.decode(episode.payload), !payload.voices.isEmpty else {
            throw VideoSourceError.invalidResponse("Kodik: повреждённые данные серии")
        }
        let voice = payload.voices.first { $0.title == payload.selected } ?? payload.voices[0]
        guard let playerURL = URL(string: voice.url) else { throw VideoSourceError.invalidResponse("Kodik: некорректная ссылка") }
        let streams: [KodikStream]
        do {
            streams = try await client.streams(for: playerURL)
        } catch {
            throw VideoSourceError.from(error)
        }
        guard !streams.isEmpty else { throw VideoSourceError.unavailable("Kodik не отдал видеопоток") }
        let limit = preferredQuality() ?? Int.max
        let chosen = streams.first { $0.quality <= limit } ?? streams.last!
        return PlaybackSource(
            providerID: id, providerName: displayName, url: chosen.url, kind: .hls,
            // Ссылки Kodik временные — не переиспользуем их дольше пары часов.
            expiresAt: Date().addingTimeInterval(2 * 3600),
            audioTracks: [MediaTrackInfo(name: voice.title, language: "ru", isDefault: true)],
            attribution: "Kodik · \(voice.title)",
            qualities: streams.map { PlaybackQuality(height: $0.quality, url: $0.url) },
            voices: payload.voices.map(\.title),
            selectedVoice: voice.title)
    }

    /// Ссылка проверяется при воспроизведении: так поиск источника не тратит время
    /// на лишние запросы к плееру Kodik (их три на каждую проверку).
    public func checkAvailability(_ episode: ProviderEpisode) async -> Availability {
        guard let payload = Payload.decode(episode.payload), !payload.voices.isEmpty else {
            return .unavailable(.episodeNotFound(episode.number))
        }
        return .available
    }

    /// Та же серия, но с другой озвучкой.
    public static func episode(_ episode: ProviderEpisode, withVoice voice: String) -> ProviderEpisode {
        guard var payload = Payload.decode(episode.payload) else { return episode }
        payload.selected = voice
        return ProviderEpisode(providerID: episode.providerID, titleID: episode.titleID, season: episode.season,
                               number: episode.number, title: episode.title, payload: payload.encoded())
    }

    // MARK: - Внутреннее

    struct Payload: Codable, Equatable {
        struct Voice: Codable, Equatable {
            let title: String
            let url: String
        }
        var selected: String?
        var voices: [Voice]

        func encoded() -> String { String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self) }
        static func decode(_ string: String) -> Payload? { try? JSONDecoder().decode(Payload.self, from: Data(string.utf8)) }
    }

    /// Объединяет серии всех озвучек. Если у тайтла один сезон, нумерация сквозная (season = nil):
    /// AniList хранит каждый сезон отдельным тайтлом, а Kodik может подписать сиквел как «сезон 2».
    static func makeEpisodes(match: KodikMatch, titleID: String, preferredVoice: String?) -> [ProviderEpisode] {
        let voices = rankedVoices(match.voices)
        var all = voices.flatMap(\.episodes)
        let regular = all.filter { $0.season > 0 }
        if !regular.isEmpty { all = regular }
        let seasons = Set(all.map(\.season))
        let flatten = seasons.count <= 1

        struct Key: Hashable { let season: Int?; let number: Int }
        var order: [Key] = []
        var byKey: [Key: (title: String?, voices: [Payload.Voice])] = [:]
        for voice in voices {
            for ep in voice.episodes where seasons.contains(ep.season) {
                let key = Key(season: flatten ? nil : ep.season, number: ep.number)
                if byKey[key] == nil { order.append(key); byKey[key] = (ep.title, []) }
                if byKey[key]!.voices.contains(where: { $0.title == voice.translation.title }) { continue }
                byKey[key]!.voices.append(.init(title: voice.translation.title, url: ep.playerURL.absoluteString))
                if byKey[key]!.title == nil { byKey[key]!.title = ep.title }
            }
        }
        // Фильмы и одиночные видео: одна «серия» с номером 1.
        if order.isEmpty {
            let list = voices.filter(\.isSingleVideo).map { Payload.Voice(title: $0.translation.title, url: $0.playerURL.absoluteString) }
            if !list.isEmpty {
                let selected = list.contains { $0.title == preferredVoice } ? preferredVoice : list[0].title
                return [ProviderEpisode(providerID: providerID, titleID: titleID, season: nil, number: 1, title: nil,
                                        payload: Payload(selected: selected, voices: list).encoded())]
            }
        }
        return order.sorted { ($0.season ?? 0, $0.number) < ($1.season ?? 0, $1.number) }.compactMap { key in
            guard let entry = byKey[key], !entry.voices.isEmpty else { return nil }
            let selected = entry.voices.contains { $0.title == preferredVoice } ? preferredVoice : entry.voices[0].title
            return ProviderEpisode(providerID: providerID, titleID: titleID, season: key.season, number: key.number,
                                   title: entry.title, payload: Payload(selected: selected, voices: entry.voices).encoded())
        }
    }

    /// Exact provider list, preserving season 0, gaps, materials and translation identity.
    /// This does not claim that provider episode 4 is catalogue episode 4.
    public static func sourceEpisodes(for voice: KodikVoiceOption, animeID: Int, season: Int? = nil) -> [Episode] {
        if voice.isSingleVideo {
            let payload = Payload(selected: voice.translation.title, voices: [.init(title: voice.translation.title, url: voice.playerURL.absoluteString)])
            let source = ProviderEpisode(providerID: providerID, titleID: voice.id, season: nil, number: 1, title: voice.title, payload: payload.encoded())
            return [Episode(animeId: animeID, number: 1, title: voice.title, sourceEpisode: source)]
        }
        let original = voice.episodes.filter { season == nil || $0.season == season }
            .sorted { ($0.season, $0.number) < ($1.season, $1.number) }
        var seen = Set<String>()
        return original.filter { seen.insert($0.id).inserted }.enumerated().map { index, ep in
            let payload = Payload(selected: voice.translation.title,
                                  voices: [.init(title: voice.translation.title, url: ep.playerURL.absoluteString)])
            let source = ProviderEpisode(providerID: providerID, titleID: voice.id, season: ep.season,
                                         number: ep.number, title: ep.title, payload: payload.encoded())
            return Episode(animeId: animeID, season: ep.season, number: index + 1,
                           title: ep.title, sourceEpisode: source)
        }
    }

    /// Озвучки в порядке «по умолчанию»: сначала озвучки (не субтитры), затем популярные студии,
    /// затем самые полные. Этот же порядок использует плеер, когда пользователь ещё ничего не выбрал.
    public static func rankedVoices(_ voices: [KodikVoiceOption]) -> [KodikVoiceOption] {
        func rank(_ title: String) -> Int {
            let t = title.lowercased()
            return popularStudios.firstIndex { t.contains($0) } ?? popularStudios.count
        }
        return voices.sorted { a, b in
            if a.translation.isVoice != b.translation.isVoice { return a.translation.isVoice }
            let ra = rank(a.translation.title), rb = rank(b.translation.title)
            if ra != rb { return ra < rb }
            return a.episodes.count > b.episodes.count
        }
    }

    /// Популярные студии — по умолчанию (пока пользователь не выбрал свою) играет одна из них.
    static let popularStudios = ["anilibria", "anidub", "studio band", "animevost", "anistar", "dream cast",
                                 "shiza", "animedia", "jam", "sovetromantica", "кубик в кубе", "aniplay"]

    actor MatchCache {
        private var matches: [String: KodikMatch] = [:]
        func store(_ match: KodikMatch, for key: String) { matches[key] = match }
        func match(for key: String) -> KodikMatch? { matches[key] }
    }
}
