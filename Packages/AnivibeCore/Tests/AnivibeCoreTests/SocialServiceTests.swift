import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

final class SocialServiceTests: XCTestCase {
    static let actorID = "00000000-0000-0000-0000-00000000000a"
    static let targetID = "00000000-0000-0000-0000-00000000000b"
    static let row = """
    {"user_id":"00000000-0000-0000-0000-00000000000a","username":"alice_1","display_name":"Алиса","bio":"О себе","visibility":"private","created_at":"2026-10-13T10:00:00Z","updated_at":"2026-10-13T10:00:00Z"}
    """
    func service(_ t: StubTransport) -> SupabaseSocialService {
        let config = AppConfiguration.Supabase(url: URL(string: "https://example.supabase.co")!, anonKey: "sb_publishable_test")
        let session = AuthSession(accessToken: "user-jwt", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), user: AuthUser(id: Self.actorID, email: "private@example.com"))
        let auth = SupabaseAuthClient(config: config, transport: t, store: InMemoryTokenStore(session))
        return SupabaseSocialService(config: config, auth: auth, transport: t)
    }
    func testDraftNormalization() throws {
        let draft = try ProfileDraft(username: " Alice_1 ", displayName: " Алиса ", bio: " About ", visibility: .privateProfile).validated()
        XCTAssertEqual(draft.username, "alice_1"); XCTAssertEqual(draft.displayName, "Алиса"); XCTAssertEqual(draft.bio, "About")
    }
    func testInvalidDrafts() {
        for username in ["a", "админ", "x';drop table", "admin", String(repeating: "a", count: 25)] {
            XCTAssertThrowsError(try ProfileDraft(username: username, displayName: "User", bio: "", visibility: .privateProfile).validated())
        }
        XCTAssertThrowsError(try ProfileDraft(username: "valid", displayName: " ", bio: "", visibility: .privateProfile).validated())
        XCTAssertThrowsError(try ProfileDraft(username: "valid", displayName: "User", bio: String(repeating: "a", count: 501), visibility: .privateProfile).validated())
    }
    func testOwnProfileHeadersAndFilter() async throws {
        let t = StubTransport { _ in (200, Data("[\(Self.row)]".utf8), [:]) }
        let profile = try await service(t).ownProfile()
        XCTAssertEqual(profile.userID, Self.actorID)
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user-jwt")
        XCTAssertTrue(request.url!.absoluteString.contains(Self.actorID))
        XCTAssertFalse(request.url!.absoluteString.contains("private@example.com"))
    }
    func testProfilePatchHasNoOwnershipOrAdminFields() async throws {
        let t = StubTransport { _ in (200, Data("[\(Self.row)]".utf8), [:]) }
        _ = try await service(t).updateProfile(ProfileDraft(username: "alice_1", displayName: "Алиса", bio: "", visibility: .publicProfile))
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(Set(request.bodyJSON.keys), Set(["username", "display_name", "bio", "visibility"]))
        XCTAssertNil(request.bodyJSON["user_id"]); XCTAssertNil(request.bodyJSON["email"])
    }
    func testInvalidProfileDoesNotUseNetwork() async {
        let t = StubTransport { _ in (200, Data(), [:]) }
        do { _ = try await service(t).updateProfile(ProfileDraft(username: "a", displayName: "User", bio: "", visibility: .privateProfile)); XCTFail() } catch {}
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testTakenUsernameError() async {
        let t = StubTransport { _ in (409, Data(#"{"code":"23505"}"#.utf8), [:]) }
        do { _ = try await service(t).updateProfile(ProfileDraft(username: "alice_1", displayName: "User", bio: "", visibility: .privateProfile)); XCTFail() }
        catch { XCTAssertEqual(error as? SocialError, .usernameTaken) }
    }
    func testMissingMigrationIsExplicit() async {
        let t = StubTransport { _ in (404, Data(#"{"code":"PGRST205"}"#.utf8), [:]) }
        do { _ = try await service(t).ownProfile(); XCTFail() } catch { XCTAssertEqual(error as? SocialError, .backendMissing) }
    }
    func testFriendActionCannotSendActorOrStatus() async throws {
        let t = StubTransport { _ in (204, Data(), [:]) }
        try await service(t).friendAction(targetID: Self.targetID, action: .accept)
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.url?.path, "/rest/v1/rpc/anivibe_friend_action")
        XCTAssertEqual(Set(request.bodyJSON.keys), Set(["p_target", "p_action"]))
        XCTAssertEqual(request.bodyJSON["p_action"] as? String, "accept")
        XCTAssertEqual(request.bodyJSON["p_target"] as? String, Self.targetID)
    }
    func testInvalidFriendIDDoesNotUseNetwork() async {
        let t = StubTransport { _ in (204, Data(), [:]) }
        do { try await service(t).friendAction(targetID: "fake-id", action: .send); XCTFail() }
        catch { XCTAssertEqual(error as? SocialError, .denied) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testRateLimitError() async {
        let t = StubTransport { _ in (400, Data(#"{"code":"P0001","message":"request_rate_limited"}"#.utf8), [:]) }
        do { try await service(t).friendAction(targetID: Self.targetID, action: .send); XCTFail() }
        catch { XCTAssertEqual(error as? SocialError, .rateLimited) }
    }
    func testProfileAccountMismatchDoesNotUseNetwork() async {
        let t = StubTransport { _ in (200, Data(), [:]) }
        do {
            _ = try await service(t).updateProfile(ProfileDraft(username: "valid", displayName: "User", bio: "", visibility: .privateProfile), expectedUserID: Self.targetID)
            XCTFail()
        } catch { XCTAssertEqual(error as? AuthError, .notSignedIn) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testFriendAccountMismatchDoesNotUseNetwork() async {
        let t = StubTransport { _ in (204, Data(), [:]) }
        do { try await service(t).friendAction(targetID: Self.targetID, action: .send, expectedUserID: Self.targetID); XCTFail() }
        catch { XCTAssertEqual(error as? AuthError, .notSignedIn) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testSearchUsesServerRPC() async throws {
        let t = StubTransport { _ in (200, Data("[]".utf8), [:]) }
        _ = try await service(t).searchProfiles(username: " Alice ")
        XCTAssertEqual(t.requests.first?.url?.path, "/rest/v1/rpc/anivibe_search_profiles")
        XCTAssertEqual(t.requests.first?.bodyJSON["p_username"] as? String, "alice")
    }
    func testOldProfileWithoutAvatarStillDecodes() throws {
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(Self.row.utf8))
        XCTAssertNil(profile.avatarPath)
    }
    func testCommentsPaginationRequest() async throws {
        let t = StubTransport { _ in (200, Data("[]".utf8), [:]) }
        _ = try await service(t).comments(animeID: 123, offset: 20, popular: true)
        let req = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(req.url?.path, "/rest/v1/rpc/anivibe_comments")
        XCTAssertEqual(req.bodyJSON["p_anime"] as? Int, 123)
        XCTAssertEqual(req.bodyJSON["p_offset"] as? Int, 20)
        XCTAssertEqual(req.bodyJSON["p_popular"] as? Bool, true)
    }
    func testCommentActionHasNoActorOrCounters() async throws {
        let t = StubTransport { _ in (204, Data(), [:]) }
        try await service(t).commentAction(animeID: 123, action: "create", text: "Тест", expectedUserID: Self.actorID)
        let req = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(Set(req.bodyJSON.keys), Set(["p_anime","p_action","p_comment","p_text","p_value"]))
        XCTAssertTrue(req.bodyJSON["p_comment"] is NSNull)
        XCTAssertNil(req.bodyJSON["author_id"])
    }
    func testCommentAccountChangeDoesNotSend() async {
        let t = StubTransport { _ in (204, Data(), [:]) }
        do { try await service(t).commentAction(animeID: 123, action: "create", text: "Тест", expectedUserID: Self.targetID); XCTFail() }
        catch { XCTAssertEqual(error as? AuthError, .notSignedIn) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testAvatarUploadUsesUserJWTAndBinaryBody() async throws {
        let t = StubTransport { _ in (200, Data("{}".utf8), [:]) }
        let bytes = Data([255,216,255,217])
        try await service(t).setAvatar(jpeg: bytes, expectedUserID: Self.actorID)
        let req = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(req.url?.path, "/functions/v1/avatar")
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertEqual(req.httpBody, bytes)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer user-jwt")
    }
    func testAvatarDeleteAndNullLink() async throws {
        let t = StubTransport { _ in (200, Data(#"{"url":null}"#.utf8), [:]) }
        try await service(t).setAvatar(jpeg: nil, expectedUserID: Self.actorID)
        let url = try await service(t).avatarURL(userID: Self.targetID)
        XCTAssertNil(url)
        XCTAssertEqual(t.requests.first?.httpMethod, "DELETE")
        XCTAssertEqual(t.requests.last?.bodyJSON["user_id"] as? String, Self.targetID)
    }
    func testAvatarAccountAndSizeGuards() async {
        let t = StubTransport { _ in (200, Data(), [:]) }
        do { try await service(t).setAvatar(jpeg: Data(), expectedUserID: Self.targetID); XCTFail() } catch {}
        do { try await service(t).setAvatar(jpeg: Data(repeating: 0,count: 1048577), expectedUserID: Self.actorID); XCTFail() } catch {}
        XCTAssertTrue(t.requests.isEmpty)
    }


    func testOldProfileDefaultsEverySharedSectionToPrivate() throws {
        let profile = try JSONDecoder().decode(UserProfile.self, from: Data(Self.row.utf8))
        XCTAssertEqual(profile.friendsVisibility, .privateOnly)
        XCTAssertEqual(profile.historyVisibility, .privateOnly)
        XCTAssertEqual(profile.libraryVisibility, .privateOnly)
    }
    func testSharingSettingsEncodeOnlyExplicitFields() throws {
        let draft = try ProfileDraft(username: "alice_1", displayName: "Alice", bio: "", visibility: .privateProfile,
            friendsVisibility: .friends, historyVisibility: .privateOnly, libraryVisibility: .publicProfile).validated()
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
        XCTAssertEqual(json["friends_visibility"] as? String, "friends")
        XCTAssertEqual(json["history_visibility"] as? String, "private")
        XCTAssertEqual(json["library_visibility"] as? String, "public")
        XCTAssertNil(json["user_id"])
    }
    func testAvatarSigningIsCoalescedAcrossConcurrentCells() async throws {
        let t = StubTransport(delay: 0.05) { _ in (200, Data(#"{"url":"https://example.com/avatar?signed=1"}"#.utf8), [:]) }
        let subject = service(t)
        async let a = subject.avatarURL(userID: Self.targetID, expectedUserID: Self.actorID, revision: "r1")
        async let b = subject.avatarURL(userID: Self.targetID, expectedUserID: Self.actorID, revision: "r1")
        let pair = try await (a,b)
        XCTAssertEqual(pair.0, pair.1)
        _ = try await subject.avatarURL(userID: Self.targetID, expectedUserID: Self.actorID, revision: "r1")
        XCTAssertEqual(t.requests.count, 1)
        _ = try await subject.avatarURL(userID: Self.targetID, expectedUserID: Self.actorID, revision: "r2")
        XCTAssertEqual(t.requests.count, 2)
    }
    func testSocialProfileChecksViewingAccountBeforeNetwork() async {
        let t = StubTransport { _ in (200, Data(), [:]) }
        do {
            _ = try await service(t).socialProfile(targetID: Self.targetID, expectedUserID: Self.targetID)
            XCTFail()
        } catch { XCTAssertEqual(error as? AuthError, .notSignedIn) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testSocialProfileUsesSafeRPCAndIndependentOffsets() async throws {
        let targetRow = Self.row.replacingOccurrences(of: Self.actorID, with: Self.targetID)
        let envelope = """
        {"profile":\(targetRow),"friends":[],"friends_count":null,"friends_allowed":false,
         "history_allowed":false,"library_allowed":false,"history":[],"library":[],
         "history_has_more":false,"library_has_more":false,"stats":null}
        """
        let t = StubTransport { _ in (200, Data(envelope.utf8), [:]) }
        _ = try await service(t).socialProfile(targetID: Self.targetID, historyOffset: 40, libraryOffset: 80, expectedUserID: Self.actorID)
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.url?.path, "/rest/v1/rpc/anivibe_social_profile")
        XCTAssertEqual(request.bodyJSON["p_history_offset"] as? Int, 40)
        XCTAssertEqual(request.bodyJSON["p_library_offset"] as? Int, 80)
        XCTAssertNil(request.bodyJSON["viewer_id"])
    }
}
