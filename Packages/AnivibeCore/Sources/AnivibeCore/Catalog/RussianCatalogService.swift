import Foundation

/// AniList remains the canonical ID/format/filter catalogue; Russian metadata is best-effort.
public actor RussianCatalogService: CatalogService {
    public let name = "AniList + Shikimori"
    public let isDemo = false
    private let catalog: AniListCatalogService
    private let metadata: RussianMetadataService
    private let cache: MetadataCache
    public init(catalog: AniListCatalogService, metadata: RussianMetadataService, cache: MetadataCache) {
        self.catalog = catalog; self.metadata = metadata; self.cache = cache
    }
    public func search(_ input: CatalogQuery) async throws -> CatalogPage {
        let q = input.validated()
        let base: CatalogPage
        var primaryError: Error?
        do { base = try await catalog.search(q) }
        catch {
            if Task.isCancelled { throw APIError.cancelled }
            guard !q.trimmedSearch.isEmpty else { throw error }
            primaryError = error
            base = CatalogPage(items: [], page: q.page, hasNextPage: false)
        }
        var items = await localize(base.items)
        var russianHasMore = false
        if !q.trimmedSearch.isEmpty {
            let hasCyrillic = q.trimmedSearch.range(of: #"[А-Яа-яЁё]"#, options: .regularExpression) != nil
            let dictionaryHits = q.page == 1 ? RussianTitleDictionary.matches(query: q.trimmedSearch, limit: q.perPage) : []
            var matches = (try? await metadata.search(q.trimmedSearch, page: q.page, limit: q.perPage)) ?? []
            if matches.isEmpty, hasCyrillic {
                // Запрос на русском, Shikimori не нашёл: пробуем ромадзи из словаря, затем транслит («Ванпанчмен» → «vanpanchmen»).
                for variant in Self.queryVariants(q.trimmedSearch, hits: dictionaryHits) where matches.isEmpty {
                    matches = (try? await metadata.search(variant, page: q.page, limit: q.perPage)) ?? []
                }
            }
            russianHasMore = matches.count == q.perPage
            let byMetadataID = Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var wanted = matches.map(\.id)
            let strongHits = dictionaryHits.filter { $0.score >= 500 }.map(\.entry.malID)
            wanted += strongHits.filter { !byMetadataID.keys.contains($0) }
            let known = Set(items.compactMap(\.malID))
            var seenIDs = Set<Int>()
            wanted = wanted.filter { !known.contains($0) && seenIDs.insert($0).inserted }
            if !wanted.isEmpty, let mapped = try? await catalog.anime(malIDs: Array(wanted.prefix(50))) {
                items += mapped.map { anime in anime.malID.flatMap { byMetadataID[$0] }?.apply(to: anime) ?? anime }
            }
            if q.page == 1, let data = await cache.data(for: "russian-name-index"), let known = try? JSONDecoder().decode([Anime].self, from: data) {
                items += known.filter { CatalogSearchRanking.score(query: q.trimmedSearch, anime: $0) > 0 }
            }
        }
        try Task.checkCancellation()
        if items.isEmpty, let primaryError { throw primaryError }
        items = RussianTitleTranslator.localize(items)
        var byID: [Int: Anime] = [:]
        for anime in items where Self.accepts(anime, query: q) {
            if byID[anime.id] == nil || (anime.title.russian != nil && byID[anime.id]?.title.russian == nil) { byID[anime.id] = anime }
        }
        let sorted = byID.values.sorted { a, b in
            switch q.effectiveSort {
            case .relevance:
                let sa = CatalogSearchRanking.score(query: q.trimmedSearch, anime: a), sb = CatalogSearchRanking.score(query: q.trimmedSearch, anime: b)
                if sa != sb { return sa > sb }
            case .title: return a.title.preferred.localizedStandardCompare(b.title.preferred) == .orderedAscending
            case .score: if a.averageScore != b.averageScore { return (a.averageScore ?? 0) > (b.averageScore ?? 0) }
            case .recentlyAdded: return a.id > b.id
            case .newest: if a.year != b.year { return (a.year ?? 0) > (b.year ?? 0) }
            default: break
            }
            // Keep AniList's ranking where it knows popularity/trending; deterministic tie fallback.
            let ia = items.firstIndex { $0.id == a.id } ?? Int.max, ib = items.firstIndex { $0.id == b.id } ?? Int.max
            return ia == ib ? a.id < b.id : ia < ib
        }
        await remember(sorted)
        return CatalogPage(items: sorted, page: base.page, hasNextPage: base.hasNextPage || russianHasMore)
    }
    public func details(id: Int) async throws -> AnimeDetails {
        var details = try await catalog.details(id: id)
        if let malID = details.anime.malID, let russian = try? await metadata.details(malID: malID) {
            details.anime = russian.apply(to: details.anime)
        }
        details.anime = RussianTitleTranslator.localize(details.anime)
        details.relations = details.relations.map { RelatedAnime(relation: $0.relation, anime: RussianTitleTranslator.localize($0.anime)) }
        try Task.checkCancellation()
        await remember([details.anime])
        return details
    }
    public func homeFeed() async throws -> HomeFeed {
        let home = try await catalog.homeFeed()
        let all = home.popular + home.seasonal + home.trending + home.recentlyAdded
        let localized = await localize(all)
        let byID = Dictionary(localized.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func list(_ items: [Anime]) -> [Anime] { items.map { byID[$0.id] ?? $0 } }
        return HomeFeed(popular: list(home.popular), seasonal: list(home.seasonal), trending: list(home.trending),
                        recentlyAdded: list(home.recentlyAdded), seasonLabel: home.seasonLabel)
    }
    public func genres() async throws -> [String] { try await catalog.genres() }
    public func recentEpisodes() async throws -> [AiredEpisode] { try await catalog.recentEpisodes() }
    private func localize(_ items: [Anime]) async -> [Anime] {
        var byID: [Int: RussianMetadataService.Metadata] = [:]
        let ids = Array(Set(items.compactMap(\.malID))).sorted()
        for offset in stride(from: 0, to: ids.count, by: 50) {
            let group = Array(ids[offset..<min(ids.count, offset + 50)])
            for metadata in (try? await metadata.titles(malIDs: group)) ?? [] { byID[metadata.id] = metadata }
        }
        let localized = RussianTitleTranslator.localize(items.map { anime in anime.malID.flatMap { byID[$0] }?.apply(to: anime) ?? anime })
        await remember(localized)
        return localized
    }

    /// Варианты запроса для Shikimori, когда поиск по русскому тексту ничего не дал.
    static func queryVariants(_ text: String, hits: [(entry: RussianTitleDictionary.Entry, score: Int)]) -> [String] {
        var variants: [String] = []
        for hit in hits.prefix(2) where hit.score >= 500 { variants.append(hit.entry.romaji) }
        let latin = CatalogSearchRanking.transliterate(text)
        if latin != text { variants.append(latin) }
        return variants
    }
    private func remember(_ items: [Anime]) async {
        let known: [Anime]
        if let data = await cache.data(for: "russian-name-index"), let decoded = try? JSONDecoder().decode([Anime].self, from: data) { known = decoded }
        else { known = [] }
        var seen = Set<Int>()
        let recent = (items + known).filter { seen.insert($0.id).inserted }.prefix(500)
        if let data = try? JSONEncoder().encode(Array(recent)) { await cache.store(data, for: "russian-name-index") }
    }
    private static func accepts(_ anime: Anime, query: CatalogQuery) -> Bool {
        (query.year == nil || query.year == anime.year) && (query.season == nil || query.season == anime.season)
        && (query.status == nil || query.status == anime.status)
        && (query.formats.isEmpty || anime.format.map { query.formats.contains($0) } == true)
        && query.genres.isSubset(of: Set(anime.genres))
    }
}
