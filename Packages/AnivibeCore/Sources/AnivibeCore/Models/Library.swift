import Foundation

/// Пользовательские списки. «Избранное» — отдельный флаг, т.к. тайтл может быть
/// одновременно, например, «Смотрю» и «Избранное».
public enum LibraryStatus: String, Codable, CaseIterable, Sendable {
    case watching, completed, planned, onHold, dropped

    public var localizedName: String {
        switch self {
        case .watching: return "Смотрю"
        case .completed: return "Просмотрено"
        case .planned: return "Запланировано"
        case .onHold: return "Отложено"
        case .dropped: return "Брошено"
        }
    }

    public var systemImage: String {
        switch self {
        case .watching: return "play.circle"
        case .completed: return "checkmark.circle"
        case .planned: return "calendar"
        case .onHold: return "pause.circle"
        case .dropped: return "xmark.circle"
        }
    }
}

public struct LibraryEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { anime.id }
    public var anime: AnimeSnapshot
    public var status: LibraryStatus?
    public var isFavorite: Bool
    /// Последняя открытая серия.
    public var lastEpisode: Int?
    public var updatedAt: Date
    /// Мягкое удаление — нужно для синхронизации между устройствами.
    public var isDeleted: Bool

    public init(anime: AnimeSnapshot, status: LibraryStatus? = nil, isFavorite: Bool = false,
                lastEpisode: Int? = nil, updatedAt: Date = Date(), isDeleted: Bool = false) {
        self.anime = anime
        self.status = status
        self.isFavorite = isFavorite
        self.lastEpisode = lastEpisode
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    /// Запись ничего не хранит и может быть скрыта.
    public var isEmpty: Bool { status == nil && !isFavorite }
}

public struct ProgressKey: Hashable, Codable, Sendable {
    public let sourceKey: String?
    public let animeId: Int
    public let episode: Int
    public init(animeId: Int, episode: Int, sourceKey: String? = nil) {
        self.sourceKey = sourceKey
        self.animeId = animeId
        self.episode = episode
    }
}

public struct WatchProgress: Hashable, Codable, Sendable {
    public let sourceKey: String?
    public let animeId: Int
    public let episode: Int
    /// Позиция в секундах.
    public var position: Double
    /// Длительность в секундах (0 — неизвестна).
    public var duration: Double
    public var updatedAt: Date

    public init(animeId: Int, episode: Int, position: Double, duration: Double, updatedAt: Date = Date(), sourceKey: String? = nil) {
        self.sourceKey = sourceKey
        self.animeId = animeId
        self.episode = episode
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
    }

    public var key: ProgressKey { ProgressKey(animeId: animeId, episode: episode, sourceKey: sourceKey) }

    public var fraction: Double {
        guard duration > 0, position.isFinite else { return 0 }
        return min(1, max(0, position / duration))
    }

    /// Серия считается просмотренной после 90% (финальные титры обычно не досматривают).
    public static let finishedThreshold = 0.9

    public var isFinished: Bool { fraction >= Self.finishedThreshold }

    public var percent: Int { Int((fraction * 100).rounded()) }

    /// Старые файлы округляли даты до секунды. При равенстве дат используем
    /// последнюю открытую серию, затем порядок записи, а не первый элемент массива.
    static func latest(in progress: [WatchProgress], preferredEpisode: Int? = nil) -> WatchProgress? {
        progress.enumerated().max { lhs, rhs in
            if lhs.element.updatedAt != rhs.element.updatedAt {
                return lhs.element.updatedAt < rhs.element.updatedAt
            }
            if let preferredEpisode {
                let leftMatches = lhs.element.episode == preferredEpisode
                let rightMatches = rhs.element.episode == preferredEpisode
                if leftMatches != rightMatches { return !leftMatches }
            }
            return lhs.offset < rhs.offset
        }?.element
    }
}

public struct HistoryItem: Identifiable, Hashable, Codable, Sendable {
    public var sourceKey: String?
    public var deletedAt: Date?
    public var syncTimestamp: Date { deletedAt ?? watchedAt }
    public let id: UUID
    public var anime: AnimeSnapshot
    public var episode: Int
    public var watchedAt: Date

    public init(id: UUID = UUID(), anime: AnimeSnapshot, episode: Int, watchedAt: Date = Date(), sourceKey: String? = nil, deletedAt: Date? = nil) {
        self.deletedAt = deletedAt
        self.sourceKey = sourceKey
        self.id = id
        self.anime = anime
        self.episode = episode
        self.watchedAt = watchedAt
    }
}

/// Откуда продолжить просмотр тайтла.
public struct ResumePoint: Hashable, Sendable {
    public let animeId: Int
    public let episode: Int
    public let position: Double
    public let fraction: Double
    /// `true`, если это переход к следующей серии после завершённой.
    public let isNextEpisode: Bool
    public var sourceKey: String? = nil

    /// Это якорь просмотренной серии источника, а не угаданный номер следующей.
    /// Следующую серию можно выбрать только из фактического списка провайдера.
    public var isFinishedSourceEpisode: Bool {
        sourceKey != nil && fraction >= WatchProgress.finishedThreshold
    }
}

public struct ContinueWatchingItem: Identifiable, Hashable, Sendable {
    public var id: Int { anime.id }
    public let anime: AnimeSnapshot
    public let resume: ResumePoint
    public let updatedAt: Date
}

/// Сохраняемое состояние библиотеки.
public struct LibrarySnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 2
    public var version: Int
    public var entries: [LibraryEntry]
    public var progress: [WatchProgress]
    public var history: [HistoryItem]
    public var historyTombstones: [HistoryItem]?
    public var lastSyncAt: Date?

    public init(version: Int = LibrarySnapshot.currentVersion, entries: [LibraryEntry] = [],
                progress: [WatchProgress] = [], history: [HistoryItem] = [], lastSyncAt: Date? = nil, historyTombstones: [HistoryItem]? = nil) {
        self.historyTombstones = historyTombstones
        self.version = version
        self.entries = entries
        self.progress = progress
        self.history = history
        self.lastSyncAt = lastSyncAt
    }

    public static let empty = LibrarySnapshot()

    public var visibleEntries: [LibraryEntry] { entries.filter { !$0.isDeleted && !$0.isEmpty } }

    public func entry(for animeId: Int) -> LibraryEntry? {
        entries.first { $0.anime.id == animeId && !$0.isDeleted }
    }

    public func progress(animeId: Int, episode: Int, sourceKey: String? = nil) -> WatchProgress? {
        progress.first { $0.animeId == animeId && $0.episode == episode && $0.sourceKey == sourceKey }
    }

    public func latestProgress(animeId: Int, episode: Int? = nil) -> WatchProgress? {
        WatchProgress.latest(in: progress.filter {
            $0.animeId == animeId && (episode == nil || $0.episode == episode)
        }, preferredEpisode: entry(for: animeId)?.lastEpisode)
    }

    public func entries(in status: LibraryStatus) -> [LibraryEntry] {
        visibleEntries.filter { $0.status == status }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public var favorites: [LibraryEntry] {
        visibleEntries.filter(\.isFavorite).sorted { $0.updatedAt > $1.updatedAt }
    }
}
