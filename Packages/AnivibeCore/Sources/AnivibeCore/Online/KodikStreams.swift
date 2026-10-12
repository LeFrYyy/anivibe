import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Прямой HLS-поток Kodik одного качества.
public struct KodikStream: Hashable, Sendable, Identifiable {
    public var id: Int { quality }
    /// Высота кадра: 240, 360, 480, 720, 1080…
    public let quality: Int
    public let url: URL

    public init(quality: Int, url: URL) {
        self.quality = quality
        self.url = url
    }

    public var label: String { "\(quality)p" }
}

/// Получает прямые ссылки на видео из плеера Kodik (тот же путь, что использует сам веб-плеер):
/// 1) страница плеера → параметры `urlParams` и `vInfo`;
/// 2) POST на эндпоинт плеера (обычно `/ftor`) → закодированные ссылки по качествам;
/// 3) декодирование (сдвиг букв + base64) → HLS-плейлисты.
public struct KodikStreamResolver: Sendable {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private let transport: HTTPTransport

    public init(transport: HTTPTransport) {
        self.transport = transport
    }

    /// Возвращает доступные качества, от лучшего к худшему.
    public func streams(for playerURL: URL) async throws -> [KodikStream] {
        let page = try await get(playerURL, referer: nil)
        guard let info = Self.parsePlayerPage(page) else {
            throw APIError.decoding("Kodik: не удалось разобрать страницу плеера")
        }
        guard let host = playerURL.host else { throw APIError.invalidResponse("Kodik: некорректная ссылка плеера") }
        let origin = "https://\(host)"

        var endpoint = "/ftor"
        if let scriptPath = Self.playerScriptPath(in: page),
           let scriptURL = URL(string: scriptPath.hasPrefix("http") ? scriptPath : origin + scriptPath),
           let script = try? await get(scriptURL, referer: playerURL),
           let found = Self.endpoint(inPlayerScript: script) {
            endpoint = found
        }
        guard let apiURL = URL(string: endpoint.hasPrefix("http") ? endpoint : origin + endpoint) else {
            throw APIError.invalidResponse("Kodik: некорректный адрес API плеера")
        }

        var form = info.params
        form["type"] = info.type
        form["hash"] = info.hash
        form["id"] = info.id
        form["bad_user"] = "true"
        form["cdn_is_working"] = "true"
        form["info"] = "{}"

        var request = URLRequest(url: apiURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = Self.formEncode(form).data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue(playerURL.absoluteString, forHTTPHeaderField: "Referer")

        let (data, response) = try await transport.send(request)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }
        let streams = try Self.parseLinks(data)
        guard !streams.isEmpty else { throw APIError.notFound }
        return streams
    }

    // MARK: - Сеть

    private func get(_ url: URL, referer: URL?) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let referer { request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer") }
        let (data, response) = try await transport.send(request)
        if let error = APIError.from(status: response.statusCode, data: data, headers: response) { throw error }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Разбор (internal для тестов)

    struct PlayerInfo: Equatable {
        let type: String
        let hash: String
        let id: String
        let params: [String: String]
    }

    static func parsePlayerPage(_ html: String) -> PlayerInfo? {
        guard let type = firstMatch(#"(?:vInfo|videoInfo)\.type\s*=\s*['"]([^'"]+)['"]"#, in: html),
              let hash = firstMatch(#"(?:vInfo|videoInfo)\.hash\s*=\s*['"]([^'"]+)['"]"#, in: html),
              let id = firstMatch(#"(?:vInfo|videoInfo)\.id\s*=\s*['"]([^'"]+)['"]"#, in: html) else { return nil }
        var params: [String: String] = [:]
        if let json = firstMatch(#"urlParams\s*=\s*'([^']*)'"#, in: html),
           let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
            for key in ["d", "d_sign", "pd", "pd_sign", "ref", "ref_sign"] {
                if let value = object[key] { params[key] = "\(value)" }
            }
        }
        return PlayerInfo(type: type, hash: hash, id: id, params: params)
    }

    static func playerScriptPath(in html: String) -> String? {
        firstMatch(#"src=["']([^"']*app\.player_single[^"']*\.js)["']"#, in: html)
    }

    static func endpoint(inPlayerScript script: String) -> String? {
        guard let encoded = firstMatch(#"type:\s*"POST",\s*url:\s*atob\("([^"]+)"\)"#, in: script),
              let decoded = base64Decode(encoded), decoded.hasPrefix("/") else { return nil }
        return decoded
    }

    static func parseLinks(_ data: Data) throws -> [KodikStream] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let links = object["links"] as? [String: Any] else {
            throw APIError.decoding("Kodik: неожиданный ответ плеера")
        }
        var byQuality: [Int: URL] = [:]
        for (key, value) in links {
            guard let declared = Int(key),
                  let items = value as? [[String: Any]],
                  let src = items.first?["src"] as? String,
                  let link = decodeSource(src),
                  let url = KodikClient.makePlayerURL(from: link) else { continue }
            // Kodik иногда отдаёт под «720» тот же 480p-файл — берём реальное качество из имени файла.
            let actual = firstMatch(#"/(\d{3,4})\.mp4"#, in: link).flatMap(Int.init) ?? declared
            if byQuality[actual] == nil { byQuality[actual] = url }
        }
        return byQuality.map { KodikStream(quality: $0.key, url: $0.value) }.sorted { $0.quality > $1.quality }
    }

    /// Ссылки закодированы: буквы сдвинуты (сейчас на 18) и результат — base64.
    /// Сдвиг Kodik периодически меняет, поэтому при неудаче перебираем все варианты.
    static func decodeSource(_ src: String) -> String? {
        if src.contains("//") { return src }
        for shift in [18] + Array(0..<26).filter({ $0 != 18 }) {
            if let decoded = base64Decode(caesar(src, shift: shift)),
               decoded.contains("//"), decoded.contains("m3u8") || decoded.contains(".mp4") {
                return decoded
            }
        }
        return nil
    }

    static func caesar(_ text: String, shift: Int) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar -> Unicode.Scalar in
            let v = scalar.value
            let base: UInt32
            switch v {
            case 65...90: base = 65
            case 97...122: base = 97
            default: return scalar
            }
            return Unicode.Scalar(base + (v - base + UInt32(shift)) % 26)!
        }))
    }

    static func base64Decode(_ text: String) -> String? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s), let decoded = String(data: data, encoding: .utf8) else { return nil }
        return decoded
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

extension KodikClient {
    /// Прямые HLS-потоки для ссылки плеера (серии или фильма), от лучшего качества к худшему.
    public func streams(for playerURL: URL) async throws -> [KodikStream] {
        try await KodikStreamResolver(transport: transport).streams(for: playerURL)
    }
}
