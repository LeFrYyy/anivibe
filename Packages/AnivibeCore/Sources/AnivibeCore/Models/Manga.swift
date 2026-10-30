import Foundation

/// Формат печатного первоисточника (Shikimori `kind`).
public enum MangaFormat: String, Codable, CaseIterable, Sendable {
    case manga, manhwa, manhua, lightNovel = "light_novel", novel
    case oneShot = "one_shot", doujin, ranobe

    public init(apiValue: String?) {
        self = apiValue.flatMap(MangaFormat.init(rawValue:)) ?? .manga
    }

    public var localizedName: String {
        switch self {
        case .manga: return "Манга"
        case .manhwa: return "Манхва"
        case .manhua: return "Маньхуа"
        case .lightNovel: return "Лайт-новелла"
        case .novel: return "Новелла"
        case .oneShot: return "Ваншот"
        case .doujin: return "Додзинси"
        case .ranobe: return "Ранобэ"
        }
    }
}

/// Статус публикации (Shikimori `status` для манги).
public enum MangaStatus: String, Codable, Sendable {
    case anons, ongoing, released, paused, discontinued

    public init(apiValue: String?) {
        self = apiValue.flatMap(MangaStatus.init(rawValue:)) ?? .ongoing
    }

    public var localizedName: String {
        switch self {
        case .anons: return "Анонс"
        case .ongoing: return "Выходит"
        case .released: return "Завершена"
        case .paused: return "Пауза"
        case .discontinued: return "Прекращена"
        }
    }
}

/// Манга/ранобэ. Идентификатор = Shikimori ID (= MAL manga ID); через `animeMALIDs`
/// связана с аниме-адаптациями — манга обычно первоисточник.
public struct Manga: Identifiable, Hashable, Codable, Sendable {
    public var id: Int
    public var title: AnimeTitle
    public var synonyms: [String]
    public var searchAliases: [String]?
    public var synopsis: String?
    public var synopsisOriginal: String?
    public var synopsisSource: String?
    public var coverURL: URL?
    public var year: Int?
    public var genres: [String]
    public var status: MangaStatus?
    public var format: MangaFormat?
    public var volumes: Int?
    public var chapters: Int?
    /// Оценка Shikimori 0–10.
    public var score: Double?
    /// ID аниме-адаптаций этой манги (Shikimori/MAL anime ID) — где манга первоисточник.
    public var animeMALIDs: [Int]
    /// ID записи на MangaDex (источник глав на русском).
    public var mangadexID: String?

    public init(id: Int, title: AnimeTitle, synonyms: [String] = [], synopsis: String? = nil,
                coverURL: URL? = nil, year: Int? = nil, genres: [String] = [],
                status: MangaStatus? = nil, format: MangaFormat? = nil,
                volumes: Int? = nil, chapters: Int? = nil, score: Double? = nil,
                animeMALIDs: [Int] = [], mangadexID: String? = nil) {
        self.id = id
        self.title = title
        self.synonyms = synonyms
        self.synopsis = synopsis
        self.coverURL = coverURL
        self.year = year
        self.genres = genres
        self.status = status
        self.format = format
        self.volumes = volumes
        self.chapters = chapters
        self.score = score
        self.animeMALIDs = animeMALIDs
        self.mangadexID = mangadexID
    }

    /// Все названия: официальные, синонимы, разговорные варианты и автоперевод.
    public var searchableTitles: [String] {
        var seen = Set<String>()
        return (title.all + synonyms + (searchAliases ?? [])).filter { seen.insert($0.lowercased()).inserted }
    }

    /// «2019 · Манга · 34 т.» — только известные значения.
    public var metaLine: String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if let format { parts.append(format.localizedName) }
        if let volumes { parts.append("\(volumes) т.") } else if let chapters { parts.append("\(chapters) гл.") }
        return parts.joined(separator: " · ")
    }

    /// Оценка 0–10 → «★ 8.7».
    public var scoreText: String? {
        score.map { "★ " + String(format: "%.1f", $0) }
    }
}

public struct MangaPage: Hashable, Sendable {
    public var items: [Manga]
    public var page: Int
    public var hasNextPage: Bool

    public init(items: [Manga], page: Int, hasNextPage: Bool) {
        self.items = items
        self.page = page
        self.hasNextPage = hasNextPage
    }
}

/// Глава манги на русском (источник — MangaDex или внешний сайт).
public struct MangaChapter: Hashable, Sendable, Identifiable {
    /// ID главы у источника (MangaDex UUID); для внешних ссылок — сам URL.
    public var id: String
    public var number: Double?
    public var volume: Double?
    public var title: String?
    /// Сканлейтор/группа перевода.
    public var group: String?
    public var pageCount: Int
    /// Ссылка на внешнего читалку (если глава не читается прямо в приложении).
    public var externalURL: URL?

    public init(id: String, number: Double?, volume: Double?, title: String?,
                group: String?, pageCount: Int, externalURL: URL? = nil) {
        self.id = id
        self.number = number
        self.volume = volume
        self.title = title
        self.group = group
        self.pageCount = pageCount
        self.externalURL = externalURL
    }

    /// «Гл. 10 — Спасение» или «Гл. 10»; без номера — «Спешл».
    public var displayTitle: String {
        let base = number.map { n in "Гл. \(n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n))" } ?? "Спешл"
        return title.map { base + " — " + $0 } ?? base
    }

    /// «Т. 2» или пусто.
    public var volumeText: String? {
        volume.map { "Т. " + ($0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0)) }
    }
}
