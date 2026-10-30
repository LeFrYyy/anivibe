import Foundation

/// Названия тайтла из каталога. Все поля опциональны, кроме хотя бы одного.
public struct AnimeTitle: Hashable, Codable, Sendable {
    public var romaji: String?
    public var english: String?
    public var native: String?
    public var russian: String?
    /// Откуда взято русское название; `nil` — источник неизвестен (старый кэш) и название считается официальным.
    public var russianSource: RussianTitleSource?

    public init(romaji: String? = nil, english: String? = nil, native: String? = nil, russian: String? = nil,
                russianSource: RussianTitleSource? = nil) {
        self.russian = russian
        self.romaji = romaji
        self.english = english
        self.native = native
        self.russianSource = russianSource
    }

    /// Русское название — автоматический перевод, а не официальное.
    public var isRussianAutomatic: Bool { russianSource == .automatic && russian?.nilIfBlank != nil }

    /// Основное отображаемое название.
    public var preferred: String {
        russian?.nilIfBlank ?? english?.nilIfBlank ?? romaji?.nilIfBlank ?? native?.nilIfBlank ?? "Без названия"
    }

    /// Все известные варианты названия без дублей (в порядке приоритета).
    public var all: [String] {
        var seen = Set<String>()
        return [russian, english, romaji, native].compactMap { $0?.nilIfBlank }.filter { seen.insert($0).inserted }
    }

    /// Только официальные названия: автоматический перевод исключён, чтобы не сопоставлять по нему источники видео.
    public var official: [String] {
        isRussianAutomatic ? all.filter { $0 != russian } : all
    }
}

public enum AiringStatus: String, Codable, CaseIterable, Sendable {
    case finished = "FINISHED"
    case releasing = "RELEASING"
    case notYetReleased = "NOT_YET_RELEASED"
    case cancelled = "CANCELLED"
    case hiatus = "HIATUS"
    case unknown = "UNKNOWN"

    public init(apiValue: String?) {
        self = apiValue.flatMap(AiringStatus.init(rawValue:)) ?? .unknown
    }

    public var localizedName: String {
        switch self {
        case .finished: return "Завершён"
        case .releasing: return "Онгоинг"
        case .notYetReleased: return "Анонс"
        case .cancelled: return "Отменён"
        case .hiatus: return "Перерыв"
        case .unknown: return "Неизвестно"
        }
    }

    /// Статусы, доступные в фильтре каталога.
    public static var filterable: [AiringStatus] { [.releasing, .finished, .notYetReleased, .hiatus, .cancelled] }
}

public enum AnimeFormat: String, Codable, CaseIterable, Sendable {
    case tv = "TV", tvShort = "TV_SHORT", movie = "MOVIE", special = "SPECIAL"
    case ova = "OVA", ona = "ONA", music = "MUSIC"

    public var localizedName: String {
        switch self {
        case .tv: return "ТВ"
        case .tvShort: return "ТВ (короткие)"
        case .movie: return "Фильм"
        case .special: return "Спешл"
        case .ova: return "OVA"
        case .ona: return "ONA"
        case .music: return "Клип"
        }
    }

    /// Форматы, которые образуют «сезоны» сериала.
    public var isSeries: Bool { self == .tv || self == .tvShort || self == .ona }
}

public enum AnimeSeason: String, Codable, CaseIterable, Sendable {
    case winter = "WINTER", spring = "SPRING", summer = "SUMMER", fall = "FALL"

    public var localizedName: String {
        switch self {
        case .winter: return "Зима"
        case .spring: return "Весна"
        case .summer: return "Лето"
        case .fall: return "Осень"
        }
    }

    /// Аниме-сезон для даты (по UTC-календарю, как в AniList).
    public static func current(for date: Date = Date(), calendar: Calendar = .utcGregorian) -> (season: AnimeSeason, year: Int) {
        let comps = calendar.dateComponents([.month, .year], from: date)
        let month = comps.month ?? 1
        let year = comps.year ?? 2000
        switch month {
        case 1...3: return (.winter, year)
        case 4...6: return (.spring, year)
        case 7...9: return (.summer, year)
        default: return (.fall, year)
        }
    }
}

