import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProfileVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case privateProfile = "private", publicProfile = "public"
    public var title: String { self == .publicProfile ? "Публичный" : "Приватный" }
}
public enum SharingVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case privateOnly = "private", friends, publicProfile = "public"
    public var title: String {
        switch self { case .privateOnly: return "Только я"; case .friends: return "Друзья"; case .publicProfile: return "Все пользователи" }
    }
}
public struct UserProfile: Codable, Hashable, Sendable, Identifiable {
    public var id: String { userID }
    public let userID: String
    public let username: String?
    public let displayName: String
    public let bio: String
    public let avatarPath: String?
    public let visibility: ProfileVisibility
    public let createdAt: String
    public let updatedAt: String
    public let friendsVisibility: SharingVisibility
    public let historyVisibility: SharingVisibility
    public let libraryVisibility: SharingVisibility
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(String.self, forKey: .userID)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        displayName = try c.decode(String.self, forKey: .displayName)
        bio = try c.decode(String.self, forKey: .bio)
        avatarPath = try c.decodeIfPresent(String.self, forKey: .avatarPath)
        visibility = try c.decode(ProfileVisibility.self, forKey: .visibility)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        friendsVisibility = try c.decodeIfPresent(SharingVisibility.self, forKey: .friendsVisibility) ?? .privateOnly
        historyVisibility = try c.decodeIfPresent(SharingVisibility.self, forKey: .historyVisibility) ?? .privateOnly
        libraryVisibility = try c.decodeIfPresent(SharingVisibility.self, forKey: .libraryVisibility) ?? .privateOnly
    }
    enum CodingKeys: String, CodingKey {
        case userID = "user_id", username, displayName = "display_name", bio, visibility
        case avatarPath = "avatar_path"
        case createdAt = "created_at", updatedAt = "updated_at"
        case friendsVisibility = "friends_visibility", historyVisibility = "history_visibility", libraryVisibility = "library_visibility"
    }
}
public struct ProfileDraft: Encodable, Sendable {
    public var username: String
    public var displayName: String
    public var bio: String
    public var visibility: ProfileVisibility
    public var friendsVisibility: SharingVisibility?
    public var historyVisibility: SharingVisibility?
    public var libraryVisibility: SharingVisibility?
    public init(username: String, displayName: String, bio: String, visibility: ProfileVisibility, friendsVisibility: SharingVisibility? = nil, historyVisibility: SharingVisibility? = nil, libraryVisibility: SharingVisibility? = nil) {
        self.username = username; self.displayName = displayName; self.bio = bio; self.visibility = visibility
        self.friendsVisibility = friendsVisibility; self.historyVisibility = historyVisibility; self.libraryVisibility = libraryVisibility
    }
    enum CodingKeys: String, CodingKey { case username, displayName = "display_name", bio, visibility
        case friendsVisibility = "friends_visibility", historyVisibility = "history_visibility", libraryVisibility = "library_visibility"
    }
    public func validated() throws -> ProfileDraft {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let about = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let reserved = ["admin", "administrator", "support", "supabase", "anivibe"]
        guard (3...24).contains(name.count), name.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil,
              !reserved.contains(name) else { throw SocialError.validation("Username: 3–24 латинские буквы, цифры или _. Служебные имена недоступны.") }
        guard (1...60).contains(display.unicodeScalars.count), about.unicodeScalars.count <= 500 else {
            throw SocialError.validation("Имя: 1–60 символов; описание: до 500 символов.")
        }
        return ProfileDraft(username: name, displayName: display, bio: about, visibility: visibility, friendsVisibility: friendsVisibility, historyVisibility: historyVisibility, libraryVisibility: libraryVisibility)
    }
}
public struct Friendship: Codable, Hashable, Sendable, Identifiable {
    public var id: String { userLow + ":" + userHigh }
    public let userLow: String
    public let userHigh: String
    public let requesterID: String
    public let status: String
    enum CodingKeys: String, CodingKey { case userLow = "user_low", userHigh = "user_high", requesterID = "requester_id", status }
    public func peerID(for userID: String) -> String { userLow == userID ? userHigh : userLow }
}
public enum FriendAction: String, Sendable { case send, accept, decline, cancel, remove }
public enum SocialError: Error, Equatable, Sendable {
    case validation(String), usernameTaken, backendMissing, profileMissing, denied, rateLimited, friendLimit, duplicate, server
    public var userMessage: String {
        switch self {
        case .validation(let text): return text
        case .usernameTaken: return "Этот username уже занят. Выберите другой."
        case .backendMissing: return "На сервере отсутствует нужная миграция профилей. Примените миграции из supabase/migrations, включая social_sharing_collections."
        case .profileMissing: return "Профиль не найден. Проверьте миграцию профилей на сервере."
        case .denied: return "Действие недоступно или запрос уже изменился. Обновите список."
        case .rateLimited: return "Слишком много запросов. Подождите и попробуйте позже."
        case .friendLimit: return "Достигнут лимит друзей (10) у одного из участников."
        case .duplicate: return "Запрос уже существует или пользователь уже в друзьях."
        case .server: return "Не удалось выполнить действие на сервере. Попробуйте позже."
        }
    }
}

