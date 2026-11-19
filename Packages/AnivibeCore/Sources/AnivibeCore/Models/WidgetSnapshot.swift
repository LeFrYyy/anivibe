import Foundation

/// Данные, которыми приложение делится с виджетом через App Group.
///
/// Модель намеренно платформенно-независима (только Foundation), чтобы её мог читать
/// и тестировать `AnivibeCore`, а виджет — просто декодировать из общего файла.
/// Никаких секретов и токенов здесь нет: только название, постер и прогресс.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    /// Один тайтл для отображения в виджете.
    public struct Item: Codable, Hashable, Sendable, Identifiable {
        /// ID тайтла AniList — из него строится deep link `anivibe://anime/<id>`.
        public let id: Int
        public let title: String
        public let coverURL: URL?
        public let episode: Int
        public let progress: Double

        public init(id: Int, title: String, coverURL: URL? = nil, episode: Int, progress: Double) {
            self.id = id
            self.title = title
            self.coverURL = coverURL
            self.episode = episode
            self.progress = progress
        }

        /// Прогресс, безопасный для отрисовки (0…1, конечное число).
        public var safeProgress: Double {
            guard progress.isFinite else { return 0 }
            return min(1, max(0, progress))
        }

        public var percent: Int { Int((safeProgress * 100).rounded()) }
    }

    public var version: Int
    /// Тайтлы «Продолжить просмотр», от новых к старым.
    public var continueWatching: [Item]
    /// Сколько тайтлов в библиотеке со статусом (для бейджа).
    public var libraryCount: Int
    public var updatedAt: Date

    public init(version: Int = WidgetSnapshot.currentVersion, continueWatching: [Item] = [],
                libraryCount: Int = 0, updatedAt: Date = Date()) {
        self.version = version
        self.continueWatching = continueWatching
        self.libraryCount = libraryCount
        self.updatedAt = updatedAt
    }

    public static let empty = WidgetSnapshot()

    /// Первый тайтл для отрисовки (например, в small-семействе).
    public var primaryItem: Item? { continueWatching.first }

    /// deep link для тайтла: `anivibe://anime/<id>`.
    public static func deepLink(for animeID: Int) -> URL? {
        URL(string: "anivibe://anime/\(animeID)")
    }

    /// Разбор deep link виджета. `nil`, если это не ссылка на тайтл.
    public static func animeID(from url: URL) -> Int? {
        guard url.scheme == "anivibe", url.host == "anime" else { return nil }
        let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !id.isEmpty, let value = Int(id), value > 0 else { return nil }
        return value
    }
}

/// Общий файл обмена между приложением и виджетом (App Group).
public enum WidgetSnapshotStore {
    /// Идентификатор App Group. Должен совпадать в обоих таргетах.
    public static let appGroupIdentifier = "group.com.example.anivibe"
    public static let filename = "widget-snapshot.json"

    /// Каталог App Group. `nil`, если App Group не настроен (например, в тестах).
    public static func directory(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    public static func fileURL(fileManager: FileManager = .default) -> URL? {
        directory(fileManager: fileManager)?.appendingPathComponent(filename)
    }

    /// Сохраняет снимок в общий контейнер. Молча ничего не делает без App Group.
    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot, fileManager: FileManager = .default) -> Bool {
        guard let url = fileURL(fileManager: fileManager) else { return false }
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// Читает снимок; при отсутствии/повреждении файла возвращает `.empty`.
    public static func read(fileManager: FileManager = .default) -> WidgetSnapshot {
        guard let url = fileURL(fileManager: fileManager),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Строит снимок из текущего состояния библиотеки (вызывается приложением).
    public static func make(from items: [ContinueWatchingItem], libraryCount: Int, now: Date = Date()) -> WidgetSnapshot {
        let mapped = items.prefix(6).map { item in
            WidgetSnapshot.Item(id: item.anime.id, title: item.anime.title, coverURL: item.anime.coverURL,
                 episode: item.resume.episode, progress: item.resume.fraction)
        }
        return WidgetSnapshot(continueWatching: mapped, libraryCount: libraryCount, updatedAt: now)
    }
}
