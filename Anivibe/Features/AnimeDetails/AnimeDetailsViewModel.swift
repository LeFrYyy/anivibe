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

    init(anime: Anime) {
        self.anime = anime
    }

    func load(catalog: CatalogService) async {
        if details != nil { return }
        phase = .loading
        do {
            let d = try await catalog.details(id: anime.id)
            details = d
            anime = d.anime
            episodeList = EpisodeListBuilder.build(from: d)
            phase = .loaded
        } catch let e as APIError {
            if e != .cancelled { phase = .failed(e.userMessage) }
        } catch {
            phase = .failed("Не удалось загрузить тайтл.")
        }
    }

    func retry(catalog: CatalogService) async {
        details = nil
        await load(catalog: catalog)
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
