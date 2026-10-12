import Foundation

/// Ограничитель частоты запросов (скользящее окно) с поддержкой Retry-After.
public actor RateLimiter {
    private let limit: Int
    private let interval: TimeInterval
    private var timestamps: [Date] = []
    private var blockedUntil: Date?
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(limit: Int, per interval: TimeInterval,
                now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64(max(0, $0) * 1_000_000_000)) }) {
        self.limit = max(1, limit)
        self.interval = interval
        self.now = now
        self.sleep = sleep
    }

    /// Задержка до момента, когда можно выполнить следующий запрос (0 — можно сейчас).
    public func delayBeforeNextRequest() -> TimeInterval {
        let current = now()
        timestamps.removeAll { current.timeIntervalSince($0) >= interval }
        var delay: TimeInterval = 0
        if let blockedUntil, blockedUntil > current { delay = blockedUntil.timeIntervalSince(current) }
        if timestamps.count >= limit, let oldest = timestamps.first {
            delay = max(delay, interval - current.timeIntervalSince(oldest))
        }
        return delay
    }

    /// Ждёт свободный слот и резервирует его. Бросает CancellationError при отмене.
    public func acquire(maxWait: TimeInterval = 65) async throws {
        while true {
            try Task.checkCancellation()
            let delay = delayBeforeNextRequest()
            if delay <= 0 {
                timestamps.append(now())
                return
            }
            if delay > maxWait { throw APIError.rateLimited(retryAfter: delay) }
            try await sleep(delay)
        }
    }

    /// Сервер ответил 429 — блокируем запросы на указанное время.
    public func block(for seconds: TimeInterval) {
        blockedUntil = now().addingTimeInterval(seconds)
    }
}
