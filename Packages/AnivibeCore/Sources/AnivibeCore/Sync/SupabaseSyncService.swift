import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Синхронизация библиотеки через Supabase PostgREST (/rest/v1).
/// Таблицы и политики RLS — в `supabase/migrations`.
/// Правило конфликтов: побеждает запись с более поздним `updated_at`.
public actor SupabaseSyncService {
    public struct Report: Equatable, Sendable {
        public let pushed: Int
        public let pulled: Int
        public let finishedAt: Date
    }

    private let config: AppConfiguration.Supabase
    private let transport: HTTPTransport
    private let auth: SupabaseAuthClient
    private let library: LibraryRepository
    private let now: @Sendable () -> Date
    private var isRunning = false

    public init(config: AppConfiguration.Supabase, transport: HTTPTransport, auth: SupabaseAuthClient,
                library: LibraryRepository, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.transport = transport
        self.auth = auth
        self.library = library
        self.now = now
    }

    public func sync() async throws -> Report {
        guard !isRunning else { throw APIError.badRequest("Синхронизация уже выполняется") }
        isRunning = true
        defer { isRunning = false }

        let session = try await auth.validSession()
        guard await library.activeAccountID == session.user.id else { throw AuthError.notSignedIn }
        let startedAt = now()
        let snapshot = await library.snapshot()
        let since = snapshot.lastSyncAt
        let changes = await library.changes(since: since)
        let userID = session.user.id

        // 1. Отправляем локальные изменения.
        if !changes.entries.isEmpty {
            try await upsert(table: "library_entries", conflict: "user_id,anime_id",
                             rows: changes.entries.map { EntryRow(entry: $0, userID: userID) }, token: session.accessToken)
        }
        if !changes.progress.isEmpty {
            try await upsert(table: "watch_progress", conflict: "user_id,anime_id,episode,source_key",
                             rows: changes.progress.map { ProgressRow(progress: $0, userID: userID) }, token: session.accessToken)
        }
        if !changes.history.isEmpty {
            try await upsert(table: "watch_history", conflict: "id",
                             rows: changes.history.map { HistoryRow(item: $0, userID: userID) }, token: session.accessToken)
        }

        // 2. Забираем изменения с сервера (с небольшим перекрытием на расхождение часов).
        let pullSince = since?.addingTimeInterval(-120)
        let entries: [EntryRow] = try await fetch(table: "library_entries", timeColumn: "updated_at", since: pullSince, token: session.accessToken)
        let progress: [ProgressRow] = try await fetch(table: "watch_progress", timeColumn: "updated_at", since: pullSince, token: session.accessToken)
        let history: [HistoryRow] = try await fetch(table: "watch_history", timeColumn: "updated_at", since: pullSince, token: session.accessToken)

        guard await library.applySync(entries: entries.map(\.model), progress: progress.map(\.model), history: history.map(\.model),
                                      accountID: userID, startedAt: startedAt) else { throw APIError.badRequest("Аккаунт сменился или библиотека не сохранилась. Повторите синхронизацию.") }
        return Report(pushed: changes.entries.count + changes.progress.count + changes.history.count,
                      pulled: entries.count + progress.count + history.count, finishedAt: now())
    }

    // MARK: - REST

    private func upsert<Row: Encodable>(table: String, conflict: String, rows: [Row], token: String) async throws {
        for chunk in stride(from: 0, to: rows.count, by: 200).map({ Array(rows[$0..<min($0 + 200, rows.count)]) }) {
            var comps = URLComponents(url: config.url.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [URLQueryItem(name: "on_conflict", value: conflict)]
            let request = URLRequest.json(url: comps.url!, body: try Self.encoder.encode(chunk), headers: [
                "apikey": config.anonKey,
                "Authorization": "Bearer \(token)",
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ])
            let (data, response) = try await transport.send(request)
            if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }
        }
    }

    private func fetch<Row: Decodable>(table: String, timeColumn: String, since: Date?, token: String) async throws -> [Row] {
        var output: [Row] = []
        var offset = 0
        let tieBreaker = table == "watch_history" ? "id.asc" : (table == "watch_progress" ? "anime_id.asc,episode.asc,source_key.asc" : "anime_id.asc")
        while true {
            try Task.checkCancellation()
            var comps = URLComponents(url: config.url.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
            var items = [URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "order", value: "\(timeColumn).asc,\(tieBreaker)"),
                         URLQueryItem(name: "limit", value: "500"), URLQueryItem(name: "offset", value: String(offset))]
            if let since { items.append(URLQueryItem(name: timeColumn, value: "gt.\(Self.iso.string(from: since))")) }
            comps.queryItems = items
            comps.percentEncodedQuery = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            let request = URLRequest.json(url: comps.url!, method: "GET", body: nil, headers: [
                "apikey": config.anonKey, "Authorization": "Bearer \(token)"
            ])
            let (data, response) = try await transport.send(request)
            if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }
            let rows: [Row]
            do { rows = try Self.decoder.decode([Row].self, from: data) }
            catch { throw APIError.decoding(String(describing: error)) }
            output += rows
            if rows.count < 500 { return output }
            offset += rows.count
        }
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(iso.string(from: date))
        }
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let d = iso.date(from: s) { return d }
            let plain = ISO8601DateFormatter()
            if let d = plain.date(from: s) { return d }
            // Postgres может вернуть «2026-10-11T10:00:00.123456+00:00» — обрезаем микросекунды.
            if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
                var t = s
                let frac = String(s[r].prefix(4))
                t.replaceSubrange(r, with: frac)
                if let d = iso.date(from: t) { return d }
            }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }
}

