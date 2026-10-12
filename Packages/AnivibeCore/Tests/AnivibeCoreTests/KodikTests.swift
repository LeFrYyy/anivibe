import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

final class KodikTests: XCTestCase {

    /// Фикстура повторяет документированный формат ответа kodik-api.com/search
    /// (материал повторяется для каждой озвучки; ссылки протокол-относительные).
    static let searchFixture = """
    {
      "time": "12ms",
      "total": 4,
      "results": [
        {
          "id": "serial-100",
          "type": "anime-serial",
          "link": "//kodik.info/serial/100/aaaa1111/720p",
          "title": "Атака титанов",
          "title_orig": "Shingeki no Kyojin",
          "other_title": "Attack on Titan / Вторжение гигантов",
          "translation": {"id": 643, "title": "AniDUB", "type": "voice"},
          "year": 2013,
          "last_season": 1,
          "last_episode": 3,
          "episodes_count": 3,
          "shikimori_id": "16498",
          "quality": "HDTVRip 720p",
          "seasons": {
            "1": {
              "link": "//kodik.info/serial/100/aaaa1111/720p",
              "episodes": {
                "1": {"title": "К тебе, 2000 лет спустя", "link": "//kodik.info/seria/1001/bbbb/720p", "screenshots": ["https://i.kodik.biz/1.jpg"]},
                "2": {"title": "Этот день", "link": "//kodik.info/seria/1002/cccc/720p"},
                "3": {"link": "//kodik.info/seria/1003/dddd/720p"}
              }
            }
          }
        },
        {
          "id": "serial-100",
          "type": "anime-serial",
          "link": "//kodik.info/serial/100/eeee5555/720p",
          "title": "Атака титанов",
          "title_orig": "Shingeki no Kyojin",
          "translation": {"id": 111, "title": "Anilibria", "type": "voice"},
          "year": 2013,
          "seasons": {
            "1": {
              "link": "//kodik.info/serial/100/eeee5555/720p",
              "episodes": {
                "1": "//kodik.info/seria/2001/ffff/720p",
                "2": "//kodik.info/seria/2002/gggg/720p"
              }
            }
          }
        },
        {
          "id": "serial-200",
          "type": "anime-serial",
          "link": "//kodik.info/serial/200/hhhh/720p",
          "title": "Совершенно другой тайтл",
          "translation": {"id": 42, "title": "SubStudio", "type": "subtitles"},
          "year": 2020
        },
        {
          "id": "movie-300",
          "type": "anime",
          "link": "//kodik.info/video/300/iiii/720p",
          "title": "Ещё один фильм",
          "year": 2019
        }
      ]
    }
    """

    private func makeClient(_ handler: @escaping StubTransport.Handler) -> (KodikClient, StubTransport) {
        let transport = StubTransport(handler: handler)
        return (KodikClient(token: "TEST_TOKEN", transport: transport), transport)
    }

    func testSearchGroupsTranslationsAndEpisodes() async throws {
        let (client, _) = makeClient { _ in (200, Data(Self.searchFixture.utf8), [:]) }
        let match = try await client.search(titles: ["Attack on Titan", "Shingeki no Kyojin"], year: 2013)
        let m = try XCTUnwrap(match)
        XCTAssertEqual(m.materialID, "serial-100")
        XCTAssertEqual(m.matchedTitle, "Атака титанов")
        XCTAssertEqual(m.voices.count, 2)

        let anidub = try XCTUnwrap(m.voices.first { $0.translation.title == "AniDUB" })
        XCTAssertTrue(anidub.translation.isVoice)
        XCTAssertEqual(anidub.episodes.count, 3)
        XCTAssertEqual(anidub.episodes.map(\.number), [1, 2, 3])
        XCTAssertEqual(anidub.episodes.first?.title, "К тебе, 2000 лет спустя")
        XCTAssertEqual(anidub.playerURL.absoluteString, "https://kodik.info/serial/100/aaaa1111/720p")
        XCTAssertEqual(anidub.seasonPlayerURLs[1]?.absoluteString, "https://kodik.info/serial/100/aaaa1111/720p")

        // Второй перевод: эпизоды заданы «голыми» строками — тоже разбираются.
        let anilibria = try XCTUnwrap(m.voices.first { $0.translation.title == "Anilibria" })
        XCTAssertEqual(anilibria.episodes.count, 2)
        XCTAssertNil(anilibria.episodes.first?.title)
        XCTAssertEqual(anilibria.episodes.first?.playerURL.scheme, "https")
    }

