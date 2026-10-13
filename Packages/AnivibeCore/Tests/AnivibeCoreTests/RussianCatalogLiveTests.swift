import XCTest
@testable import AnivibeCore
final class RussianCatalogLiveTests: XCTestCase {
    func testRussianTitleAndTensuraAliasAgainstPublicAPIs() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ANIVIBE_LIVE_TESTS"] == "1", "Live-тест отключён")
        let transport = URLSessionTransport.standard(timeout: 20)
        let cache = MetadataCache(directory: nil)
        let catalogue = RussianCatalogService(catalog: AniListCatalogService(transport: transport, cache: cache),
            metadata: RussianMetadataService(transport: transport, cache: cache), cache: cache)
        let page = try await catalogue.search(.init(search: "О моём перерождении в слизь", sort: .relevance, perPage: 5))
        let title = try XCTUnwrap(page.items.first { $0.malID == 37430 })
        XCTAssertEqual(title.title.russian, "О моём перерождении в слизь")
        let details = try await catalogue.details(id: title.id)
        XCTAssertEqual(details.anime.synopsisSource, "Shikimori")
        XCTAssertNotNil(details.anime.synopsisOriginal)
        for query in ["Слизь", "ТенСура", "Tensura"] {
            let matches = try await catalogue.search(.init(search: query, sort: .relevance, perPage: 5))
            XCTAssertTrue(matches.items.contains { $0.malID == 37430 }, query)
            XCTAssertEqual(matches.items.count, Set(matches.items.map(\.id)).count)
        }
    }
}