// MARK: - Row DTOs (snake_case = колонки таблиц)

struct EntryRow: Codable {
    let user_id: String
    let anime_id: Int
    let title: String
    let cover_url: String?
    let episode_count: Int?
    let status: String?
    let is_favorite: Bool
    let last_episode: Int?
    let is_deleted: Bool
    let updated_at: Date

    init(entry: LibraryEntry, userID: String) {
        user_id = userID
        anime_id = entry.anime.id
        title = entry.anime.title
        cover_url = entry.anime.coverURL?.absoluteString
        episode_count = entry.anime.episodeCount
        status = entry.status?.rawValue
        is_favorite = entry.isFavorite
        last_episode = entry.lastEpisode
        is_deleted = entry.isDeleted
        updated_at = entry.updatedAt
    }

    var model: LibraryEntry {
        LibraryEntry(anime: AnimeSnapshot(id: anime_id, title: title, coverURL: cover_url.flatMap(URL.init(string:)), episodeCount: episode_count),
                     status: status.flatMap(LibraryStatus.init(rawValue:)), isFavorite: is_favorite,
                     lastEpisode: last_episode, updatedAt: updated_at, isDeleted: is_deleted)
    }
}

struct ProgressRow: Codable {
    let source_key: String?
    let user_id: String
    let anime_id: Int
    let episode: Int
    let position_seconds: Double
    let duration_seconds: Double
    let updated_at: Date

    init(progress: WatchProgress, userID: String) {
        user_id = userID
        source_key = progress.sourceKey ?? ""
        anime_id = progress.animeId
        episode = progress.episode
        position_seconds = progress.position
        duration_seconds = progress.duration
        updated_at = progress.updatedAt
    }

    var model: WatchProgress {
        WatchProgress(animeId: anime_id, episode: episode, position: position_seconds, duration: duration_seconds, updatedAt: updated_at, sourceKey: source_key?.nilIfBlank)
    }
}

struct HistoryRow: Codable {
    let deleted_at: Date?
    let updated_at: Date?
    let source_key: String?
    let id: UUID
    let user_id: String
    let anime_id: Int
    let title: String
    let cover_url: String?
    let episode: Int
    let watched_at: Date

    init(item: HistoryItem, userID: String) {
        deleted_at = item.deletedAt
        updated_at = item.syncTimestamp
        source_key = item.sourceKey ?? ""
        id = item.id
        user_id = userID
        anime_id = item.anime.id
        title = item.anime.title
        cover_url = item.anime.coverURL?.absoluteString
        episode = item.episode
        watched_at = item.watchedAt
    }

    var model: HistoryItem {
        HistoryItem(id: id, anime: AnimeSnapshot(id: anime_id, title: title, coverURL: cover_url.flatMap(URL.init(string:))),
                    episode: episode, watchedAt: watched_at, sourceKey: source_key?.nilIfBlank, deletedAt: deleted_at)
    }
}