    func testSearchSendsTokenAndParameters() async throws {
        let (client, transport) = makeClient { _ in (200, Data(#"{"total":0,"results":[]}"#.utf8), [:]) }
        let match = try await client.search(titles: ["Naruto"], year: 2002)
        XCTAssertNil(match)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.path, "/search")
        XCTAssertEqual(query["token"], "TEST_TOKEN")
        XCTAssertEqual(query["title"], "Naruto")
        XCTAssertEqual(query["limit"], "100")
        XCTAssertEqual(query["with_episodes"], "true")
    }

    func testSearchFallsBackToNextTitle() async throws {
        let (client, transport) = makeClient { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let title = query.first { $0.name == "title" }?.value ?? ""
            if title == "No Such Title" {
                return (200, Data(#"{"total":0,"results":[]}"#.utf8), [:])
            }
            return (200, Data(Self.searchFixture.utf8), [:])
        }
        let match = try await client.search(titles: ["No Such Title", "Shingeki no Kyojin"], year: 2013)
        XCTAssertEqual(match?.materialID, "serial-100")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testSearchDoesNotGuessByYear() async throws {
        // Раньше при несовпадении названий брался «тайтл того же года» или вообще первый
        // результат — так подставлялись чужие аниме. Теперь честное «не найдено».
        let (client, _) = makeClient { _ in (200, Data(Self.searchFixture.utf8), [:]) }
        let match = try await client.search(titles: ["ZZZZZ ничего общего"], year: 2020)
        XCTAssertNil(match)
    }

    static let shikimoriFixture = """
    {"total": 2, "results": [
      {"id": "serial-777", "type": "anime-serial", "link": "//kodik.info/serial/777/x/720p",
       "title": "Чёрный клевер 2", "title_orig": "Black Clover 2nd Season", "year": 2026, "shikimori_id": "62177",
       "translation": {"id": 610, "title": "AniLibria.TV", "type": "voice"}},
      {"id": "serial-777", "type": "anime-serial", "link": "//kodik.info/serial/777/y/720p",
       "title": "Чёрный клевер 2", "title_orig": "Black Clover 2nd Season", "year": 2026, "shikimori_id": 62177,
       "translation": {"id": 609, "title": "AniDUB", "type": "voice"}}
    ]}
    """

    func testSearchByShikimoriIDFirst() async throws {
        let (client, transport) = makeClient { _ in (200, Data(Self.shikimoriFixture.utf8), [:]) }
        let match = try await client.search(titles: ["Black Clover Season 2"], year: 2026, shikimoriID: 62177)
        XCTAssertEqual(match?.materialID, "serial-777")
        XCTAssertEqual(match?.voices.count, 2)
        XCTAssertEqual(transport.requests.count, 1, "по точному ID поиск по названиям не нужен")
        let items = URLComponents(url: try XCTUnwrap(transport.requests.first?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "shikimori_id" }?.value, "62177")
        XCTAssertNil(items.first { $0.name == "title" })
    }

    func testTitleSearchRejectsDifferentShikimoriID() async throws {
        // По ID ничего, по названию нашёлся тайтл с ТАКИМ ЖЕ именем, но другим ID — не он.
        let (client, _) = makeClient { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if items.contains(where: { $0.name == "shikimori_id" }) { return (200, Data(#"{"total":0,"results":[]}"#.utf8), [:]) }
            return (200, Data(Self.shikimoriFixture.utf8), [:])
        }
        let match = try await client.search(titles: ["Black Clover 2nd Season"], year: 2026, shikimoriID: 34572)
        XCTAssertNil(match)
    }

    func testErrorFieldMapsToUnauthorized() async throws {
        let (client, _) = makeClient { _ in (200, Data(#"{"error":"invalid token"}"#.utf8), [:]) }
        do {
            _ = try await client.search(titles: ["Naruto"], year: nil)
            XCTFail("Ожидалась ошибка")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testHTTPErrorIsPropagated() async throws {
        let (client, _) = makeClient { _ in (403, Data(), [:]) }
        do {
            _ = try await client.search(titles: ["Naruto"], year: nil)
            XCTFail("Ожидалась ошибка")
        } catch let error as APIError {
            XCTAssertEqual(error, .forbidden)
        }
    }

    func testPlayerURLNormalization() {
        XCTAssertEqual(KodikClient.makePlayerURL(from: "//kodik.info/seria/1/x/720p")?.absoluteString,
                       "https://kodik.info/seria/1/x/720p")
        XCTAssertEqual(KodikClient.makePlayerURL(from: "https://kodik.info/a")?.absoluteString, "https://kodik.info/a")
        XCTAssertNil(KodikClient.makePlayerURL(from: "   "))
        XCTAssertNil(KodikClient.makePlayerURL(from: "not a url with spaces"))
    }
}
