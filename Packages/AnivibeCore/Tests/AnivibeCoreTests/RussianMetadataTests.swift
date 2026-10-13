import XCTest
@testable import AnivibeCore
final class RussianMetadataTests: XCTestCase {
    func testUnavailableTranslationDoesNotBlockOriginalDetails() async throws {
        let json = "{\"data\":{\"Media\":" + Fixtures.mediaJSON(id: 1, english: "Original", romaji: "Original", extra: ", \"idMal\":37430, \"description\":\"Original description\"") + "}}"
        let transport = StubTransport { request in
            request.url!.host == "russian.invalid" ? (503, Data(), [:]) : (200, Data(json.utf8), [:])
        }
        let cache = MetadataCache(directory: nil)
        let service = RussianCatalogService(catalog: AniListCatalogService(transport: transport, cache: cache),
            metadata: RussianMetadataService(transport: transport, cache: cache, baseURL: URL(string: "https://russian.invalid/api")!), cache: cache)
        let details = try await service.details(id: 1)
        XCTAssertEqual(details.anime.synopsis, "Original description")
        XCTAssertNil(details.anime.synopsisSource)
    }
    func testFailureOfBothSourcesIsNotReportedAsEmptySearch() async {
        let transport = StubTransport { _ in (503, Data(), [:]) }
        let cache = MetadataCache(directory: nil)
        let service = RussianCatalogService(catalog: AniListCatalogService(transport: transport, cache: cache),
            metadata: RussianMetadataService(transport: transport, cache: cache), cache: cache)
        do { _ = try await service.search(.init(search: "ТенСура")); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .server(status: 503)) }
    }
    func testMetadataIsCachedAndOfficialIDsMustAgree() async throws {
        let transport = StubTransport { _ in
            (200, Data(#"{"id":37430,"russian":"О моём перерождении в слизь","synonyms":["Tensura"],"description":"[b]Описание[/b]"}"#.utf8), [:])
        }
        let service = RussianMetadataService(transport: transport, cache: MetadataCache(directory: nil))
        let first = try await service.details(malID: 37430)
        _ = try await service.details(malID: 37430)
        XCTAssertEqual(transport.requests.count, 1)
        let anime = Anime(id: 101280, title: .init(romaji: "Tensei"), synopsis: "Original", malID: 37430)
        let localized = first.apply(to: anime)
        XCTAssertEqual(localized.synopsis, "Описание")
        XCTAssertEqual(localized.synopsisOriginal, "Original")
        XCTAssertEqual(localized.synopsisSource, "Shikimori")
    }
}
