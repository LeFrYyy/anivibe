import Foundation

/// Результат проверки источника для конкретной серии.
public struct SourceCandidate: Identifiable, Hashable, Sendable {
    public var id: ProviderID { providerID }
    public let providerID: ProviderID
    public let providerName: String
    public let isTestContent: Bool
    public let episode: ProviderEpisode?
    public let availability: Availability

    public init(providerID: ProviderID, providerName: String, isTestContent: Bool, episode: ProviderEpisode?,
                availability: Availability) {
        self.providerID = providerID
        self.providerName = providerName
        self.isTestContent = isTestContent
        self.episode = episode
        self.availability = availability
    }
}

/// Progressive snapshot of a source search (see `ProviderRegistry.candidateUpdates`).
public struct CandidateSearchUpdate: Equatable, Sendable {
    /// Resolved candidates so far, already in priority order.
    public let candidates: [SourceCandidate]
    /// Providers still being checked.
    public let pendingProviderIDs: [ProviderID]
    /// Best available candidate that no pending provider can outrank; safe to play now.
    public let decisive: SourceCandidate?
    public var isComplete: Bool { pendingProviderIDs.isEmpty }

    public init(candidates: [SourceCandidate], pendingProviderIDs: [ProviderID], decisive: SourceCandidate?) {
        self.candidates = candidates
        self.pendingProviderIDs = pendingProviderIDs
        self.decisive = decisive
    }
}

public struct ProviderInfo: Identifiable, Hashable, Sendable {
    public let id: ProviderID
    public let name: String
    public let isEnabled: Bool
    public let isTestContent: Bool

    public init(id: ProviderID, name: String, isEnabled: Bool, isTestContent: Bool) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.isTestContent = isTestContent
    }
}

/// Реестр видеопровайдеров: регистрация, включение/отключение, опрос доступности.
public actor ProviderRegistry {
    private var providers: [VideoSourceProvider] = []
    private var disabled: Set<ProviderID> = []
    private let timeout: TimeInterval

    public init(providers: [VideoSourceProvider] = [], timeout: TimeInterval = 12) {
        self.providers = providers
        self.timeout = timeout
    }

    public func register(_ provider: VideoSourceProvider) {
        providers.removeAll { $0.id == provider.id }
        providers.append(provider)
    }

    public func setEnabled(_ enabled: Bool, for id: ProviderID) {
        if enabled { disabled.remove(id) } else { disabled.insert(id) }
    }

    public func allProviders() -> [ProviderInfo] {
        providers.map { ProviderInfo(id: $0.id, name: $0.displayName, isEnabled: !disabled.contains($0.id), isTestContent: $0.providesTestContent) }
    }

    public func provider(_ id: ProviderID) -> VideoSourceProvider? {
        providers.first { $0.id == id }
    }

    /// Опрашивает все включённые провайдеры параллельно, с тайм-аутом на каждый.
    /// Доступным считается только источник, чья ссылка реально проверена.
    /// Реальные источники идут перед тестовыми.
    public func candidates(for anime: Anime, season: Int = 1, episode number: Int, excluding: Set<ProviderID> = []) async -> [SourceCandidate] {
        var last: [SourceCandidate] = []
        for await update in candidateUpdates(for: anime, season: season, episode: number, excluding: excluding) {
            last = update.candidates
        }
        return last
    }

    /// Same search, reported progressively. Every element is a full, priority-sorted
    /// snapshot. `decisive` appears as soon as no still-pending provider could outrank
    /// the best available result, so playback does not wait for the slowest mirror.
    /// Cancelling the consumer cancels the remaining provider checks.
    public func candidateUpdates(for anime: Anime, season: Int = 1, episode number: Int,
                                 excluding: Set<ProviderID> = []) -> AsyncStream<CandidateSearchUpdate> {
        let active = providers.filter { !disabled.contains($0.id) && !excluding.contains($0.id) }
        let timeout = self.timeout
        return AsyncStream { continuation in
            let task = Task {
                var resolved: [(Int, SourceCandidate)] = []
                var pending = Set(active.indices)
                continuation.yield(Self.update(resolved: resolved, pending: pending, active: active))
                await withTaskGroup(of: (Int, SourceCandidate).self) { group in
                    for (index, provider) in active.enumerated() {
                        group.addTask {
                            let candidate = await Self.withTimeout(timeout, provider: provider) {
                                await Self.check(provider: provider, anime: anime, season: season, number: number)
                            }
                            return (index, candidate)
                        }
                    }
                    for await result in group {
                        resolved.append(result)
                        pending.remove(result.0)
                        continuation.yield(Self.update(resolved: resolved, pending: pending, active: active))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Priority: real before test, available first, Kodik first, then registration order.
    static func precedes(_ lhs: (Int, SourceCandidate), _ rhs: (Int, SourceCandidate)) -> Bool {
        if lhs.1.isTestContent != rhs.1.isTestContent { return !lhs.1.isTestContent }
        if lhs.1.availability.isAvailable != rhs.1.availability.isAvailable { return lhs.1.availability.isAvailable }
        if (lhs.1.providerID == KodikProvider.providerID) != (rhs.1.providerID == KodikProvider.providerID) {
            return lhs.1.providerID == KodikProvider.providerID
        }
        return lhs.0 < rhs.0
    }

    static func update(resolved: [(Int, SourceCandidate)], pending: Set<Int>,
                       active: [VideoSourceProvider]) -> CandidateSearchUpdate {
        let sorted = resolved.sorted(by: precedes)
        let pendingIndices = pending.sorted()
        // The best a pending provider could still achieve is "available".
        let bestPossible = pendingIndices.map { index in
            (index, SourceCandidate(providerID: active[index].id, providerName: active[index].displayName,
                                    isTestContent: active[index].providesTestContent, episode: nil, availability: .available))
        }
        var decisive: SourceCandidate?
        if let best = sorted.first(where: { $0.1.availability.isAvailable }),
           bestPossible.allSatisfy({ precedes(best, $0) }) {
            decisive = best.1
        }
        return CandidateSearchUpdate(candidates: sorted.map(\.1),
                                     pendingProviderIDs: pendingIndices.map { active[$0].id },
                                     decisive: decisive)
    }

    static func check(provider: VideoSourceProvider, anime: Anime, season: Int, number: Int) async -> SourceCandidate {
        func fail(_ e: VideoSourceError, episode: ProviderEpisode? = nil) -> SourceCandidate {
            SourceCandidate(providerID: provider.id, providerName: provider.displayName, isTestContent: provider.providesTestContent,
                            episode: episode, availability: .unavailable(e))
        }
        do {
            guard let title = try await provider.match(anime: anime) else { return fail(.titleNotFound) }
            let episodes = try await provider.episodes(for: title)
            guard let ep = EpisodeMatcher.match(season: season, number: number, in: episodes) else { return fail(.episodeNotFound(number)) }
            let availability = await provider.checkAvailability(ep)
            return SourceCandidate(providerID: provider.id, providerName: provider.displayName, isTestContent: provider.providesTestContent,
                                   episode: ep, availability: availability)
        } catch {
            return fail(.from(error))
        }
    }

    static func withTimeout(_ seconds: TimeInterval, provider: VideoSourceProvider,
                            _ work: @escaping @Sendable () async -> SourceCandidate) async -> SourceCandidate {
        await withTaskGroup(of: SourceCandidate?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? SourceCandidate(providerID: provider.id, providerName: provider.displayName,
                                            isTestContent: provider.providesTestContent, episode: nil,
                                            availability: .unavailable(.timeout))
        }
    }
}
