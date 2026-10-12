import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

final class AnilibriaTests: XCTestCase {

    /// Формат ответа GET /api/v1/app/search/releases?query=... (снят с живого API 11.10.2026).
    static let searchFixture = """
    [
      {
        "id": 8789,
        "type": {"value": "TV", "description": "ТВ"},
        "year": 2020,
        "name": {"main": "Магическая битва", "english": "Jujutsu Kaisen", "alternative": null},
        "alias": "jujutsu-kaisen",
        "episodes_total": 24
      },
      {
        "id": 9999,
        "type": {"value": "TV", "description": "ТВ"},
        "year": 2024,
        "name": {"main": "Совершенно другой тайтл", "english": "Unrelated Show", "alternative": null},
        "alias": "unrelated-show"
      }
    ]
    """

    /// Формат ответа GET /api/v1/anime/releases/{id} (снят с живого API, сокращён).
    static let releaseFixture = """
    {
      "id": 8789,
      "name": {"main": "Магическая битва", "english": "Jujutsu Kaisen", "alternative": null},
      "is_blocked_by_geo": false,
      "is_blocked_by_copyrights": false,
      "episodes_total": 3,
      "episodes": [
        {
          "id": "95d6e739-789e-11ec-ae92-0242ac120002",
          "name": null,
          "ordinal": 1,
          "hls_480": "https://cache.libria.fun/videos/media/ts/8789/1/480/aaa.m3u8",
          "hls_720": "https://cache.libria.fun/videos/media/ts/8789/1/720/bbb.m3u8",
          "hls_1080": "https://cache.libria.fun/videos/media/ts/8789/1/1080/ccc.m3u8",
          "duration": 1435
        },
        {
          "id": "96000000-789e-11ec-ae92-0242ac120002",
          "name": "Название второй серии",
          "ordinal": 2,
          "hls_480": "https://cache.libria.fun/videos/media/ts/8789/2/480/ddd.m3u8",
          "hls_720": "https://cache.libria.fun/videos/media/ts/8789/2/720/eee.m3u8",
          "hls_1080": null,
          "duration": 1420
        },
        {
          "id": "97000000-789e-11ec-ae92-0242ac120002",
          "name": "PV",
          "ordinal": 2.5,
          "hls_480": null, "hls_720": "https://cache.libria.fun/x.m3u8", "hls_1080": null
        },
        {
          "id": "98000000-789e-11ec-ae92-0242ac120002",
          "name": null,
          "ordinal": 3,
          "hls_480": null, "hls_720": null, "hls_1080": null
        }
      ]
    }
    """

    static let blockedReleaseFixture = """
    {
      "id": 5555,
      "name": {"main": "Заблокированный", "english": null, "alternative": null},
      "is_blocked_by_geo": false,
      "is_blocked_by_copyrights": true,
      "episodes": []
    }
    """

    private func makeProvider(_ handler: @escaping StubTransport.Handler) -> (AnilibriaProvider, StubTransport) {
        let transport = StubTransport(handler: handler)
        return (AnilibriaProvider(transport: transport), transport)
    }

    private func route(_ request: URLRequest) -> (Int, Data, [String: String]) {
        let path = request.url?.path ?? ""
        if path.contains("/app/search/releases") { return (200, Data(Self.searchFixture.utf8), [:]) }
        if path.contains("/anime/releases/5555") { return (200, Data(Self.blockedReleaseFixture.utf8), [:]) }
        if path.contains("/anime/releases/") { return (200, Data(Self.releaseFixture.utf8), [:]) }
        // Плейлист HLS при resolve.
        return (200, Data(Fixtures.bipbopMaster.utf8), [:])
    }

    func testSearchMapsReleases() async throws {
        let (provider, transport) = makeProvider(route)
        let titles = try await provider.search(title: "jujutsu")
        XCTAssertEqual(titles.count, 2)
        XCTAssertEqual(titles[0].id, "8789")
        XCTAssertTrue(titles[0].titles.contains("Магическая битва"))
        XCTAssertTrue(titles[0].titles.contains("Jujutsu Kaisen"))
        let query = URLComponents(url: try XCTUnwrap(transport.requests.first?.url), resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "query" }?.value
        XCTAssertEqual(query, "jujutsu")
    }

    func testMatchFindsAnimeByEnglishTitle() async throws {
        let (provider, _) = makeProvider(route)
        let match = try await provider.match(anime: makeAnime(title: "Jujutsu Kaisen", romaji: "Jujutsu Kaisen"))
        XCTAssertEqual(match?.id, "8789")
    }

    func testEpisodesSkipFractionalAndStreamless() async throws {
        let (provider, _) = makeProvider(route)
        let title = ProviderTitle(id: "8789", providerID: AnilibriaProvider.providerID, titles: ["Jujutsu Kaisen"])
        let episodes = try await provider.episodes(for: title)
        // Серия 2.5 (спецвыпуск) и серия 3 (без ссылок) пропущены.
        XCTAssertEqual(episodes.map(\.number), [1, 2])
        XCTAssertNil(episodes[0].title)
        XCTAssertEqual(episodes[1].title, "Название второй серии")
        // Лучшее качество: 1080, при его отсутствии — 720.
        XCTAssertTrue(episodes[0].payload.contains("/1080/"))
        XCTAssertTrue(episodes[1].payload.contains("/720/"))
    }

