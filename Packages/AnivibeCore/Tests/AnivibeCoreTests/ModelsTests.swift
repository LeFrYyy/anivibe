import XCTest
@testable import AnivibeCore

final class ModelsTests: XCTestCase {
    func testPreferredTitleFallbacks() {
        XCTAssertEqual(AnimeTitle(romaji: "Romaji", english: "English").preferred, "English")
        XCTAssertEqual(AnimeTitle(romaji: "Romaji", english: "  ").preferred, "Romaji")
        XCTAssertEqual(AnimeTitle(native: "進撃").preferred, "進撃")
        XCTAssertEqual(AnimeTitle().preferred, "Без названия")
        XCTAssertEqual(AnimeTitle(romaji: "Same", english: "Same").all, ["Same"])
    }

    func testAllTitlesIncludeSynonymsWithoutDuplicates() {
        let a = Anime(id: 1, title: AnimeTitle(romaji: "Kimetsu", english: "Demon Slayer"), synonyms: ["demon slayer", "KnY"])
        XCTAssertEqual(a.allTitles, ["Demon Slayer", "Kimetsu", "KnY"])
    }

    func testReleasedEpisodeCountIsNotInvented() {
        var a = makeAnime(episodes: nil, status: .releasing)
        XCTAssertNil(a.releasedEpisodeCount)
        a.nextAiringEpisode = 6
        XCTAssertEqual(a.releasedEpisodeCount, 5)
        XCTAssertEqual(makeAnime(episodes: 12, status: .notYetReleased).releasedEpisodeCount, 0)
        XCTAssertEqual(makeAnime(episodes: 12).releasedEpisodeCount, 12)
    }

    func testWatchProgressFraction() {
        XCTAssertEqual(WatchProgress(animeId: 1, episode: 1, position: 50, duration: 100).fraction, 0.5)
        XCTAssertEqual(WatchProgress(animeId: 1, episode: 1, position: 50, duration: 0).fraction, 0)
        XCTAssertEqual(WatchProgress(animeId: 1, episode: 1, position: 150, duration: 100).fraction, 1)
        XCTAssertFalse(WatchProgress(animeId: 1, episode: 1, position: 89, duration: 100).isFinished)
        XCTAssertTrue(WatchProgress(animeId: 1, episode: 1, position: 90, duration: 100).isFinished)
        XCTAssertEqual(WatchProgress(animeId: 1, episode: 1, position: 1, duration: 3).percent, 33)
    }

    func testCurrentSeason() {
        let cal = Calendar.utcGregorian
        func date(_ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: m, day: 15))! }
        XCTAssertEqual(AnimeSeason.current(for: date(2)).season, .winter)
        XCTAssertEqual(AnimeSeason.current(for: date(5)).season, .spring)
        XCTAssertEqual(AnimeSeason.current(for: date(8)).season, .summer)
        XCTAssertEqual(AnimeSeason.current(for: date(10)).season, .fall)
        XCTAssertEqual(AnimeSeason.current(for: date(10)).year, 2026)
    }

    func testHTMLToPlainText() {
        let s = HTMLText.plainText("Hello<br><br>\n<i>world</i> &amp; friends&#039;<br>\n(Source: X)")
        XCTAssertEqual(s, "Hello\n\nworld & friends'\n(Source: X)")
    }

    func testRelationsSplitIntoSeasonsAndOther() {
        var sequel = makeAnime(id: 2)
        sequel.format = .tv
        var movie = makeAnime(id: 3)
        movie.format = .movie
        let manga = makeAnime(id: 4)
        let details = AnimeDetails(anime: makeAnime(), relations: [
            RelatedAnime(relation: .sequel, anime: sequel),
            RelatedAnime(relation: .sideStory, anime: movie),
            RelatedAnime(relation: .adaptation, anime: manga)
        ])
        XCTAssertEqual(details.otherSeasons.map(\.id), [2])
        XCTAssertEqual(details.otherRelations.map(\.id), [3])
    }

    func testCatalogQueryValidation() {
        var q = CatalogQuery(search: "  naruto  ", year: 1800, sort: .relevance, page: 0, perPage: 500)
        q.status = .unknown
        let v = q.validated(currentYear: 2026)
        XCTAssertEqual(v.search, "naruto")
        XCTAssertNil(v.year)
        XCTAssertNil(v.status)
        XCTAssertEqual(v.page, 1)
        XCTAssertEqual(v.perPage, 50)
        XCTAssertEqual(CatalogQuery(search: "", sort: .relevance).effectiveSort, .popularity)
        XCTAssertEqual(CatalogQuery(search: "x", sort: .relevance).effectiveSort, .relevance)
        XCTAssertFalse(CatalogQuery().hasActiveFilters)
        XCTAssertTrue(CatalogQuery(genres: ["Action"]).hasActiveFilters)
        XCTAssertEqual(String(repeating: "a", count: 300).count, 300)
        XCTAssertEqual(CatalogQuery(search: String(repeating: "a", count: 300)).validated().search.count, 100)
    }

    // MARK: - «Вышло N из M»

    func testAiredEpisodesText() {
        var ongoingUnknownTotal = makeAnime(episodes: nil, status: .releasing)
        ongoingUnknownTotal.nextAiringEpisode = 3
        XCTAssertEqual(ongoingUnknownTotal.airedEpisodesText, "2/?")

        var ongoingKnownTotal = makeAnime(episodes: 11, status: .releasing)
        ongoingKnownTotal.nextAiringEpisode = 2
        XCTAssertEqual(ongoingKnownTotal.airedEpisodesText, "1/11")

        XCTAssertNil(makeAnime(episodes: 12, status: .finished).airedEpisodesText)
        // Онгоинг без даты следующей серии — данных нет, ничего не выдумываем.
        XCTAssertNil(makeAnime(episodes: 12, status: .releasing).airedEpisodesText)
    }

    func testAniListMediaDecodesMalID() throws {
        let json = #"{"id": 195604, "idMal": 62177, "title": {"romaji": "Black Clover 2nd Season"}, "status": "RELEASING", "nextAiringEpisode": {"episode": 3}}"#
        let dto = try JSONDecoder().decode(MediaDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.model.malID, 62177)
        XCTAssertEqual(dto.model.airedEpisodesText, "2/?")
    }

    func testPlaybackControlsStateHide() {
        var state = PlaybackControlsState()
        XCTAssertTrue(state.isVisible)
        state.hide()
        XCTAssertFalse(state.isVisible)
        XCTAssertNil(state.deadline)
    }
}

