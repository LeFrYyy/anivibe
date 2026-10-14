import XCTest
@testable import AnivibeCore

/// Platform-independent regressions. Run with `swift test` / the existing macOS CI.
/// SwiftUI animation timing, AVPlayer and UIKit decoding still need an iOS device.
final class MotionPerformanceTests: XCTestCase {
    func testSmallPosterUsesDisplayPixelsRatherThan1600() {
        let target = ImageDownsampling.targetSize(width: 40, height: 60, scale: 3)
        XCTAssertEqual(target, ImageDecodeSize(width: 128, height: 192))
        let pixels = ImageDownsampling.thumbnailPixelSize(sourceWidth: 1200, sourceHeight: 1800, target: target)
        XCTAssertEqual(pixels, 192)
    }

    func testGridPosterKeepsRetinaResolution() {
        let target = ImageDownsampling.targetSize(width: 130, height: 195, scale: 3)
        XCTAssertEqual(target, ImageDecodeSize(width: 512, height: 768))
        let pixels = ImageDownsampling.thumbnailPixelSize(sourceWidth: 1200, sourceHeight: 1800, target: target)
        XCTAssertEqual(pixels, 768)
    }

    func testNearbyLayoutSizesShareCacheBucket() {
        XCTAssertEqual(ImageDownsampling.targetSize(width: 120, height: 180, scale: 2),
                       ImageDownsampling.targetSize(width: 121, height: 181, scale: 2))
    }

    func testWideBannerUsesAspectFillRatherThanLongestDisplaySide() {
        let pixels = ImageDownsampling.thumbnailPixelSize(
            sourceWidth: 1900, sourceHeight: 400, target: ImageDecodeSize(width: 600, height: 200)
        )
        XCTAssertEqual(pixels, 950, "A 600 px decode would blur the vertically cropped banner.")
    }

    func testSmallOriginalIsNeverUpscaledAndLargeDecodeIsCapped() {
        XCTAssertEqual(ImageDownsampling.thumbnailPixelSize(sourceWidth: 60, sourceHeight: 90, target: .full), 90)
        XCTAssertEqual(ImageDownsampling.thumbnailPixelSize(sourceWidth: 6000, sourceHeight: 4000, target: .full), 1600)
    }

    func testInvalidGeometryAndSourceDimensionsAreSafe() {
        let target = ImageDownsampling.targetSize(width: .nan, height: -.infinity, scale: .nan)
        XCTAssertEqual(target, ImageDecodeSize(width: 64, height: 64))
        XCTAssertEqual(ImageDownsampling.thumbnailPixelSize(sourceWidth: 0, sourceHeight: .nan, target: target), 1600)
        XCTAssertEqual(ImageDecodeSize(width: Int.min, height: Int.max), ImageDecodeSize(width: 1, height: 1600))
    }

    func testContinueWatchingAcceptsZeroAndNegativeLimits() async {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        let anime = AnimeSnapshot(id: 1, title: "Test", episodeCount: 12)
        await repo.recordProgress(anime: anime, episode: 1, position: 20, duration: 100)
        let zero = await repo.continueWatching(limit: 0)
        let negative = await repo.continueWatching(limit: -1)
        XCTAssertTrue(zero.isEmpty)
        XCTAssertTrue(negative.isEmpty)
    }

    func testCorruptExtremeEpisodeDoesNotOverflowResumePoint() {
        let state = LibrarySnapshot(progress: [
            WatchProgress(animeId: 1, episode: Int.max, position: 100, duration: 100)
        ])
        XCTAssertNil(LibraryRepository.resumePoint(in: state, animeId: 1, lastAvailableEpisode: nil))
    }

