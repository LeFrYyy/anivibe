import Foundation

/// Источник манги: каталог метаданных и главы для чтения на русском.
public protocol MangaService: Sendable {
    var name: String { get }
    /// Популярная манга (лента для главной и каталога).
    func popular(page: Int, limit: Int) async throws -> MangaPage
    /// Поиск по русским и оригинальным названиям.
    func search(_ text: String, page: Int, limit: Int) async throws -> MangaPage
    /// Полная карточка + связи (адаптации) + ID источника глав.
    func details(id: Int) async throws -> Manga
    /// Главы с русским переводом, отсортированные по номеру.
    func chapters(of manga: Manga) async throws -> [MangaChapter]
    /// URL страниц главы для встроенной читалки (`nil`/пусто — читать нельзя, только внешняя ссылка).
    func pageURLs(chapterID: String) async throws -> [URL]
}

public extension MangaService {
    func pageURLs(chapterID: String) async throws -> [URL] { [] }
}
