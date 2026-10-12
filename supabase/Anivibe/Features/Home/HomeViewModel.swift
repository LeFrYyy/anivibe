import SwiftUI
import AnivibeCore

@Observable
@MainActor
final class HomeViewModel {
    enum State { case idle, loading, loaded(HomeFeed), failed(String) }

    private(set) var state: State = .idle
    private(set) var recommendations: [Anime] = []
    private(set) var recommendationsBasis: String?
    @ObservationIgnored private var lastRecommendationSource: Int?

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

    /// Рекомендации строятся от последнего просмотренного тайтла (данные AniList).
    func loadRecommendations(catalog: CatalogService, basedOn item: ContinueWatchingItem?) async {
        guard let item else {
            recommendations = []
            recommendationsBasis = nil
            return
        }
        guard item.anime.id != lastRecommendationSource else { return }
        lastRecommendationSource = item.anime.id
        if let details = try? await catalog.details(id: item.anime.id) {
            recommendations = details.recommendations
            recommendationsBasis = item.anime.title
        }
    }
}
