import Foundation

/// Бизнес-логика личной библиотеки: списки, избранное, прогресс, история.
/// Все изменения сразу сохраняются в постоянное хранилище.
public actor LibraryRepository {
    public static let historyLimit = 500
    /// Повторный просмотр той же серии в пределах этого окна не создаёт новую запись истории.
    public static let historyMergeWindow: TimeInterval = 30 * 60

    private var state: LibrarySnapshot
    private var persistence: LibraryPersistence
    private let guestPersistence: LibraryPersistence
    private var accountStores: [String: LibraryPersistence] = [:]
    public private(set) var activeAccountID: String?
    private var canPersist = true
    private let now: @Sendable () -> Date
    public private(set) var lastSaveError: String?

    public init(persistence: LibraryPersistence, now: @escaping @Sendable () -> Date = { Date() }) {
        self.persistence = persistence
        self.guestPersistence = persistence
        self.now = now
        do {
            state = try persistence.load()
        } catch {
            // Повреждённый файл не должен ронять приложение; начинаем с пустой библиотеки.
            state = .empty
            canPersist = false
            lastSaveError = "Не удалось прочитать библиотеку: \(error.localizedDescription)"
        }
    }

    public func snapshot() -> LibrarySnapshot { state }

    /// One actor read keeps the visible library, continue row and error consistent.
    public struct ViewState: Sendable {
        public let snapshot: LibrarySnapshot
        public let continueWatching: [ContinueWatchingItem]
        public let accountID: String?
        public let errorMessage: String?
    }

    public func viewState(limit: Int = 20) -> ViewState {
        ViewState(snapshot: state, continueWatching: Self.continueWatching(in: state, limit: limit),
                  accountID: activeAccountID, errorMessage: lastSaveError)
    }

    /// Separate local files per account. Legacy library.json is the guest library and is never auto-uploaded.
    public func switchAccount(userID: String?) throws {
        guard userID != activeAccountID else { return }
        if let userID, userID.isEmpty || userID.utf8.count > 120 { throw APIError.badRequest("Некорректный ID аккаунта") }
        let target: LibraryPersistence
        if let userID {
            if let known = accountStores[userID] { target = known }
            else if let file = guestPersistence as? FileLibraryPersistence {
                let safe = Data(userID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
                let created = FileLibraryPersistence(fileURL: file.fileURL.deletingLastPathComponent().appendingPathComponent("library-user-\(safe).json"))
                accountStores[userID] = created; target = created
            } else {
                let created = InMemoryLibraryPersistence(); accountStores[userID] = created; target = created
            }
        } else { target = guestPersistence }
        // Loading first keeps the current library intact when a destination file is corrupt.
        let next = try target.load()
        persistence = target
        state = next
        activeAccountID = userID
        canPersist = true
        lastSaveError = nil
    }

    // MARK: - Lists

    public func setStatus(_ status: LibraryStatus?, for anime: AnimeSnapshot) {
        mutateEntry(anime) { $0.status = status }
    }

    public func setFavorite(_ favorite: Bool, for anime: AnimeSnapshot) {
        mutateEntry(anime) { $0.isFavorite = favorite }
    }

    public func toggleFavorite(_ anime: AnimeSnapshot) -> Bool {
        let newValue = !(state.entry(for: anime.id)?.isFavorite ?? false)
        setFavorite(newValue, for: anime)
        return newValue
    }

    /// Удаляет тайтл из всех списков (мягко — для синхронизации).
    public func remove(animeId: Int) {
        guard let i = state.entries.firstIndex(where: { $0.anime.id == animeId }) else { return }
        state.entries[i].status = nil
        state.entries[i].isFavorite = false
        state.entries[i].isDeleted = true
        state.entries[i].updatedAt = now()
        persist()
    }

    /// Отметить весь тайтл просмотренным.
    public func markCompleted(_ anime: AnimeSnapshot) {
        mutateEntry(anime) { entry in
            entry.status = .completed
            if let total = anime.episodeCount { entry.lastEpisode = total }
        }
    }

    // MARK: - Progress

    /// Сохраняет позицию просмотра. Вызывается плеером периодически и при паузе/выходе.
    public func recordProgress(anime: AnimeSnapshot, episode: Int, position: Double, duration: Double, sourceKey: String? = nil) {
        guard episode > 0, position.isFinite, position >= 0 else { return }
        let t = now()
        let safeDuration = duration.isFinite && duration > 0 ? duration : 0
        let progress = WatchProgress(animeId: anime.id, episode: episode, position: min(position, safeDuration > 0 ? safeDuration : position),
                                     duration: safeDuration, updatedAt: t, sourceKey: sourceKey)
        if let i = state.progress.firstIndex(where: { $0.key == progress.key }) {
            state.progress[i] = progress
        } else {
            state.progress.append(progress)
        }

        mutateEntry(anime, persistNow: false) { entry in
            entry.lastEpisode = episode
            if entry.status == nil || entry.status == .planned || entry.status == .onHold { entry.status = .watching }
            if sourceKey == nil, progress.isFinished, let total = anime.episodeCount, episode >= total { entry.status = .completed }
        }
        appendHistory(anime: anime, episode: episode, at: t, sourceKey: sourceKey)
        persist()
    }

    /// Reject late player events from a session that no longer owns the visible library.
    public func recordProgressForAccount(anime: AnimeSnapshot, episode: Int, position: Double, duration: Double,
                                         sourceKey: String? = nil, accountID: String?) {
        guard activeAccountID == accountID else { return }
        recordProgress(anime: anime, episode: episode, position: position, duration: duration, sourceKey: sourceKey)
    }

    /// Отметить серию просмотренной без воспроизведения.
    public func markEpisodeWatched(anime: AnimeSnapshot, episode: Int, watched: Bool = true) {
        let key = ProgressKey(animeId: anime.id, episode: episode)
        if watched {
            let existingDuration = state.progress.first { $0.key == key }?.duration ?? 0
            let duration = existingDuration > 0 ? existingDuration : 1
            recordProgress(anime: anime, episode: episode, position: duration, duration: duration)
        } else {
            state.progress.removeAll { $0.key == key }
            persist()
        }
    }

    public func progress(animeId: Int, episode: Int, sourceKey: String? = nil) -> WatchProgress? {
        state.progress(animeId: animeId, episode: episode, sourceKey: sourceKey)
    }

    /// Точка продолжения: незавершённая серия или следующая после завершённой.
    public func resumePoint(for anime: AnimeSnapshot, releasedEpisodes: Int? = nil) -> ResumePoint? {
        Self.resumePoint(in: state, animeId: anime.id, lastAvailableEpisode: releasedEpisodes ?? anime.episodeCount)
    }

    public static func resumePoint(in state: LibrarySnapshot, animeId: Int, lastAvailableEpisode: Int?) -> ResumePoint? {
        resumePoint(in: state.progress.filter { $0.animeId == animeId },
                    animeId: animeId, lastAvailableEpisode: lastAvailableEpisode)
    }

    private static func resumePoint(in progress: [WatchProgress], animeId: Int, lastAvailableEpisode: Int?) -> ResumePoint? {
        guard let latest = progress.max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        if let sourceKey = latest.sourceKey {
            guard !latest.isFinished else { return nil } // No guessed next episode/offset.
            return ResumePoint(animeId: animeId, episode: latest.episode, position: latest.position,
                               fraction: latest.fraction, isNextEpisode: false, sourceKey: sourceKey)
        }
        if !latest.isFinished {
            return ResumePoint(animeId: animeId, episode: latest.episode, position: latest.position, fraction: latest.fraction, isNextEpisode: false)
        }
        guard latest.episode < Int.max else { return nil }
        let next = latest.episode + 1
        if let last = lastAvailableEpisode, next > last { return nil }
        let nextProgress = progress.first { $0.episode == next && $0.sourceKey == nil }
        return ResumePoint(animeId: animeId, episode: next, position: nextProgress?.isFinished == false ? nextProgress?.position ?? 0 : 0,
                           fraction: nextProgress?.isFinished == false ? nextProgress?.fraction ?? 0 : 0, isNextEpisode: true)
    }

    /// «Продолжить просмотр» для главного экрана.
    public func continueWatching(limit: Int = 20) -> [ContinueWatchingItem] {
        Self.continueWatching(in: state, limit: limit)
    }

    static func continueWatching(in state: LibrarySnapshot, limit: Int) -> [ContinueWatchingItem] {
        guard limit > 0 else { return [] }
        let byAnime = Dictionary(grouping: state.progress, by: \.animeId)
        // Keep the first entry, as the old first(where:) lookup did; tolerate old duplicates.
        let entries = Dictionary(state.entries.map { ($0.anime.id, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [ContinueWatchingItem] = []
        for (animeId, list) in byAnime {
            guard let entry = entries[animeId], !entry.isDeleted,
                  entry.status != .completed,
                  let resume = resumePoint(in: list, animeId: animeId, lastAvailableEpisode: entry.anime.episodeCount),
                  let updated = list.max(by: { $0.updatedAt < $1.updatedAt })?.updatedAt else { continue }
            items.append(ContinueWatchingItem(anime: entry.anime, resume: resume, updatedAt: updated))
        }
        return Array(items.sorted {
            $0.updatedAt == $1.updatedAt ? $0.anime.id < $1.anime.id : $0.updatedAt > $1.updatedAt
        }.prefix(limit))
    }

    // MARK: - History

    public func clearHistory() {
        let t = now()
        let removed = state.history.map { item -> HistoryItem in var item = item; item.deletedAt = t; return item }
        state.historyTombstones = (state.historyTombstones ?? []) + removed
        state.history.removeAll()
        persist()
    }

    public func removeHistoryItem(id: UUID) {
        guard var item = state.history.first(where: { $0.id == id }) else { return }
        item.deletedAt = now()
        state.historyTombstones = (state.historyTombstones ?? []) + [item]
        state.history.removeAll { $0.id == id }
        persist()
    }

    private func appendHistory(anime: AnimeSnapshot, episode: Int, at t: Date, sourceKey: String? = nil) {
        if let i = state.history.firstIndex(where: { $0.anime.id == anime.id && $0.episode == episode && $0.sourceKey == sourceKey }),
           t.timeIntervalSince(state.history[i].watchedAt) < Self.historyMergeWindow {
            state.history[i].watchedAt = t
            state.history[i].anime = anime
        } else {
            state.history.append(HistoryItem(anime: anime, episode: episode, watchedAt: t, sourceKey: sourceKey))
        }
        state.history.sort { $0.watchedAt > $1.watchedAt }
        if state.history.count > Self.historyLimit { state.history.removeLast(state.history.count - Self.historyLimit) }
    }

    // MARK: - Sync support

    public func setLastSync(_ date: Date) {
        state.lastSyncAt = date
        persist()
    }

    /// Изменения после даты (для отправки на сервер).
    public func changes(since date: Date?) -> (entries: [LibraryEntry], progress: [WatchProgress], history: [HistoryItem]) {
        let history = state.history + (state.historyTombstones ?? [])
        guard let date else { return (state.entries, state.progress, history) }
        return (state.entries.filter { $0.updatedAt > date },
                state.progress.filter { $0.updatedAt > date },
                history.filter { $0.syncTimestamp > date })
    }

    @discardableResult
    public func applySync(entries: [LibraryEntry], progress: [WatchProgress], history: [HistoryItem],
                          accountID: String, startedAt: Date) -> Bool {
        guard activeAccountID == accountID else { return false }
        let previousWatermark = state.lastSyncAt
        state = Self.merged(state, entries: entries, progress: progress, history: history)
        state.lastSyncAt = startedAt
        persist()
        if lastSaveError != nil { state.lastSyncAt = previousWatermark; return false }
        return true
    }

    /// Слияние с данными сервера по правилу «последняя запись побеждает».
    public func merge(entries remote: [LibraryEntry], progress remoteProgress: [WatchProgress], history remoteHistory: [HistoryItem]) {
        state = Self.merged(state, entries: remote, progress: remoteProgress, history: remoteHistory)
        persist()
    }

    static func merged(_ base: LibrarySnapshot, entries remote: [LibraryEntry], progress remoteProgress: [WatchProgress], history remoteHistory: [HistoryItem]) -> LibrarySnapshot {
        var s = base
        for r in remote {
            if let i = s.entries.firstIndex(where: { $0.anime.id == r.anime.id }) {
                if r.updatedAt > s.entries[i].updatedAt { s.entries[i] = r }
            } else {
                s.entries.append(r)
            }
        }
        for r in remoteProgress {
            if let i = s.progress.firstIndex(where: { $0.key == r.key }) {
                if r.updatedAt > s.progress[i].updatedAt { s.progress[i] = r }
            } else {
                s.progress.append(r)
            }
        }
        var byID = Dictionary((s.history + (s.historyTombstones ?? [])).map { ($0.id, $0) }, uniquingKeysWith: { a, b in a.syncTimestamp >= b.syncTimestamp ? a : b })
        for item in remoteHistory {
            if let existing = byID[item.id], existing.syncTimestamp >= item.syncTimestamp { continue }
            byID[item.id] = item
        }
        s.history = byID.values.filter { $0.deletedAt == nil }.sorted { $0.watchedAt > $1.watchedAt }
        let tombstones = byID.values.filter { $0.deletedAt != nil }.sorted { $0.syncTimestamp > $1.syncTimestamp }
        s.historyTombstones = tombstones.isEmpty ? nil : tombstones
        if s.history.count > historyLimit { s.history.removeLast(s.history.count - historyLimit) }
        return s
    }

    // MARK: - Helpers

    private func mutateEntry(_ anime: AnimeSnapshot, persistNow: Bool = true, _ change: (inout LibraryEntry) -> Void) {
        let t = now()
        if let i = state.entries.firstIndex(where: { $0.anime.id == anime.id }) {
            var entry = state.entries[i]
            entry.anime = anime
            entry.isDeleted = false
            change(&entry)
            entry.updatedAt = t
            state.entries[i] = entry
        } else {
            var entry = LibraryEntry(anime: anime, updatedAt: t)
            change(&entry)
            state.entries.append(entry)
        }
        if persistNow { persist() }
    }

    private func persist() {
        guard canPersist else { return } // Preserve the unreadable original file for recovery.
        do {
            state.version = LibrarySnapshot.currentVersion
            try persistence.save(state)
            lastSaveError = nil
        } catch {
            lastSaveError = "Не удалось сохранить библиотеку: \(error.localizedDescription)"
        }
    }
}
