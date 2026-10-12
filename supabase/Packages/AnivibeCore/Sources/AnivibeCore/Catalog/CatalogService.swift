import Foundation

/// Источник МЕТАДАННЫХ (каталог). Не знает ничего о видео.
public protocol CatalogService: Sendable {
    var name: String { get }
    /// `true` для демонстрационного каталога (только режим разработки).
    var isDemo: Bool { get }
    func search(_ query: CatalogQuery) async throws -> CatalogPage
    func details(id: Int) async throws -> AnimeDetails
    func homeFeed() async throws -> HomeFeed
    func genres() async throws -> [String]
}
