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

    func testHTTPErrorMapsToVideoSourceError() async throws {
        let (provider, _) = makeProvider { _ in (429, Data(), ["Retry-After": "30"]) }
        do {
            _ = try await provider.search(title: "naruto")
            XCTFail("Ожидалась ошибка")
        } catch let error as VideoSourceError {
            guard case .rateLimited = error else { return XCTFail("Не та ошибка: \(error)") }
        }
    }
}
