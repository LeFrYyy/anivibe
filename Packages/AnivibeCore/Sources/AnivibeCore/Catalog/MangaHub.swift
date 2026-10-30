import Foundation

/// Источник глав манги, переключаемый в карточке.
public enum MangaChapterSource: String, Sendable, CaseIterable {
    case mangalib, senkuro, mangadex

    public var displayName: String {
        switch self {
        case .mangalib: return "MangaLib"
        case .senkuro: return "Senkuro"
        case .mangadex: return "MangaDex"
        }
    }
}

/// Фасад манги: каталог и метаданные — Shikimori; главы на русском — MangaLib (lib.social),
/// Senkuro и MangaDex (переключаемые источники, по умолчанию первый непустой в этом порядке).
/// Обложки — Shikimori, затем MangaDex. Привязки slug'ов выполняются параллельно.
public actor MangaHub: MangaService {
    public let name = "Shikimori + MangaLib"
    private let catalog: ShikimoriMangaService
    private let lib: LibSocialService
    private let senkuro: SenkuroService
    private let reader: MangaDexService
    private let cache: MetadataCache
    /// Разрешённые привязки источников: libSlug / senkuro (slug|branch) / mangadexID.
    private var resolved: [Int: (lib: String?, senkuro: (slug: String, branchID: String)?, dex: String?)] = [:]

    public init(catalog: ShikimoriMangaService, lib: LibSocialService, senkuro: SenkuroService, reader: MangaDexService, cache: MetadataCache) {
        self.catalog = catalog
        self.lib = lib
        self.senkuro = senkuro
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
        await resolveSources(for: manga)
        manga.mangadexID = resolved[id]?.dex
        manga.libSlug = resolved[id]?.lib
        if manga.coverURL == nil, let mangadexID = manga.mangadexID {
            manga.coverURL = await reader.coverURL(mangadexID: mangadexID)
        }
        return manga
    }

    /// Привязки всех источников параллельно; результат кэшируется в актере.
    private func resolveSources(for manga: Manga) async {
        if resolved[manga.id] != nil { return }
        let titles = manga.searchableTitles
        async let libSlug = lib.slug(forMangaID: manga.id, titles: titles)
        async let sen = senkuro.resolve(forMangaID: manga.id, titles: titles)
        async let dexID = reader.mangadexID(forMALID: manga.id, titles: titles)
        resolved[manga.id] = (await libSlug, await sen, await dexID)
    }

    /// Главы по умолчанию: первый непустой источник (MangaLib → Senkuro → MangaDex).
    public func chapters(of manga: Manga) async throws -> [MangaChapter] {
        let map = await chaptersBySource(of: manga)
        for source in MangaChapterSource.allCases {
            if let list = map[source], !list.isEmpty { return list }
        }
        return []
    }

    /// Главы всех источников параллельно: источник → список глав (может быть пустым).
    public func chaptersBySource(of manga: Manga) async -> [MangaChapterSource: [MangaChapter]] {
        await resolveSources(for: manga)
        let bindings = resolved[manga.id] ?? (manga.libSlug, nil, manga.mangadexID)
        async let libList = libChapters(slug: bindings.lib ?? manga.libSlug)
        async let senList = senChapters(binding: bindings.senkuro)
        async let dexList = dexChapters(mangadexID: bindings.dex ?? manga.mangadexID)
        return [.mangalib: await libList, .senkuro: await senList, .mangadex: await dexList]
    }

    /// Глава с префиксом `lib|` читается через MangaLib, `sen|` — через Senkuro,
    /// без префикса — через MangaDex (обратная совместимость существующих id).
    public func pageURLs(chapterID: String) async throws -> [URL] {
        if chapterID.hasPrefix("lib|") {
            return try await lib.pageURLs(chapterID: chapterID)
        }
        if chapterID.hasPrefix("sen|") {
            return try await senkuro.pageURLs(chapterID: chapterID)
        }
        return try await reader.pageURLs(chapterID: chapterID)
    }

    private func libChapters(slug: String?) async -> [MangaChapter] {
        guard let slug else { return [] }
        return (try? await lib.chapters(slug: slug)) ?? []
    }

    private func senChapters(binding: (slug: String, branchID: String)?) async -> [MangaChapter] {
        guard let binding else { return [] }
        return (try? await senkuro.chapters(branchID: binding.branchID, slug: binding.slug)) ?? []
    }

    private func dexChapters(mangadexID: String?) async -> [MangaChapter] {
        guard let mangadexID else { return [] }
        return (try? await reader.chapters(mangadexID: mangadexID, language: "ru")) ?? []
    }
}
