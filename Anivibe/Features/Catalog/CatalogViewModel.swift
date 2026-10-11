import SwiftUI
import AnivibeCore

@Observable
@MainActor
final class CatalogViewModel {
    enum Phase: Equatable { case idle, loading, loaded, empty, failed(String) }

    var query = CatalogQuery(sort: .popularity)
    private(set) var items: [Anime] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var hasNextPage = false
    private(set) var genres: [String] = []
    private let runner = LatestTaskRunner()
    @ObservationIgnored private var loadMoreTask: Task<Void, Never>?
    @ObservationIgnored private var page = 1

    /// Новый поиск. Предыдущий запрос (и подгрузка страниц) отменяется.
    func reload(catalog: CatalogService, debounce: TimeInterval = 0) {
        loadMoreTask?.cancel()
        isLoadingMore = false
        var q = query.withPage(1)
        // При вводе текста логичнее «по совпадению», если пользователь не выбрал иное.
        if !q.trimmedSearch.isEmpty && q.sort == .popularity { q.sort = .relevance }
        if phase != .loaded || items.isEmpty { phase = .loading }
        runner.run(debounce: debounce, operation: { try await catalog.search(q) }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let page):
                self.page = 1
                self.items = page.items
                self.hasNextPage = page.hasNextPage
                self.phase = page.items.isEmpty ? .empty : .loaded
            case .failure(let error):
                self.phase = .failed((error as? APIError)?.userMessage ?? "Не удалось загрузить каталог.")
            }
        }
    }

    /// Постраничная подгрузка при прокрутке к концу списка.
    func loadMoreIfNeeded(current anime: Anime, catalog: CatalogService) {
        guard hasNextPage, !isLoadingMore, phase == .loaded,
              let index = items.firstIndex(of: anime), index >= items.count - 6 else { return }
        isLoadingMore = true
        var q = query.withPage(page + 1)
        if !q.trimmedSearch.isEmpty && q.sort == .popularity { q.sort = .relevance }
        loadMoreTask = Task { [weak self] in
            do {
                let next = try await catalog.search(q)
                guard !Task.isCancelled, let self else { return }
                let known = Set(self.items.map(\.id))
                self.items.append(contentsOf: next.items.filter { !known.contains($0.id) })
                self.page = next.page
                self.hasNextPage = next.hasNextPage
            } catch {
                // Ошибку подгрузки не показываем на весь экран — можно прокрутить ещё раз.
            }
            self?.isLoadingMore = false
        }
    }

    func loadGenres(catalog: CatalogService) async {
        guard genres.isEmpty else { return }
        genres = (try? await catalog.genres()) ?? []
    }

    func resetFilters() {
        query.genres = []
        query.year = nil
        query.status = nil
        query.formats = []
        query.season = nil
    }
}
