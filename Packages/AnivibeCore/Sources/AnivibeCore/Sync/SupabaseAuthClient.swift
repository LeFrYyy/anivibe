import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AuthUser: Codable, Hashable, Sendable {
    public let id: String
    public let email: String?
}

public struct AuthSession: Codable, Hashable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let user: AuthUser

    public func needsRefresh(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) < leeway
    }
}

/// Хранилище токенов. В iOS — Keychain (см. KeychainTokenStore в приложении).
public protocol TokenStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession?)
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?
    public init(_ session: AuthSession? = nil) { self.session = session }
    public func load() -> AuthSession? { lock.lock(); defer { lock.unlock() }; return session }
    public func save(_ session: AuthSession?) { lock.lock(); defer { lock.unlock() }; self.session = session }
}

public enum AuthError: Error, Equatable, Sendable {
    case invalidCode
    case expiredCode
    case invalidCredentials
    case emailNotConfirmed
    case userAlreadyExists
    case weakPassword(String)
    case invalidEmail
    case confirmationRequired
    case notSignedIn
    case sessionExpired
    case rateLimited
    case server(String)
    case network(String)

    public var userMessage: String {
        switch self {
        case .invalidCode: return "Неверный код подтверждения."
        case .expiredCode: return "Код истёк. Запросите новый код."
        case .invalidCredentials: return "Неверный email или пароль."
        case .emailNotConfirmed: return "Email не подтверждён. Проверьте почту."
        case .userAlreadyExists: return "Пользователь с таким email уже зарегистрирован."
        case .weakPassword(let m): return "Слишком простой пароль. \(m)"
        case .invalidEmail: return "Введите корректный email."
        case .confirmationRequired: return "Аккаунт создан. Введите код из письма для подтверждения email. Если письмо содержит только ссылку, откройте её и войдите с паролем."
        case .notSignedIn: return "Вы не вошли в аккаунт."
        case .sessionExpired: return "Сессия истекла. Войдите снова."
        case .rateLimited: return "Слишком много попыток. Подождите немного."
        case .server: return "Сервис авторизации отклонил запрос. Повторите позже или проверьте настройки."
        case .network(let m): return m
        }
    }
}

