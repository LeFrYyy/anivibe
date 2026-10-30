import Foundation

/// Источник МЕТАДАННЫХ (каталог). Не знает ничего о видео.
public protocol CatalogService: Sendable {
    var name: String { get }
    /// `true` для демонстрационного каталога (только режим разработки).
    var isDemo: Bool { get }
    func search(_ query: CatalogQuery) async throws -> CatalogPage
    func details(id: Int) async throws -> AnimeDetails
    func homeFeed() async throws -> HomeFeed
    /// Тайтлы по их MAL/Shikimori ID (привязка манга→аниме и словарь названий).
    func anime(malIDs: [Int]) async throws -> [Anime]
    func genres() async throws -> [String]
    /// Недавно вышедшие серии, от новых к старым.
    func recentEpisodes() async throws -> [AiredEpisode]
}

public extension CatalogService {
    func recentEpisodes() async throws -> [AiredEpisode] { [] }
    func anime(malIDs: [Int]) async throws -> [Anime] { [] }
}
