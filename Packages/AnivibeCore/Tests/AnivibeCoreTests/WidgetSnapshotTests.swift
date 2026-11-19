import Foundation
import XCTest
@testable import AnivibeCore

final class WidgetSnapshotTests: XCTestCase {
    func testDeepLinkRoundTrip() {
        let url = WidgetSnapshot.deepLink(for: 16498)
        XCTAssertEqual(url?.absoluteString, "anivibe://anime/16498")
        XCTAssertEqual(WidgetSnapshot.animeID(from: url!), 16498)
    }

    func testDeepLinkRejectsForeignAndMalformedURLs() {
        XCTAssertNil(WidgetSnapshot.animeID(from: URL(string: "https://example.com/anime/1")!))
        XCTAssertNil(WidgetSnapshot.animeID(from: URL(string: "anivibe://auth/callback")!))
        XCTAssertNil(WidgetSnapshot.animeID(from: URL(string: "anivibe://anime/")!))
        XCTAssertNil(WidgetSnapshot.animeID(from: URL(string: "anivibe://anime/abc")!))
        XCTAssertNil(WidgetSnapshot.animeID(from: URL(string: "anivibe://anime/-5")!))
        XCTAssertNil(WidgetSnapshot.animeID(from: URL(string: "anivibe://anime/0")!))
    }

    func testProgressIsClampedAndFinite() {
        let item = WidgetSnapshot.Item(id: 1, title: "A", episode: 3, progress: 5)
        XCTAssertEqual(item.safeProgress, 1)
        XCTAssertEqual(item.percent, 100)
        let negative = WidgetSnapshot.Item(id: 1, title: "A", episode: 1, progress: -1)
        XCTAssertEqual(negative.safeProgress, 0)
        let nan = WidgetSnapshot.Item(id: 1, title: "A", episode: 1, progress: .nan)
        XCTAssertEqual(nan.safeProgress, 0)
    }

    func testSnapshotEncodesAndDecodesWithoutGroup() throws {
        let snapshot = WidgetSnapshot(continueWatching: [
            WidgetSnapshot.Item(id: 7, title: "Frieren", coverURL: URL(string: "https://x/c.jpg"), episode: 2, progress: 0.4)
        ], libraryCount: 12, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let data = try WidgetSnapshotStore.encoder.encode(snapshot)
        let decoded = try WidgetSnapshotStore.decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.primaryItem?.id, 7)
        XCTAssertEqual(decoded.version, WidgetSnapshot.currentVersion)
    }

    func testSnapshotBuildsFromContinueWatchingAndCapsAtSix() {
        let items = (1...9).map { index in
            ContinueWatchingItem(
                anime: AnimeSnapshot(id: index, title: "Title \(index)"),
                resume: ResumePoint(animeId: index, episode: index, position: 10, fraction: 0.5, isNextEpisode: false),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let snapshot = WidgetSnapshotStore.make(from: items, libraryCount: 9, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snapshot.continueWatching.count, 6)
        XCTAssertEqual(snapshot.continueWatching.map(\.id), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(snapshot.libraryCount, 9)
    }

    func testReadFallsBackToEmptyWhenFileMissing() {
        // В тестах App Group недоступен — read обязан вернуть пустой снимок, а не упасть.
        let snapshot = WidgetSnapshotStore.read()
        XCTAssertEqual(snapshot, .empty)
    }
}
