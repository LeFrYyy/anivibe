import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore
final class AuthRaceTests: XCTestCase {
    struct DelayedTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if request.url!.path.hasSuffix("logout") { return (Data("{}".utf8), response) }
            // Intentionally ignores cancellation, to simulate a late network callback.
            return await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) {
                    continuation.resume(returning: (Data(AuthTests.sessionJSON(token: "late-refresh").utf8), response))
                }
            }
        }
    }
    func testLateRefreshCannotUndoLogout() async throws {
        let expired = AuthSession(accessToken: "old", refreshToken: "refresh", expiresAt: Date().addingTimeInterval(-10), user: .init(id: "u", email: nil))
        let store = InMemoryTokenStore(expired)
        let auth = SupabaseAuthClient(config: .init(url: URL(string: "https://example.supabase.co")!, anonKey: "test"), transport: DelayedTransport(), store: store)
        let refreshing = Task { try await auth.validSession() }
        try await Task.sleep(nanoseconds: 20_000_000)
        await auth.signOut()
        _ = try? await refreshing.value
        let session = await auth.currentSession
        XCTAssertNil(session)
        XCTAssertNil(store.load())
    }
}
