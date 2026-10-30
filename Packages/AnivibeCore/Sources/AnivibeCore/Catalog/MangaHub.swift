import Foundation

/// Фасад манги: каталог и метаданные — Shikimori, главы на русском — lib.social (MangaLib)
/// с фолбэком на MangaDex. Обложки — Shikimori, затем MangaDex.
/// Привязка slug'ов выполняется параллельно, чтобы страница открывалась быстрее.
public actor MangaHub: MangaService {
    public let name = "Shikimori + MangaLib"
    private let catalog: ShikimoriMangaService
    private let lib: LibSocialService
    private let reader: MangaDexService
    private let cache: MetadataCache

    public init(catalog: ShikimoriMangaService, lib: LibSocialService, reader: MangaDexService, cache: MetadataCache) {
        self.catalog = catalog
        self.lib = lib
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
        let titles = manga.searchableTitles
        async let dexID = reader.mangadexID(forMALID: id, titles: titles)
        async let slug = lib.slug(forMangaID: id, titles: titles)
        manga.mangadexID = await dexID
        manga.libSlug = await slug
        if manga.coverURL == nil, let mangadexID = manga.mangadexID {
            manga.coverURL = await reader.coverURL(mangadexID: mangadexID)
        }
        return manga
    }

    /// Главы: lib.social и MangaDex опрашиваются параллельно; предпочитаем lib.social —
    /// там русских переводов заметно больше. MangaDex остаётся фолбэком.
    public func chapters(of manga: Manga) async throws -> [MangaChapter] {
        async let libChapters = libChapters(of: manga)
        async let dexChapters = dexChapters(of: manga)
        let lib = await libChapters
        if !lib.isEmpty { return lib }
        return await dexChapters
    }

    /// Глава с `lib|`-идентификатором читается через lib.social, остальные — через MangaDex.
    public func pageURLs(chapterID: String) async throws -> [URL] {
        if chapterID.hasPrefix("lib|") {
            return try await lib.pageURLs(chapterID: chapterID)
        }
        return try await reader.pageURLs(chapterID: chapterID)
    }

    private func libChapters(of manga: Manga) async -> [MangaChapter] {
        var slug = manga.libSlug
        if slug == nil {
            slug = await lib.slug(forMangaID: manga.id, titles: manga.searchableTitles)
        }
        guard let slug else { return [] }
        return (try? await lib.chapters(slug: slug)) ?? []
    }

    private func dexChapters(of manga: Manga) async -> [MangaChapter] {
        var mangadexID = manga.mangadexID
        if mangadexID == nil {
            mangadexID = await reader.mangadexID(forMALID: manga.id, titles: manga.searchableTitles)
        }
        guard let mangadexID else { return [] }
        return (try? await reader.chapters(mangadexID: mangadexID, language: "ru")) ?? []
    }
}