/// Real PostgREST profile reads/updates and server-owned friend actions. No admin key.
public actor SupabaseSocialService {
    private let config: AppConfiguration.Supabase
    private let auth: SupabaseAuthClient
    private let transport: HTTPTransport
    public init(config: AppConfiguration.Supabase, auth: SupabaseAuthClient, transport: HTTPTransport) {
        self.config = config; self.auth = auth; self.transport = transport
    }
    public func ownProfile() async throws -> UserProfile {
        let session = try await auth.validSession()
        let data = try await request(path: "profiles", method: "GET", session: session,
                                     query: [URLQueryItem(name: "user_id", value: "eq.\(session.user.id)"), URLQueryItem(name: "limit", value: "1")])
        let rows = try JSONDecoder().decode([UserProfile].self, from: data)
        guard let row = rows.first, row.userID == session.user.id else { throw SocialError.profileMissing }
        return row
    }
    public func updateProfile(_ draft: ProfileDraft, expectedUserID: String? = nil) async throws -> UserProfile {
        let body = try JSONEncoder().encode(draft.validated())
        let session = try await auth.validSession()
        if let expectedUserID, session.user.id != expectedUserID { throw AuthError.notSignedIn }
        let data = try await request(path: "profiles", method: "PATCH", body: body, session: session,
                                     query: [URLQueryItem(name: "user_id", value: "eq.\(session.user.id)")])
        let rows = try JSONDecoder().decode([UserProfile].self, from: data)
        guard let row = rows.first, row.userID == session.user.id else { throw SocialError.profileMissing }
        return row
    }
    public func searchProfiles(username: String) async throws -> [UserProfile] {
        let term = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (3...24).contains(term.count), term.range(of: "^[a-z0-9_]+$", options: .regularExpression) != nil else {
            throw SocialError.validation("Для поиска введите минимум 3 символа username: латиница, цифры или _.")
        }
        let session = try await auth.validSession()
        let data = try await request(path: "rpc/anivibe_search_profiles", method: "POST", body: try JSONEncoder().encode(["p_username": term]), session: session)
        return try JSONDecoder().decode([UserProfile].self, from: data)
    }
    public func friendships() async throws -> [Friendship] {
        let session = try await auth.validSession()
        var rows: [Friendship] = []; var offset = 0
        while true {
            try Task.checkCancellation()
            let data = try await request(path: "friendships", method: "GET", session: session, query: [
                URLQueryItem(name: "select", value: "user_low,user_high,requester_id,status"),
                URLQueryItem(name: "order", value: "user_low.asc,user_high.asc"),
                URLQueryItem(name: "limit", value: "100"), URLQueryItem(name: "offset", value: String(offset))])
            let page = try JSONDecoder().decode([Friendship].self, from: data)
            rows += page; if page.count < 100 { return rows }; offset += page.count
        }
    }
    public func profiles(ids: [String]) async throws -> [UserProfile] {
        guard !ids.isEmpty else { return [] }
        guard ids.count <= 100, ids.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw SocialError.denied }
        let session = try await auth.validSession()
        let data = try await request(path: "profiles", method: "GET", session: session,
                                     query: [URLQueryItem(name: "user_id", value: "in.(\(ids.joined(separator: ",")))")])
        return try JSONDecoder().decode([UserProfile].self, from: data)
    }
    public func friendAction(targetID: String, action: FriendAction, expectedUserID: String? = nil) async throws {
        guard UUID(uuidString: targetID) != nil else { throw SocialError.denied }
        let session = try await auth.validSession()
        if let expectedUserID, session.user.id != expectedUserID { throw AuthError.notSignedIn }
        _ = try await request(path: "rpc/anivibe_friend_action", method: "POST", body: try JSONEncoder().encode(["p_target": targetID, "p_action": action.rawValue]), session: session)
        avatarLinks.removeAll(); avatarFlights.values.forEach { $0.cancel() }; avatarFlights.removeAll()
    }
    /// Server checks base profile access and each sharing setting independently.
    public func socialProfile(targetID: String, historyOffset: Int = 0, libraryOffset: Int = 0, expectedUserID: String) async throws -> SocialProfileDetails {
        guard UUID(uuidString: targetID) != nil, historyOffset >= 0, libraryOffset >= 0 else { throw SocialError.denied }
        let session = try await auth.validSession()
        guard session.user.id == expectedUserID else { throw AuthError.notSignedIn }
        let body = try JSONSerialization.data(withJSONObject: ["p_target": targetID, "p_history_offset": historyOffset, "p_library_offset": libraryOffset])
        let data = try await request(path: "rpc/anivibe_social_profile", method: "POST", body: body, session: session)
        let response = try SupabaseSyncService.decoder.decode(SocialProfileDetails.self, from: data)
        guard response.profile.userID == targetID,
              (try await auth.validSession()).user.id == expectedUserID else { throw SocialError.denied }
        return response
    }

    public func comments(animeID: Int, offset: Int = 0, popular: Bool = false, expectedUserID: String? = nil) async throws -> [TitleComment] {
        let session = try await auth.validSession()
        if let expectedUserID, session.user.id != expectedUserID { throw AuthError.notSignedIn }
        let body = try JSONSerialization.data(withJSONObject: ["p_anime": animeID, "p_offset": offset, "p_popular": popular])
        return try JSONDecoder().decode([TitleComment].self, from: await request(path: "rpc/anivibe_comments", method: "POST", body: body, session: session))
    }
    public func commentAction(animeID: Int, action: String, commentID: String? = nil, text: String = "", value: Int = 0, expectedUserID: String) async throws {
        let session = try await auth.validSession()
        guard session.user.id == expectedUserID else { throw AuthError.notSignedIn }
        var payload: [String: Any] = ["p_anime": animeID, "p_action": action, "p_text": text, "p_value": value]
        payload["p_comment"] = commentID.map { $0 as Any } ?? NSNull()
        _ = try await request(path: "rpc/anivibe_comment_action", method: "POST", body: JSONSerialization.data(withJSONObject: payload), session: session)
    }
    private struct CachedAvatarLink { let url: URL?; let expires: Date }
    private var avatarLinks: [String: CachedAvatarLink] = [:]
    private var avatarFlights: [String: Task<URL?, Error>] = [:]
    public func avatarURL(userID: String, expectedUserID: String? = nil, revision: String = "") async throws -> URL? {
        guard UUID(uuidString: userID) != nil else { throw SocialError.denied }
        let session = try await auth.validSession()
        if let expectedUserID, session.user.id != expectedUserID { throw AuthError.notSignedIn }
        let key = session.user.id + "/" + userID + "/" + revision
        if let cached = avatarLinks[key], cached.expires > Date() { return cached.url }
        if let pending = avatarFlights[key] { return try await pending.value }
        let pending = Task<URL?, Error> { [self] in
            let data = try await avatarRequest(method: "POST", body: JSONEncoder().encode(["user_id": userID]), session: session)
            return try JSONDecoder().decode(AvatarLink.self, from: data).url
        }
        avatarFlights[key] = pending
        defer { avatarFlights[key] = nil }
        let url = try await pending.value
        try Task.checkCancellation()
        // Server links live for 60 s. Keep margin for network/decoding, never persist.
        avatarLinks = avatarLinks.filter { $0.value.expires > Date() }
        avatarLinks[key] = CachedAvatarLink(url: url, expires: Date().addingTimeInterval(url == nil ? 10 : 40))
        return url
    }
    public func setAvatar(jpeg: Data?, expectedUserID: String) async throws {
        let session = try await auth.validSession()
        guard session.user.id == expectedUserID else { throw AuthError.notSignedIn }
        guard jpeg == nil || jpeg!.count <= 1_048_576 else { throw SocialError.validation("Аватар слишком большой (максимум 1 МБ).") }
        _ = try await avatarRequest(method: jpeg == nil ? "DELETE" : "PUT", body: jpeg, session: session)
        avatarLinks.removeAll()
    }
    private func avatarRequest(method: String, body: Data?, session: AuthSession) async throws -> Data {
        var req = URLRequest(url: config.url.appendingPathComponent("functions/v1/avatar"))
        req.httpMethod = method; req.httpBody = body
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(method == "PUT" ? "image/jpeg" : "application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await transport.send(req)
        if response.statusCode == 401 { throw AuthError.sessionExpired }
        if response.statusCode == 429 { throw SocialError.rateLimited }
        if response.statusCode == 400 || response.statusCode == 413 { throw SocialError.validation("Не удалось проверить изображение. Выберите другое фото размером до 1 МБ.") }
        guard (200..<300).contains(response.statusCode) else { throw SocialError.validation("Аватары недоступны. Проверьте миграцию avatars_comments и развёртывание функции avatar.") }
        return data
    }
    private func request(path: String, method: String, body: Data? = nil, session: AuthSession, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: config.url.appendingPathComponent("rest/v1/\(path)"), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        let request = URLRequest.json(url: components.url!, method: method, body: body, headers: [
            "apikey": config.anonKey, "Authorization": "Bearer \(session.accessToken)", "Prefer": "return=representation"])
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let code = fields["code"] as? String ?? ""
            let message = fields["message"] as? String ?? ""
            if code == "23505" { throw SocialError.usernameTaken }
            if ["42P01", "PGRST202", "PGRST205"].contains(code) { throw SocialError.backendMissing }
            if code == "23514" { throw SocialError.validation("Данные профиля не соответствуют ограничениям сервера.") }
            if response.statusCode == 401 { throw AuthError.sessionExpired }
            if message == "comment_invalid" { throw SocialError.validation("Комментарий: 1–2000 символов; повторные сообщения запрещены.") }
            if response.statusCode == 429 || message == "request_rate_limited" { throw SocialError.rateLimited }
            if message == "profile_incomplete" { throw SocialError.validation("Сначала выберите username в своём профиле.") }
            if message == "friends_limit_reached" { throw SocialError.friendLimit }
            if message == "request_already_exists" { throw SocialError.duplicate }
            if response.statusCode == 403 || message == "request_not_allowed" { throw SocialError.denied }
            throw SocialError.server
        }
        return data
    }
}

