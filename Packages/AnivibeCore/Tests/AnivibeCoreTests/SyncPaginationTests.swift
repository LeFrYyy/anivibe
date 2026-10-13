import XCTest
@testable import AnivibeCore
final class SyncPaginationTests: XCTestCase {
    func testMoreThanFiveHundredRowsAreNotTruncated() async throws {
        let clock = Clock()
        let user = AuthUser(id: "user-1", email: nil)
        let session = AuthSession(accessToken: "test", refreshToken: "r", expiresAt: clock.now.addingTimeInterval(3000), user: user)
        let config = AppConfiguration.Supabase(url: URL(string: "https://example.supabase.co")!, anonKey: "test")
        let transport = StubTransport { request in
            guard request.url!.path.hasSuffix("library_entries") else { return (200, Data("[]".utf8), [:]) }
            let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value ?? "0"
            let ids = offset == "0" ? Array(1...500) : [501]
            let entries: [[String: Any]] = ids.map { ["user_id":"user-1", "anime_id":$0, "title":"Title \($0)",
                "status":"planned", "is_favorite":false, "is_deleted":false, "updated_at":"2026-10-11T10:00:00Z"] }
            return (200, try JSONSerialization.data(withJSONObject: entries), [:])
        }
        let repo = LibraryRepository(persistence: InMemoryLibraryPersistence(), now: { clock.now })
        try await repo.switchAccount(userID: "user-1")
        let auth = SupabaseAuthClient(config: config, transport: transport, store: InMemoryTokenStore(session), now: { clock.now })
        let sync = SupabaseSyncService(config: config, transport: transport, auth: auth, library: repo, now: { clock.now })
        let report = try await sync.sync()
        XCTAssertEqual(report.pulled, 501)
        let snapshot = await repo.snapshot()
        XCTAssertNotNil(snapshot.entry(for: 501))
        XCTAssertTrue(transport.requests.contains { $0.url!.query!.contains("offset=500") })
    }
}
