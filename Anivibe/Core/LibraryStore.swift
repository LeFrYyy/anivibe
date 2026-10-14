import SwiftUI
import AnivibeCore

/// Наблюдаемая обёртка над `LibraryRepository` для SwiftUI.
@Observable
@MainActor
final class LibraryStore {
    private(set) var snapshot: LibrarySnapshot = .empty
    private(set) var continueWatching: [ContinueWatchingItem] = []
    private(set) var errorMessage: String?
    private(set) var isAccountStorageAvailable = true
    @ObservationIgnored private var refreshGeneration = UUID()
    let repository: LibraryRepository
    /// Вызывается после локальных изменений (для отложенной синхронизации).
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?

    init(repository: LibraryRepository) {
        self.repository = repository
    }

    func load() async { await refresh() }

    func hideVisibleOnAccountFailure() {
        refreshGeneration = UUID(); isAccountStorageAvailable = false; snapshot = .empty; continueWatching = []
        errorMessage = "Хранилище аккаунта недоступно. Исходные файлы сохранены."
    }
    func allowAccountStorage() { refreshGeneration = UUID(); isAccountStorageAvailable = true }
    func refresh() async {
        guard isAccountStorageAvailable else { return }
        refreshGeneration = UUID()
        let request = refreshGeneration
        let view = await repository.viewState()
        let account = await repository.activeAccountID
        guard isAccountStorageAvailable, request == refreshGeneration,
              view.accountID == account else { return }
        // Observation otherwise invalidates every dependent list even on a no-op refresh.
        if snapshot != view.snapshot { snapshot = view.snapshot }
        if continueWatching != view.continueWatching { continueWatching = view.continueWatching }
        if errorMessage != view.errorMessage { errorMessage = view.errorMessage }
    }

    // MARK: Queries

    func entry(for id: Int) -> LibraryEntry? { snapshot.entry(for: id) }
    func isFavorite(_ id: Int) -> Bool { snapshot.entry(for: id)?.isFavorite ?? false }
    func status(of id: Int) -> LibraryStatus? { snapshot.entry(for: id)?.status }
    func progress(_ id: Int, episode: Int, sourceKey: String? = nil) -> WatchProgress? { snapshot.progress(animeId: id, episode: episode, sourceKey: sourceKey) }

    /// Логика продолжения — общая с ядром (`LibraryRepository`), без дублирования.
    func resumePoint(for anime: Anime) -> ResumePoint? {
        LibraryRepository.resumePoint(in: snapshot, animeId: anime.id, lastAvailableEpisode: anime.releasedEpisodeCount)
    }

    // MARK: Mutations

    func setStatus(_ status: LibraryStatus?, for anime: AnimeSnapshot) async {
        guard isAccountStorageAvailable else { return }
        await repository.setStatus(status, for: anime)
        await changed()
    }

    func toggleFavorite(_ anime: AnimeSnapshot) async {
        guard isAccountStorageAvailable else { return }
        _ = await repository.toggleFavorite(anime)
        await changed()
    }

    func remove(_ id: Int) async {
        guard isAccountStorageAvailable else { return }
        await repository.remove(animeId: id)
        await changed()
    }

    func markCompleted(_ anime: AnimeSnapshot) async {
        guard isAccountStorageAvailable else { return }
        await repository.markCompleted(anime)
        await changed()
    }

    func setEpisodeWatched(_ anime: AnimeSnapshot, episode: Int, watched: Bool) async {
        guard isAccountStorageAvailable else { return }
        await repository.markEpisodeWatched(anime: anime, episode: episode, watched: watched)
        await changed()
    }

    func recordProgress(anime: AnimeSnapshot, episode: Int, position: Double, duration: Double, sourceKey: String? = nil, accountID: String?) async {
        guard isAccountStorageAvailable else { return }
        await repository.recordProgressForAccount(anime: anime, episode: episode, position: position, duration: duration, sourceKey: sourceKey, accountID: accountID)
        await changed()
    }

    func clearHistory() async {
        guard isAccountStorageAvailable else { return }
        await repository.clearHistory()
        await changed()
    }

    func removeHistoryItem(_ id: UUID) async {
        guard isAccountStorageAvailable else { return }
        await repository.removeHistoryItem(id: id)
        await changed()
    }

    private func changed() async {
        await refresh()
        onLocalChange?()
    }
}
