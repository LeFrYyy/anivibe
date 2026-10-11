import XCTest
@testable import AnivibeCore

final class LibraryTests: XCTestCase {
    let anime = AnimeSnapshot(id: 1, title: "AoT", episodeCount: 3)

    private func repo(_ clock: Clock = Clock(), store: LibraryPersistence = InMemoryLibraryPersistence()) -> LibraryRepository {
        LibraryRepository(persistence: store, now: { clock.now })
    }

    func testStatusFavoriteAndRemove() async {
        let r = repo()
        await r.setStatus(.planned, for: anime)
        let fav = await r.toggleFavorite(anime)
        XCTAssertTrue(fav)
        var s = await r.snapshot()
        XCTAssertEqual(s.entries(in: .planned).map(\.id), [1])
        XCTAssertEqual(s.favorites.map(\.id), [1])

        await r.setStatus(.onHold, for: anime)
        s = await r.snapshot()
        XCTAssertTrue(s.entries(in: .planned).isEmpty)
        XCTAssertEqual(s.entries(in: .onHold).count, 1)

        await r.remove(animeId: 1)
        s = await r.snapshot()
        XCTAssertTrue(s.visibleEntries.isEmpty)
        XCTAssertTrue(s.entries.first?.isDeleted ?? false, "мягкое удаление для синхронизации")

        await r.setFavorite(true, for: anime)
        s = await r.snapshot()
        XCTAssertEqual(s.favorites.count, 1, "повторное добавление восстанавливает запись")
        XCTAssertNil(s.entry(for: 1)?.status)
    }

    func testRecordProgressUpdatesStatusLastEpisodeAndHistory() async {
        let clock = Clock()
        let r = repo(clock)
        await r.setStatus(.planned, for: anime)
        await r.recordProgress(anime: anime, episode: 1, position: 300, duration: 1440)
        var s = await r.snapshot()
        XCTAssertEqual(s.entry(for: 1)?.status, .watching)
        XCTAssertEqual(s.entry(for: 1)?.lastEpisode, 1)
        XCTAssertEqual(s.progress(animeId: 1, episode: 1)?.position, 300)
        XCTAssertEqual(s.history.count, 1)

        clock.advance(60)
        await r.recordProgress(anime: anime, episode: 1, position: 360, duration: 1440)
        s = await r.snapshot()
        XCTAssertEqual(s.history.count, 1, "повторные сохранения той же серии не дублируют историю")

        clock.advance(LibraryRepository.historyMergeWindow + 1)
        await r.recordProgress(anime: anime, episode: 1, position: 400, duration: 1440)
        s = await r.snapshot()
        XCTAssertEqual(s.history.count, 2)
    }

    func testFinishingLastEpisodeCompletes() async {
        let r = repo()
        await r.recordProgress(anime: anime, episode: 3, position: 1400, duration: 1440)
        let s = await r.snapshot()
        XCTAssertEqual(s.entry(for: 1)?.status, .completed)
    }

    func testInvalidProgressIgnored() async {
        let r = repo()
        await r.recordProgress(anime: anime, episode: 0, position: 10, duration: 100)
        await r.recordProgress(anime: anime, episode: 1, position: .nan, duration: 100)
        await r.recordProgress(anime: anime, episode: 1, position: -5, duration: 100)
        let s = await r.snapshot()
        XCTAssertTrue(s.progress.isEmpty)
        await r.recordProgress(anime: anime, episode: 1, position: 500, duration: 100)
        let p = await r.progress(animeId: 1, episode: 1)
        XCTAssertEqual(p?.position, 100, "позиция не превышает длительность")
    }

    func testResumePoint() async {
        let clock = Clock()
        let r = repo(clock)
        var rp = await r.resumePoint(for: anime)
        XCTAssertNil(rp)

        await r.recordProgress(anime: anime, episode: 1, position: 600, duration: 1440)
        rp = await r.resumePoint(for: anime)
        XCTAssertEqual(rp?.episode, 1)
        XCTAssertEqual(rp?.position, 600)
        XCTAssertEqual(rp?.isNextEpisode, false)

        clock.advance(10)
        await r.recordProgress(anime: anime, episode: 1, position: 1400, duration: 1440)
        rp = await r.resumePoint(for: anime)
        XCTAssertEqual(rp?.episode, 2)
        XCTAssertEqual(rp?.position, 0)
        XCTAssertEqual(rp?.isNextEpisode, true)

        clock.advance(10)
        await r.recordProgress(anime: anime, episode: 3, position: 1440, duration: 1440)
        rp = await r.resumePoint(for: anime)
        XCTAssertNil(rp, "после последней серии продолжать нечего")
    }

    func testResumeRespectsReleasedEpisodesOfOngoing() async {
        let ongoing = AnimeSnapshot(id: 9, title: "Ongoing", episodeCount: nil)
        let r = repo()
        await r.recordProgress(anime: ongoing, episode: 5, position: 1440, duration: 1440)
        let next = await r.resumePoint(for: ongoing, releasedEpisodes: 6)
        XCTAssertEqual(next?.episode, 6)
        let none = await r.resumePoint(for: ongoing, releasedEpisodes: 5)
        XCTAssertNil(none)
    }

