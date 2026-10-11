import SwiftUI
import AnivibeCore

/// Наблюдаемая обёртка над `LibraryRepository` для SwiftUI.
@Observable
@MainActor
final class LibraryStore {
    private(set) var snapshot: LibrarySnapshot = .empty
    private(set) var continueWatching: [ContinueWatchingItem] = []
    private(set) var errorMessage: String?
    let repository: LibraryRepository
    /// Вызывается после локальных изменений (для отложенной синхронизации).
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    func load() async { await refresh() }

    func refresh() async {
        snapshot = await repository.snapshot()
        continueWatching = await repository.continueWatching()
        errorMessage = await repository.lastSaveError
    }

    // MARK: Queries

    func entry(for id: Int) -> LibraryEntry? { snapshot.entry(for: id) }
    func isFavorite(_ id: Int) -> Bool { snapshot.entry(for: id)?.isFavorite ?? false }
    func status(of id: Int) -> LibraryStatus? { snapshot.entry(for: id)?.status }
    func progress(_ id: Int, episode: Int) -> WatchProgress? { snapshot.progress(animeId: id, episode: episode) }

    /// Логика продолжения — общая с ядром (`LibraryRepository`), без дублирования.
    func resumePoint(for anime: Anime) -> ResumePoint? {
        LibraryRepository.resumePoint(in: snapshot, animeId: anime.id, lastAvailableEpisode: anime.releasedEpisodeCount)
    }

    // MARK: Mutations

    func setStatus(_ status: LibraryStatus?, for anime: AnimeSnapshot) async {
        await repository.setStatus(status, for: anime)
        await changed()
    }

    func toggleFavorite(_ anime: AnimeSnapshot) async {
        _ = await repository.toggleFavorite(anime)
        await changed()
    }

    func remove(_ id: Int) async {
        await repository.remove(animeId: id)
        await changed()
    }

    func markCompleted(_ anime: AnimeSnapshot) async {
        await repository.markCompleted(anime)
        await changed()
    }

    func setEpisodeWatched(_ anime: AnimeSnapshot, episode: Int, watched: Bool) async {
        await repository.markEpisodeWatched(anime: anime, episode: episode, watched: watched)
        await changed()
    }

    func recordProgress(anime: AnimeSnapshot, episode: Int, position: Double, duration: Double) async {
        await repository.recordProgress(anime: anime, episode: episode, position: position, duration: duration)
        await changed()
    }

    func clearHistory() async {
        await repository.clearHistory()
        await changed()
    }

    func removeHistoryItem(_ id: UUID) async {
        await repository.removeHistoryItem(id: id)
        await changed()
    }

    private func changed() async {
        await refresh()
        onLocalChange?()
    }
}
