import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

final class ConfigurationTests: XCTestCase {
    typealias K = AppConfiguration.Key

    func testEmptyAndPlaceholderValuesMeanLocalMode() {
        let c = AppConfiguration.from(infoDictionary: [K.supabaseURL: "$(ANIVIBE_SUPABASE_URL)", K.supabaseAnonKey: "", K.manifestURL: " "])
        XCTAssertNil(c.supabase)
        XCTAssertNil(c.manifestURL)
        XCTAssertFalse(c.demoCatalog)
        XCTAssertTrue(c.testStreamsEnabledByDefault)
        XCTAssertTrue(c.warnings.isEmpty)
        XCTAssertFalse(c.isSyncConfigured)
    }

    func testValidSupabase() {
        let c = AppConfiguration.from(infoDictionary: [K.supabaseURL: "https://abc.supabase.co", K.supabaseAnonKey: "sb_publishable_123",
                                                       K.demoCatalog: "YES", K.testStreams: "NO"])
        XCTAssertEqual(c.supabase?.url.host, "abc.supabase.co")
        XCTAssertTrue(c.demoCatalog)
        XCTAssertFalse(c.testStreamsEnabledByDefault)
    }

    func testRejectsInsecureAndPartialConfig() {
        let insecure = AppConfiguration.from(infoDictionary: [K.supabaseURL: "http://abc.supabase.co", K.supabaseAnonKey: "k"])
        XCTAssertNil(insecure.supabase)
        XCTAssertEqual(insecure.warnings.count, 1)
        let local = AppConfiguration.from(infoDictionary: [K.supabaseURL: "http://127.0.0.1:54321", K.supabaseAnonKey: "k"])
        XCTAssertNotNil(local.supabase, "http разрешён только для локального Supabase")
        let partial = AppConfiguration.from(infoDictionary: [K.supabaseURL: "https://abc.supabase.co"])
        XCTAssertNil(partial.supabase)
        XCTAssertEqual(partial.warnings.count, 1)
        let manifest = AppConfiguration.from(infoDictionary: [K.manifestURL: "http://example.com/m.json"])
        XCTAssertNil(manifest.manifestURL)
    }

