import Foundation

public struct Episode: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(animeId)-\(season)-\(number)" }
    public let animeId: Int
    /// Сезон внутри записи каталога. В AniList каждый сезон — отдельный тайтл, поэтому обычно 1.
    public let season: Int
    public let number: Int
    public var title: String?
    public var thumbnailURL: URL?

    public init(animeId: Int, season: Int = 1, number: Int, title: String? = nil, thumbnailURL: URL? = nil) {
        self.animeId = animeId
        self.season = season
        self.number = number
        self.title = title
        self.thumbnailURL = thumbnailURL
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return "\(number). \(title)" }
        return "Серия \(number)"
    }
}

public struct EpisodeList: Hashable, Sendable {
    public let episodes: [Episode]
    /// Общее число серий известно и совпадает со списком.
    public let isCountKnown: Bool
    /// Пояснение для пользователя, если список неполный/неизвестен.
    public let note: String?
}

/// Строит список серий только из реально известных данных каталога.
public enum EpisodeListBuilder {
    public static func build(from details: AnimeDetails) -> EpisodeList {
        let anime = details.anime
        // Названия серий с официальных площадок (если есть), сопоставленные по номеру.
        var titled: [Int: StreamingEpisodeInfo] = [:]
        for info in details.streamingEpisodes {
            if let parsed = EpisodeNumberParser.parse(info.title), titled[parsed.number] == nil {
                titled[parsed.number] = info
            }
        }

        let count: Int?
        let note: String?
        let known: Bool
        switch anime.status {
        case .notYetReleased:
            count = 0
            known = anime.episodeCount != nil
            note = "Тайтл ещё не вышел."
        case .releasing:
            if let released = anime.releasedEpisodeCount {
                count = released
                known = false
                let total = anime.episodeCount.map { " из \($0)" } ?? ""
                note = "Онгоинг: вышло \(released)\(total)."
            } else {
                count = titled.keys.max()
                known = false
                note = "Онгоинг: точное количество вышедших серий неизвестно."
            }
        default:
            if let total = anime.episodeCount {
                count = total
                known = true
                note = nil
            } else if let maxTitled = titled.keys.max() {
                count = maxTitled
                known = false
                note = "Общее количество серий в каталоге не указано."
            } else {
                count = nil
                known = false
                note = "Количество серий неизвестно."
            }
        }

        let episodes = (count ?? 0) > 0 ? (1...(count ?? 0)).map { number -> Episode in
            let info = titled[number]
            return Episode(animeId: anime.id, number: number,
                           title: info.flatMap { EpisodeNumberParser.parse($0.title)?.title },
                           thumbnailURL: info?.thumbnailURL)
        } : []
        return EpisodeList(episodes: episodes, isCountKnown: known, note: note)
    }
}
