import XCTest
@testable import AnivibeCore

final class EpisodeTests: XCTestCase {
    func testEpisodeNumberParser() {
        XCTAssertEqual(EpisodeNumberParser.parse("Episode 3 - To You, in 2000 Years")?.number, 3)
        XCTAssertEqual(EpisodeNumberParser.parse("Episode 3 - To You, in 2000 Years")?.title, "To You, in 2000 Years")
        XCTAssertEqual(EpisodeNumberParser.parse("S02E05 Title")?.season, 2)
        XCTAssertEqual(EpisodeNumberParser.parse("S02E05 Title")?.number, 5)
        XCTAssertEqual(EpisodeNumberParser.parse("Серия 7")?.number, 7)
        XCTAssertEqual(EpisodeNumberParser.parse("第12話 決戦")?.number, 12)
        XCTAssertEqual(EpisodeNumberParser.parse("12 - Finale")?.number, 12)
        XCTAssertEqual(EpisodeNumberParser.parse("Ep. 4: Name")?.title, "Name")
        XCTAssertNil(EpisodeNumberParser.parse("Special Opening"))
        XCTAssertNil(EpisodeNumberParser.parse("Episode 0"))
    }

    func testEpisodeListForFinishedSeriesWithTitles() {
        let details = AnimeDetails(anime: makeAnime(episodes: 3), streamingEpisodes: [
            StreamingEpisodeInfo(title: "Episode 2 - Second"),
            StreamingEpisodeInfo(title: "Episode 1 - First")
        ])
        let list = EpisodeListBuilder.build(from: details)
        XCTAssertEqual(list.episodes.map(\.number), [1, 2, 3])
        XCTAssertEqual(list.episodes.map(\.title), ["First", "Second", nil])
        XCTAssertTrue(list.isCountKnown)
        XCTAssertNil(list.note)
    }

    func testEpisodeListUnknownCount() {
        let list = EpisodeListBuilder.build(from: AnimeDetails(anime: makeAnime(episodes: nil)))
        XCTAssertTrue(list.episodes.isEmpty)
        XCTAssertFalse(list.isCountKnown)
        XCTAssertEqual(list.note, "Количество серий неизвестно.")
    }

    func testEpisodeListOngoingUsesAiredCountOnly() {
        var anime = makeAnime(episodes: 24, status: .releasing)
        anime.nextAiringEpisode = 8
        let list = EpisodeListBuilder.build(from: AnimeDetails(anime: anime))
        XCTAssertEqual(list.episodes.count, 7)
        XCTAssertEqual(list.note, "Онгоинг: вышло 7 из 24.")
    }

    func testEpisodeListNotYetReleased() {
        let list = EpisodeListBuilder.build(from: AnimeDetails(anime: makeAnime(episodes: 12, status: .notYetReleased)))
        XCTAssertTrue(list.episodes.isEmpty)
    }

    func testEpisodeMatcher() {
        let p: ProviderID = "p"
        let seasoned = [ProviderEpisode(providerID: p, titleID: "t", season: 1, number: 1, payload: "a"),
                        ProviderEpisode(providerID: p, titleID: "t", season: 2, number: 1, payload: "b")]
        XCTAssertEqual(EpisodeMatcher.match(season: 2, number: 1, in: seasoned)?.payload, "b")
        XCTAssertNil(EpisodeMatcher.match(season: 3, number: 1, in: seasoned))

        let absolute = (1...30).map { ProviderEpisode(providerID: p, titleID: "t", season: nil, number: $0, payload: "\($0)") }
        XCTAssertEqual(EpisodeMatcher.match(season: 1, number: 5, in: absolute)?.payload, "5")
        XCTAssertEqual(EpisodeMatcher.match(season: 2, number: 1, in: absolute, absoluteOffset: 25)?.payload, "26")
        XCTAssertNil(EpisodeMatcher.match(season: 1, number: 31, in: absolute))
    }

    func testTitleMatcher() {
        XCTAssertEqual(TitleMatcher.normalize("Shingeki no Kyojin: The Final Season!"), "shingeki no kyojin the final season")
        XCTAssertEqual(TitleMatcher.normalize("Pokémon"), "pokemon")
        XCTAssertEqual(TitleMatcher.seasonNumber(in: "Spy x Family Season 2"), 2)
        XCTAssertEqual(TitleMatcher.seasonNumber(in: "Mob Psycho 100 II"), 2)
        XCTAssertEqual(TitleMatcher.seasonNumber(in: "Kaguya-sama 3rd Season"), 3)
        XCTAssertEqual(TitleMatcher.seasonNumber(in: "Магическая битва 2 сезон"), 2)
        XCTAssertNil(TitleMatcher.seasonNumber(in: "Naruto"))
        XCTAssertTrue(TitleMatcher.matches(query: "kyojin", titles: ["Shingeki no Kyojin"]))
        XCTAssertTrue(TitleMatcher.matches(query: "AOT", titles: ["Attack on Titan", "AoT"]))
        XCTAssertFalse(TitleMatcher.matches(query: "bleach", titles: ["Naruto"]))
    }

    func testBestMatchRespectsSeasonAndThreshold() {
        struct C { let t: [String] }
        let cands = [C(t: ["Spy x Family"]), C(t: ["Spy x Family Season 2"]), C(t: ["Family Guy"])]
        XCTAssertEqual(TitleMatcher.bestMatch(for: ["SPY×FAMILY Season 2"], among: cands, titlesOf: \.t)?.t, ["Spy x Family Season 2"])
        XCTAssertEqual(TitleMatcher.bestMatch(for: ["Spy x Family"], among: cands, titlesOf: \.t)?.t, ["Spy x Family"])
        XCTAssertNil(TitleMatcher.bestMatch(for: ["Bleach"], among: cands, titlesOf: \.t))
    }
}
