import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

final class CatalogTests: XCTestCase {
    private func service(_ transport: StubTransport, ttl: TimeInterval = 3600) -> AniListCatalogService {
        AniListCatalogService(transport: transport, cache: MetadataCache(directory: nil, ttl: ttl),
                              limiter: RateLimiter(limit: 100, per: 60))
    }

    func testSearchSendsFiltersAsGraphQLVariables() async throws {
        let body = """
        {"data": {"Page": {"pageInfo": {"currentPage": 2, "hasNextPage": true}, "media": [
          \(Fixtures.mediaJSON(id: 16498, english: "Attack on Titan", romaji: "Shingeki no Kyojin")),
          \(Fixtures.mediaJSON(id: 99, english: nil, romaji: "Adult", adult: true)),
          null
        ]}}}
        """
        let t = StubTransport { _ in (200, Data(body.utf8), [:]) }
        let q = CatalogQuery(search: " titan ", genres: ["Drama", "Action"], year: 2013, status: .finished, formats: [.tv], sort: .score, page: 2, perPage: 20)
        let page = try await service(t).search(q)

        XCTAssertEqual(page.items.map(\.id), [16498], "isAdult и null-элементы отбрасываются")
        XCTAssertEqual(page.page, 2)
        XCTAssertTrue(page.hasNextPage)
        let anime = try XCTUnwrap(page.items.first)
        XCTAssertEqual(anime.title.preferred, "Attack on Titan")
        XCTAssertEqual(anime.synonyms, ["Alt 16498"])
        XCTAssertEqual(anime.bannerURL?.scheme, "https", "http-ссылки повышаются до https")
        XCTAssertEqual(anime.status, .finished)
        XCTAssertEqual(anime.episodeCount, 12)

        let req = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(req.url, AniListCatalogService.endpoint)
        XCTAssertEqual(req.httpMethod, "POST")
        let vars = try XCTUnwrap(req.bodyJSON["variables"] as? [String: Any])
        XCTAssertEqual(vars["search"] as? String, "titan")
        XCTAssertEqual(vars["genres"] as? [String], ["Action", "Drama"])
        XCTAssertEqual(vars["year"] as? Int, 2013)
        XCTAssertEqual(vars["status"] as? String, "FINISHED")
        XCTAssertEqual(vars["formats"] as? [String], ["TV"])
        XCTAssertEqual(vars["sort"] as? [String], ["SCORE_DESC"])
        XCTAssertEqual(vars["page"] as? Int, 2)
        XCTAssertNil(vars["season"])
    }

    func testResponsesAreCached() async throws {
        let body = #"{"data": {"GenreCollection": ["Action", "Hentai", "Drama"]}}"#
        let t = StubTransport { _ in (200, Data(body.utf8), [:]) }
        let s = service(t)
        let g1 = try await s.genres()
        let g2 = try await s.genres()
        XCTAssertEqual(g1, ["Action", "Drama"])
        XCTAssertEqual(g2, g1)
        XCTAssertEqual(t.requests.count, 1)
    }

    func testCacheExpires() async throws {
        let clock = Clock()
        let body = #"{"data": {"GenreCollection": ["Action"]}}"#
        let t = StubTransport { _ in (200, Data(body.utf8), [:]) }
        let s = AniListCatalogService(transport: t, cache: MetadataCache(directory: nil, ttl: 60, now: { clock.now }),
                                      limiter: RateLimiter(limit: 100, per: 60))
        _ = try await s.genres()
        clock.advance(61)
        _ = try await s.genres()
        XCTAssertEqual(t.requests.count, 2)
    }

