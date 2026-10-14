import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only authenticated public-key RPCs. Never contains service_role or a reward-setting API.
public actor SupabaseCommunityService {
    private let config: AppConfiguration.Supabase
    private let auth: SupabaseAuthClient
    private let transport: HTTPTransport
    public init(config: AppConfiguration.Supabase, auth: SupabaseAuthClient, transport: HTTPTransport) {
        self.config = config; self.auth = auth; self.transport = transport
    }
    public func hub(userId: String) async throws -> CommunityHub {
        try await decode("anivibe_community_hub", body: [:], userId: userId)
    }
    public func episodes(anilistId: Int? = nil, after: Int = 0, userId: String) async throws -> [CanonicalWatchEpisode] {
        try await decode("anivibe_episode_catalog", body: ["p_anilist": anilistId.map { $0 as Any } ?? NSNull(), "p_after": max(0, after), "p_limit": 100], userId: userId)
    }
    public func room(_ id: String, userId: String) async throws -> WatchRoom {
        try await decode("anivibe_watch_get", body: ["p_session": id], userId: userId)
    }
    public func invite(peerId: String, episodeId: String, mappingId: String, requestId: UUID, userId: String) async throws -> WatchRoom {
        try await decode("anivibe_watch_invite", body: ["p_peer": peerId, "p_episode": episodeId, "p_mapping": mappingId, "p_request": requestId.uuidString], userId: userId)
    }
    public func action(roomId: String, action: String, position: Double? = nil, episodeId: String? = nil, mappingId: String? = nil, userId: String) async throws -> WatchRoom {
        try await decode("anivibe_watch_action", body: ["p_session": roomId, "p_action": action,
            "p_value": position.map { $0 as Any } ?? NSNull(), "p_episode": episodeId.map { $0 as Any } ?? NSNull(),
            "p_mapping": mappingId.map { $0 as Any } ?? NSNull()], userId: userId)
    }
    public func heartbeat(roomId: String, episodeId: String, mappingId: String, eventId: UUID, clientId: UUID, sequence: Int,
                          position: Double, duration: Double, state: String, userId: String) async throws -> WatchRoom {
        guard position.isFinite, duration.isFinite else { throw CommunityError.server("progress_invalid") }
        return try await decode("anivibe_watch_heartbeat", body: ["p_session": roomId, "p_episode": episodeId, "p_mapping": mappingId,
            "p_event": eventId.uuidString, "p_client": clientId.uuidString, "p_sequence": sequence, "p_position": max(0, position),
            "p_duration": duration > 0 ? duration as Any : NSNull(), "p_state": state, "p_rate": 1], userId: userId)
    }
    public func purchase(itemId: String, requestId: UUID, userId: String) async throws -> PurchaseReceipt {
        try await decode("anivibe_shop_purchase", body: ["p_item": itemId, "p_request": requestId.uuidString], userId: userId)
    }
    public func equip(slot: String, itemId: String?, userId: String) async throws {
        _ = try await rpc("anivibe_cosmetic_equip", body: ["p_slot": slot, "p_item": itemId.map { $0 as Any } ?? NSNull()], userId: userId)
    }
    public func preferences(invites: String, hideWatching: Bool, userId: String) async throws {
        _ = try await rpc("anivibe_preferences", body: ["p_invites": invites, "p_hide": hideWatching], userId: userId)
    }
    public func readNotification(_ id: String, userId: String) async throws -> Bool {
        try await decode("anivibe_notification_read", body: ["p_id": id], userId: userId)
    }
    public func presentation(targetId: String, userId: String) async throws -> CosmeticPresentation {
        try await decode("anivibe_cosmetic_profile", body: ["p_user": targetId], userId: userId)
    }
    private func decode<T: Decodable>(_ name: String, body: [String: Any], userId: String) async throws -> T {
        let data = try await rpc(name, body: body, userId: userId)
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
    private func rpc(_ name: String, body: [String: Any], userId: String) async throws -> Data {
        let session = try await auth.validSession()
        guard session.user.id.lowercased() == userId.lowercased() else { throw CommunityError.wrongAccount }
        let url = config.url.appendingPathComponent("rest/v1/rpc").appendingPathComponent(name)
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.send(request)
        try Task.checkCancellation()
        let current = await auth.currentSession
        guard current?.user.id.lowercased() == userId.lowercased() else { throw CommunityError.wrongAccount }
        guard (200..<300).contains(response.statusCode) else {
            let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if response.statusCode == 401 { throw AuthError.sessionExpired }
            if ["PGRST202", "PGRST205", "42P01"].contains(fields["code"] as? String ?? "") { throw CommunityError.unavailable }
            throw CommunityError.server(fields["message"] as? String ?? "server")
        }
        return data
    }

    /// Authenticated Supabase Postgres Changes, with cancellation and bounded reconnect.
    /// Values are invalidations only: always refetch the authorized server snapshot.
    public func invalidations(userId: String, roomId: String? = nil) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                #if canImport(FoundationNetworking)
                // FoundationNetworking does not provide the Apple WebSocket implementation.
                while !Task.isCancelled {
                    continuation.yield(())
                    do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { break }
                }
                #else
                var backoff: UInt64 = 1
                while !Task.isCancelled {
                    do {
                        let session = try await self.auth.validSession()
                        guard session.user.id.lowercased() == userId.lowercased() else { break }
                        var components = URLComponents(url: self.config.url, resolvingAgainstBaseURL: false)!
                        components.scheme = components.scheme == "http" ? "ws" : "wss"
                        components.path = "/realtime/v1/websocket"
                        components.queryItems = [URLQueryItem(name: "apikey", value: self.config.anonKey), URLQueryItem(name: "vsn", value: "1.0.0")]
                        guard let url = components.url else { break }
                        let network = URLSession(configuration: .ephemeral)
                        let socket = network.webSocketTask(with: url)
                        let topic = "realtime:anivibe:\(roomId ?? userId)"
                        let filters: [[String: String]]
                        if let roomId {
                            filters = [["event": "*", "schema": "public", "table": "watch_sessions", "filter": "id=eq.\(roomId)"]]
                        } else {
                            filters = [["event": "*", "schema": "public", "table": "community_notifications", "filter": "user_id=eq.\(userId)"],
                                       ["event": "*", "schema": "public", "table": "watch_sessions", "filter": "host_id=eq.\(userId)"],
                                       ["event": "*", "schema": "public", "table": "watch_sessions", "filter": "guest_id=eq.\(userId)"]]
                        }
                        socket.resume()
                        let join: [String: Any] = ["topic": topic, "event": "phx_join", "ref": "1",
                            "payload": ["access_token": session.accessToken, "config": ["postgres_changes": filters]]]
                        let joinData = try JSONSerialization.data(withJSONObject: join)
                        let expiry = Task {
                            do {
                                let seconds = max(1, min(1500, session.expiresAt.timeIntervalSinceNow - 30))
                                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                                socket.cancel(with: .goingAway, reason: nil)
                            } catch { }
                        }
                        let heartbeat = Task {
                            while !Task.isCancelled {
                                do {
                                    try await Task.sleep(nanoseconds: 25_000_000_000)
                                    try await socket.send(.string("{\"topic\":\"phoenix\",\"event\":\"heartbeat\",\"payload\":{},\"ref\":\"heartbeat\"}"))
                                } catch { socket.cancel(with: .goingAway, reason: nil); break }
                            }
                        }
                        defer { expiry.cancel(); heartbeat.cancel(); socket.cancel(with: .goingAway, reason: nil); network.invalidateAndCancel() }
                        try await withTaskCancellationHandler(operation: {
                            try await socket.send(.string(String(decoding: joinData, as: UTF8.self)))
                            while !Task.isCancelled {
                                let message = try await socket.receive()
                                let raw: Data
                                switch message { case .data(let data): raw = data; case .string(let text): raw = Data(text.utf8); @unknown default: continue }
                                let object = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any]
                                let event = object?["event"] as? String
                                if event == "phx_error" || event == "phx_close" { throw CommunityError.server("realtime_disconnected") }
                                if event == "phx_reply", object?["ref"] as? String == "1" {
                                    let payload = object?["payload"] as? [String: Any]
                                    guard payload?["status"] as? String == "ok" else { throw CommunityError.server("realtime_disconnected") }
                                    backoff = 1; continuation.yield(())
                                }
                                if event == "postgres_changes" { continuation.yield(()) }
                            }
                        }, onCancel: { socket.cancel(with: .goingAway, reason: nil); network.invalidateAndCancel() })
                    } catch { if Task.isCancelled { break } }
                    do { try await Task.sleep(nanoseconds: backoff * 1_000_000_000) } catch { break }
                    backoff = min(30, backoff * 2)
                }
                #endif
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
