import Foundation
import XCTest
@testable import AnivibeCore

final class Bugfix20261015Tests: XCTestCase {
    private let anime = AnimeSnapshot(id: 15, title: "Resume regression", episodeCount: 12)
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func sourceEpisode(_ number: Int, season: Int = 6, index: Int = 1,
                               voiceID: String = "serial-15#111") -> Episode {
        let source = ProviderEpisode(providerID: KodikProvider.providerID, titleID: voiceID,
                                     season: season, number: number, payload: "{}")
        return Episode(animeId: anime.id, season: season, number: index, sourceEpisode: source)
    }

    private func resume(_ episode: Episode, finished: Bool = false) -> ResumePoint {
        ResumePoint(animeId: episode.animeId, episode: episode.progressNumber,
                    position: finished ? 100 : 25, fraction: finished ? 1 : 0.25,
                    isNextEpisode: false, sourceKey: episode.sourceKey)
    }

    func testDroppedListIsIndependentAndKeepsFavoritesAndHistory() async {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        await repo.recordProgress(anime: anime, episode: 2, position: 40, duration: 100)
        await repo.setFavorite(true, for: anime)
        await repo.setStatus(.dropped, for: anime)
        let snapshot = await repo.snapshot()
        let continuing = await repo.continueWatching()
        XCTAssertEqual(snapshot.entries(in: .dropped).map(\.id), [anime.id])
        XCTAssertTrue(snapshot.entries(in: .onHold).isEmpty)
        XCTAssertEqual(snapshot.favorites.count, 1)
        XCTAssertEqual(snapshot.history.count, 1)
        XCTAssertEqual(snapshot.progress.count, 1)
        XCTAssertTrue(continuing.isEmpty)
        XCTAssertEqual(LibraryStatus.dropped.localizedName, "Брошено")
    }

    func testDroppedStatusSurvivesPersistenceAndSyncDTO() throws {
        let entry = LibraryEntry(anime: anime, status: .dropped, isFavorite: true, updatedAt: date)
        let snapshot = LibrarySnapshot(entries: [entry])
        let data = try FileLibraryPersistence.encoder.encode(snapshot)
        let restored = try FileLibraryPersistence.decoder.decode(LibrarySnapshot.self, from: data)
        XCTAssertEqual(restored.entries.first?.status, .dropped)
        let row = EntryRow(entry: entry, userID: "user")
        let decoded = try SupabaseSyncService.decoder.decode(EntryRow.self,
            from: SupabaseSyncService.encoder.encode(row))
        XCTAssertEqual(decoded.model.status, .dropped)
        XCTAssertEqual(LibraryStatus(rawValue: "onHold"), .onHold)
        XCTAssertEqual(Set(LibraryStatus.allCases.map(\.rawValue)).count, 5)
    }

    func testBackgroundProgressDoesNotSilentlyCompleteADroppedTitle() async {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        await repo.setStatus(.dropped, for: anime)
        await repo.recordProgress(anime: anime, episode: 12, position: 100, duration: 100)
        let snapshot = await repo.snapshot()
        XCTAssertEqual(snapshot.entry(for: anime.id)?.status, .dropped)
    }

