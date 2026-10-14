import SwiftUI
import AnivibeCore

@Observable
@MainActor
final class AnimeDetailsViewModel {
    enum Phase { case loading, loaded, failed(String) }

    private(set) var anime: Anime
    private(set) var details: AnimeDetails?
    private(set) var episodeList: EpisodeList?
    private(set) var phase: Phase = .loading
    @ObservationIgnored private var loadRequestID: UUID?

    init(anime: Anime) {
        self.anime = anime
    }

    func load(catalog: CatalogService, force: Bool = false) async {
        if details != nil, !force { return }
        guard force || loadRequestID == nil else { return }
        let requestID = UUID()
        loadRequestID = requestID
        defer { if loadRequestID == requestID { loadRequestID = nil } }
        phase = .loading
        do {
            let d = try await catalog.details(id: anime.id)
            guard !Task.isCancelled, loadRequestID == requestID else { return }
            details = d
            anime = d.anime
            episodeList = EpisodeListBuilder.build(from: d)
            phase = .loaded
        } catch {
            guard !Task.isCancelled, loadRequestID == requestID,
                  !(error is CancellationError), (error as? APIError) != .cancelled else { return }
            phase = .failed((error as? APIError)?.userMessage ?? "Не удалось загрузить тайтл.")
        }
    }

    func retry(catalog: CatalogService) async {
        details = nil
        await load(catalog: catalog, force: true)
    }
}

/// Запрос на воспроизведение, передаваемый в плеер.
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let anime: Anime
    let episodes: [Episode]
    let episode: Int
    let startPosition: Double
}
