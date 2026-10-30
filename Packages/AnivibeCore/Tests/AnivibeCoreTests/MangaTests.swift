import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

/// Манга: Shikimori-каталог, MangaDex-главы и связь первоисточник↔аниме.
final class MangaTests: XCTestCase {

    private let listJSON = """
    [{"id":23390,"name":"Shingeki no Kyojin","russian":"Атака титанов",
      "image":{"original":"/system/mangas/original/23390.jpg","preview":"/system/mangas/preview/23390.jpg"},
      "kind":"manga","status":"released","volumes":34,"chapters":141,"score":"9.0",
      "aired_on":"2009-09-09","genres":[{"name":"Action","russian":"Экшен","kind":"genre"}],
      "synonyms":["Вторжение гигантов","AoT"],"english":["Attack on Titan"],"japanese":["進撃の巨人"],
      "description":"<div>Описание</div>"},
     {"id":116778,"name":"Chainsaw Man","russian":null,
      "image":{"original":"/system/mangas/original/116778.jpg"},
      "kind":"manga","status":"ongoing","volumes":0,"chapters":0,"score":"8.5",
      "aired_on":"2018-12-03","genres":[],"synonyms":[],"english":["Chainsaw Man"],"japanese":["チェンソーマン"],
      "description":null}]
    """

    private func shikimori(_ list: String, related: String = "[]") -> StubTransport {
        StubTransport { request in
            if request.url!.path.contains("/related") { return (200, Data(related.utf8), [:]) }
            return (200, Data(list.utf8), [:])
        }
    }

    func testShikimoriListDecodingAndLocalization() async throws {
        let service = ShikimoriMangaService(transport: shikimori(listJSON), cache: MetadataCache(directory: nil))
        let page = try await service.list(page: 1, limit: 30)
        XCTAssertEqual(page.items.count, 2)
        let titan = try XCTUnwrap(page.items.first)
        XCTAssertEqual(titan.id, 23390)
        XCTAssertEqual(titan.title.russian, "Атака титанов")
        XCTAssertEqual(titan.title.russianSource, .shikimori)
        XCTAssertEqual(titan.coverURL?.absoluteString, "https://shikimori.io/system/mangas/original/23390.jpg")
        XCTAssertEqual(titan.volumes, 34)
        XCTAssertEqual(titan.chapters, 141)
        XCTAssertEqual(titan.score, 9.0)
        XCTAssertEqual(titan.genres, ["Экшен"])
        XCTAssertEqual(titan.year, 2009)
        // У Chainsaw Man нет официального русского — автоперевод помечается.
        let chainsaw = page.items[1]
        XCTAssertNotNil(chainsaw.title.russian)
        XCTAssertEqual(chainsaw.title.russianSource, .automatic)
        XCTAssertTrue(chainsaw.title.isRussianAutomatic)
    }

    func testAdaptationsFromRelated() async throws {
        let related = """
        [{"relation":"Spin-off","anime":null,"manga":{"id":43999}},
         {"relation":"Adaptation","anime":{"id":16498},"manga":null},
         {"relation":"Adaptation","anime":{"id":19391},"manga":null},
         {"relation":"Adaptation","anime":{"id":16498},"manga":null},
         {"relation":"Alternative Version","anime":null,"manga":{"id":58203}}]
        """
        let service = ShikimoriMangaService(transport: shikimori(listJSON, related: related), cache: MetadataCache(directory: nil))
        let ids = try await service.adaptations(of: 23390)
        XCTAssertEqual(ids, [16498, 19391])
    }

    func testDetailsIncludesAdaptations() async throws {
        let detailJSON = """
        {"id":23390,"name":"Shingeki no Kyojin","russian":"Атака титанов",
         "image":{"original":"/system/mangas/original/23390.jpg"},
         "kind":"manga","status":"released","volumes":34,"chapters":141,"score":"9.0",
         "aired_on":"2009-09-09","genres":[],"synonyms":[],"english":[],"japanese":[],"description":null}
        """
        let related = """
        [{"relation":"Adaptation","anime":{"id":16498},"manga":null}]
        """
        let transport = StubTransport { request in
            if request.url!.path.contains("/related") { return (200, Data(related.utf8), [:]) }
            return (200, Data(detailJSON.utf8), [:])
        }
        let service = ShikimoriMangaService(transport: transport, cache: MetadataCache(directory: nil))
        let manga = try await service.details(id: 23390)
        XCTAssertEqual(manga.animeMALIDs, [16498])
        XCTAssertEqual(manga.title.russian, "Атака титанов")
    }

    // MARK: - MangaDex

