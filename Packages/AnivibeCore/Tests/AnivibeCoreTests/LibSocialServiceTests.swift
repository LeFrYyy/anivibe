import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

/// lib.social (MangaLib): поиск slug по названиям, главы с ветками, страницы через image-серверы.
final class LibSocialServiceTests: XCTestCase {

    private let searchJSON = """
    {"data":[{"id":7965,"slug":"chainsaw-man","slug_url":"7965--chainsaw-man",
      "name":"Chainsaw Man","rus_name":"Человек-бензопила","eng_name":"Chainsaw Man",
      "cover":{"default":"https://cover.imglib.info/uploads/cover/chainsaw-man/cover/x.jpg"},
      "type":{"id":4,"label":"Манга"},"rating":{"average":"8.9"}}]}
    """

    private let chaptersJSON = """
    {"data":[
      {"id":223269,"index":1,"item_number":1,"volume":"1","number":"1","name":"Пёс и бензопила",
       "branches_count":2,"branches":[{"id":223269,"branch_id":4667,"teams":[{"name":"Nippa"}]},{"id":999,"branch_id":1,"teams":[{"name":"B"}]}]},
      {"id":223270,"index":2,"item_number":2,"volume":"1","number":"2","name":null,
       "branches_count":1,"branches":[{"id":223270,"branch_id":4667,"teams":[{"name":"Nippa"}]}]}
    ]}
    """

    private let pagesJSON = """
    {"data":{"id":223269,"pages":[
      {"id":2,"image":"01.png","slug":2,"url":"//manga/chainsaw-man/chapters/1-1/01.jpg"},
      {"id":1,"image":"00.png","slug":1,"url":"//manga/chainsaw-man/chapters/1-1/00.jpg"}]}}
    """

    private let constantsJSON = """
    {"data":{"imageServers":[{"id":"main","url":"https://img2.imglib.info","site_ids":[1,3]},
                             {"id":"secondary","url":"https://img3.cdnrulib.link","site_ids":[1,3]}]}}
    """

    private func service(_ stub: @escaping (URLRequest) throws -> (Int, Data, [String: String])) -> LibSocialService {
        LibSocialService(transport: StubTransport(handler: stub), cache: MetadataCache(directory: nil))
    }

    func testSlugMatchByRussianTitle() async {
        let service = service { request in
            XCTAssertTrue(request.url!.absoluteString.contains("site_id%5B%5D=1"))
            return (200, Data(self.searchJSON.utf8), [:])
        }
        let slug = await service.slug(forMangaID: 116778, titles: ["Человек-бензопила", "Chainsaw Man"])
        XCTAssertEqual(slug, "chainsaw-man")
    }

    func testSlugMissWhenNoTitleMatches() async {
        let service = service { _ in (200, Data(self.searchJSON.utf8), [:]) }
        let slug = await service.slug(forMangaID: 1, titles: ["Совершенно другое название"])
        XCTAssertNil(slug)
    }

    func testChaptersFlattenFirstBranch() async throws {
        let service = service { _ in (200, Data(self.chaptersJSON.utf8), [:]) }
        let chapters = try await service.chapters(slug: "chainsaw-man")
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].number, 1)
        XCTAssertEqual(chapters[0].title, "Пёс и бензопила")
        XCTAssertEqual(chapters[0].group, "Nippa")
        XCTAssertEqual(chapters[0].id, "lib|chainsaw-man|1|1|4667")
        XCTAssertEqual(chapters[1].id, "lib|chainsaw-man|1|2|4667")
    }

    func testPageURLsUseImageServerAndSortBySlug() async throws {
        let service = service { request in
            let path = request.url!.path
            if path.contains("constants") { return (200, Data(self.constantsJSON.utf8), [:]) }
            return (200, Data(self.pagesJSON.utf8), [:])
        }
        let urls = try await service.pageURLs(chapterID: "lib|chainsaw-man|1|1|4667")
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://img2.imglib.info/manga/chainsaw-man/chapters/1-1/00.jpg",
            "https://img2.imglib.info/manga/chainsaw-man/chapters/1-1/01.jpg"
        ])
    }

    func testPageURLsFallbackHostsWhenConstantsFail() async throws {
        let service = service { request in
            let path = request.url!.path
            if path.contains("constants") { return (500, Data(), [:]) }
            return (200, Data(self.pagesJSON.utf8), [:])
        }
        let urls = try await service.pageURLs(chapterID: "lib|chainsaw-man|1|1|0")
        XCTAssertEqual(urls.first?.host, "img3.cdnrulib.link")
        XCTAssertEqual(urls.count, 2)
    }

    func testBadChapterIDReturnsEmpty() async throws {
        let service = service { _ in (200, Data(), [:]) }
        let urls = try await service.pageURLs(chapterID: "abc123")
        XCTAssertEqual(urls, [])
    }

    /// Хаб: lib.social отдал главы → MangaDex не опрашивается (хотя запросы параллельны,
    /// результат берётся из lib), а `pageURLs` маршрутизируется по префиксу id.
    func testHubPrefersLibChaptersAndRoutesPages() async throws {
        let libTransport = StubTransport { request in
            let path = request.url!.path
            if path.hasSuffix("/chapters") { return (200, Data(self.chaptersJSON.utf8), [:]) }
            return (200, Data(self.searchJSON.utf8), [:])
        }
        let hub = MangaHub(
            catalog: ShikimoriMangaService(transport: StubTransport { _ in (404, Data(), [:]) }, cache: MetadataCache(directory: nil)),
            lib: LibSocialService(transport: libTransport, cache: MetadataCache(directory: nil)),
            reader: MangaDexService(transport: StubTransport { _ in (200, Data("{\"data\":[]}".utf8), [:]) }, cache: MetadataCache(directory: nil)),
            cache: MetadataCache(directory: nil))
        var manga = Manga(id: 116778, title: AnimeTitle(romaji: "Chainsaw Man", russian: "Человек-бензопила"))
        manga.libSlug = "chainsaw-man"
        let chapters = try await hub.chapters(of: manga)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertTrue(chapters[0].id.hasPrefix("lib|"))
    }
}
