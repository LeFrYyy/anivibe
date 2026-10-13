import Foundation

/// Озвучка/перевод в терминах Kodik.
public struct KodikTranslation: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case voice        // озвучка
        case subtitles    // субтитры
        case unknown
    }

    public let id: Int
    public let title: String
    public let kind: Kind

    public init(id: Int, title: String, kind: Kind) {
        self.id = id
        self.title = title
        self.kind = kind
    }

    public var isVoice: Bool { kind == .voice }
}

/// Ссылка на конкретную серию в плеере Kodik (embed-iframe, НЕ прямой поток).
public struct KodikEpisode: Hashable, Sendable, Identifiable {
    public var id: String { "\(season):\(number)" }
    public let season: Int
    public let number: Int
    public let title: String?
    /// URL веб-плеера (iframe). Открывается в WKWebView, в AVPlayer его подставлять нельзя.
    public let playerURL: URL

    public init(season: Int, number: Int, title: String?, playerURL: URL) {
        self.season = season
        self.number = number
        self.title = title
        self.playerURL = playerURL
    }
}

/// Один вариант озвучки тайтла у Kodik: материал × перевод.
public struct KodikVoiceOption: Hashable, Sendable, Identifiable {
    public var id: String { "\(materialID)#\(translation.id)" }
    /// Внутренний id материала Kodik (например, "serial-45534").
    public let materialID: String
    public let translation: KodikTranslation
    /// Название тайтла у Kodik (может отличаться от каталога).
    public let title: String
    public let year: Int?
    public let quality: String?
    /// Плеер тайтла целиком (для фильма — само видео; для сериала — плеер с выбором сезона/серии).
    public let playerURL: URL
    /// Серии, если Kodik их вернул (пусто для фильмов и при ответе без `with_episodes`).
    public let episodes: [KodikEpisode]
    /// Ссылки на плееры сезонов (сезон → URL), если сериал многосезонный.
    public let seasonPlayerURLs: [Int: URL]

    public init(materialID: String, translation: KodikTranslation, title: String, year: Int?,
                quality: String?, playerURL: URL, episodes: [KodikEpisode], seasonPlayerURLs: [Int: URL], isSingleVideo: Bool? = nil) {
        self.isSingleVideo = isSingleVideo ?? (episodes.isEmpty && seasonPlayerURLs.isEmpty)
        self.materialID = materialID
        self.translation = translation
        self.title = title
        self.year = year
        self.quality = quality
        self.playerURL = playerURL
        self.episodes = episodes
        self.seasonPlayerURLs = seasonPlayerURLs
    }

    /// Фильм/одиночное видео: серий нет, играем сам материал.
    public let isSingleVideo: Bool

    public var seasons: [Int] { seasonPlayerURLs.keys.sorted() }

    public func episodes(season: Int) -> [KodikEpisode] {
        episodes.filter { $0.season == season }.sorted { $0.number < $1.number }
    }
}

/// Результат сопоставления тайтла каталога с материалом Kodik:
/// один материал и все его варианты озвучки.
public struct KodikMatch: Hashable, Sendable {
    public let materialID: String
    /// Название, под которым Kodik знает тайтл (показываем пользователю для прозрачности).
    public let matchedTitle: String
    public let year: Int?
    public let voices: [KodikVoiceOption]

    public init(materialID: String, matchedTitle: String, year: Int?, voices: [KodikVoiceOption]) {
        self.materialID = materialID
        self.matchedTitle = matchedTitle
        self.year = year
        // Сначала озвучки, потом субтитры; внутри — по алфавиту.
        self.voices = voices.sorted { lhs, rhs in
            if lhs.translation.isVoice != rhs.translation.isVoice { return lhs.translation.isVoice }
            return lhs.translation.title.localizedCaseInsensitiveCompare(rhs.translation.title) == .orderedAscending
        }
    }
}

// MARK: - DTO (внутреннее представление ответа kodik-api.com)

struct KodikSearchResponseDTO: Decodable {
    let total: Int?
    let results: [KodikMaterialDTO]?
    /// Kodik возвращает 200 с {"error": "..."} при некоторых ошибках (например, неверный токен).
    let error: String?
}

struct KodikMaterialDTO: Decodable {
    let id: String
    let type: String?
    let link: String
    let title: String?
    let titleOrig: String?
    let otherTitle: String?
    let year: Int?
    let quality: String?
    let translation: TranslationDTO?
    let seasons: [String: SeasonDTO]?
    /// ID Shikimori (= ID MyAnimeList). Kodik отдаёт строкой, терпим и число.
    let shikimoriID: Int?

    enum CodingKeys: String, CodingKey {
        case id, type, link, title, year, quality, translation, seasons
        case titleOrig = "title_orig"
        case otherTitle = "other_title"
        case shikimoriID = "shikimori_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        link = try c.decode(String.self, forKey: .link)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        titleOrig = try c.decodeIfPresent(String.self, forKey: .titleOrig)
        otherTitle = try c.decodeIfPresent(String.self, forKey: .otherTitle)
        year = try? c.decodeIfPresent(Int.self, forKey: .year)
        quality = try c.decodeIfPresent(String.self, forKey: .quality)
        translation = try c.decodeIfPresent(TranslationDTO.self, forKey: .translation)
        seasons = try c.decodeIfPresent([String: SeasonDTO].self, forKey: .seasons)
        if let n = try? c.decodeIfPresent(Int.self, forKey: .shikimoriID) {
            shikimoriID = n
        } else if let str = try? c.decodeIfPresent(String.self, forKey: .shikimoriID) {
            shikimoriID = Int(str)
        } else {
            shikimoriID = nil
        }
    }

    struct TranslationDTO: Decodable {
        let id: Int?
        let title: String?
        let type: String?
    }

    struct SeasonDTO: Decodable {
        let link: String?
        let episodes: [String: EpisodeDTO]?
    }

    /// Эпизод обычно объект {"link": ..., "title": ...}, но терпим и к «голой» строке-ссылке.
    struct EpisodeDTO: Decodable {
        let link: String
        let title: String?

        init(link: String, title: String?) {
            self.link = link
            self.title = title
        }

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self),
               let link = try container.decodeIfPresent(String.self, forKey: .link) {
                self.link = link
                self.title = try container.decodeIfPresent(String.self, forKey: .title)
                return
            }
            let single = try decoder.singleValueContainer()
            self.link = try single.decode(String.self)
            self.title = nil
        }

        private enum CodingKeys: String, CodingKey { case link, title }
    }
}