/// Клиент Supabase Auth (GoTrue) через REST — без сторонних зависимостей.
/// Эндпоинты: /auth/v1/signup, /auth/v1/token, /auth/v1/recover, /auth/v1/logout, /auth/v1/user.
public actor SupabaseAuthClient {
    private let config: AppConfiguration.Supabase
    private let transport: HTTPTransport
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private var refreshTask: Task<AuthSession, Error>?
    private var sessionEpoch: UInt = 0
    private var refreshID: UUID?
    private func saveSession(_ session: AuthSession?) { sessionEpoch &+= 1; store.save(session) }

    public init(config: AppConfiguration.Supabase, transport: HTTPTransport, store: TokenStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.transport = transport
        self.store = store
        self.now = now
    }

    public var currentSession: AuthSession? { store.load() }

    public static func validate(email: String, password: String?) throws {
        let e = email.trimmingCharacters(in: .whitespaces)
        let ok = e.count <= 254 && e.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
        guard ok else { throw AuthError.invalidEmail }
        if let password, password.count < 8 { throw AuthError.weakPassword("Минимум 8 символов.") }
    }

    /// Регистрация. Если в проекте включено подтверждение email, сессии не будет — бросаем `.confirmationRequired`.
    @discardableResult
    public func signUp(email: String, password: String) async throws -> AuthSession {
        try Self.validate(email: email, password: password)
        let data = try await post(path: "auth/v1/signup", body: ["email": email.trimmingCharacters(in: .whitespaces), "password": password])
        if let session = try? decodeSession(data) {
            saveSession(session)
            return session
        }
        throw AuthError.confirmationRequired
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> AuthSession {
        try Self.validate(email: email, password: nil)
        let data = try await post(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
                                  body: ["email": email.trimmingCharacters(in: .whitespaces), "password": password])
        let session = try decodeSession(data)
        saveSession(session)
        return session
    }

    /// The server generates/verifies OTP, applies expiry/rate limits and sends via configured SMTP.
    public func resendSignupCode(email: String) async throws {
        try Self.validate(email: email, password: nil)
        _ = try await post(path: "auth/v1/resend", body: ["type": "signup", "email": email.trimmingCharacters(in: .whitespacesAndNewlines)])
    }
    public func verifySignupCode(email: String, code: String) async throws -> AuthSession {
        try Self.validate(email: email, password: nil)
        let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count == 6, token.allSatisfy({ $0.isASCII && $0.isNumber }) else { throw AuthError.invalidCode }
        let data = try await post(path: "auth/v1/verify", body: ["type": "signup", "email": email.trimmingCharacters(in: .whitespacesAndNewlines), "token": token])
        let session = try decodeSession(data); saveSession(session); return session
    }
    public func googleAuthorizationURL(redirectURL: URL, challenge: String) -> URL {
        var url = URLComponents(url: config.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "provider", value: "google"), URLQueryItem(name: "redirect_to", value: redirectURL.absoluteString),
                         URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "s256")]
        return url.url!
    }
    public func exchangeOAuthCode(_ code: String, verifier: String) async throws -> AuthSession {
        guard !code.isEmpty, (43...128).contains(verifier.count) else { throw AuthError.invalidCredentials }
        let data = try await post(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "pkce")],
                                  body: ["auth_code": code, "code_verifier": verifier])
        let session = try decodeSession(data); saveSession(session); return session
    }

    /// Письмо для восстановления пароля.
    public func recoverPassword(email: String) async throws {
        try Self.validate(email: email, password: nil)
        _ = try await post(path: "auth/v1/recover", body: ["email": email.trimmingCharacters(in: .whitespaces)])
    }

    public func signOut() async {
        let session = store.load()
        refreshTask?.cancel(); refreshTask = nil; refreshID = nil
        saveSession(nil) // Clear immediately: a delayed refresh must never restore a logged-out session.
        if let session { _ = try? await post(path: "auth/v1/logout", body: [:], bearer: session.accessToken) }
    }

    /// Действующий токен; при необходимости обновляет его (одновременные вызовы объединяются).
    public func validSession() async throws -> AuthSession {
        guard let session = store.load() else { throw AuthError.notSignedIn }
        guard session.needsRefresh(now: now()) else { return session }
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await self.refresh(session) }
        let id = UUID()
        refreshTask = task; refreshID = id
        defer { if refreshID == id { refreshTask = nil; refreshID = nil } }
        return try await task.value
    }

    private func refresh(_ session: AuthSession) async throws -> AuthSession {
        let epoch = sessionEpoch
        do {
            let data = try await post(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                      body: ["refresh_token": session.refreshToken])
            let fresh = try decodeSession(data)
            guard epoch == sessionEpoch, store.load()?.refreshToken == session.refreshToken else { throw AuthError.notSignedIn }
            saveSession(fresh)
            return fresh
        } catch AuthError.invalidCredentials {
            if epoch == sessionEpoch { saveSession(nil) }
            throw AuthError.sessionExpired
        }
    }

    // MARK: - HTTP

    private func post(path: String, query: [URLQueryItem] = [], body: [String: String], bearer: String? = nil) async throws -> Data {
        var comps = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var headers = ["apikey": config.anonKey]
        // API keys identify the project; only a user's JWT belongs in Bearer.
        // Works with both sb_publishable_* and legacy anon keys.
        if let bearer { headers["Authorization"] = "Bearer \(bearer)" }
        let request = URLRequest.json(url: comps.url!, body: try JSONEncoder().encode(body), headers: headers)
        let data: Data, response: HTTPURLResponse
        do { (data, response) = try await transport.send(request) } catch let e as APIError {
            throw AuthError.network(e.userMessage)
        }
        guard (200..<300).contains(response.statusCode) else { throw Self.mapError(status: response.statusCode, data: data) }
        return data
    }

    static func mapError(status: Int, data: Data) -> AuthError {
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let code = (json["error_code"] as? String) ?? (json["code"] as? String) ?? (json["error"] as? String) ?? ""
        let message = (json["msg"] as? String) ?? (json["message"] as? String) ?? (json["error_description"] as? String) ?? ""
        if status == 429 || code == "over_request_rate_limit" || code == "over_email_send_rate_limit" { return .rateLimited }
        switch code {
        case "invalid_credentials", "invalid_grant", "refresh_token_not_found", "refresh_token_already_used": return .invalidCredentials
        case "otp_expired": return .expiredCode
        case "otp_disabled", "invalid_otp": return .invalidCode
        case "email_not_confirmed": return .emailNotConfirmed
        case "user_already_exists", "email_exists": return .userAlreadyExists
        case "weak_password": return .weakPassword(message)
        case "email_address_invalid", "validation_failed": return .invalidEmail
        default: break
        }
        if status == 400 && message.lowercased().contains("invalid login") { return .invalidCredentials }
        if status == 401 || status == 403 { return .invalidCredentials }
        return .server(message.isEmpty ? "HTTP \(status)" : message)
    }

    private func decodeSession(_ data: Data) throws -> AuthSession {
        struct DTO: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double?
            let expires_at: Double?
            let user: AuthUser
        }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        let expires = dto.expires_at.map { Date(timeIntervalSince1970: $0) } ?? now().addingTimeInterval(dto.expires_in ?? 3600)
        return AuthSession(accessToken: dto.access_token, refreshToken: dto.refresh_token, expiresAt: expires, user: dto.user)
    }
}
