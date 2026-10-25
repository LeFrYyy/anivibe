import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Retries only *idempotent* requests (GET/HEAD) after short-lived failures:
/// a dropped connection, a refused connect, a DNS hiccup or 502/503/504.
///
/// Deliberately not retried: POST/PATCH/PUT/DELETE (auth, social writes, AniList
/// GraphQL — it has its own 429 policy), 4xx, timeouts (a retry would multiply a
/// long wait) and "no internet" (the offline message must appear immediately).
public struct RetryingTransport: HTTPTransport {
    public let base: HTTPTransport
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(base: HTTPTransport, maxRetries: Int = 2, baseDelay: TimeInterval = 0.4,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                }) {
        self.base = base
        self.maxRetries = max(0, maxRetries)
        self.baseDelay = max(0, baseDelay)
        self.sleep = sleep
    }

    static let retryableStatuses: Set<Int> = [502, 503, 504]
    static let transientURLErrorCodes: Set<Int> = [
        URLError.networkConnectionLost.rawValue,
        URLError.cannotConnectToHost.rawValue,
        URLError.dnsLookupFailed.rawValue
    ]
    /// A server asking for a longer pause is answered, not hammered.
    static let maxHonouredRetryAfter: TimeInterval = 3

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard Self.isIdempotent(request) else { return try await base.send(request) }
        var attempt = 0
        while true {
            guard !Task.isCancelled else { throw APIError.cancelled }
            let result: (Data, HTTPURLResponse)
            do {
                result = try await base.send(request)
            } catch let error as APIError {
                guard attempt < maxRetries, Self.isTransient(error) else { throw error }
                attempt += 1
                try await pause(delay(for: attempt))
                continue
            }
            let response = result.1
            guard attempt < maxRetries, Self.retryableStatuses.contains(response.statusCode) else { return result }
            var retryAfter: TimeInterval?
            if let header = response.value(forHTTPHeaderField: "Retry-After") {
                // Unknown/HTTP-date formats are conservative: return the response rather
                // than retrying sooner than the server requested. Never pass NaN to sleep.
                guard let seconds = TimeInterval(header), seconds.isFinite, seconds >= 0,
                      seconds <= Self.maxHonouredRetryAfter else { return result }
                retryAfter = seconds
            }
            attempt += 1
            try await pause(max(retryAfter ?? 0, delay(for: attempt)))
        }
    }

    func delay(for attempt: Int) -> TimeInterval {
        baseDelay * pow(2, Double(max(0, attempt - 1)))
    }

    private func pause(_ seconds: TimeInterval) async throws {
        do { try await sleep(seconds) } catch { throw APIError.cancelled }
        if Task.isCancelled { throw APIError.cancelled }
    }

    static func isIdempotent(_ request: URLRequest) -> Bool {
        let method = (request.httpMethod ?? "GET").uppercased()
        return method == "GET" || method == "HEAD"
    }

    static func isTransient(_ error: APIError) -> Bool {
        guard case .network(_, let code) = error else { return false }
        return transientURLErrorCodes.contains(code)
    }
}
