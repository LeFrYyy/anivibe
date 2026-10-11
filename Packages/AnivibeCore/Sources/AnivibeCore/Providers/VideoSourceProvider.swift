import Foundation

/// Тайтл в терминах конкретного видеопровайдера.
public struct ProviderTitle: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let providerID: ProviderID
    public let titles: [String]
    /// Идентификатор AniList, если провайдер явно его указывает (самое надёжное сопоставление).
    public let anilistID: Int?
    /// Год выхода у провайдера — используется как запасной критерий сопоставления.
    public let year: Int?

    public init(id: String, providerID: ProviderID, titles: [String], anilistID: Int? = nil, year: Int? = nil) {
        self.id = id
        self.providerID = providerID
        self.titles = titles
        self.anilistID = anilistID
        self.year = year
    }
}

/// Серия в терминах провайдера.
public struct ProviderEpisode: Hashable, Codable, Sendable, Identifiable {
    public var id: String { "\(providerID.rawValue):\(titleID):\(season ?? 0):\(number)" }
    public let providerID: ProviderID
    public let titleID: String
    /// Сезон у провайдера (`nil` — сквозная нумерация).
    public let season: Int?
    public let number: Int
    public let title: String?
    /// Внутренние данные провайдера, необходимые для получения ссылки.
    public let payload: String

    public init(providerID: ProviderID, titleID: String, season: Int?, number: Int, title: String? = nil, payload: String) {
        self.providerID = providerID
        self.titleID = titleID
        self.season = season
        self.number = number
        self.title = title
        self.payload = payload
    }
}

public struct ProviderCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let search = ProviderCapabilities(rawValue: 1 << 0)
    public static let episodeList = ProviderCapabilities(rawValue: 1 << 1)
    public static let audioTracksInfo = ProviderCapabilities(rawValue: 1 << 2)
    public static let subtitlesInfo = ProviderCapabilities(rawValue: 1 << 3)
    public static let availabilityCheck = ProviderCapabilities(rawValue: 1 << 4)
}

public enum Availability: Hashable, Sendable {
    case available
    case unavailable(VideoSourceError)

    public var isAvailable: Bool { if case .available = self { return true } else { return false } }
}

/// Ошибки видеоисточников — показываются пользователю как есть.
public enum VideoSourceError: Error, Hashable, Sendable {
    case notConfigured(String)
    case disabled
    case titleNotFound
    case episodeNotFound(Int)
    case unavailable(String)
    case unsupportedFormat(String)
    case linkExpired
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized
    case network(String)
    case invalidResponse(String)
    case timeout

    public var userMessage: String {
        switch self {
        case .notConfigured(let what): return "Источник не настроен: \(what)."
        case .disabled: return "Источник отключён в настройках."
        case .titleNotFound: return "У источника нет этого тайтла."
        case .episodeNotFound(let n): return "У источника нет серии \(n)."
        case .unavailable(let reason): return "Видео недоступно: \(reason)"
        case .unsupportedFormat(let f): return "Формат не поддерживается плеером: \(f)."
        case .linkExpired: return "Срок действия ссылки истёк. Обновите источник."
        case .rateLimited: return "Источник временно ограничил запросы. Попробуйте позже."
        case .unauthorized: return "Источник отклонил доступ (проверьте ключ/авторизацию)."
        case .network(let m): return "Сетевая ошибка: \(m)"
        case .invalidResponse(let m): return "Некорректный ответ источника: \(m)"
        case .timeout: return "Источник не ответил вовремя."
        }
    }

    static func from(_ error: Error) -> VideoSourceError {
        if let e = error as? VideoSourceError { return e }
        if let api = error as? APIError {
            switch api {
            case .unauthorized, .forbidden: return .unauthorized
            case .notFound: return .unavailable("ресурс не найден (404)")
            case .rateLimited(let r): return .rateLimited(retryAfter: r)
            case .network: return .network(api.userMessage)
            case .notConfigured(let w): return .notConfigured(w)
            default: return .invalidResponse(api.userMessage)
            }
        }
        return .invalidResponse(String(describing: error))
    }
}

/// Единый интерфейс видеоисточника. Новые провайдеры реализуют этот протокол
/// и регистрируются в `ProviderRegistry` — каталог и плеер менять не нужно.
///
/// Подключайте ТОЛЬКО источники, условия которых разрешают встраивание в стороннее приложение.
public protocol VideoSourceProvider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }
    /// Источник отдаёт тестовые потоки, а не серии аниме.
    var providesTestContent: Bool { get }

    /// Поиск по названию у провайдера.
    func search(title: String) async throws -> [ProviderTitle]
    /// Сопоставление с тайтлом каталога (по ID или названиям). `nil` — не найдено.
    func match(anime: Anime) async throws -> ProviderTitle?
    /// Список серий у провайдера.
    func episodes(for title: ProviderTitle) async throws -> [ProviderEpisode]
    /// Разрешённая ссылка для воспроизведения + сведения о дорожках.
    func resolve(_ episode: ProviderEpisode) async throws -> PlaybackSource
    /// Проверка доступности конкретной серии (без начала воспроизведения).
    func checkAvailability(_ episode: ProviderEpisode) async -> Availability
}

public extension VideoSourceProvider {
    var providesTestContent: Bool { false }

    func match(anime: Anime) async throws -> ProviderTitle? {
        let candidates = try await search(title: anime.title.preferred)
        if let byID = candidates.first(where: { $0.anilistID == anime.id }) { return byID }
        return TitleMatcher.bestMatch(for: anime.allTitles, among: candidates, titlesOf: \.titles)
    }

    func checkAvailability(_ episode: ProviderEpisode) async -> Availability {
        do {
            let source = try await resolve(episode)
            return source.isExpired() ? .unavailable(.linkExpired) : .available
        } catch {
            return .unavailable(.from(error))
        }
    }
}

/// Сопоставление сезона/номера серии каталога с сериями провайдера.
public enum EpisodeMatcher {
    /// - Parameters:
    ///   - season: сезон, который ожидает каталог (для AniList обычно 1 — каждый сезон отдельный тайтл).
    ///   - number: номер серии внутри сезона.
    ///   - absoluteOffset: если провайдер нумерует сквозняком, сколько серий было в предыдущих сезонах.
    public static func match(season: Int, number: Int, in episodes: [ProviderEpisode], absoluteOffset: Int? = nil) -> ProviderEpisode? {
        if let exact = episodes.first(where: { $0.season == season && $0.number == number }) { return exact }
        let unseasoned = episodes.filter { $0.season == nil }
        if let offset = absoluteOffset, let abs = unseasoned.first(where: { $0.number == offset + number }) { return abs }
        if season == 1 || absoluteOffset == nil, let plain = unseasoned.first(where: { $0.number == number }) { return plain }
        // Провайдер хранит только один сезон под номером 1, а каталог просит сезон 1.
        return nil
    }
}
