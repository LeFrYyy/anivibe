import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

/// Реальные сетевые проверки. Запуск: `ANIVIBE_LIVE_TESTS=1 swift test --filter LiveIntegrationTests`.
/// По умолчанию пропускаются, чтобы не расходовать лимит AniList.
final class LiveIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ANIVIBE_LIVE_TESTS"] == "1", "Live-тесты отключены")
    }

    // Одна сессия на весь набор: на Linux создание множества URLSession иногда роняет
    // FoundationNetworking (libcurl). На iOS используется системный URLSession.
    static let transport = URLSessionTransport.standard()
    static let catalog = AniListCatalogService(transport: transport, cache: MetadataCache(directory: nil))
    private var catalog: AniListCatalogService { Self.catalog }

    func testAniListSearchWithFilters() async throws {
        let page = try await catalog.search(CatalogQuery(search: "Shingeki no Kyojin", sort: .relevance, perPage: 5))
        XCTAssertFalse(page.items.isEmpty)
        XCTAssertTrue(page.items.contains { $0.id == 16498 })

        let filtered = try await catalog.search(CatalogQuery(genres: ["Action"], year: 2019, status: .finished, formats: [.tv], sort: .popularity, perPage: 10))
        XCTAssertFalse(filtered.items.isEmpty)
        XCTAssertTrue(filtered.items.allSatisfy { $0.genres.contains("Action") && $0.status == .finished && $0.year == 2019 })

        let empty = try await catalog.search(CatalogQuery(search: "zzqxjv nonexistent anime title 12345"))
        XCTAssertTrue(empty.items.isEmpty)
    }

    func testAniListAlternativeTitleSearch() async throws {
        // Поиск по синониму/английскому названию.
        let page = try await catalog.search(CatalogQuery(search: "Attack on Titan", sort: .relevance, perPage: 5))
        XCTAssertTrue(page.items.contains { $0.id == 16498 })
    }

    func testAniListDetailsHomeAndGenres() async throws {
        let d = try await catalog.details(id: 16498)
        XCTAssertEqual(d.anime.episodeCount, 25)
        XCTAssertNotNil(d.anime.synopsis)
        XCTAssertFalse(d.otherSeasons.isEmpty)
        XCTAssertEqual(EpisodeListBuilder.build(from: d).episodes.count, 25)

        let feed = try await catalog.homeFeed()
        XCTAssertFalse(feed.popular.isEmpty)
        XCTAssertFalse(feed.trending.isEmpty)
        XCTAssertFalse(feed.recentlyAdded.isEmpty)

        let genres = try await catalog.genres()
        XCTAssertTrue(genres.contains("Action"))
        XCTAssertFalse(genres.contains("Hentai"))
    }

    func testTestStreamsAreReachableAndDeclareTracks() async throws {
        let provider = TestStreamProvider(transport: Self.transport)
        let eps = try await provider.episodes(for: ProviderTitle(id: "t", providerID: provider.id, titles: []))
        let bipbop = try await provider.resolve(eps[0])
        XCTAssertEqual(bipbop.audioTracks.count, 2)
        XCTAssertGreaterThanOrEqual(bipbop.subtitleTracks.count, 2)
        let bbb = try await provider.resolve(eps[1])
        XCTAssertEqual(bbb.kind, .hls)
        let registry = ProviderRegistry(providers: [provider])
        let candidates = await registry.candidates(for: makeAnime(), episode: 1)
        XCTAssertTrue(candidates.first?.availability.isAvailable ?? false)
    }

    /// Сквозная проверка: настоящий AniList → настоящая Anilibria (с зеркалами).
    func testAnilibriaMatchesByMalIDLive() async throws {
        let anilibria = AnilibriaProvider(transport: Self.transport)
        // Code Geass R1 / R2 — должны попасть точно в свои релизы.
        let r1 = try await catalog.details(id: 1575).anime
        XCTAssertEqual(r1.malID, 1575)
        let m1 = try await anilibria.match(anime: r1)
        XCTAssertEqual(m1?.malID, 1575)
        print("LIVE R1:", m1?.id ?? "nil", m1?.titles ?? [])
        let r2 = try await catalog.details(id: 2904).anime
        let m2 = try await anilibria.match(anime: r2)
        XCTAssertEqual(m2?.malID, 2904)
        print("LIVE R2:", m2?.id ?? "nil", m2?.titles ?? [])
        // Black Clover 2nd Season: у Anilibria его нет — никаких подмен.
        let bc = try await catalog.details(id: 195604).anime
        let mbc = try await anilibria.match(anime: bc)
        print("LIVE Black Clover S2: mal=\(bc.malID ?? -1) aired=\(bc.airedEpisodesText ?? "-") match=\(mbc?.id ?? "nil") \(mbc?.titles ?? [])")
        if let mbc { XCTAssertEqual(mbc.malID, bc.malID, "подставлен чужой тайтл: \(mbc.titles)") }
    }
}

