import SwiftUI
import AnivibeCore

@Observable
@MainActor
final class HomeViewModel {
    enum State { case idle, loading, loaded(HomeFeed), failed(String) }

    private(set) var state: State = .idle
    private(set) var recommendations: [Anime] = []
    private(set) var recommendationsBasis: String?
    private(set) var recentEpisodes: [AiredEpisode] = []
    @ObservationIgnored private var lastRecommendationSource: Int?
    @ObservationIgnored private var recommendationRequestID: UUID?

    func load(catalog: CatalogService, force: Bool = false) async {
        if case .loaded = state, !force { return }
        if case .idle = state { state = .loading }
        if force, case .failed = state { state = .loading }
        do {
            state = .loaded(try await catalog.homeFeed())
        } catch let e as APIError {
            if e != .cancelled { state = .failed(e.userMessage) }
        } catch {
            state = .failed("Не удалось загрузить главную.")
        }
    }

    /// «Недавно вышедшие» грузятся отдельно: их ошибка не ломает главную.
    func loadRecentEpisodes(catalog: CatalogService) async {
        if let list = try? await catalog.recentEpisodes() { recentEpisodes = list }
    }

    /// Рекомендации строятся от последнего просмотренного тайтла (данные AniList).
    func loadRecommendations(catalog: CatalogService, basedOn item: ContinueWatchingItem?) async {
        guard let item else {
            recommendations = []
            recommendationsBasis = nil
            lastRecommendationSource = nil
            recommendationRequestID = nil
            return
        }
        guard item.anime.id != lastRecommendationSource else { return }
        let requestID = UUID()
        recommendationRequestID = requestID
        lastRecommendationSource = nil
        recommendations = []
        recommendationsBasis = nil
        if let details = try? await catalog.details(id: item.anime.id) {
            guard recommendationRequestID == requestID, !Task.isCancelled else { return }
            lastRecommendationSource = item.anime.id
            recommendations = details.recommendations
            recommendationsBasis = item.anime.title
        }
    }
}
