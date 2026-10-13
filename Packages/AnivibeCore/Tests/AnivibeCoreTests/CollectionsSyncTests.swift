import XCTest
@testable import AnivibeCore

final class CollectionsSyncTests: XCTestCase {
    let first = Date(timeIntervalSince1970: 1_800_000_000)
    func testDeleteTombstoneBeatsOldDevice() {
        var local = AnimeCollections(); let id = local.create(name: "Любимое")
        var document = CollectionsSyncState(); document.capture(local, at: first)
        let stale = document.records
        local.delete(id); document.capture(local, at: first.addingTimeInterval(10))
        document.merge(stale)
        XCTAssertTrue(document.visible.collections.isEmpty)
        XCTAssertTrue(document.records.first?.isDeleted == true)
        XCTAssertEqual(document.recordsToUpload.count, 1)
    }
    func testIndependentFoldersMergeAndKeepOrderedItems() {
        var a = AnimeCollections(); let id = a.create(name: "A", with: AnimeSnapshot(id: 1, title: "First"))
        a.add(AnimeSnapshot(id: 2, title: "Second"), to: id)
        var left = CollectionsSyncState(); left.capture(a, at: first)
        var b = AnimeCollections(); _ = b.create(name: "B")
        var right = CollectionsSyncState(); right.capture(b, at: first)
        left.merge(right.records)
        XCTAssertEqual(left.visible.collections.count, 2)
        XCTAssertEqual(left.visible.collection(id)?.items.map(\.id), [2,1])
    }
    func testLocalMutationDuringRequestRemainsDirty() {
        var folders = AnimeCollections(); let id = folders.create(name: "Before")
        var document = CollectionsSyncState(); document.capture(folders, at: first)
        let inFlight = document.records
        folders.rename(id, to: "After"); document.capture(folders, at: first.addingTimeInterval(5))
        document.merge(inFlight)
        XCTAssertEqual(document.visible.collection(id)?.name, "After")
        XCTAssertEqual(document.recordsToUpload.count, 1)
    }
    func testAcknowledgedFoldersAreNotUploadedAgain() {
        var folders = AnimeCollections(); _ = folders.create(name: "A")
        var document = CollectionsSyncState(); document.capture(folders, at: first)
        document.merge(document.records)
        XCTAssertTrue(document.recordsToUpload.isEmpty)
    }
    func testReorderIsCapturedAndRoundTrips() throws {
        var folders = AnimeCollections(); let a = folders.create(name: "A"); let b = folders.create(name: "B")
        var document = CollectionsSyncState(); document.capture(folders, at: first)
        folders.moveCollection(b, to: a); document.capture(folders, at: first.addingTimeInterval(5))
        let decoded = try JSONDecoder().decode(CollectionsSyncState.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.visible.collections.map(\.id), [b,a])
    }
    func testEqualTimestampHasDeterministicTieBreak() {
        let folder = AnimeCollection(name: "A")
        let low = CollectionSyncRecord(folder: folder, rank: 0, updatedAt: first,
            mutationID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        var changed = folder; changed.name = "B"
        let high = CollectionSyncRecord(folder: changed, rank: 0, updatedAt: first,
            mutationID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        var left = CollectionsSyncState(records: [low]); var right = CollectionsSyncState(records: [high])
        left.merge([high]); right.merge([low])
        XCTAssertEqual(left.visible, right.visible)
        XCTAssertEqual(left.visible.collections.first?.name, "B")
    }
    func testServerClampOfSameMutationIsAccepted() {
        let record = CollectionSyncRecord(folder: AnimeCollection(name: "A"), rank: 0, updatedAt: first.addingTimeInterval(3600))
        var canonical = record; canonical.updatedAt = first
        var document = CollectionsSyncState(records: [record]); document.merge([canonical])
        XCTAssertEqual(document.records.first?.updatedAt, first)
        XCTAssertTrue(document.recordsToUpload.isEmpty)
    }
}

final class CollectionsCloudTests: XCTestCase {
    private let owner = "00000000-0000-0000-0000-00000000000a"
    private func service(_ transport: StubTransport) -> SupabaseSyncService {
        let config = AppConfiguration.Supabase(url: URL(string: "https://example.supabase.co")!, anonKey: "test")
        let session = AuthSession(accessToken: "jwt", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), user: AuthUser(id: owner, email: nil))
        let auth = SupabaseAuthClient(config: config, transport: transport, store: InMemoryTokenStore(session))
        return SupabaseSyncService(config: config, transport: transport, auth: auth, library: LibraryRepository(persistence: InMemoryLibraryPersistence()))
    }
    func testAccountMismatchDoesNotSendFolderData() async {
        let transport = StubTransport { _ in (200, Data("[]".utf8), [:]) }
        do { _ = try await service(transport).syncCollections([], expectedUserID: "other"); XCTFail() }
        catch { XCTAssertEqual(error as? AuthError, .notSignedIn) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testFolderPayloadIncludesOrderItemsAndDeletionAndUsesUserJWT() async throws {
        let record = CollectionSyncRecord(folder: AnimeCollection(name: "A", items: [AnimeSnapshot(id: 1,title: "Title")]), rank: 3, isDeleted: true)
        let rows = [CollectionRow(record: record, userID: owner)]
        let response = try SupabaseSyncService.encoder.encode(rows)
        let transport = StubTransport { request in request.httpMethod == "POST" ? (204,Data(),[:]) : (200,response,[:]) }
        let result = try await service(transport).syncCollections([record], expectedUserID: owner)
        XCTAssertEqual(result.first?.rank, 3)
        XCTAssertTrue(result.first?.isDeleted == true)
        XCTAssertEqual(result.first?.folder.items.map(\.id), [1])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt")
        XCTAssertEqual(request.url?.path, "/rest/v1/account_collections")
        let sent = try SupabaseSyncService.decoder.decode([CollectionRow].self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(sent.first?.user_id, owner)
        XCTAssertEqual(sent.first?.mutation_id, record.mutationID)
    }
}