    func testEpisodesAreCached() async throws {
        let (provider, transport) = makeProvider(route)
        let title = ProviderTitle(id: "8789", providerID: AnilibriaProvider.providerID, titles: ["Jujutsu Kaisen"])
        _ = try await provider.episodes(for: title)
        _ = try await provider.episodes(for: title)
        XCTAssertEqual(transport.requests.filter { $0.url?.path.contains("/anime/releases/") == true }.count, 1)
    }

    func testBlockedReleaseThrows() async throws {
        let (provider, _) = makeProvider(route)
        let title = ProviderTitle(id: "5555", providerID: AnilibriaProvider.providerID, titles: ["X"])
        do {
            _ = try await provider.episodes(for: title)
            XCTFail("Ожидалась ошибка")
        } catch let error as VideoSourceError {
            if case .unavailable(let reason) = error {
                XCTAssertTrue(reason.contains("правообладателя"))
            } else {
                XCTFail("Не та ошибка: \(error)")
            }
        }
    }

    func testResolveReturnsHLSWithRussianTrack() async throws {
        let (provider, _) = makeProvider(route)
        let title = ProviderTitle(id: "8789", providerID: AnilibriaProvider.providerID, titles: ["Jujutsu Kaisen"])
        let episodes = try await provider.episodes(for: title)
        let episode = try XCTUnwrap(episodes.first)
        let source = try await provider.resolve(episode)
        XCTAssertEqual(source.kind, .hls)
        XCTAssertFalse(source.isTestContent)
        XCTAssertEqual(source.providerID, AnilibriaProvider.providerID)
        // Фикстура bipbop содержит свои дорожки — они и передаются дальше.
        XCTAssertFalse(source.audioTracks.isEmpty)
        XCTAssertEqual(source.attribution, "Видео и озвучка: Anilibria (anilibria.top)")
    }

    func testResolveFailsOnDeadPlaylist() async throws {
        let (provider, _) = makeProvider { request in
            let path = request.url?.path ?? ""
            if path.contains("/anime/releases/") { return (200, Data(Self.releaseFixture.utf8), [:]) }
            return (404, Data(), [:]) // плейлист мёртв
        }
        let title = ProviderTitle(id: "8789", providerID: AnilibriaProvider.providerID, titles: ["Jujutsu Kaisen"])
        let episodes = try await provider.episodes(for: title)
        let episode = try XCTUnwrap(episodes.first)
        do {
            _ = try await provider.resolve(episode)
            XCTFail("Ожидалась ошибка")
        } catch let error as VideoSourceError {
            guard case .unavailable = error else { return XCTFail("Не та ошибка: \(error)") }
        }
    }

    /// Реальные результаты поиска «Code Geass» (сняты с живого API 11.10.2026).
    static let geassSearchFixture = """
    [
      {"id": 406, "name": {"main": "Код Гиасс: Восставший Лелуш R1", "english": "Code Geass: Hangyaku no Lelouch R1"}, "year": 2006},
      {"id": 407, "name": {"main": "Код Гиасс: Восстание Лелуша R2", "english": "Code Geass: Lelouch of the Rebellion R2"}, "year": 2008},
      {"id": 8084, "name": {"main": "Код Гиасс: Отступник Акито", "english": "Code Geass: Boukoku no Akito"}, "year": 2012}
    ]
    """

    private func makeGeassProvider() -> AnilibriaProvider {
        AnilibriaProvider(transport: StubTransport { request in
            let path = request.url?.path ?? ""
            if path.contains("/app/search/releases") { return (200, Data(Self.geassSearchFixture.utf8), [:]) }
            return (404, Data(), [:])
        })
    }

    func testMatchCodeGeassSeason1() async throws {
        // AniList: english «Code Geass: Lelouch of the Rebellion», romaji «Code Geass: Hangyaku no Lelouch».
        var anime = makeAnime(id: 1575, title: "Code Geass: Lelouch of the Rebellion", romaji: "Code Geass: Hangyaku no Lelouch", episodes: 25)
        anime.year = 2006
        let match = try await makeGeassProvider().match(anime: anime)
        XCTAssertEqual(match?.id, "406")
    }

    func testMatchCodeGeassSeason2() async throws {
        var anime = makeAnime(id: 2904, title: "Code Geass: Lelouch of the Rebellion R2", romaji: "Code Geass: Hangyaku no Lelouch R2", episodes: 25)
        anime.year = 2008
        let match = try await makeGeassProvider().match(anime: anime)
        XCTAssertEqual(match?.id, "407")
    }

    func testSeasonNumberRSuffix() {
        XCTAssertEqual(TitleMatcher.seasonNumber(in: "Код Гиасс: Восставший Лелуш R1"), 1)
        XCTAssertEqual(TitleMatcher.seasonNumber(in: "Code Geass: Lelouch of the Rebellion R2"), 2)
        XCTAssertNil(TitleMatcher.seasonNumber(in: "Обычное название"))
        XCTAssertNil(TitleMatcher.seasonNumber(in: "R2 посередине строки"))
    }

