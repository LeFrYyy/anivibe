import Foundation

/// Фасад манги: каталог и метаданные — Shikimori, главы на русском и страницы — MangaDex.
/// Обложки берутся из Shikimori; если их нет — из MangaDex.
public actor MangaHub: MangaService {
    public let name = "Shikimori + MangaDex"
    private let catalog: ShikimoriMangaService
    private let reader: MangaDexService
    private let cache: MetadataCache

    public init(catalog: ShikimoriMangaService, reader: MangaDexService, cache: MetadataCache) {
        self.catalog = catalog
        self.reader = reader
        self.cache = cache
    }

    public func popular(page: Int, limit: Int) async throws -> MangaPage {
        try await catalog.list(page: page, limit: limit)
    }

    public func search(_ text: String, page: Int, limit: Int) async throws -> MangaPage {
        var result = try await catalog.list(page: page, limit: limit, query: text)
        if result.items.isEmpty {
            // Запрос на русском без результата — повторяем транслитом («ванпанчмен» → «vanpanchmen»).
            let latin = CatalogSearchRanking.transliterate(text)
            if latin != text { result = try await catalog.list(page: page, limit: limit, query: latin) }
        }
        return result
    }

    public func details(id: Int) async throws -> Manga {
        var manga = try await catalog.details(id: id)
        manga.mangadexID = await reader.mangadexID(forMALID: id, titles: manga.searchableTitles)
        if manga.coverURL == nil, let mangadexID = manga.mangadexID {
            manga.coverURL = await reader.coverURL(mangadexID: mangadexID)
        }
        return manga
    }

    public func chapters(of manga: Manga) async throws -> [MangaChapter] {
        var mangadexID = manga.mangadexID
        if mangadexID == nil {
            mangadexID = await reader.mangadexID(forMALID: manga.id, titles: manga.searchableTitles)
        }
        guard let mangadexID else { return [] }
        return try await reader.chapters(mangadexID: mangadexID, language: "ru")
    }

    public func pageURLs(chapterID: String) async throws -> [URL] {
        try await reader.pageURLs(chapterID: chapterID)
    }
}
