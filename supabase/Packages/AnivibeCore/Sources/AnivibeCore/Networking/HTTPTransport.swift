import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Абстракция сетевого слоя: в приложении — URLSession, в тестах — заглушка.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    /// Сессия с тайм-аутами и HTTP-кэшем по умолчанию.
    public static func standard(timeout: TimeInterval = 20) -> URLSessionTransport {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 3
        #if !canImport(FoundationNetworking)
        config.waitsForConnectivity = false
        #endif
        config.httpAdditionalHeaders = ["User-Agent": "Anivibe/1.0 (iOS)"]
        return URLSessionTransport(session: URLSession(configuration: config))
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse("Нет HTTP-ответа") }
            return (data, http)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as URLError {
            if error.code == .cancelled { throw APIError.cancelled }
            throw APIError.network(error.localizedDescription, code: error.code.rawValue)
        }
    }
}

/// Единая система ошибок сетевых сервисов с понятными сообщениями.
public enum APIError: Error, Equatable, Sendable {
    case network(String, code: Int)
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case badRequest(String)
    case invalidResponse(String)
    case decoding(String)
    case graphQL([String])
    case notConfigured(String)
    case cancelled

    public static func from(status: Int, data: Data, headers: HTTPURLResponse) -> APIError? {
        switch status {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429:
            let retry = (headers.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: retry)
        case 400, 422:
            return .badRequest(String(data: data.prefix(500), encoding: .utf8) ?? "")
        case 500...: return .server(status: status)
        default: return .invalidResponse("HTTP \(status)")
        }
    }

    public var userMessage: String {
        switch self {
        case .network(_, let code):
            if code == URLError.notConnectedToInternet.rawValue { return "Нет подключения к интернету." }
            if code == URLError.timedOut.rawValue { return "Сервер слишком долго не отвечает. Попробуйте ещё раз." }
            if code == URLError.cannotFindHost.rawValue || code == URLError.dnsLookupFailed.rawValue {
                return "Не удалось найти сервер (DNS). Проверьте сеть."
            }
            if code == URLError.secureConnectionFailed.rawValue || code == URLError.serverCertificateUntrusted.rawValue {
                return "Не удалось установить защищённое соединение."
            }
            return "Ошибка сети. Проверьте подключение."
        case .unauthorized: return "Требуется авторизация (401)."
        case .forbidden: return "Доступ запрещён (403)."
        case .notFound: return "Не найдено (404)."
        case .rateLimited(let retry):
            if let retry { return "Слишком много запросов (429). Повторите через \(Int(retry)) с." }
            return "Слишком много запросов (429). Подождите минуту."
        case .server(let status): return "Ошибка сервера (\(status)). Попробуйте позже."
        case .badRequest: return "Некорректный запрос."
        case .invalidResponse: return "Сервер вернул неожиданный ответ."
        case .decoding: return "Не удалось обработать ответ сервера."
        case .graphQL(let messages): return messages.first ?? "Ошибка каталога."
        case .notConfigured(let what): return "\(what) не настроен."
        case .cancelled: return "Запрос отменён."
        }
    }
}

extension URLRequest {
    static func json(url: URL, method: String = "POST", body: Data?, headers: [String: String] = [:], timeout: TimeInterval = 20) -> URLRequest {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }
}
