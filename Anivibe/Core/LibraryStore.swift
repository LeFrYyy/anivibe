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
    /// Счётчик успешных правок библиотеки: вьюхи вешают на него `.sensoryFeedback`.
    /// Нужен потому, что мутации асинхронные и вызываются из разных мест —
    /// вести тактильный отклик из каждой кнопки значило бы дублировать код.
    private(set) var changeFeedback = 0
    enum ChangeKind: Equatable { case light, success }
    private(set) var lastChangeKind: ChangeKind = .light
    @ObservationIgnored private var refreshGeneration = UUID()
    /// Последний опубликованный в виджет снимок — чтобы не писать файл без изменений.
    @ObservationIgnored private var publishedContinueWatching: [ContinueWatchingItem] = []
    @ObservationIgnored private var publishedLibraryCount = -1
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
        // Виджет обновляем только при реальном изменении списка: иначе каждая
        // синхронизация писала бы файл в App Group и перезапускала таймлайн.
        if publishedContinueWatching != view.continueWatching || publishedLibraryCount != view.snapshot.visibleEntries.count {
            publishedContinueWatching = view.continueWatching
            publishedLibraryCount = view.snapshot.visibleEntries.count
            WidgetBridge.publish(continueWatching: view.continueWatching, libraryCount: publishedLibraryCount)
        }
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
        signalChange(status == nil ? .light : (status == .completed ? .success : .light))
    }

    func toggleFavorite(_ anime: AnimeSnapshot) async {
        guard isAccountStorageAvailable else { return }
        let nowFavorite = await repository.toggleFavorite(anime)
        await changed()
        signalChange(nowFavorite ? .success : .light)
    }

    func setFavorite(_ favorite: Bool, for anime: AnimeSnapshot) async {
        guard isAccountStorageAvailable else { return }
        await repository.setFavorite(favorite, for: anime)
        await changed()
        signalChange(favorite ? .success : .light)
    }

    func remove(_ id: Int) async {
        guard isAccountStorageAvailable else { return }
        await repository.remove(animeId: id)
        await changed()
        signalChange(.light)
    }

    func markCompleted(_ anime: AnimeSnapshot) async {
        guard isAccountStorageAvailable else { return }
        await repository.markCompleted(anime)
        await changed()
        signalChange(.success)
    }

    func setEpisodeWatched(_ anime: AnimeSnapshot, episode: Int, watched: Bool) async {
        guard isAccountStorageAvailable else { return }
        await repository.markEpisodeWatched(anime: anime, episode: episode, watched: watched)
        await changed()
        signalChange(watched ? .success : .light)
    }

    func recordProgress(anime: AnimeSnapshot, episode: Int, position: Double, duration: Double,
                        sourceKey: String? = nil, accountID: String?, recordedAt: Date? = nil) async {
        guard isAccountStorageAvailable else { return }
        await repository.recordProgressForAccount(anime: anime, episode: episode, position: position, duration: duration,
                                                  sourceKey: sourceKey, accountID: accountID, recordedAt: recordedAt)
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

    private func signalChange(_ kind: ChangeKind) {
        lastChangeKind = kind
        changeFeedback &+= 1
    }

    // MARK: Undo

    /// Удаляет запись, сохраняя её для отката. Возвращает восстановитель,
    /// который `LibraryView` показывает в плашке «Удалено — Отменить».
    @discardableResult
    func removeWithUndo(_ id: Int) async -> (() async -> Void)? {
        guard isAccountStorageAvailable, let entry = snapshot.entry(for: id) else { return nil }
        await remove(id)
        let anime = entry.anime
        let status = entry.status
        let favorite = entry.isFavorite
        return { [weak self] in
            guard let self else { return }
            if let status { await self.setStatus(status, for: anime) }
            if favorite { await self.setFavorite(true, for: anime) }
        }
    }
}
