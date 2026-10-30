import SwiftUI
import AnivibeCore

/// Ссылка для навигации к карточке манги из чужих стеков (детали аниме, главная).
struct MangaLink: Hashable {
    let id: Int
    let title: String?
    let coverURL: URL?

    init(id: Int, title: String? = nil, coverURL: URL? = nil) {
        self.id = id
        self.title = title
        self.coverURL = coverURL
    }

    init(_ manga: Manga) {
        self.init(id: manga.id, title: manga.title.preferred, coverURL: manga.coverURL)
    }
}

@Observable
@MainActor
final class MangaCatalogViewModel {
    enum FeedState { case idle, loading, loaded([Manga]), failed(String) }

    private(set) var feed: FeedState = .idle
    private(set) var searchResults: [Manga] = []
    private(set) var searching = false
    @ObservationIgnored private var searchID = 0

    var isIdle: Bool { if case .idle = feed { return true }; return false }

    func load(service: MangaService, force: Bool = false) async {
        guard force || isIdle else { return }
        if case .loading = feed { return }
        feed = .loading
        do {
            feed = .loaded(try await service.popular(page: 1, limit: 30).items)
        } catch {
            if Task.isCancelled || (error as? APIError) == .cancelled { feed = .idle; return }
            feed = .failed((error as? APIError)?.userMessage ?? "Не удалось загрузить мангу.")
        }
    }

    /// Дебаунс-поиск по русским и оригинальным названиям; вызывается из `.task(id: searchText)` вью.
    func search(text: String, service: MangaService) async {
        searchID += 1
        let id = searchID
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { searchResults = []; searching = false; return }
        searching = true
        do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
        guard id == searchID else { return }
        let results = try? await service.search(query, page: 1, limit: 40)
        guard id == searchID, !Task.isCancelled else { return }
        searchResults = results?.items ?? []
        searching = false
    }
}

@Observable
@MainActor
final class MangaDetailsViewModel {
    private(set) var manga: Manga?
    private(set) var loading = false
    private(set) var error: String?
    private(set) var chapters: [MangaChapter] = []
    private(set) var chaptersState: ChaptersState = .idle
    private(set) var adaptations: [Anime] = []

    enum ChaptersState { case idle, loading, loaded, empty, failed }

    func load(id: Int, service: MangaService, catalog: CatalogService) async {
        guard manga?.id != id else { return }
        loading = true
        error = nil
        do {
            let details = try await service.details(id: id)
            guard !Task.isCancelled else { return }
            manga = details
            loading = false
            adaptations = (try? await catalog.anime(malIDs: details.animeMALIDs)) ?? []
            await loadChapters(service: service)
        } catch {
            if Task.isCancelled { return }
            self.error = (error as? APIError)?.userMessage ?? "Не удалось загрузить мангу."
            loading = false
        }
    }

    func loadChapters(service: MangaService) async {
        guard let manga, chaptersState != .loading else { return }
        chaptersState = .loading
        do {
            let list = try await service.chapters(of: manga)
            guard !Task.isCancelled else { return }
            chapters = list
            chaptersState = list.isEmpty ? .empty : .loaded
        } catch {
            chaptersState = Task.isCancelled ? .idle : .failed
        }
    }
}

@Observable
@MainActor
final class MangaReaderViewModel {
    private(set) var pages: [URL] = []
    private(set) var loading = false
    private(set) var error: String?

    func load(chapterID: String, service: MangaService) async {
        guard pages.isEmpty, !loading else { return }
        loading = true
        error = nil
        do {
            pages = try await service.pageURLs(chapterID: chapterID)
            if pages.isEmpty { error = "Страницы главы недоступны." }
        } catch {
            if !Task.isCancelled { self.error = "Не удалось загрузить главу." }
        }
        loading = false
    }
}