    func testRejectsServiceRoleKey() {
        // JWT с payload {"role":"service_role"} (подпись фиктивная).
        let payload = Data(#"{"role":"service_role","iss":"supabase"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let jwt = "eyJhbGciOiJIUzI1NiJ9.\(payload).sig"
        let c = AppConfiguration.from(infoDictionary: [K.supabaseURL: "https://abc.supabase.co", K.supabaseAnonKey: jwt])
        XCTAssertNil(c.supabase)
        XCTAssertTrue(c.warnings.first?.contains("service_role") ?? false)
        XCTAssertTrue(AppConfiguration.looksLikeServiceRoleKey("sb_secret_abc"))
        let anonPayload = Data(#"{"role":"anon"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertFalse(AppConfiguration.looksLikeServiceRoleKey("x.\(anonPayload).y"))
    }
}

final class AuthTests: XCTestCase {
    let config = AppConfiguration.Supabase(url: URL(string: "https://abc.supabase.co")!, anonKey: "anon")

    static func sessionJSON(token: String = "access", expiresIn: Int = 3600) -> String {
        #"{"access_token": ""# + token + #"", "refresh_token": "refresh", "expires_in": "# + String(expiresIn) + #", "token_type": "bearer", "user": {"id": "user-1", "email": "a@b.co"}}"#
    }

    func testSignInStoresSessionAndSendsHeaders() async throws {
        let t = StubTransport { _ in (200, Data(Self.sessionJSON().utf8), [:]) }
        let store = InMemoryTokenStore()
        let auth = SupabaseAuthClient(config: config, transport: t, store: store)
        let s = try await auth.signIn(email: " a@b.co ", password: "password1")
        XCTAssertEqual(s.user.id, "user-1")
        XCTAssertEqual(store.load()?.accessToken, "access")
        let req = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://abc.supabase.co/auth/v1/token?grant_type=password")
        XCTAssertEqual(req.value(forHTTPHeaderField: "apikey"), "anon")
        XCTAssertEqual(req.bodyJSON["email"] as? String, "a@b.co")
    }

    func testErrorMapping() async {
        let t = StubTransport { _ in (400, Data(#"{"code": 400, "error_code": "invalid_credentials", "msg": "Invalid login credentials"}"#.utf8), [:]) }
        let auth = SupabaseAuthClient(config: config, transport: t, store: InMemoryTokenStore())
        do { try await auth.signIn(email: "a@b.co", password: "wrongpass"); XCTFail() } catch {
            XCTAssertEqual(error as? AuthError, .invalidCredentials)
        }
        XCTAssertEqual(SupabaseAuthClient.mapError(status: 422, data: Data(#"{"error_code":"user_already_exists"}"#.utf8)), .userAlreadyExists)
        XCTAssertEqual(SupabaseAuthClient.mapError(status: 429, data: Data()), .rateLimited)
        XCTAssertEqual(SupabaseAuthClient.mapError(status: 400, data: Data(#"{"error_code":"email_not_confirmed"}"#.utf8)), .emailNotConfirmed)
    }

    func testInputValidationHappensBeforeNetwork() async {
        let t = StubTransport { _ in (200, Data(), [:]) }
        let auth = SupabaseAuthClient(config: config, transport: t, store: InMemoryTokenStore())
        do { try await auth.signUp(email: "not-an-email", password: "password1"); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .invalidEmail) }
        do { try await auth.signUp(email: "a@b.co", password: "short"); XCTFail() } catch {
            guard case .weakPassword = error as? AuthError else { return XCTFail() }
        }
        XCTAssertTrue(t.requests.isEmpty)
    }

    func testSignUpRequiringConfirmation() async {
        let t = StubTransport { _ in (200, Data(#"{"id": "user-1", "email": "a@b.co", "confirmation_sent_at": "2026-10-11T00:00:00Z"}"#.utf8), [:]) }
        let store = InMemoryTokenStore()
        let auth = SupabaseAuthClient(config: config, transport: t, store: store)
        do { try await auth.signUp(email: "a@b.co", password: "password1"); XCTFail() } catch {
            XCTAssertEqual(error as? AuthError, .confirmationRequired)
        }
        XCTAssertNil(store.load())
    }

    func testRefreshWhenExpiringAndSignOut() async throws {
        let clock = Clock()
        let expiring = AuthSession(accessToken: "old", refreshToken: "r", expiresAt: clock.now.addingTimeInterval(10), user: AuthUser(id: "u", email: nil))
        let t = StubTransport { req in
            if req.url?.path == "/auth/v1/logout" { return (204, Data(), [:]) }
            return (200, Data(Self.sessionJSON(token: "new").utf8), [:])
        }
        let store = InMemoryTokenStore(expiring)
        let auth = SupabaseAuthClient(config: config, transport: t, store: store, now: { clock.now })
        let s = try await auth.validSession()
        XCTAssertEqual(s.accessToken, "new")
        XCTAssertEqual(t.requests.first?.url?.query, "grant_type=refresh_token")
        await auth.signOut()
        XCTAssertNil(store.load())
        XCTAssertEqual(t.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer new")
    }

    func testExpiredRefreshTokenClearsSession() async {
        let clock = Clock()
        let expired = AuthSession(accessToken: "old", refreshToken: "r", expiresAt: clock.now.addingTimeInterval(-10), user: AuthUser(id: "u", email: nil))
        let t = StubTransport { _ in (400, Data(#"{"error_code":"refresh_token_not_found"}"#.utf8), [:]) }
        let store = InMemoryTokenStore(expired)
        let auth = SupabaseAuthClient(config: config, transport: t, store: store, now: { clock.now })
        do { _ = try await auth.validSession(); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .sessionExpired) }
        XCTAssertNil(store.load())
    }
}

final class SyncTests: XCTestCase {
    let config = AppConfiguration.Supabase(url: URL(string: "https://abc.supabase.co")!, anonKey: "anon")

    func testSyncPushesLocalChangesAndMergesRemote() async throws {
        let clock = Clock()
        let session = AuthSession(accessToken: "tok", refreshToken: "r", expiresAt: clock.now.addingTimeInterval(3600), user: AuthUser(id: "user-1", email: nil))
        let remoteEntries = #"[{"user_id":"user-1","anime_id":2,"title":"Remote","cover_url":null,"episode_count":12,"status":"planned","is_favorite":true,"last_episode":null,"is_deleted":false,"updated_at":"2026-10-11T10:00:00.123456+00:00"}]"#
        let remoteProgress = #"[{"user_id":"user-1","anime_id":2,"episode":3,"position_seconds":120.5,"duration_seconds":1400,"updated_at":"2026-10-11T10:00:00+00:00"}]"#
        let t = StubTransport { req in
            let path = req.url?.path ?? ""
            if req.httpMethod == "POST" { return (201, Data(), [:]) }
            if path.hasSuffix("library_entries") { return (200, Data(remoteEntries.utf8), [:]) }
            if path.hasSuffix("watch_progress") { return (200, Data(remoteProgress.utf8), [:]) }
            return (200, Data("[]".utf8), [:])
        }
        let library = LibraryRepository(persistence: InMemoryLibraryPersistence(), now: { clock.now })
        await library.recordProgress(anime: AnimeSnapshot(id: 1, title: "Local", episodeCount: 3), episode: 1, position: 10, duration: 100)
        let auth = SupabaseAuthClient(config: config, transport: t, store: InMemoryTokenStore(session), now: { clock.now })
        let sync = SupabaseSyncService(config: config, transport: t, auth: auth, library: library, now: { clock.now })

        let report = try await sync.sync()
        XCTAssertEqual(report.pushed, 3) // entry + progress + history
        XCTAssertEqual(report.pulled, 2)

        let posts = t.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.count, 3)
        let entryPost = try XCTUnwrap(posts.first { $0.url?.path.hasSuffix("library_entries") == true })
        XCTAssertEqual(entryPost.url?.query, "on_conflict=user_id,anime_id")
        XCTAssertEqual(entryPost.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(entryPost.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: entryPost.httpBody!) as? [[String: Any]])
        XCTAssertEqual(rows.first?["user_id"] as? String, "user-1")
        XCTAssertEqual(rows.first?["status"] as? String, "watching")

        let s = await library.snapshot()
        XCTAssertEqual(s.entry(for: 2)?.anime.title, "Remote")
        XCTAssertEqual(s.entry(for: 2)?.isFavorite, true)
        XCTAssertEqual(s.progress(animeId: 2, episode: 3)?.position, 120.5)
        XCTAssertEqual(s.lastSyncAt, clock.now)

        // Второй проход: отправляем только новое и запрашиваем изменения после lastSyncAt.
        clock.advance(100)
        let before = t.requests.count
        _ = try await sync.sync()
        let newRequests = t.requests.dropFirst(before)
        XCTAssertTrue(newRequests.allSatisfy { $0.httpMethod == "GET" }, "нет локальных изменений — нечего отправлять")
        XCTAssertTrue(newRequests.first?.url?.query?.contains("updated_at=gt.") ?? false)
        XCTAssertFalse(newRequests.first?.url?.query?.contains("+") ?? true, "плюс в дате экранируется")
    }

    func testSyncRequiresSignIn() async {
        let t = StubTransport { _ in (200, Data(), [:]) }
        let library = LibraryRepository(persistence: InMemoryLibraryPersistence())
        let auth = SupabaseAuthClient(config: config, transport: t, store: InMemoryTokenStore())
        let sync = SupabaseSyncService(config: config, transport: t, auth: auth, library: library)
        do { _ = try await sync.sync(); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .notSignedIn) }
    }

    func testSyncSurfacesRLSForbidden() async {
        let clock = Clock()
        let session = AuthSession(accessToken: "tok", refreshToken: "r", expiresAt: clock.now.addingTimeInterval(3600), user: AuthUser(id: "u", email: nil))
        let t = StubTransport { _ in (403, Data(#"{"code":"42501","message":"new row violates row-level security policy"}"#.utf8), [:]) }
        let library = LibraryRepository(persistence: InMemoryLibraryPersistence(), now: { clock.now })
        await library.setStatus(.watching, for: AnimeSnapshot(id: 1, title: "A"))
        let auth = SupabaseAuthClient(config: config, transport: t, store: InMemoryTokenStore(session), now: { clock.now })
        let sync = SupabaseSyncService(config: config, transport: t, auth: auth, library: library, now: { clock.now })
        do { _ = try await sync.sync(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .forbidden) }
        let s = await library.snapshot()
        XCTAssertNil(s.lastSyncAt, "при ошибке отметка синхронизации не сдвигается")
    }
}
