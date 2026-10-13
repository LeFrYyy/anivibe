import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Клиент Kodik API (kodik-api.com) для поиска тайтлов и вариантов озвучки.
///
/// Важно честно:
/// * API требует токен партнёра (получается при регистрации на kodik.biz). Без токена клиент не создаётся.
/// * Kodik отдаёт ссылки на свой ВЕБ-плеер (iframe), а не прямые потоки. Поэтому это
///   НЕ `VideoSourceProvider`: воспроизведение идёт в WKWebView, а не в нашем AVPlayer.
/// * Прямые HLS-потоки (для нативного плеера с выбором качества и скорости) — см. `KodikStreamResolver`.
public struct KodikClient: Sendable {

    public static let defaultBaseURL = URL(string: "https://kodik-api.com")!

    private let token: String
    private let baseURL: URL
    let transport: HTTPTransport

    public init(token: String, baseURL: URL = KodikClient.defaultBaseURL, transport: HTTPTransport) {
        self.token = token
        self.baseURL = baseURL
        self.transport = transport
    }

    /// Ищет тайтл и возвращает совпадение со всеми вариантами озвучки. `nil` — у Kodik такого нет.
    ///
    /// Если известен `shikimoriID` (= `idMal` из AniList), сначала ищем точно по нему —
    /// это исключает подмену сезона или похожего по названию тайтла. Иначе — по названиям,
    /// отбрасывая материалы с другим Shikimori ID.
    public func search(titles: [String], year: Int? = nil, shikimoriID: Int? = nil) async throws -> KodikMatch? {
        if let shikimoriID {
            let exact = try await requestMaterials([URLQueryItem(name: "shikimori_id", value: String(shikimoriID))])
                .filter { $0.shikimoriID == nil || $0.shikimoriID == shikimoriID }
            if exact.contains(where: { $0.shikimoriID == shikimoriID }), let match = Self.exactGroup(among: exact) { return match }
        }
        for title in titles where !title.isEmpty {
            let groups = try await requestMaterials([URLQueryItem(name: "title", value: title)])
            if let match = Self.bestGroup(for: titles, year: year, shikimoriID: shikimoriID, among: groups) { return match }
        }
        return nil
    }

    // MARK: - Запрос

