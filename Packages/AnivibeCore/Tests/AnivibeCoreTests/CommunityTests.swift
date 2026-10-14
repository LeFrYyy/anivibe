import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

/// Prepared XCTest suite; must be run with Swift/Xcode, not inferred from source scans.
final class CommunityTests: XCTestCase {
    private let userId = "00000000-0000-0000-0000-00000000000a"
    func service(_ transport: StubTransport) -> SupabaseCommunityService {
        let config = AppConfiguration.Supabase(url: URL(string: "https://example.supabase.co")!, anonKey: "public-test-key")
        let session = AuthSession(accessToken: "user-jwt", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), user: AuthUser(id: userId, email: nil))
        let auth = SupabaseAuthClient(config: config, transport: transport, store: InMemoryTokenStore(session))
        return SupabaseCommunityService(config: config, auth: auth, transport: transport)
    }
    func testReconciliationUsesElapsedMonotonicTimeNotWallClock() {
        XCTAssertEqual(WatchReconciliation.target(anchor: 10, elapsed: 3, playing: true, duration: 100), 13)
        XCTAssertEqual(WatchReconciliation.target(anchor: 10, elapsed: 999, playing: true, duration: 100), 40)
        XCTAssertEqual(WatchReconciliation.target(anchor: 10, elapsed: -20, playing: true, duration: 100), 10)
    }
    func testPausedPositionDoesNotAdvanceAndClampsAtDuration() {
        XCTAssertEqual(WatchReconciliation.target(anchor: 10, elapsed: 10, playing: false, duration: 100), 10)
        XCTAssertEqual(WatchReconciliation.target(anchor: 95, elapsed: 10, playing: true, duration: 100), 100)
    }
    func testNonFinitePositionsDoNotCauseSeeks() {
        XCTAssertFalse(WatchReconciliation.needsSeek(local: .nan, target: 10))
        XCTAssertFalse(WatchReconciliation.needsSeek(local: 10, target: .infinity))
        XCTAssertEqual(WatchReconciliation.target(anchor: .nan, elapsed: .nan, playing: true, duration: nil), 0)
    }
    func testTinyDriftDoesNotSeekEveryHeartbeat() {
        XCTAssertFalse(WatchReconciliation.needsSeek(local: 10, target: 11.4))
        XCTAssertTrue(WatchReconciliation.needsSeek(local: 10, target: 12))
    }
    func testPurchaseSendsOnlyItemAndIdempotencyKey() async throws {
        let nonce = UUID()
        let transport = StubTransport { _ in (200, Data(#"{"item_id":"friends_15","balance":700,"charged":300,"replayed":false}"#.utf8), [:]) }
        let receipt = try await service(transport).purchase(itemId: "friends_15", requestId: nonce, userId: userId)
        XCTAssertEqual(receipt.balance, 700)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(Set(request.bodyJSON.keys), ["p_item", "p_request"])
        XCTAssertEqual(request.bodyJSON["p_request"] as? String, nonce.uuidString)
        XCTAssertNil(request.bodyJSON["price"]); XCTAssertNil(request.bodyJSON["user_id"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user-jwt")
    }
    func testAccountMismatchCannotIssuePurchase() async {
        let transport = StubTransport { _ in (200, Data(), [:]) }
        do { _ = try await service(transport).purchase(itemId: "friends_15", requestId: UUID(), userId: "other"); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .wrongAccount) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testMissingCommunityMigrationHasExplicitError() async {
        let transport = StubTransport { _ in (404, Data(#"{"code":"PGRST202"}"#.utf8), [:]) }
        do { _ = try await service(transport).hub(userId: userId); XCTFail() }
        catch { XCTAssertEqual(error as? CommunityError, .unavailable) }
    }
    func testNaNProgressNeverLeavesClient() async {
        let transport = StubTransport { _ in (200, Data(), [:]) }
        do { _ = try await service(transport).heartbeat(roomId: "r", episodeId: "e", mappingId: "m", eventId: UUID(), clientId: UUID(), sequence: 1, position: .nan, duration: 100, state: "playing", userId: userId); XCTFail() }
        catch {}
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testCanonicalDescriptorSupportsStringAndOriginalRawValueObject() throws {
        for provider in [#""kodik""#, #"{"rawValue":"kodik"}"#] {
            let json = """
            {"id":"mapping","provider_id":"kodik","voice":"Voice","source_offset":0,"verified":true,
             "source_episode":{"providerID":\(provider),"titleID":"title","season":2,"number":1,"title":"Special","payload":"{}"}}
            """
            let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
            let mapping = try decoder.decode(WatchSourceMapping.self, from: Data(json.utf8))
            XCTAssertEqual(mapping.sourceEpisode.providerID.rawValue, "kodik")
            XCTAssertEqual(mapping.sourceEpisode.season, 2); XCTAssertEqual(mapping.sourceEpisode.number, 1)
        }
    }
    func testLevelPreservesArbitrarilyLargeXpAsText() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value = try decoder.decode(FriendshipLevel.self, from: Data(#"{"level":400,"xp":"1000000000000000000000000000000","in_level":"10","needed":"1000","progress":0.01}"#.utf8))
        XCTAssertEqual(value.level, 400); XCTAssertEqual(value.xp.count, 31); XCTAssertEqual(value.progress, 0.01)
    }
    func testMarkReadDecodesAtomicClaim() async throws {
        let transport = StubTransport { _ in (200, Data("true".utf8), [:]) }
        let claimed = try await service(transport).readNotification("notice", userId: userId)
        XCTAssertTrue(claimed)
    }
}
