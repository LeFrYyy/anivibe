import Foundation

/// Выполняет только последнюю запущенную операцию: предыдущая отменяется.
/// Используется для поиска «по мере ввода», чтобы устаревшие ответы не перетирали новые.
@MainActor
public final class LatestTaskRunner {
    private var task: Task<Void, Never>?
    private var generation = 0

    public init() {}

    /// - Parameters:
    ///   - debounce: задержка перед стартом (сек.), чтобы не слать запрос на каждый символ.
    ///   - operation: асинхронная работа.
    ///   - completion: вызывается на MainActor только для актуальной (неотменённой) операции.
    public func run<T: Sendable>(debounce: TimeInterval = 0,
                                 operation: @escaping @Sendable () async throws -> T,
                                 completion: @escaping @MainActor (Result<T, Error>) -> Void) {
        task?.cancel()
        generation += 1
        let current = generation
        task = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            let result: Result<T, Error>
            do { result = .success(try await operation()) } catch { result = .failure(error) }
            guard !Task.isCancelled, let self, self.generation == current else { return }
            if case .failure(let error) = result, (error is CancellationError || (error as? APIError) == .cancelled) { return }
            completion(result)
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        generation += 1
    }
}