    func testHTTPErrorMapsToVideoSourceError() async throws {
        let (provider, _) = makeProvider { _ in (429, Data(), ["Retry-After": "30"]) }
        do {
            _ = try await provider.search(title: "naruto")
            XCTFail("Ожидалась ошибка")
        } catch let error as VideoSourceError {
            guard case .rateLimited = error else { return XCTFail("Не та ошибка: \(error)") }
        }
    }

    // MARK: - Точное сопоставление по MAL ID (живые данные 11.10.2026)

    /// Реальный ответ поиска «Black Clover 2nd Season»: второго сезона у Anilibria нет,
    /// зато есть спешл 2016 и «Чёрный факел» 2026 — его раньше и подставляло.
    static let blackCloverSearch = """
    [
      {"id": 5152, "year": 2016, "name": {"main": "Чёрный Клевер (Спэшл)", "english": "Black Clover Special", "alternative": "Черный клевер спешл"},
       "mal": {"id": null}, "shikimori": {"id": null}},
      {"id": 505, "year": 2014, "name": {"main": "Черная пуля", "english": "Black Bullet", "alternative": null},
       "mal": {"id": 20787}, "shikimori": {"id": 20787}},
      {"id": 10248, "year": 2026, "name": {"main": "Чёрный факел", "english": "Black Torch", "alternative": null},
       "mal": {"id": 60000}, "shikimori": {"id": 60000}}
    ]
    """

    static let codeGeassSearch = """
    [
      {"id": 407, "year": 2008, "name": {"main": "Код Гиасс: Восставший Лелуш R2", "english": "Code Geass: Hangyaku no Lelouch R2", "alternative": null},
       "mal": {"id": 2904, "url": "https://myanimelist.net/anime/2904"}, "shikimori": {"id": 2904}},
      {"id": 406, "year": 2006, "name": {"main": "Код Гиасс: Восставший Лелуш", "english": "Code Geass: Hangyaku no Lelouch R1", "alternative": null},
       "mal": {"id": 1575, "url": "https://myanimelist.net/anime/1575"}, "shikimori": {"id": 1575}}
    ]
    """

    func testSearchDecodesMalID() async throws {
        let (provider, _) = makeProvider { _ in (200, Data(Self.codeGeassSearch.utf8), [:]) }
        let titles = try await provider.search(title: "code geass")
        XCTAssertEqual(titles.map(\.malID), [2904, 1575])
    }

    func testBlackCloverSeason2IsNotReplacedBySameYearTitle() async throws {
        let (provider, _) = makeProvider { _ in (200, Data(Self.blackCloverSearch.utf8), [:]) }
        var anime = makeAnime(id: 195604, title: "Black Clover Season 2", romaji: "Black Clover 2nd Season", episodes: nil, status: .releasing)
        anime.year = 2026
        anime.malID = 62177
        let match = try await provider.match(anime: anime)
        XCTAssertNil(match, "у Anilibria нет 2-го сезона — нельзя подставлять «Чёрный факел»")
    }

    func testExactMalIDWinsOverTitles() async throws {
        let (provider, transport) = makeProvider { _ in (200, Data(Self.codeGeassSearch.utf8), [:]) }
        // Название нарочно непохожее — решает MAL ID.
        var anime = makeAnime(id: 1575, title: "Совсем другое название", romaji: "Zzz", episodes: 25)
        anime.malID = 1575
        let match = try await provider.match(anime: anime)
        XCTAssertEqual(match?.id, "406")
        XCTAssertEqual(transport.requests.count, 1, "точное совпадение найдено с первого поиска")
    }

    func testConflictingMalIDIsRejectedEvenWithSameTitle() async throws {
        let (provider, _) = makeProvider { _ in (200, Data(Self.codeGeassSearch.utf8), [:]) }
        var anime = makeAnime(id: 1, title: "Code Geass: Hangyaku no Lelouch R2", romaji: "Code Geass: Hangyaku no Lelouch R2", episodes: 25)
        anime.malID = 99999 // совсем другой тайтл с похожим именем
        let match = try await provider.match(anime: anime)
        XCTAssertNil(match)
    }

    func testFallsBackToMirrorOnCloudflare520() async throws {
        let (provider, transport) = makeProvider { request in
            if request.url?.host == "anilibria.top" { return (520, Data("error code: 520".utf8), [:]) }
            return (200, Data(Self.searchFixture.utf8), [:])
        }
        let first = try await provider.search(title: "jujutsu")
        XCTAssertEqual(first.first?.id, "8789")
        XCTAssertEqual(transport.requests.map { $0.url?.host }, ["anilibria.top", "api.anilibria.app"])
        // Рабочее зеркало запоминается — второй запрос сразу туда.
        _ = try await provider.search(title: "jujutsu")
        XCTAssertEqual(transport.requests.last?.url?.host, "api.anilibria.app")
        XCTAssertEqual(transport.requests.count, 3)
    }
}