    func testContinueWatchingOrderAndExclusions() async {
        let clock = Clock()
        let r = repo(clock)
        let other = AnimeSnapshot(id: 2, title: "Other", episodeCount: 12)
        let done = AnimeSnapshot(id: 3, title: "Done", episodeCount: 1)
        await r.recordProgress(anime: anime, episode: 1, position: 100, duration: 1000)
        clock.advance(5)
        await r.recordProgress(anime: other, episode: 4, position: 100, duration: 1000)
        clock.advance(5)
        await r.recordProgress(anime: done, episode: 1, position: 1000, duration: 1000)
        let items = await r.continueWatching()
        XCTAssertEqual(items.map(\.anime.id), [2, 1])
        XCTAssertEqual(items.first?.resume.fraction ?? 0, 0.1, accuracy: 0.0001)
    }

    func testMarkCompletedAndEpisodeWatched() async {
        let r = repo()
        await r.markEpisodeWatched(anime: anime, episode: 2)
        var p = await r.progress(animeId: 1, episode: 2)
        XCTAssertEqual(p?.isFinished, true)
        await r.markEpisodeWatched(anime: anime, episode: 2, watched: false)
        p = await r.progress(animeId: 1, episode: 2)
        XCTAssertNil(p)
        await r.markCompleted(anime)
        let s = await r.snapshot()
        XCTAssertEqual(s.entry(for: 1)?.status, .completed)
        XCTAssertEqual(s.entry(for: 1)?.lastEpisode, 3)
    }

    func testHistoryLimitAndClear() async {
        let clock = Clock()
        let r = repo(clock)
        for i in 1...(LibraryRepository.historyLimit + 20) {
            clock.advance(1)
            await r.recordProgress(anime: AnimeSnapshot(id: i, title: "\(i)"), episode: 1, position: 1, duration: 10)
        }
        var s = await r.snapshot()
        XCTAssertEqual(s.history.count, LibraryRepository.historyLimit)
        XCTAssertEqual(s.history.first?.anime.id, LibraryRepository.historyLimit + 20, "новые сверху")
        await r.clearHistory()
        s = await r.snapshot()
        XCTAssertTrue(s.history.isEmpty)
    }

    func testFilePersistenceRoundTrip() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("anivibe-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileLibraryPersistence(fileURL: url)
        let r1 = LibraryRepository(persistence: store)
        await r1.setStatus(.watching, for: anime)
        await r1.recordProgress(anime: anime, episode: 2, position: 42.5, duration: 1440)

        // «Перезапуск приложения»: новый репозиторий читает тот же файл.
        let r2 = LibraryRepository(persistence: FileLibraryPersistence(fileURL: url))
        let s = await r2.snapshot()
        XCTAssertEqual(s.entry(for: 1)?.status, .watching)
        XCTAssertEqual(s.progress(animeId: 1, episode: 2)?.position, 42.5)
        XCTAssertEqual(s.history.count, 1)
    }

    func testCorruptedFileDoesNotCrash() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("anivibe-bad-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{broken".utf8).write(to: url)
        let r = LibraryRepository(persistence: FileLibraryPersistence(fileURL: url))
        let s = await r.snapshot()
        XCTAssertTrue(s.entries.isEmpty)
        let err = await r.lastSaveError
        XCTAssertNotNil(err)
    }

    func testMergeLastWriteWins() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var local = LibrarySnapshot()
        local.entries = [LibraryEntry(anime: anime, status: .watching, updatedAt: t0.addingTimeInterval(10))]
        local.progress = [WatchProgress(animeId: 1, episode: 1, position: 100, duration: 1000, updatedAt: t0)]
        let remoteEntries = [
            LibraryEntry(anime: anime, status: .completed, updatedAt: t0),                       // старее — игнор
            LibraryEntry(anime: AnimeSnapshot(id: 2, title: "B"), isFavorite: true, updatedAt: t0) // новая
        ]
        let remoteProgress = [WatchProgress(animeId: 1, episode: 1, position: 500, duration: 1000, updatedAt: t0.addingTimeInterval(5))]
        let h = HistoryItem(anime: anime, episode: 1, watchedAt: t0)
        let merged = LibraryRepository.merged(local, entries: remoteEntries, progress: remoteProgress, history: [h, h])
        XCTAssertEqual(merged.entry(for: 1)?.status, .watching)
        XCTAssertEqual(merged.entry(for: 2)?.isFavorite, true)
        XCTAssertEqual(merged.progress(animeId: 1, episode: 1)?.position, 500)
        XCTAssertEqual(merged.history.count, 1, "история не дублируется по id")
    }

    func testChangesSince() async {
        let clock = Clock()
        let r = repo(clock)
        await r.setStatus(.watching, for: anime)
        let mark = clock.now
        clock.advance(1)
        await r.setFavorite(true, for: AnimeSnapshot(id: 2, title: "B"))
        let ch = await r.changes(since: mark)
        XCTAssertEqual(ch.entries.map(\.id), [2])
        let all = await r.changes(since: nil)
        XCTAssertEqual(all.entries.count, 2)
    }
}
