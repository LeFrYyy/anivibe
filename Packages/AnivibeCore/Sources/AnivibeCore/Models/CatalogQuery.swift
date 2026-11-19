import Foundation

public enum CatalogSort: String, CaseIterable, Codable, Sendable {
    case popularity = "POPULARITY_DESC"
    case trending = "TRENDING_DESC"
    case score = "SCORE_DESC"
    case newest = "START_DATE_DESC"
    case recentlyAdded = "ID_DESC"
    case title = "TITLE_ROMAJI"
    case relevance = "SEARCH_MATCH"

    public var localizedName: String {
        switch self {
        case .popularity: return "По популярности"
        case .trending: return "В тренде"
        case .score: return "По рейтингу"
        case .newest: return "Сначала новые"
        case .recentlyAdded: return "Недавно добавленные"
        case .title: return "По названию"
        case .relevance: return "По совпадению"
        }
    }

    /// Сортировки, которые имеет смысл показывать пользователю.
    public static var userSelectable: [CatalogSort] { [.relevance, .popularity, .trending, .score, .newest, .title] }
}

/// Параметры запроса каталога (поиск + фильтры + сортировка + страница).
///
/// Год задаётся диапазоном `yearFrom...yearTo` (обе границы включительно и опциональны).
/// В AniList это `startDate_greater` / `startDate_lesser` в формате FuzzyDateInt (YYYYMMDD),
/// поэтому одиночный год — это диапазон с совпадающими границами.
public struct CatalogQuery: Hashable, Codable, Sendable {
    /// Начальный/конечный год фильтра `startDate_greater`/`startDate_lesser` в формате YYYYMMDD.
    ///
    /// Значение сравнивается как целое, поэтому `20130401 >= 20130101` и `20121231 < 20130101`,
    /// то есть границы корректно отсекают тайтлы по дате начала показа.
    public enum YearBound: Hashable, Sendable {
        case from(Int)
        case to(Int)

        /// Год границы (то, что ввёл пользователь).
        public var year: Int {
            switch self {
            case .from(let year), .to(let year): return year
            }
        }
    }

    public var search: String
    public var genres: Set<String>
    public var yearFrom: Int?
    public var yearTo: Int?
    public var season: AnimeSeason?
    public var status: AiringStatus?
    public var formats: Set<AnimeFormat>
    public var sort: CatalogSort
    public var page: Int
    public var perPage: Int

    public init(search: String = "", genres: Set<String> = [], year: Int? = nil, yearFrom: Int? = nil,
                yearTo: Int? = nil, season: AnimeSeason? = nil,
                status: AiringStatus? = nil, formats: Set<AnimeFormat> = [], sort: CatalogSort = .popularity,
                page: Int = 1, perPage: Int = 30) {
        self.search = search
        self.genres = genres
        // `year:` — удобство для точного года (диапазон с равными границами).
        self.yearFrom = yearFrom ?? year
        self.yearTo = yearTo ?? year
        self.season = season
        self.status = status
        self.formats = formats
        self.sort = sort
        self.page = page
        self.perPage = perPage
    }

    /// Точный год как диапазон (`yearFrom == yearTo`). `nil`, если диапазон не вырожден.
    public var year: Int? {
        get { yearFrom == yearTo ? yearFrom : nil }
        set { yearFrom = newValue; yearTo = newValue }
    }

    /// Диапазон лет в виде `ClosedRange`, если заданы обе границы.
    public var yearRange: ClosedRange<Int>? {
        guard let yearFrom, let yearTo, yearFrom <= yearTo else { return nil }
        return yearFrom...yearTo
    }

    /// Границы для AniList: `startDate_greater` и `startDate_lesser` в FuzzyDateInt.
    public var yearBounds: [YearBound] {
        var bounds: [YearBound] = []
        if let yearFrom { bounds.append(.from(yearFrom)) }
        if let yearTo { bounds.append(.to(yearTo)) }
        return bounds
    }

    public var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Сортировка с учётом поиска: «по совпадению» без текста запроса бессмысленна.
    public var effectiveSort: CatalogSort {
        if sort == .relevance && trimmedSearch.isEmpty { return .popularity }
        return sort
    }

    public var hasActiveFilters: Bool {
        !genres.isEmpty || yearFrom != nil || yearTo != nil || status != nil || !formats.isEmpty || season != nil
    }

    public func withPage(_ page: Int) -> CatalogQuery {
        var copy = self
        copy.page = page
        return copy
    }

    /// Валидация пользовательского ввода перед отправкой во внешний API.
    public func validated(currentYear: Int = Calendar.utcGregorian.component(.year, from: Date())) -> CatalogQuery {
        var copy = self
        copy.search = String(trimmedSearch.prefix(100))
        // Год ограничен разумным окном (первое аниме — 1917) и «текущий год + 2» для анонсов.
        let lower = 1917, upper = currentYear + 2
        if let from = copy.yearFrom, !(lower...upper).contains(from) { copy.yearFrom = nil }
        if let to = copy.yearTo, !(lower...upper).contains(to) { copy.yearTo = nil }
        // Перевёрнутый диапазон (from > to) не может ничего вернуть — не отправляем его.
        if let from = copy.yearFrom, let to = copy.yearTo, from > to {
            copy.yearFrom = nil
            copy.yearTo = nil
        }
        copy.page = max(1, min(page, 500))
        copy.perPage = max(1, min(perPage, 50))
        copy.genres = Set(genres.prefix(10).map { String($0.prefix(40)) })
        if copy.status == .unknown { copy.status = nil }
        return copy
    }
}

public struct CatalogPage: Hashable, Sendable {
    public let items: [Anime]
    public let page: Int
    public let hasNextPage: Bool
    public init(items: [Anime], page: Int, hasNextPage: Bool) {
        self.items = items
        self.page = page
        self.hasNextPage = hasNextPage
    }
}

public struct HomeFeed: Hashable, Sendable {
    public let popular: [Anime]
    public let seasonal: [Anime]
    public let trending: [Anime]
    public let recentlyAdded: [Anime]
    public let seasonLabel: String
    public init(popular: [Anime], seasonal: [Anime], trending: [Anime], recentlyAdded: [Anime], seasonLabel: String) {
        self.popular = popular
        self.seasonal = seasonal
        self.trending = trending
        self.recentlyAdded = recentlyAdded
        self.seasonLabel = seasonLabel
    }
}

/// Недавно вышедшая серия (по расписанию AniList).
public struct AiredEpisode: Hashable, Sendable, Identifiable {
    public var id: String { "\(anime.id)-\(episode)" }
    public let anime: Anime
    public let episode: Int
    public let airedAt: Date
    public init(anime: Anime, episode: Int, airedAt: Date) {
        self.anime = anime
        self.episode = episode
        self.airedAt = airedAt
    }
}