    func testDuplicateLegacyEntriesPreserveFirstEntryWithoutDictionaryTrap() async {
        let anime = AnimeSnapshot(id: 1, title: "Duplicate", episodeCount: 12)
        let state = LibrarySnapshot(entries: [
            LibraryEntry(anime: anime, status: .completed),
            LibraryEntry(anime: anime, status: .watching)
        ], progress: [WatchProgress(animeId: 1, episode: 1, position: 20, duration: 100)])
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence(state))
        let continuing = await repo.continueWatching()
        XCTAssertTrue(continuing.isEmpty)
    }

    func testEqualTimestampsHaveStableTitleIDOrder() async {
        let time = Date(timeIntervalSince1970: 1000)
        let entries = [3, 1, 2].map { LibraryEntry(anime: AnimeSnapshot(id: $0, title: "\($0)"), status: .watching) }
        let progress = [3, 1, 2].map { WatchProgress(animeId: $0, episode: 1, position: 20, duration: 100, updatedAt: time) }
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence(LibrarySnapshot(entries: entries, progress: progress)))
        let continuing = await repo.continueWatching()
        XCTAssertEqual(continuing.map(\.id), [1, 2, 3])
    }

    func testSourceScopedProgressNeverGuessesNextEpisode() async {
        let anime = AnimeSnapshot(id: 1, title: "Source", episodeCount: 24)
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        await repo.recordProgress(anime: anime, episode: 4, position: 25, duration: 100, sourceKey: "kodik:voice:6:4")
        let unfinished = await repo.continueWatching()
        XCTAssertEqual(unfinished.first?.resume.sourceKey, "kodik:voice:6:4")
        XCTAssertEqual(unfinished.first?.resume.episode, 4)
        await repo.recordProgress(anime: anime, episode: 4, position: 100, duration: 100, sourceKey: "kodik:voice:6:4")
        let finished = await repo.continueWatching()
        XCTAssertTrue(finished.isEmpty)
    }

    func testLargeLibraryUsesSameResumeSemanticsAndHonorsLimit() async {
        var entries: [LibraryEntry] = []
        var progress: [WatchProgress] = []
        for id in 1...400 {
            let anime = AnimeSnapshot(id: id, title: "Title \(id)", episodeCount: 24)
            entries.append(LibraryEntry(anime: anime, status: .watching))
            for episode in 1...12 {
                progress.append(WatchProgress(animeId: id, episode: episode, position: 20, duration: 100,
                                              updatedAt: Date(timeIntervalSince1970: Double(id * 100 + episode))))
            }
        }
        let state = LibrarySnapshot(entries: entries, progress: progress)
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence(state))
        let view = await repo.viewState(limit: 60)
        XCTAssertEqual(view.snapshot, state)
        XCTAssertEqual(view.continueWatching.map(\.id), Array(stride(from: 400, through: 341, by: -1)))
        for item in view.continueWatching {
            XCTAssertEqual(item.resume, LibraryRepository.resumePoint(in: state, animeId: item.id, lastAvailableEpisode: 24))
            XCTAssertEqual(item.resume.episode, 12)
        }
    }

    func testViewStateKeepsAccountSnapshotAndContinueRowTogether() async throws {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        let account = "10000000-0000-0000-0000-000000000001"
        try await repo.switchAccount(userID: account)
        let anime = AnimeSnapshot(id: 8, title: "Account", episodeCount: 12)
        await repo.recordProgressForAccount(anime: anime, episode: 2, position: 50, duration: 100, accountID: account)
        let view = await repo.viewState()
        XCTAssertEqual(view.accountID, account)
        XCTAssertEqual(view.snapshot.progress.first?.position, 50)
        XCTAssertEqual(view.continueWatching.first?.resume.position, 50)
        XCTAssertNil(view.errorMessage)
        try await repo.switchAccount(userID: nil)
        let guest = await repo.viewState()
        XCTAssertNil(guest.accountID)
        XCTAssertTrue(guest.snapshot.progress.isEmpty)
        XCTAssertTrue(guest.continueWatching.isEmpty)
    }

    func testViewStateIncludesStorageFailureWithoutInventingData() async {
        let repo = LibraryRepository(persistence: UnreadablePersistence())
        let view = await repo.viewState()
        XCTAssertEqual(view.snapshot, .empty)
        XCTAssertTrue(view.continueWatching.isEmpty)
        XCTAssertNotNil(view.errorMessage)
    }
}

private struct UnreadablePersistence: LibraryPersistence {
    func load() throws -> LibrarySnapshot { throw CocoaError(.fileReadCorruptFile) }
    func save(_ snapshot: LibrarySnapshot) throws { throw CocoaError(.fileWriteUnknown) }
}