/// Карточка тайтла из каталога метаданных.
/// Наличие тайтла в каталоге НЕ означает, что для него есть видеоисточник.
public struct Anime: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public var title: AnimeTitle
    public var synonyms: [String]
    public var synopsis: String?
    public var synopsisOriginal: String?
    public var synopsisSource: String?
    public var coverURL: URL?
    public var bannerURL: URL?
    public var coverColorHex: String?
    public var year: Int?
    public var season: AnimeSeason?
    public var genres: [String]
    public var status: AiringStatus
    public var format: AnimeFormat?
    /// Средняя оценка 0–100, если источник её предоставляет.
    public var averageScore: Int?
    /// Общее число серий; `nil`, если неизвестно.
    public var episodeCount: Int?
    public var episodeDurationMinutes: Int?
    /// Номер следующей серии для онгоингов (если известен).
    public var nextAiringEpisode: Int?
    /// ID на MyAnimeList (= ID на Shikimori). По нему видеоисточники сопоставляются
    /// точно, без угадывания по названию.
    public var malID: Int?
    /// Разговорные и альтернативные русские названия для поиска (не используются для сопоставления с источниками).
    public var searchAliases: [String]?

    public init(id: Int, title: AnimeTitle, synonyms: [String] = [], synopsis: String? = nil,
                coverURL: URL? = nil, bannerURL: URL? = nil, coverColorHex: String? = nil,
                year: Int? = nil, season: AnimeSeason? = nil, genres: [String] = [],
                status: AiringStatus = .unknown, format: AnimeFormat? = nil, averageScore: Int? = nil,
                episodeCount: Int? = nil, episodeDurationMinutes: Int? = nil, nextAiringEpisode: Int? = nil,
                malID: Int? = nil) {
        self.id = id
        self.title = title
        self.synonyms = synonyms
        self.synopsis = synopsis
        self.coverURL = coverURL
        self.bannerURL = bannerURL
        self.coverColorHex = coverColorHex
        self.year = year
        self.season = season
        self.genres = genres
        self.status = status
        self.format = format
        self.averageScore = averageScore
        self.episodeCount = episodeCount
        self.episodeDurationMinutes = episodeDurationMinutes
        self.nextAiringEpisode = nextAiringEpisode
        self.malID = malID
    }

    /// Все названия, включая синонимы (для поиска и сопоставления с источниками).
    public var allTitles: [String] {
        var seen = Set<String>()
        return (title.official + synonyms).filter { seen.insert($0.lowercased()).inserted }
    }

    /// Всё, по чему тайтл можно найти: названия, синонимы, разговорные варианты и автоперевод.
    public var searchableTitles: [String] {
        var seen = Set<String>()
        return (title.all + synonyms + (searchAliases ?? [])).filter { seen.insert($0.lowercased()).inserted }
    }

    /// Количество уже вышедших серий (известное), без домыслов.
    public var releasedEpisodeCount: Int? {
        if let next = nextAiringEpisode, status == .releasing { return max(0, next - 1) }
        if status == .notYetReleased { return 0 }
        return episodeCount
    }

    /// Сколько серий вышло из скольких — только для выходящих тайтлов:
    /// «2/11», а если общее число ещё не объявлено — «2/?». Для завершённых — `nil`
    /// (там достаточно «N эп.»).
    public var airedEpisodesText: String? {
        guard status == .releasing || status == .hiatus, let next = nextAiringEpisode else { return nil }
        let aired = max(0, next - 1)
        let total = episodeCount.map(String.init) ?? "?"
        return "\(aired)/\(total)"
    }

    public var snapshot: AnimeSnapshot {
        AnimeSnapshot(id: id, title: title.preferred, coverURL: coverURL, episodeCount: episodeCount)
    }
}

