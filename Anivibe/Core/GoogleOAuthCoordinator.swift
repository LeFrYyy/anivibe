import AuthenticationServices
import CryptoKit
import Security
import UIKit

@MainActor
final class GoogleOAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    func authorize(makeURL: (URL, String) async -> URL) async throws -> (code: String, verifier: String) {
        let verifier = try Self.random(bytes: 64)
        let state = try Self.random(bytes: 32)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let redirect = URL(string: "anivibe://auth/callback?state=\(state)")!
        let url = await makeURL(redirect, challenge)
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "anivibe") { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? CocoaError(.userCancelled)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() { continuation.resume(throwing: CocoaError(.featureUnsupported)) }
        }
        defer { session = nil }
        let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        let query = components?.queryItems ?? []
        guard callback.scheme == "anivibe", callback.host == "auth", callback.path == "/callback",
              query.first(where: { $0.name == "state" })?.value == state,
              let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (code, verifier)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private static func random(bytes: Int) throws -> String {
        var data = Data(count: bytes)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        guard result == errSecSuccess else { throw CocoaError(.coderInvalidValue) }
        return base64URL(data)
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
