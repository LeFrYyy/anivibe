import Foundation

/// Демонстрационный каталог — ТОЛЬКО для режима разработки (флаг ANIVIBE_DEMO_CATALOG).
/// Содержит вымышленные тайтлы с явной пометкой «Демо», без постеров и чужих материалов.
public final class DemoCatalogService: CatalogService, @unchecked Sendable {
    public let name = "Демо-каталог"
    public let isDemo = true

    public static let items: [Anime] = [
        Anime(id: 900_001, title: AnimeTitle(romaji: "Demo: Hoshi no Kioku", english: "Демо: Память звёзд"),
              synonyms: ["Star Memory Demo"], synopsis: "Вымышленный тайтл для проверки интерфейса в режиме разработки.",
              year: 2024, genres: ["Drama", "Sci-Fi"], status: .finished, format: .tv, averageScore: 78, episodeCount: 12, episodeDurationMinutes: 24),
        Anime(id: 900_002, title: AnimeTitle(romaji: "Demo: Kaze no Michi", english: "Демо: Дорога ветра"),
              synonyms: ["Wind Road Demo"], synopsis: "Вымышленный онгоинг для проверки статусов и неполного списка серий.",
              year: 2026, genres: ["Adventure", "Fantasy"], status: .releasing, format: .tv, averageScore: nil, episodeCount: nil, nextAiringEpisode: 6),
        Anime(id: 900_003, title: AnimeTitle(romaji: "Demo: Yoru no Kissaten", english: "Демо: Ночное кафе"),
              synopsis: "Вымышленный фильм без данных о рейтинге.",
              year: 2023, genres: ["Slice of Life"], status: .finished, format: .movie, episodeCount: 1, episodeDurationMinutes: 95),
        Anime(id: 900_004, title: AnimeTitle(romaji: "Demo: Mirai Kouhai", english: "Демо: Анонс"),
              synopsis: "Вымышленный анонс — серий пока нет.",
              year: 2027, genres: ["Comedy"], status: .notYetReleased, format: .tv)
    ]

    public init() {}

    public func search(_ query: CatalogQuery) async throws -> CatalogPage {
        let q = query.validated()
        var result = Self.items.filter { anime in
            TitleMatcher.matches(query: q.trimmedSearch, titles: anime.allTitles)
                && (q.genres.isEmpty || q.genres.isSubset(of: Set(anime.genres)))
                && (q.year == nil || anime.year == q.year)
                && (q.status == nil || anime.status == q.status)
                && (q.formats.isEmpty || anime.format.map(q.formats.contains) == true)
        }
        switch q.effectiveSort {
        case .score: result.sort { ($0.averageScore ?? -1) > ($1.averageScore ?? -1) }
        case .newest: result.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .title: result.sort { $0.title.preferred < $1.title.preferred }
        default: break
        }
        let start = (q.page - 1) * q.perPage
        let slice = start < result.count ? Array(result[start..<min(result.count, start + q.perPage)]) : []
        return CatalogPage(items: slice, page: q.page, hasNextPage: start + q.perPage < result.count)
    }

    public func details(id: Int) async throws -> AnimeDetails {
        guard let anime = Self.items.first(where: { $0.id == id }) else { throw APIError.notFound }
        return AnimeDetails(anime: anime, recommendations: Self.items.filter { $0.id != id })
    }

    public func homeFeed() async throws -> HomeFeed {
        HomeFeed(popular: Self.items, seasonal: Self.items.filter { $0.status == .releasing },
                 trending: Self.items.reversed(), recentlyAdded: Self.items, seasonLabel: "Демо-сезон")
    }

    public func genres() async throws -> [String] {
        Array(Set(Self.items.flatMap(\.genres))).sorted()
    }
}