    private func requestMaterials(_ criteria: [URLQueryItem]) async throws -> [KodikMaterialDTO] {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.notConfigured("Kodik token") }
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)] + criteria + [
            URLQueryItem(name: "types", value: "anime,anime-serial"),
            URLQueryItem(name: "limit", value: "100"),
            // Просим ссылки на сезоны и серии, чтобы строить список эпизодов.
            URLQueryItem(name: "with_episodes", value: "true"),
            URLQueryItem(name: "with_episodes_data", value: "true"),
        ]
        guard let url = components?.url else { throw APIError.invalidResponse("Не удалось собрать URL запроса") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport.send(request)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }

        let decoded: KodikSearchResponseDTO
        do {
            decoded = try JSONDecoder().decode(KodikSearchResponseDTO.self, from: data)
        } catch {
            throw APIError.decoding("Kodik: неожиданный формат ответа")
        }
        if let message = decoded.error, !message.isEmpty {
            // Kodik сообщает об ошибках телом даже при HTTP 200.
            let lowered = message.lowercased()
            if lowered.contains("token") || lowered.contains("токен") || lowered.contains("auth") {
                throw APIError.unauthorized
            }
            throw APIError.badRequest(message)
        }
        // Оставляем только аниме-материалы (у Kodik в базе есть и обычное кино).
        return (decoded.results ?? []).filter { dto in
            guard let type = dto.type else { return true }
            return type == "anime" || type == "anime-serial"
        }
    }

    // MARK: - Сопоставление

    /// Объединяет записи Kodik, относящиеся к одному тайтлу.
    ///
    /// У Kodik каждая озвучка — отдельная запись (свой `id`), и у части записей нет
    /// `shikimori_id`. Поэтому связываем записи, если совпадает `id`, `shikimori_id`
    /// или (при отсутствии конфликта Shikimori ID) нормализованное название.
    static func groupMaterials(_ results: [KodikMaterialDTO]) -> [String: [KodikMaterialDTO]] {
        guard !results.isEmpty else { return [:] }
        var parent = Array(results.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb {
                let aIDs = Set(results.indices.filter { find($0) == ra }.compactMap { results[$0].shikimoriID })
                let bIDs = Set(results.indices.filter { find($0) == rb }.compactMap { results[$0].shikimoriID })
                guard aIDs.isEmpty || bIDs.isEmpty || aIDs == bIDs else { return }
                parent[max(ra, rb)] = min(ra, rb)
            }
        }
        func names(_ m: KodikMaterialDTO) -> Set<String> {
            Set([m.title, m.titleOrig].compactMap { $0 }.map(TitleMatcher.normalize).filter { !$0.isEmpty })
        }
        let nameSets = results.map(names)
        for i in results.indices {
            for j in results.indices where j > i {
                let a = results[i], b = results[j]
                if a.id == b.id {
                    union(i, j)
                } else if let sa = a.shikimoriID, let sb = b.shikimoriID {
                    if sa == sb { union(i, j) }
                } else if !nameSets[i].isDisjoint(with: nameSets[j]) {
                    union(i, j)
                }
            }
        }
        var groups: [String: [KodikMaterialDTO]] = [:]
        for i in results.indices {
            let root = results[find(i)]
            let key: String
            if let s = root.shikimoriID ?? results.indices.filter({ find($0) == find(i) }).compactMap({ results[$0].shikimoriID }).first {
                key = "shiki_\(s)"
            } else {
                key = "group_\(root.id)"
            }
            groups[key, default: []].append(results[i])
        }
        return groups
    }

    /// Группирует результаты по материалу/тайтлу и возвращает совпадение со всеми доступными озвучками.
    static func exactGroup(among results: [KodikMaterialDTO]) -> KodikMatch? {
        guard !results.isEmpty else { return nil }
        let byGroup = groupMaterials(results)
        let ordered = byGroup.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key
        }
        for (_, materials) in ordered {
            if let match = makeMatch(from: materials) { return match }
        }
        return nil
    }

    static func bestGroup(for titles: [String], year: Int?, shikimoriID: Int? = nil,
                          among results: [KodikMaterialDTO]) -> KodikMatch? {
        let results = results.filter { !TitleMatcher.idsConflict(shikimoriID, $0.shikimoriID) }
        let byGroup = groupMaterials(results)
        struct Candidate {
            let id: String
            let titles: [String]
            let year: Int?
            let materials: [KodikMaterialDTO]
        }
        let candidates: [Candidate] = byGroup.map { id, materials in
            var names: [String] = []
            for m in materials {
                for t in [m.title, m.titleOrig, m.otherTitle] {
                    guard let t else { continue }
                    // other_title — перечень вариантов через «/».
                    names.append(contentsOf: t.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) })
                }
            }
            var seen = Set<String>()
            let unique = names.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            return Candidate(id: id, titles: unique, year: materials.first?.year, materials: materials)
        }
        guard !candidates.isEmpty else { return nil }

        // Нечёткое совпадение названия (с учётом номера сезона в названии).
        if let best = TitleMatcher.bestMatch(for: titles, among: candidates, titlesOf: \.titles, threshold: 0.6) {
            return makeMatch(from: best.materials)
        }
        return nil
    }

    private static func makeMatch(from materials: [KodikMaterialDTO], id: String? = nil) -> KodikMatch? {
        var voices: [KodikVoiceOption] = []
        for voice in materials.compactMap(makeVoice(from:)) {
            // Одна и та же озвучка может прийти несколькими записями — оставляем самую полную.
            if let index = voices.firstIndex(where: { $0.id == voice.id }) {
                if voice.episodes.count > voices[index].episodes.count { voices[index] = voice }
            } else {
                voices.append(voice)
            }
        }
        guard !voices.isEmpty else { return nil }
        let first = materials[0]
        let title = first.title ?? first.titleOrig ?? voices[0].title
        let matchID = first.id
        return KodikMatch(materialID: matchID, matchedTitle: title, year: first.year, voices: voices)
    }

    private static func makeVoice(from dto: KodikMaterialDTO) -> KodikVoiceOption? {
        guard let playerURL = makePlayerURL(from: dto.link) else { return nil }

        let translation: KodikTranslation
        if let t = dto.translation, let id = t.id {
            let kind: KodikTranslation.Kind
            switch t.type {
            case "voice": kind = .voice
            case "subtitles": kind = .subtitles
            default: kind = .unknown
            }
            translation = KodikTranslation(id: id, title: t.title ?? "Перевод #\(id)", kind: kind)
        } else {
            translation = KodikTranslation(id: 0, title: "Без перевода (оригинал)", kind: .unknown)
        }

        var episodes: [KodikEpisode] = []
        var seasonURLs: [Int: URL] = [:]
        for (seasonKey, season) in dto.seasons ?? [:] {
            guard let seasonNumber = Int(seasonKey) else { continue }
            if let link = season.link, let url = makePlayerURL(from: link) {
                seasonURLs[seasonNumber] = url
            }
            for (episodeKey, episode) in season.episodes ?? [:] {
                guard let number = Int(episodeKey), let url = makePlayerURL(from: episode.link) else { continue }
                episodes.append(KodikEpisode(season: seasonNumber, number: number, title: episode.title, playerURL: url))
            }
        }
        episodes.sort { ($0.season, $0.number) < ($1.season, $1.number) }

        return KodikVoiceOption(materialID: dto.id, translation: translation,
                                title: dto.title ?? dto.titleOrig ?? "Без названия",
                                year: dto.year, quality: dto.quality,
                                playerURL: playerURL, episodes: episodes, seasonPlayerURLs: seasonURLs, isSingleVideo: dto.type != "anime-serial" && episodes.isEmpty)
    }

    /// Kodik возвращает ссылки вида «//kodik.info/…» — приводим к https
    /// и строго проверяем, что это действительно http(s)-URL с хостом.
    static func makePlayerURL(from link: String) -> URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.hasPrefix("//") ? "https:" + trimmed : trimmed
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme, ["http", "https"].contains(scheme),
              components.host != nil else { return nil }
        return components.url
    }
}