    private let mangadexSearch = """
    {"result":"ok","response":"collection","total":2,
     "data":[
       {"id":"00000000-0000-0000-0000-000000000001","type":"manga",
        "attributes":{"title":{"en":"Shingeki no Kyojin"},"altTitles":[{"ru":"Атака титанов"}],
         "description":{"en":"..."},"year":2009,"status":"completed","links":{"mal":"23390","al":"53390"}},
        "relationships":[{"type":"cover_art","attributes":{"fileName":"cover.jpg"}}]},
       {"id":"00000000-0000-0000-0000-000000000002","type":"manga",
        "attributes":{"title":{"en":"Other"},"altTitles":[],"description":{},"links":{}},
        "relationships":[]}]}
    """

    private let mangadexFeed = """
    {"result":"ok","response":"collection","total":4,
     "data":[
       {"id":"ch2","type":"chapter",
        "attributes":{"chapter":"2","volume":"1","title":"Тень","translatedLanguage":"ru","pages":40,
         "externalUrl":null,"publishAt":"2020-01-02T00:00:00+00:00"},
        "relationships":[{"type":"scanlation_group","attributes":{"name":"RuGroup"}}]},
       {"id":"ch1","type":"chapter",
        "attributes":{"chapter":"1","volume":"1","title":null,"translatedLanguage":"ru","pages":38,
         "externalUrl":null,"publishAt":"2020-01-01T00:00:00+00:00"},
        "relationships":[]},
       {"id":"ch1b","type":"chapter",
        "attributes":{"chapter":"1","volume":"1","title":null,"translatedLanguage":"ru","pages":45,
         "externalUrl":null,"publishAt":"2020-01-03T00:00:00+00:00"},
        "relationships":[{"type":"scanlation_group","attributes":{"name":"Better"}}]},
       {"id":"chx","type":"chapter",
        "attributes":{"chapter":null,"volume":null,"title":"Экстра","translatedLanguage":"ru","pages":0,
         "externalUrl":"https://example.com/x","publishAt":"2020-01-04T00:00:00+00:00"},
        "relationships":[]}]}
    """

    func testMangaDexMappingByMAL() async throws {
        let transport = StubTransport { request in
            XCTAssertTrue(request.url!.absoluteString.contains("api.mangadex.org"))
            return (200, Data(self.mangadexSearch.utf8), [:])
        }
        let service = MangaDexService(transport: transport, cache: MetadataCache(directory: nil))
        let id = await service.mangadexID(forMALID: 23390, titles: ["Shingeki no Kyojin", "Атака титанов"])
        XCTAssertEqual(id, "00000000-0000-0000-0000-000000000001")
    }

    func testChapterDedupeAndSort() {
        let chapters = [
            MangaChapter(id: "b", number: 2, volume: 1, title: "B", group: nil, pageCount: 10),
            MangaChapter(id: "a1", number: 1, volume: 1, title: nil, group: nil, pageCount: 10),
            MangaChapter(id: "a2", number: 1, volume: 1, title: nil, group: "Better", pageCount: 45),
            MangaChapter(id: "x", number: nil, volume: nil, title: "Экстра", group: nil, pageCount: 0)
        ]
        let deduped = MangaDexService.dedupe(chapters)
        XCTAssertEqual(deduped.map(\.id), ["a2", "b", "x"])
        XCTAssertEqual(deduped[0].displayTitle, "Гл. 1")
        XCTAssertEqual(deduped[1].displayTitle, "Гл. 2 — B")
        XCTAssertEqual(deduped[2].displayTitle, "Спешл — Экстра")
    }

    func testChapterFeedAndExternalLinks() async throws {
        let transport = StubTransport { request in
            if request.url!.path.contains("/feed") { return (200, Data(self.mangadexFeed.utf8), [:]) }
            return (404, Data(), [:])
        }
        let service = MangaDexService(transport: transport, cache: MetadataCache(directory: nil))
        let chapters = try await service.chapters(mangadexID: "uuid", language: "ru")
        // глава 1 дедуплицирована по максимуму страниц (45 > 38)
        XCTAssertEqual(chapters.map(\.id), ["ch1b", "ch2", "chx"])
        XCTAssertEqual(chapters[0].group, "Better")
        XCTAssertEqual(chapters[2].externalURL, URL(string: "https://example.com/x"))
        let request = transport.requests.first { $0.url!.path.contains("/feed") }!
        XCTAssertTrue(request.url!.absoluteString.contains("translatedLanguage%5B%5D=ru"))
    }

