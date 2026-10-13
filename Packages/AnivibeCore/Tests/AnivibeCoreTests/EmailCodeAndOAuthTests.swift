import XCTest
@testable import AnivibeCore
final class EmailCodeAndOAuthTests: XCTestCase {
    let config = AppConfiguration.Supabase(url: URL(string: "https://example.supabase.co")!, anonKey: "publishable-test")
    func testCodeIsVerifiedByServerAndSessionStored() async throws {
        let t = StubTransport { _ in (200, Data(AuthTests.sessionJSON().utf8), [:]) }
        let store = InMemoryTokenStore()
        let auth = SupabaseAuthClient(config: config, transport: t, store: store)
        _ = try await auth.verifySignupCode(email: " a@b.co ", code: "123456")
        XCTAssertEqual(t.requests.first?.url?.path, "/auth/v1/verify")
        XCTAssertEqual(t.requests.first?.bodyJSON["type"] as? String, "signup")
        XCTAssertEqual(t.requests.first?.bodyJSON["email"] as? String, "a@b.co")
        XCTAssertNotNil(store.load())
        do { _ = try await auth.verifySignupCode(email: "a@b.co", code: "abc"); XCTFail() }
        catch { XCTAssertEqual(error as? AuthError, .invalidCode) }
        XCTAssertEqual(t.requests.count, 1)
        XCTAssertEqual(SupabaseAuthClient.mapError(status: 403, data: Data(#"{"error_code":"otp_expired"}"#.utf8)), .expiredCode)
    }
    func testResendUsesServerAndGooglePKCEExchangesOnlyCode() async throws {
        let t = StubTransport { request in
            (200, request.url!.path.hasSuffix("resend") ? Data("{}".utf8) : Data(AuthTests.sessionJSON().utf8), [:])
        }
        let auth = SupabaseAuthClient(config: config, transport: t, store: InMemoryTokenStore())
        try await auth.resendSignupCode(email: "a@b.co")
        let url = await auth.googleAuthorizationURL(redirectURL: URL(string: "anivibe://auth/callback?state=random")!, challenge: "S256")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "code_challenge_method" }?.value, "s256")
        XCTAssertEqual(items.first { $0.name == "provider" }?.value, "google")
        _ = try await auth.exchangeOAuthCode("authorization-code", verifier: String(repeating: "v", count: 64))
        XCTAssertEqual(t.requests.last?.url?.query, "grant_type=pkce")
        XCTAssertEqual(t.requests.last?.bodyJSON["auth_code"] as? String, "authorization-code")
        XCTAssertNil(t.requests.last?.bodyJSON["client_secret"])
        await auth.signOut()
        let session = await auth.currentSession; XCTAssertNil(session)
    }
}
