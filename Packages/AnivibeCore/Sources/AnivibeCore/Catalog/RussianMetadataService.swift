import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Public metadata only. No profile, account, watch history or credentials are sent.
public actor RussianMetadataService {
    public static let endpoint = URL(string: "https://shikimori.io/api")!
    private let transport: HTTPTransport
    private let cache: MetadataCache
    private let baseURL: URL
    private let limiter = RateLimiter(limit: 4, per: 1)
    public init(transport: HTTPTransport, cache: MetadataCache, baseURL: URL = endpoint) {
        self.transport = transport; self.cache = cache; self.baseURL = baseURL
    }
    public struct Metadata: Codable, Sendable {
        public let id: Int
        public let name: String?
        public let russian: String?
        public let synonyms: [String]?
        public let english: [String]?
        public let description: String?
        public var aliases: [String] { [name, russian].compactMap { $0 } + (synonyms ?? []) + (english ?? []) }
        public func apply(to original: Anime) -> Anime {
            guard original.malID == id else { return original }
            var anime = original
            if let official = russian?.nilIfBlank {
                anime.title.russian = official
                anime.title.russianSource = .shikimori
            }
            anime.synonyms = Array(Set(anime.synonyms + aliases)).sorted()
            if let text = description?.nilIfBlank {
                let cleaned = HTMLText.plainText(text)
                    .replacingOccurrences(of: #"\[/?(?:anime|manga|character|person|url|b|i|u|s|spoiler|quote|size|color)(?:=[^\]]*)?\]"#,
                                          with: "", options: .regularExpression)
                anime.synopsisOriginal = original.synopsisOriginal ?? original.synopsis
                anime.synopsis = cleaned
                anime.synopsisSource = "Shikimori"
            }
            return anime
        }
    }
    public func search(_ text: String, page: Int, limit: Int) async throws -> [Metadata] {
        try await load(path: "animes", query: [URLQueryItem(name: "search", value: String(text.prefix(100))),
            URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(min(50, limit))),
            URLQueryItem(name: "censored", value: "true")])
    }
    public func titles(malIDs: [Int]) async throws -> [Metadata] {
        let ids = Array(Set(malIDs.filter { $0 > 0 })).sorted().prefix(50)
        guard !ids.isEmpty else { return [] }
        return try await load(path: "animes", query: [URLQueryItem(name: "ids", value: ids.map(String.init).joined(separator: ",")),
            URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "censored", value: "true")])
    }
    public func details(malID: Int) async throws -> Metadata {
        try await load(path: "animes/\(malID)", query: [])
    }
    private func load<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        let url = components.url!
        let key = "russian-metadata:" + url.absoluteString
        if let data = await cache.data(for: key), let result = try? JSONDecoder().decode(T.self, from: data) { return result }
        try await limiter.acquire()
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Anivibe/1.0 (iOS; public anime metadata)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.send(request)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }
        let result = try JSONDecoder().decode(T.self, from: data)
        await cache.store(data, for: key)
        return result
    }
}

/// Search-only transliteration; it is never stored as an official title.
public enum CatalogSearchRanking {
    public static func transliterate(_ text: String) -> String {
        let alphabet: [Character: String] = ["а":"a","б":"b","в":"v","г":"g","д":"d","е":"e","ё":"e","ж":"zh","з":"z",
            "и":"i","й":"y","к":"k","л":"l","м":"m","н":"n","о":"o","п":"p","р":"r","с":"s","т":"t","у":"u",
            "ф":"f","х":"h","ц":"ts","ч":"ch","ш":"sh","щ":"sch","ъ":"","ы":"y","ь":"","э":"e","ю":"yu","я":"ya"]
        return text.lowercased().map { alphabet[$0] ?? String($0) }.joined()
    }

    /// Оценка совпадения запроса с тайтлом: 1000 — точное русское название, 800 — точный синоним,
    /// 700+ — начало названия, 600+ — вхождение, 500 — все слова запроса есть в названии, 200 — опечатка.
    /// Понимает транслит («vanpanchmen»), ё/е, э/е, й/и и встроенный словарь популярных тайтлов.
    public static func score(query: String, anime: Anime) -> Int {
        let q = RussianTitleDictionary.fold(query)
        guard !q.isEmpty else { return 0 }
        let transliterated = TitleMatcher.normalize(transliterate(q))
        let primary = [anime.title.russian, anime.title.english, anime.title.romaji, anime.title.native].compactMap { $0 }
        var best = 0
        for (index, title) in (primary + anime.synonyms + (anime.searchAliases ?? [])).enumerated() {
            let t = RussianTitleDictionary.fold(title)
            guard !t.isEmpty else { continue }
            let exact = index < primary.count ? 1000 - index : 800
            best = max(best, score(query: q, transliterated: transliterated, title: t, exact: exact))
        }
        if let malID = anime.malID, best < 800 {
            best = max(best, RussianTitleDictionary.score(query: query, malID: malID))
        }
        return best
    }

    static func score(query q: String, transliterated: String, title t: String, exact: Int) -> Int {
        if t == q { return exact }
        if transliterated != q {
            if t == transliterated { return min(exact, 750) }
        } else if t.unicodeScalars.contains(where: { $0.value >= 0x400 && $0.value <= 0x4FF }) {
            // Запрос латиницей, название кириллицей: сравниваем транслит названия («vanpanchmen» → «Ванпанчмен»).
            let latinTitle = TitleMatcher.normalize(transliterate(t))
            if latinTitle == q { return min(exact, 750) }
            if q.count >= 3, latinTitle.hasPrefix(q) { return 650 }
        }
        if t.hasPrefix(q) { return 700 + min(q.count, 90) }
        if transliterated != q, transliterated.count >= 3, t.hasPrefix(transliterated) { return 650 }
        if q.count >= 3, t.contains(q) { return 600 + min(q.count, 40) }
        if q.contains(" "), wordsMatch(query: q, title: t) { return 500 }
        if q.count >= 4, abs(q.count - t.count) <= 2, editDistance(q, t) <= (q.count >= 8 ? 2 : 1) { return 200 }
        return 0
    }

    /// Каждое слово запроса — начало какого-то слова названия («атака тит» → «атака титанов»).
    static func wordsMatch(query: String, title: String) -> Bool {
        let titleWords = title.split(separator: " ")
        return query.split(separator: " ").allSatisfy { word in titleWords.contains { $0.hasPrefix(word) } }
    }

    public static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a.prefix(160)), b = Array(b.prefix(160))
        var row = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var next = [i + 1]
            for (j, y) in b.enumerated() { next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + (x == y ? 0 : 1))) }
            row = next
        }
        return row[b.count]
    }
}