/// Sanitized read-only view of another account. Never includes email or player position.
public struct SocialProfileDetails: Decodable, Sendable {
    public let profile: UserProfile
    public let friends: [UserProfile]
    public let friendsCount: Int?
    public let friendsAllowed: Bool
    public let historyAllowed: Bool
    public let libraryAllowed: Bool
    public let history: [HistoryItem]
    public let library: [LibraryEntry]
    public let historyHasMore: Bool
    public let libraryHasMore: Bool
    public let stats: [String: Int]?
    enum CodingKeys: String, CodingKey {
        case profile, friends, history, library, stats
        case friendsCount = "friends_count", friendsAllowed = "friends_allowed", historyAllowed = "history_allowed", libraryAllowed = "library_allowed"
        case historyHasMore = "history_has_more", libraryHasMore = "library_has_more"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decode(UserProfile.self, forKey: .profile)
        friends = try c.decode([UserProfile].self, forKey: .friends)
        friendsCount = try c.decodeIfPresent(Int.self, forKey: .friendsCount)
        friendsAllowed = try c.decode(Bool.self, forKey: .friendsAllowed)
        historyAllowed = try c.decode(Bool.self, forKey: .historyAllowed)
        libraryAllowed = try c.decode(Bool.self, forKey: .libraryAllowed)
        history = try c.decode([HistoryRow].self, forKey: .history).map(\.model)
        library = try c.decode([EntryRow].self, forKey: .library).map(\.model)
        historyHasMore = try c.decode(Bool.self, forKey: .historyHasMore)
        libraryHasMore = try c.decode(Bool.self, forKey: .libraryHasMore)
        stats = try c.decodeIfPresent([String: Int].self, forKey: .stats)
    }
}