    func testFileRestartPreservesSubsecondOrderingOfDifferentEpisodes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("anivibe-bugfix-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = Clock(date.addingTimeInterval(0.125))
        let repo = LibraryRepository(persistence: FileLibraryPersistence(fileURL: url), now: { clock.now })
        await repo.recordProgress(anime: anime, episode: 1, position: 10, duration: 100)
        clock.advance(0.5)
        await repo.recordProgress(anime: anime, episode: 4, position: 42, duration: 100)
        let restarted = LibraryRepository(persistence: FileLibraryPersistence(fileURL: url))
        let snapshot = await restarted.snapshot()
        let point = await restarted.resumePoint(for: anime)
        XCTAssertEqual(point?.episode, 4)
        XCTAssertEqual(point?.position, 42)
        XCTAssertEqual(try XCTUnwrap(snapshot.progress(animeId: anime.id, episode: 1)).updatedAt.timeIntervalSince1970,
                       date.addingTimeInterval(0.125).timeIntervalSince1970, accuracy: 0.002)
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains(".625Z"))
    }

    func testLegacyDatesWithoutFractionalSecondsStillLoad() throws {
        let legacy = JSONEncoder()
        legacy.dateEncodingStrategy = .iso8601
        let snapshot = LibrarySnapshot(entries: [LibraryEntry(anime: anime, status: .watching, updatedAt: date)],
            progress: [WatchProgress(animeId: anime.id, episode: 3, position: 31, duration: 100, updatedAt: date)])
        let restored = try FileLibraryPersistence.decoder.decode(LibrarySnapshot.self, from: legacy.encode(snapshot))
        XCTAssertEqual(restored.entries.first?.updatedAt, date)
        XCTAssertEqual(restored.progress.first?.position, 31)
    }

    func testLegacyEqualTimestampsPreferLastOpenedEpisodeNotArrayFirst() {
        let snapshot = LibrarySnapshot(entries: [
            LibraryEntry(anime: anime, status: .watching, lastEpisode: 4, updatedAt: date)
        ], progress: [
            WatchProgress(animeId: anime.id, episode: 4, position: 44, duration: 100, updatedAt: date),
            WatchProgress(animeId: anime.id, episode: 1, position: 11, duration: 100, updatedAt: date)
        ])
        let point = LibraryRepository.resumePoint(in: snapshot, animeId: anime.id, lastAvailableEpisode: 12)
        XCTAssertEqual(point?.episode, 4)
        XCTAssertEqual(snapshot.latestProgress(animeId: anime.id)?.position, 44)
    }

    func testEqualTimestampsWithoutEntryHintPreferLastWrittenProgress() {
        let snapshot = LibrarySnapshot(progress: [
            WatchProgress(animeId: anime.id, episode: 1, position: 11, duration: 100, updatedAt: date),
            WatchProgress(animeId: anime.id, episode: 4, position: 44, duration: 100, updatedAt: date)
        ])
        let point = LibraryRepository.resumePoint(in: snapshot, animeId: anime.id, lastAvailableEpisode: 12)
        XCTAssertEqual(point?.episode, 4)
    }

    func testLateOldPlayerCannotOverwriteNewPositionForSameSource() async {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        let key = "kodik:serial-15#111:6:4"
        await repo.recordProgress(anime: anime, episode: 4, position: 70, duration: 100,
                                  sourceKey: key, recordedAt: date.addingTimeInterval(2))
        await repo.recordProgress(anime: anime, episode: 4, position: 10, duration: 100,
                                  sourceKey: key, recordedAt: date.addingTimeInterval(1))
        let snapshot = await repo.snapshot()
        XCTAssertEqual(snapshot.progress(animeId: anime.id, episode: 4, sourceKey: key)?.position, 70)
        XCTAssertEqual(snapshot.history.first?.watchedAt, date.addingTimeInterval(2))
    }

    func testLatePreviousEpisodeDoesNotChangeResumeOrLastEpisode() async {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        await repo.recordProgress(anime: anime, episode: 5, position: 50, duration: 100,
                                  recordedAt: date.addingTimeInterval(2))
        await repo.recordProgress(anime: anime, episode: 1, position: 80, duration: 100,
                                  recordedAt: date.addingTimeInterval(1))
        let snapshot = await repo.snapshot()
        let point = await repo.resumePoint(for: anime)
        XCTAssertEqual(snapshot.entry(for: anime.id)?.lastEpisode, 5)
        XCTAssertEqual(point?.episode, 5)
        XCTAssertEqual(snapshot.history.first?.episode, 5)
        XCTAssertEqual(snapshot.progress(animeId: anime.id, episode: 1)?.position, 80)
    }

    func testUnknownDurationDoesNotEraseKnownDurationAndZeroSeekPersists() async {
        let clock = Clock(date)
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence(), now: { clock.now })
        await repo.recordProgress(anime: anime, episode: 2, position: 40, duration: 100)
        clock.advance(1)
        await repo.recordProgress(anime: anime, episode: 2, position: 0, duration: 0)
        let progress = await repo.progress(animeId: anime.id, episode: 2)
        XCTAssertEqual(progress?.position, 0)
        XCTAssertEqual(progress?.duration, 100)
    }

    func testFinishedSourceKeepsRecentCardAndExactAnchorAfterRestart() async {
        let persistence = InMemoryLibraryPersistence()
        let repo = LibraryRepository(persistence: persistence)
        let key = "kodik:serial-15#111:6:4"
        await repo.recordProgress(anime: anime, episode: 4, position: 100, duration: 100, sourceKey: key)
        let restarted = LibraryRepository(persistence: persistence)
        let items = await restarted.continueWatching()
        let snapshot = await restarted.snapshot()
        XCTAssertEqual(items.first?.resume.sourceKey, key)
        XCTAssertEqual(items.first?.resume.episode, 4)
        XCTAssertEqual(items.first?.resume.isFinishedSourceEpisode, true)
        XCTAssertEqual(items.first?.resume.isNextEpisode, false)
        XCTAssertEqual(snapshot.history.count, 1)
        XCTAssertEqual(snapshot.entry(for: anime.id)?.status, .watching)
    }

    func testFinishedSourceAdvancesOnlyUsingActualListIncludingNumberGaps() {
        let first = sourceEpisode(4)
        let next = sourceEpisode(7, index: 2)
        let resolved = KodikProvider.resumeEpisode(for: resume(first, finished: true), in: [first, next])
        XCTAssertEqual(resolved?.sourceKey, next.sourceKey)
        XCTAssertEqual(resolved?.progressNumber, 7, "do not guess provider episode 5")
        XCTAssertEqual(resolved?.number, 2, "player uses the real list index")
    }

    func testFinishedSourceWithoutAvailableNextDoesNotRestartFirstEpisode() {
        let episode = sourceEpisode(4)
        XCTAssertNil(KodikProvider.resumeEpisode(for: resume(episode, finished: true), in: [episode]))
        XCTAssertEqual(KodikProvider.resumeEpisode(for: resume(episode), in: [episode])?.sourceKey, episode.sourceKey)
    }

    func testResumeNeverTransfersBetweenVoicesOrTitles() {
        let original = sourceEpisode(4)
        let otherVoice = sourceEpisode(4, voiceID: "serial-15#222")
        XCTAssertNil(KodikProvider.resumeEpisode(for: resume(original), in: [otherVoice]))
        let unrelated = Episode(animeId: 999, number: 1, sourceEpisode: original.sourceEpisode)
        XCTAssertNil(KodikProvider.resumeEpisode(for: resume(original), in: [unrelated]))
        XCTAssertNil(KodikProvider.resumeEpisode(for: resume(original, finished: true), in: [original, otherVoice]))
    }

    func testLatestProgressDisplayKeepsCatalogueAndSourceSeparate() {
        let snapshot = LibrarySnapshot(progress: [
            WatchProgress(animeId: anime.id, episode: 4, position: 20, duration: 100, updatedAt: date),
            WatchProgress(animeId: anime.id, episode: 4, position: 60, duration: 100,
                          updatedAt: date.addingTimeInterval(1), sourceKey: "source")
        ])
        XCTAssertEqual(snapshot.progress(animeId: anime.id, episode: 4)?.position, 20)
        XCTAssertEqual(snapshot.progress(animeId: anime.id, episode: 4, sourceKey: "source")?.position, 60)
        XCTAssertEqual(snapshot.latestProgress(animeId: anime.id, episode: 4)?.position, 60)
    }

    func testLateExitSampleDoesNotUndoHistoryDeletionButNewPlaybackCan() async {
        let clock = Clock(date)
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence(), now: { clock.now })
        await repo.recordProgress(anime: anime, episode: 2, position: 20, duration: 100)
        clock.advance(2)
        await repo.clearHistory()
        await repo.recordProgress(anime: anime, episode: 2, position: 30, duration: 100,
                                  recordedAt: date.addingTimeInterval(1))
        let deleted = await repo.snapshot()
        XCTAssertTrue(deleted.history.isEmpty)
        clock.advance(1)
        await repo.recordProgress(anime: anime, episode: 2, position: 40, duration: 100)
        let watchedAgain = await repo.snapshot()
        XCTAssertEqual(watchedAgain.history.count, 1)
        XCTAssertEqual(watchedAgain.history.first?.watchedAt, clock.now)
    }

    func testCapturedTimestampKeepsExistingAccountProtection() async throws {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        try await repo.switchAccount(userID: "A")
        try await repo.switchAccount(userID: "B")
        await repo.recordProgressForAccount(anime: anime, episode: 2, position: 20, duration: 100,
                                            accountID: "A", recordedAt: date)
        let snapshot = await repo.snapshot()
        XCTAssertTrue(snapshot.progress.isEmpty)
        XCTAssertTrue(snapshot.history.isEmpty)
    }

    func testRemovingOnlyListMembershipPreservesFavoriteAndProgress() async {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        await repo.recordProgress(anime: anime, episode: 3, position: 33, duration: 100)
        await repo.setFavorite(true, for: anime)
        await repo.setStatus(nil, for: anime)
        let snapshot = await repo.snapshot()
        XCTAssertNil(snapshot.entry(for: anime.id)?.status)
        XCTAssertEqual(snapshot.favorites.count, 1)
        XCTAssertEqual(snapshot.progress.count, 1)
        XCTAssertEqual(snapshot.history.count, 1)
    }

    func testRegistryAndDetailsUseSameSourceProgressIdentityAcrossVoices() throws {
        func voice(_ id: Int, title: String) -> KodikVoiceOption {
            KodikVoiceOption(materialID: "serial-15", translation: KodikTranslation(id: id, title: title, kind: .voice),
                title: "Title", year: 2026, quality: "720p",
                playerURL: URL(string: "https://kodik.info/video/15/hash")!,
                episodes: [KodikEpisode(season: 6, number: 4, title: nil,
                    playerURL: URL(string: "https://kodik.info/seria/\(id)/hash")!)],
                seasonPlayerURLs: [:])
        }
        let a = voice(111, title: "Voice A")
        let b = voice(222, title: "Voice B")
        let match = KodikMatch(materialID: "serial-15", matchedTitle: "Title", year: 2026, voices: [a, b])
        let merged = try XCTUnwrap(KodikProvider.makeEpisodes(match: match, titleID: "anime:15", preferredVoice: "Voice A").first)
        let exactA = try XCTUnwrap(KodikProvider.sourceEpisodes(for: a, animeID: anime.id).first)
        let exactB = try XCTUnwrap(KodikProvider.sourceEpisodes(for: b, animeID: anime.id).first)
        XCTAssertEqual(KodikProvider.progressEpisode(for: merged).id, exactA.sourceKey)
        let switched = KodikProvider.episode(merged, withVoice: "Voice B")
        XCTAssertEqual(KodikProvider.progressEpisode(for: switched).id, exactB.sourceKey)
        XCTAssertNotEqual(KodikProvider.progressEpisode(for: merged).id,
                          KodikProvider.progressEpisode(for: switched).id)
    }

    func testLegacyKodikPayloadStillProvidesItsOriginalProgressKey() {
        let payload = KodikProvider.Payload(selected: "Voice",
            voices: [.init(title: "Voice", url: "https://kodik.info/seria/1/hash")]).encoded()
        let episode = ProviderEpisode(providerID: KodikProvider.providerID, titleID: "legacy",
                                      season: 1, number: 2, payload: payload)
        XCTAssertEqual(KodikProvider.progressEpisode(for: episode).id, episode.id)
    }
}