/// Минимальная копия тайтла для библиотеки (чтобы списки работали офлайн).
public struct AnimeSnapshot: Hashable, Codable, Sendable {
    public let id: Int
    public var title: String
    public var coverURL: URL?
    public var episodeCount: Int?

    public init(id: Int, title: String, coverURL: URL? = nil, episodeCount: Int? = nil) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
        self.episodeCount = episodeCount
    }
}

public enum RelationType: String, Codable, Sendable {
    case prequel = "PREQUEL", sequel = "SEQUEL", parent = "PARENT", sideStory = "SIDE_STORY"
    case spinOff = "SPIN_OFF", alternative = "ALTERNATIVE", summary = "SUMMARY", other = "OTHER"
    case adaptation = "ADAPTATION", source = "SOURCE", character = "CHARACTER", compilation = "COMPILATION", contains = "CONTAINS"

    public var localizedName: String {
        switch self {
        case .prequel: return "Предыстория"
        case .sequel: return "Продолжение"
        case .parent: return "Основная история"
        case .sideStory: return "Побочная история"
        case .spinOff: return "Спин-офф"
        case .alternative: return "Альтернатива"
        case .summary: return "Пересказ"
        case .compilation: return "Компиляция"
        case .contains: return "Содержит"
        default: return "Связанное"
        }
    }
}

public struct RelatedAnime: Hashable, Codable, Sendable, Identifiable {
    public var id: Int { anime.id }
    public let relation: RelationType
    public let anime: Anime
    public init(relation: RelationType, anime: Anime) {
        self.relation = relation
        self.anime = anime
    }
}

/// Ссылка на официальную площадку (открывается во внешнем браузере/приложении).
public struct ExternalLink: Hashable, Codable, Sendable, Identifiable {
    public var id: String { url.absoluteString }
    public let site: String
    public let url: URL
    public let language: String?
    public init(site: String, url: URL, language: String? = nil) {
        self.site = site
        self.url = url
        self.language = language
    }
}

/// Информация о серии с официальной площадки, которую отдаёт каталог (название, превью).
public struct StreamingEpisodeInfo: Hashable, Codable, Sendable {
    public let title: String
    public let thumbnailURL: URL?
    public let url: URL?
    public let site: String?
    public init(title: String, thumbnailURL: URL? = nil, url: URL? = nil, site: String? = nil) {
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.url = url
        self.site = site
    }
}

public struct AnimeDetails: Hashable, Codable, Sendable {
    public var anime: Anime
    public var relations: [RelatedAnime]
    public var streamingEpisodes: [StreamingEpisodeInfo]
    public var externalStreamingLinks: [ExternalLink]
    public var studios: [String]
    public var recommendations: [Anime]

    public init(anime: Anime, relations: [RelatedAnime] = [], streamingEpisodes: [StreamingEpisodeInfo] = [],
                externalStreamingLinks: [ExternalLink] = [], studios: [String] = [], recommendations: [Anime] = []) {
        self.anime = anime
        self.relations = relations
        self.streamingEpisodes = streamingEpisodes
        self.externalStreamingLinks = externalStreamingLinks
        self.studios = studios
        self.recommendations = recommendations
    }

    /// Другие сезоны сериала (прямые предыстории/продолжения в сериальном формате).
    public var otherSeasons: [RelatedAnime] {
        relations.filter { ($0.relation == .prequel || $0.relation == .sequel) && ($0.anime.format?.isSeries ?? false) }
    }

    /// Первоисточник аниме (манга, ранобэ, визуальная новелла...) — relation `SOURCE` в AniList.
    public var sourceRelation: RelatedAnime? {
        relations.first { $0.relation == .source }
    }

    /// Прочие связанные тайтлы (фильмы, OVA, спин-оффы...). Исключает адаптации-первоисточники.
    public var otherRelations: [RelatedAnime] {
        let seasonIDs = Set(otherSeasons.map(\.id))
        return relations.filter { !seasonIDs.contains($0.id) && $0.relation != .adaptation && $0.relation != .source && $0.relation != .character }
    }
}
