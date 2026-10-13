import XCTest
@testable import AnivibeCore

final class AccountAndHistoryTests: XCTestCase {
    func testAccountsAndGuestNeverShareUnsyncedPrivateLibrary() async throws {
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence())
        let guest = AnimeSnapshot(id: 1, title: "Guest")
        let a = AnimeSnapshot(id: 2, title: "A")
        await repo.setStatus(.planned, for: guest)
        try await repo.switchAccount(userID: "A")
        var snapshot = await repo.snapshot()
        XCTAssertTrue(snapshot.entries.isEmpty)
        await repo.setStatus(.watching, for: a)
        try await repo.switchAccount(userID: "B")
        await repo.recordProgressForAccount(anime: a, episode: 1, position: 10, duration: 100, accountID: "A")
        snapshot = await repo.snapshot(); XCTAssertTrue(snapshot.entries.isEmpty)
        XCTAssertTrue(snapshot.progress.isEmpty, "old player callbacks cannot write into another account")
        let accepted = await repo.applySync(entries: [LibraryEntry(anime: a)], progress: [], history: [], accountID: "A", startedAt: Date())
        XCTAssertFalse(accepted, "an in-flight sync cannot write into another account")
        try await repo.switchAccount(userID: "A")
        snapshot = await repo.snapshot(); XCTAssertEqual(snapshot.entries.map(\.id), [2])
        try await repo.switchAccount(userID: nil)
        snapshot = await repo.snapshot(); XCTAssertEqual(snapshot.entries.map(\.id), [1])
    }
    func testHistoryDeletionSurvivesRemoteMergeAndPersistence() async throws {
        let clock = Clock()
        let store = InMemoryLibraryPersistence()
        let repo = LibraryRepository(persistence: store, now: { clock.now })
        await repo.recordProgress(anime: .init(id: 1, title: "Test"), episode: 1, position: 2, duration: 100)
        var snapshot = await repo.snapshot()
        let original = try XCTUnwrap(snapshot.history.first)
        clock.advance(5)
        await repo.removeHistoryItem(id: original.id)
        await repo.merge(entries: [], progress: [], history: [original])
        snapshot = await repo.snapshot()
        XCTAssertTrue(snapshot.history.isEmpty)
        XCTAssertEqual(snapshot.historyTombstones?.count, 1)
        let changes = await repo.changes(since: clock.now.addingTimeInterval(-2))
        XCTAssertEqual(changes.history.first?.deletedAt, clock.now)
        let restored = LibraryRepository(persistence: store)
        let afterRestart = await restored.snapshot()
        XCTAssertEqual(afterRestart.historyTombstones, snapshot.historyTombstones)
        let row = HistoryRow(item: try XCTUnwrap(snapshot.historyTombstones?.first), userID: "u")
        XCTAssertEqual(row.model.deletedAt, clock.now)
    }
    func testCorruptLibraryDoesNotOverwriteOriginal() async {
        final class BrokenStore: LibraryPersistence, @unchecked Sendable {
            var writes = 0
            func load() throws -> LibrarySnapshot { throw APIError.decoding("corrupt") }
            func save(_ snapshot: LibrarySnapshot) throws { writes += 1 }
        }
        let store = BrokenStore()
        let repo = LibraryRepository(persistence: store)
        await repo.setStatus(.planned, for: .init(id: 1, title: "Test"))
        XCTAssertEqual(store.writes, 0)
        let error = await repo.lastSaveError
        XCTAssertNotNil(error)
    }
}