    func testAtHomePageURLs() async throws {
        let atHome = """
        {"result":"ok","baseUrl":"https://uploads.mangadex.org",
         "chapter":{"hash":"abc123","data":["p1.jpg","p2.png"],"dataSaver":["p1.s.jpg","p2.s.jpg"]}}
        """
        let transport = StubTransport { _ in (200, Data(atHome.utf8), [:]) }
        let service = MangaDexService(transport: transport, cache: MetadataCache(directory: nil))
        let urls = try await service.pageURLs(chapterID: "ch1")
        XCTAssertEqual(urls.map(\.absoluteString),
                       ["https://uploads.mangadex.org/data/abc123/p1.jpg",
                        "https://uploads.mangadex.org/data/abc123/p2.png"])
        let saver = try await service.pageURLs(chapterID: "ch1", dataSaver: true)
        XCTAssertEqual(saver.first?.absoluteString, "https://uploads.mangadex.org/data-saver/abc123/p1.s.jpg")
    }

    // MARK: - MangaHub + связь с аниме

    func testHubSearchFallsBackToTransliteration() async throws {
        let transport = StubTransport { request in
            if request.url!.absoluteString.contains("search=vanpanchmen") {
                return (200, Data(self.listJSON.utf8), [:])
            }
            return (200, Data("[]".utf8), [:])
        }
        let hub = MangaHub(catalog: ShikimoriMangaService(transport: transport, cache: MetadataCache(directory: nil)),
                           lib: LibSocialService(transport: StubTransport { _ in (404, Data(), [:]) }, cache: MetadataCache(directory: nil)),
                           reader: MangaDexService(transport: StubTransport { _ in (404, Data(), [:]) }, cache: MetadataCache(directory: nil)),
                           cache: MetadataCache(directory: nil))
        let page = try await hub.search("ванпанчмен", page: 1, limit: 30)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(page.items.count, 2)
    }

    func testHubChaptersResolveMapping() async throws {
        let transport = StubTransport { request in
            let path = request.url!.path
            if path.contains("/feed") { return (200, Data(self.mangadexFeed.utf8), [:]) }
            return (200, Data(self.mangadexSearch.utf8), [:])
        }
        let hub = MangaHub(catalog: ShikimoriMangaService(transport: StubTransport { _ in (404, Data(), [:]) }, cache: MetadataCache(directory: nil)),
                           lib: LibSocialService(transport: StubTransport { _ in (404, Data("{}".utf8), [:]) }, cache: MetadataCache(directory: nil)),
                           reader: MangaDexService(transport: transport, cache: MetadataCache(directory: nil)),
                           cache: MetadataCache(directory: nil))
        var manga = Manga(id: 23390, title: AnimeTitle(romaji: "Shingeki no Kyojin", russian: "Атака титанов"))
        let chapters = try await hub.chapters(of: manga)
        XCTAssertEqual(chapters.count, 3)
        manga.mangadexID = nil
    }

    // MARK: - Первоисточник в деталях аниме

    func testAnimeDetailsSourceRelation() {
        let sourceAnime = Anime(id: 5, title: AnimeTitle(romaji: "Shingeki no Kyojin"), malID: 23390)
        let sequel = Anime(id: 6, title: AnimeTitle(romaji: "Shingeki S2"), malID: 18179)
        let details = AnimeDetails(anime: Anime(id: 1, title: AnimeTitle(romaji: "Shingeki no Kyojin")),
                                   relations: [
                                       RelatedAnime(relation: .source, anime: sourceAnime),
                                       RelatedAnime(relation: .sequel, anime: sequel)
                                   ])
        XCTAssertEqual(details.sourceRelation?.anime.malID, 23390)
        XCTAssertEqual(details.sourceRelation?.relation, .source)
    }

    func testMangaMetaLineAndCodable() throws {
        let manga = Manga(id: 1, title: AnimeTitle(romaji: "Berserk", russian: "Берсерк"),
                          year: 1989, format: .manga, volumes: 41)
        XCTAssertEqual(manga.metaLine, "1989 · Манга · 41 т.")
        let data = try JSONEncoder().encode(manga)
        let decoded = try JSONDecoder().decode(Manga.self, from: data)
        XCTAssertEqual(decoded, manga)
    }
}

extension MangaTests {
    /// Реальный (live) контракт: у основной манги MAL-ссылка совпадает и есть ru-главы.
    /// Прогоняется только в LiveIntegrationTests-режиме (сеть).
    func testMangaDexSearchContractParsing() throws {
        let dto = try JSONDecoder().decode(MangaDexService.Response<MangaDexService.MangaDTO>.self,
                                           from: Data(mangadexSearch.utf8))
        let items = try XCTUnwrap(dto.data)
        XCTAssertEqual(items.first?.malID, 23390)
        XCTAssertEqual(items.first?.coverURL?.absoluteString,
                       "https://uploads.mangadex.org/covers/00000000-0000-0000-0000-000000000001/cover.jpg.512.jpg")
        XCTAssertTrue(items.first?.allTitles.contains("Атака титанов") ?? false)
    }
}