    func testDiskCacheSurvivesNewInstance() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = #"{"data": {"GenreCollection": ["Action"]}}"#
        let t = StubTransport { _ in (200, Data(body.utf8), [:]) }
        _ = try await AniListCatalogService(transport: t, cache: MetadataCache(directory: dir)).genres()
        _ = try await AniListCatalogService(transport: t, cache: MetadataCache(directory: dir)).genres()
        XCTAssertEqual(t.requests.count, 1)
    }

    func testRateLimitResponse() async {
        let t = StubTransport { _ in (429, Data(#"{"data":null,"errors":[{"message":"Too Many Requests.","status":429}]}"#.utf8), ["Retry-After": "30"]) }
        do {
            _ = try await service(t).genres()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? APIError, .rateLimited(retryAfter: 30))
        }
    }

    func testNotFoundAndGraphQLErrors() async {
        let t404 = StubTransport { _ in (404, Data(#"{"data":{"Media":null},"errors":[{"message":"Not Found.","status":404}]}"#.utf8), [:]) }
        do { _ = try await service(t404).details(id: 1); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notFound) }

        let t400 = StubTransport { _ in (400, Data(#"{"data":null,"errors":[{"message":"Variable bad","status":400}]}"#.utf8), [:]) }
        do { _ = try await service(t400).genres(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .graphQL(["Variable bad"])) }

        let t500 = StubTransport { _ in (503, Data("oops".utf8), [:]) }
        do { _ = try await service(t500).genres(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .server(status: 503)) }

        let bad = StubTransport { _ in (200, Data("not json".utf8), [:]) }
        do { _ = try await service(bad).genres(); XCTFail() } catch {
            guard case .decoding = error as? APIError else { return XCTFail("\(error)") }
        }
    }

    func testDetailsMapping() async throws {
        let extra = """
        , "description": "Line<br><br><i>Italic</i>",
        "relations": {"edges": [{"relationType": "SEQUEL", "node": \(Fixtures.mediaJSON(id: 2, english: "AoT 2", romaji: "SnK 2"))},
                                 {"relationType": "ADAPTATION", "node": \(Fixtures.mediaJSON(id: 3, english: "Manga", romaji: "Manga", format: "MANGA"))}]},
        "streamingEpisodes": [{"title": "Episode 1 - To You", "thumbnail": "https://img/1.jpg", "url": "https://www.crunchyroll.com/x", "site": "Crunchyroll"}],
        "externalLinks": [{"site": "Crunchyroll", "url": "https://www.crunchyroll.com/series/x", "type": "STREAMING", "language": null},
                          {"site": "Twitter", "url": "https://twitter.com/x", "type": "SOCIAL", "language": null}],
        "studios": {"nodes": [{"name": "Wit Studio"}]},
        "recommendations": {"nodes": [{"mediaRecommendation": \(Fixtures.mediaJSON(id: 5, english: "Rec", romaji: "Rec"))}, {"mediaRecommendation": null}]}
        """
        let body = #"{"data": {"Media": "# + Fixtures.mediaJSON(id: 1, english: "AoT", romaji: "SnK", extra: extra) + "}}"
        let t = StubTransport { _ in (200, Data(body.utf8), [:]) }
        let d = try await service(t).details(id: 1)
        XCTAssertEqual(d.anime.synopsis, "Line\n\nItalic")
        XCTAssertEqual(d.relations.count, 2)
        XCTAssertEqual(d.otherSeasons.map(\.id), [2])
        XCTAssertEqual(d.externalStreamingLinks.map(\.site), ["Crunchyroll"])
        XCTAssertEqual(d.studios, ["Wit Studio"])
        XCTAssertEqual(d.recommendations.map(\.id), [5])
        XCTAssertEqual(EpisodeListBuilder.build(from: d).episodes.first?.title, "To You")
    }

    func testHomeFeedUsesCurrentSeason() async throws {
        let page = #"{"media": ["# + Fixtures.mediaJSON(id: 1, english: "A", romaji: "A") + "]}"
        let body = #"{"data": {"popular": "# + page + #", "seasonal": "# + page + #", "trending": "# + page + #", "recent": {"media": []}}}"#
        let t = StubTransport { _ in (200, Data(body.utf8), [:]) }
        let date = Calendar.utcGregorian.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        let s = AniListCatalogService(transport: t, cache: MetadataCache(directory: nil), now: { date })
        let feed = try await s.homeFeed()
        XCTAssertEqual(feed.popular.count, 1)
        XCTAssertTrue(feed.recentlyAdded.isEmpty)
        XCTAssertEqual(feed.seasonLabel, "Осень 2026")
        let vars = try XCTUnwrap(t.requests.first?.bodyJSON["variables"] as? [String: Any])
        XCTAssertEqual(vars["season"] as? String, "FALL")
        XCTAssertEqual(vars["seasonYear"] as? Int, 2026)
        XCTAssertEqual(t.requests.count, 1, "главный экран — один запрос с алиасами")
    }

    func testDemoCatalogFilteringAndAlternativeTitles() async throws {
        let demo = DemoCatalogService()
        let bySynonym = try await demo.search(CatalogQuery(search: "wind road"))
        XCTAssertEqual(bySynonym.items.map(\.id), [900_002])
        let byGenre = try await demo.search(CatalogQuery(genres: ["Drama"]))
        XCTAssertEqual(byGenre.items.map(\.id), [900_001])
        let byStatus = try await demo.search(CatalogQuery(status: .notYetReleased))
        XCTAssertEqual(byStatus.items.map(\.id), [900_004])
        let byYear = try await demo.search(CatalogQuery(year: 2023))
        XCTAssertEqual(byYear.items.map(\.id), [900_003])
        let empty = try await demo.search(CatalogQuery(search: "zzzz"))
        XCTAssertTrue(empty.items.isEmpty)
        let paged = try await demo.search(CatalogQuery(page: 1, perPage: 3))
        XCTAssertTrue(paged.hasNextPage)
        let scored = try await demo.search(CatalogQuery(sort: .score))
        XCTAssertEqual(scored.items.first?.id, 900_001)
    }
}

final class RateLimiterTests: XCTestCase {
    func testSlidingWindow() async throws {
        let clock = Clock()
        let limiter = RateLimiter(limit: 2, per: 60, now: { clock.now }, sleep: { clock.advance($0) })
        try await limiter.acquire()
        try await limiter.acquire()
        let delay = await limiter.delayBeforeNextRequest()
        XCTAssertEqual(delay, 60, accuracy: 0.001)
        let before = clock.now
        try await limiter.acquire() // «спит» до освобождения слота
        XCTAssertEqual(clock.now.timeIntervalSince(before), 60, accuracy: 0.001)
    }

    func testBlockAfter429AndMaxWait() async {
        let clock = Clock()
        let limiter = RateLimiter(limit: 10, per: 60, now: { clock.now }, sleep: { clock.advance($0) })
        await limiter.block(for: 120)
        do {
            try await limiter.acquire(maxWait: 30)
            XCTFail("expected rateLimited")
        } catch {
            guard case .rateLimited = error as? APIError else { return XCTFail("\(error)") }
        }
    }
}

@MainActor
final class LatestTaskRunnerTests: XCTestCase {
    func testOnlyLatestResultIsDelivered() async throws {
        let runner = LatestTaskRunner()
        var delivered: [String] = []
        let done = expectation(description: "latest")
        runner.run(operation: { try await Task.sleep(nanoseconds: 200_000_000); return "old" }) { r in
            if case .success(let v) = r { delivered.append(v) }
        }
        runner.run(operation: { try await Task.sleep(nanoseconds: 20_000_000); return "new" }) { r in
            if case .success(let v) = r { delivered.append(v) }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 2)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(delivered, ["new"])
    }
}
