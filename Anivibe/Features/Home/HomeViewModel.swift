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
    /// Популярная манга для блока на главной (экспериментальная функция).
    private(set) var mangaRow: [Manga] = []
    @ObservationIgnored private var feedRequestID: UUID?
    @ObservationIgnored private var recentRequestID: UUID?
    @ObservationIgnored private var lastRecommendationSource: Int?
    @ObservationIgnored private var recommendationRequestID: UUID?

    func load(catalog: CatalogService, force: Bool = false) async {
        if case .loaded = state, !force { return }
        guard force || feedRequestID == nil else { return }
        let requestID = UUID()
        feedRequestID = requestID
        defer {
            if feedRequestID == requestID {
                feedRequestID = nil
                if Task.isCancelled, case .loading = state { state = .idle }
            }
        }
        if case .idle = state { state = .loading }
        if force, case .failed = state { state = .loading }
        do {
            let feed = try await catalog.homeFeed()
            guard !Task.isCancelled, feedRequestID == requestID else { return }
            state = .loaded(feed)
        } catch {
            guard feedRequestID == requestID else { return }
            if Task.isCancelled || error is CancellationError || (error as? APIError) == .cancelled {
                if case .loading = state { state = .idle }
                return
            }
            state = .failed((error as? APIError)?.userMessage ?? "Не удалось загрузить главную.")
        }
    }

    /// «Недавно вышедшие» грузятся отдельно: их ошибка не ломает главную.
    func loadRecentEpisodes(catalog: CatalogService, force: Bool = false) async {
        guard force || recentRequestID == nil else { return }
        let requestID = UUID()
        recentRequestID = requestID
        defer { if recentRequestID == requestID { recentRequestID = nil } }
        if let list = try? await catalog.recentEpisodes(),
           !Task.isCancelled, recentRequestID == requestID {
            recentEpisodes = list
        }
    }

    /// Популярная манга грузится отдельно: её ошибка не ломает главную.
    func loadManga(service: MangaService, enabled: Bool, force: Bool = false) async {
        guard enabled else { mangaRow = []; return }
        guard force || mangaRow.isEmpty else { return }
        if let page = try? await service.popular(page: 1, limit: 15), !Task.isCancelled {
            mangaRow = page.items
        }
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
