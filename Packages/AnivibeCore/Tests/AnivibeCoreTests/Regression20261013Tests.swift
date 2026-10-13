import XCTest
@testable import AnivibeCore

final class Regression20261013Tests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
    func testObservedSteelBallRunCatalogueAndSourceStaySeparate() throws {
        let dto = try JSONDecoder().decode(GraphQLResponse<DetailsResponseDTO>.self, from: fixture("steel-ball-run-anilist"))
        let details = try XCTUnwrap(dto.data?.Media?.detailsModel)
        XCTAssertEqual(details.anime.id, 210482)
        XCTAssertEqual(details.anime.malID, 61469)
        XCTAssertEqual(EpisodeListBuilder.build(from: details).episodes.count, 3)
        let object = try JSONSerialization.jsonObject(with: fixture("steel-ball-run-kodik-metadata")) as! [String: Any]
        let results = object["results"] as! [[String: Any]]
        let material = try XCTUnwrap(results.first { $0["id"] as? String == "serial-73739" })
        let seasons = material["seasons"] as! [String: [String: Any]]
        let keys = (seasons["6"]!["episodes"] as! [String: Any]).keys.compactMap(Int.init).sorted()
        // Fixture URLs are explicitly synthetic, only metadata keys above were observed live.
        let voice = KodikVoiceOption(materialID: "serial-73739", translation: .init(id: 609, title: "AniDUB", kind: .voice),
            title: "Steel Ball Run", year: nil, quality: nil, playerURL: URL(string: "https://example.invalid/test")!,
            episodes: keys.map { .init(season: 6, number: $0, title: nil, playerURL: URL(string: "https://example.invalid/test/\($0)")!) },
            seasonPlayerURLs: [:])
        let list = KodikProvider.sourceEpisodes(for: voice, animeID: details.anime.id)
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(list.map { $0.sourceEpisode?.season }, [6, 6, 6, 6])
        XCTAssertEqual(list.map { $0.sourceEpisode?.number }, [1, 2, 3, 4])
        XCTAssertTrue(list.allSatisfy { $0.sourceKey != nil })
        XCTAssertNil(EpisodeMatcher.match(season: 1, number: 4, in: list.compactMap(\.sourceEpisode)))
    }
    func testNoSeasonTwoGuessWithoutVerifiedOffsetAndNoAmbiguousMatch() {
        let a = ProviderEpisode(providerID: "p", titleID: "a", season: nil, number: 1, payload: "a")
        let b = ProviderEpisode(providerID: "p", titleID: "b", season: nil, number: 1, payload: "b")
        XCTAssertNil(EpisodeMatcher.match(season: 2, number: 1, in: [a]))
        XCTAssertNil(EpisodeMatcher.match(season: 1, number: 1, in: [a, b]))
        XCTAssertEqual(EpisodeMatcher.match(season: 2, number: 1, in: [a], absoluteOffset: 0), a)
    }
    func testSourceListPreservesSpecialsGapsAndIdenticalTitles() {
        let url = URL(string: "https://example.invalid")!
        let episodes = [KodikEpisode(season: 0, number: 1, title: "Same", playerURL: url),
                        KodikEpisode(season: 1, number: 1, title: "Same", playerURL: url),
                        KodikEpisode(season: 1, number: 5, title: "Same", playerURL: url)]
        let voice = KodikVoiceOption(materialID: "serial-test", translation: .init(id: 1, title: "Test", kind: .voice),
            title: "Test", year: nil, quality: nil, playerURL: url, episodes: episodes + [episodes[0]], seasonPlayerURLs: [:])
        let list = KodikProvider.sourceEpisodes(for: voice, animeID: 1)
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list.map(\.number), [1, 2, 3])
        XCTAssertEqual(list.map(\.progressNumber), [1, 1, 5])
        XCTAssertEqual(Set(list.compactMap(\.sourceKey)).count, 3)
    }
    func testControlMenuCanStayOpenForHoursAndDismissalStartsFreshTimer() {
        var state = PlaybackControlsState()
        let t = Date(timeIntervalSince1970: 1000)
        state.interact(at: t, blocked: false)
        state.interact(at: t.addingTimeInterval(1), blocked: true)
        state.tick(at: t.addingTimeInterval(7200), playing: true, blocked: true)
        XCTAssertTrue(state.isVisible)
        XCTAssertNil(state.deadline)
        state.interact(at: t.addingTimeInterval(7200), blocked: false)
        state.tick(at: t.addingTimeInterval(7203), playing: true, blocked: false)
        XCTAssertTrue(state.isVisible)
        state.tick(at: t.addingTimeInterval(7204), playing: true, blocked: false)
        XCTAssertFalse(state.isVisible)
    }
    func testBufferingSeekingAndPauseNeverAutoHideControls() {
        let t = Date()
        for playing in [true, false] {
            var state = PlaybackControlsState()
            state.interact(at: t, blocked: true)
            state.toggle(at: t, blocked: true)
            state.tick(at: t.addingTimeInterval(60), playing: playing, blocked: true)
            XCTAssertTrue(state.isVisible)
        }
        var state = PlaybackControlsState()
        state.interact(at: t, blocked: false)
        state.tick(at: t.addingTimeInterval(60), playing: false, blocked: false)
        XCTAssertTrue(state.isVisible)
    }
    func testSourceProgressDoesNotOverwriteCatalogueOrCompleteWrongTitle() async throws {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        let anime = AnimeSnapshot(id: 1, title: "Test", episodeCount: 1)
        await repo.recordProgress(anime: anime, episode: 1, position: 20, duration: 100)
        await repo.recordProgress(anime: anime, episode: 1, position: 100, duration: 100, sourceKey: "p:voice:6:1")
        var snapshot = await repo.snapshot()
        XCTAssertEqual(snapshot.progress.count, 2)
        XCTAssertEqual(snapshot.progress(animeId: 1, episode: 1)?.position, 20)
        XCTAssertEqual(snapshot.progress(animeId: 1, episode: 1, sourceKey: "p:voice:6:1")?.position, 100)
        XCTAssertEqual(snapshot.entry(for: 1)?.status, .watching)
        XCTAssertEqual(snapshot.history.count, 2)
        await repo.recordProgress(anime: anime, episode: 4, position: 12, duration: 100, sourceKey: "p:voice:6:4")
        let resume = await repo.resumePoint(for: anime)
        XCTAssertEqual(resume?.sourceKey, "p:voice:6:4")
        XCTAssertEqual(resume?.episode, 4)
        snapshot = await repo.snapshot()
        let roundtrip = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(roundtrip, snapshot)
    }
    func testLegacyEpisodeAndLibraryDecodeWithoutSourceOrRussianFields() throws {
        let ep = try JSONDecoder().decode(Episode.self, from: Data(#"{"animeId":1,"season":1,"number":1}"#.utf8))
        XCTAssertNil(ep.sourceEpisode)
        let title = try JSONDecoder().decode(AnimeTitle.self, from: Data(#"{"romaji":"Test"}"#.utf8))
        XCTAssertNil(title.russian)
        let progress = try JSONDecoder().decode(WatchProgress.self, from: Data(#"{"animeId":1,"episode":1,"position":12,"duration":100,"updatedAt":0}"#.utf8))
        XCTAssertNil(progress.sourceKey)
    }
    func testSourceScopeSurvivesSyncDTOAndNoTitleBasedGuess() throws {
        let p = WatchProgress(animeId: 1, episode: 4, position: 20, duration: 100, sourceKey: "kodik:material#voice:6:4")
        let row = ProgressRow(progress: p, userID: "user")
        let decoded = try SupabaseSyncService.decoder.decode(ProgressRow.self, from: SupabaseSyncService.encoder.encode(row))
        XCTAssertEqual(decoded.model.sourceKey, p.sourceKey)
        let info = RussianMetadataService.Metadata(id: 2, name: "Same", russian: "Проверяемое название", synonyms: [], english: [], description: nil)
        XCTAssertNil(info.apply(to: makeAnime(id: 1)).title.russian, "title similarity cannot replace MAL identity")
    }
    func testRussianTitleAliasTransliterationTyposAndRanking() {
        var slime = Anime(id: 1, title: .init(romaji: "Tensei shitara Slime Datta Ken", english: "That Time I Got Reincarnated as a Slime", russian: "О моём перерождении в слизь"), synonyms: ["Tensura"])
        XCTAssertEqual(slime.title.preferred, "О моём перерождении в слизь")
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "СЛИЗЬ", anime: slime), 0)
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "ТенСура", anime: slime), 0)
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "tensuraa", anime: slime), 0)
        XCTAssertGreaterThan(CatalogSearchRanking.score(query: "О моем перерождении в слизь", anime: slime), CatalogSearchRanking.score(query: "Слизь", anime: slime))
        XCTAssertEqual(CatalogSearchRanking.score(query: "Naruto", anime: slime), 0)
        slime.synonyms.append("О моём перерождении в слизь")
        XCTAssertEqual(Set(slime.allTitles).count, slime.allTitles.count)
    }
}
