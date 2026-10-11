import Foundation

/// Результат проверки источника для конкретной серии.
public struct SourceCandidate: Identifiable, Hashable, Sendable {
    public var id: ProviderID { providerID }
    public let providerID: ProviderID
    public let providerName: String
    public let isTestContent: Bool
    public let episode: ProviderEpisode?
    public let availability: Availability
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
    public func candidates(for anime: Anime, season: Int = 1, episode number: Int) async -> [SourceCandidate] {
        let active = providers.filter { !disabled.contains($0.id) }
        let timeout = self.timeout
        let results = await withTaskGroup(of: (Int, SourceCandidate).self) { group -> [(Int, SourceCandidate)] in
            for (index, provider) in active.enumerated() {
                group.addTask {
                    let candidate = await Self.withTimeout(timeout, provider: provider) {
                        await Self.check(provider: provider, anime: anime, season: season, number: number)
                    }
                    return (index, candidate)
                }
            }
            var out: [(Int, SourceCandidate)] = []
            for await r in group { out.append(r) }
            return out
        }
        return results.sorted { lhs, rhs in
            if lhs.1.isTestContent != rhs.1.isTestContent { return !lhs.1.isTestContent }
            if lhs.1.availability.isAvailable != rhs.1.availability.isAvailable { return lhs.1.availability.isAvailable }
            return lhs.0 < rhs.0
        }.map(\.1)
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
