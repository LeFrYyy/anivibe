import SwiftUI
import AnivibeCore

@Observable
@MainActor
final class CatalogViewModel {
    enum Phase: Equatable { case idle, loading, loaded, empty, failed(String) }

    var query = CatalogQuery(sort: .popularity)
    private(set) var items: [Anime] = []
    private(set) var suggestions: [Anime] = []
    private(set) var phase: Phase = .idle
    private(set) var isSearchingLive = false
    private(set) var isLoadingMore = false
    private(set) var hasNextPage = false
    private(set) var genres: [String] = []
    private(set) var needsReload = true

    private let runner = LatestTaskRunner()
    @ObservationIgnored private var loadMoreTask: Task<Void, Never>?
    @ObservationIgnored private var loadMoreRequestID: UUID?
    @ObservationIgnored private var reloadRequestID: UUID?
    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var page = 1
    @ObservationIgnored private var knownAnimePool: [Anime] = []

    /// Обработка изменения текста поиска в реальном времени.
    func handleSearchTextChange(catalog: CatalogService) {
        let text = query.trimmedSearch
        if text.isEmpty {
            suggestions = []
            isSearchingLive = false
            if query.sort == .relevance { query.sort = .popularity }
            reload(catalog: catalog, debounce: 0)
            return
        }

        // 1. Мгновенные подсказки из пула известных тайтлов (0 мс задержки)
        let matches = knownAnimePool
            .map { ($0, CatalogSearchRanking.score(query: text, anime: $0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        // A query with no local matches must not keep suggestions from the previous text.
        self.suggestions = Array(matches.prefix(10))

        // 2. Сетевой поиск с минимальным дебаунсом (0.25 сек)
        isSearchingLive = true
        reload(catalog: catalog, debounce: 0.25)
    }

    /// Новый поиск. Предыдущий запрос (и подгрузка страниц) отменяется.
    func reload(catalog: CatalogService, debounce: TimeInterval = 0) {
        loadMoreTask?.cancel()
        loadMoreTask = nil
        loadMoreRequestID = nil
        isLoadingMore = false
        hasNextPage = false
        isReloading = true
        needsReload = true
        let requestID = UUID()
        reloadRequestID = requestID
        var q = query.withPage(1)
        // При вводе текста логичнее «по совпадению», если пользователь не выбрал иное.
        if !q.trimmedSearch.isEmpty && q.sort == .popularity { q.sort = .relevance }
        if phase != .loaded || items.isEmpty { phase = .loading }
        let searchQuery = q
        runner.run(debounce: debounce, operation: { try await catalog.search(searchQuery) }) { [weak self] result in
            guard let self, self.reloadRequestID == requestID else { return }
            self.reloadRequestID = nil
            self.isReloading = false
            self.needsReload = false
            self.isSearchingLive = false
            switch result {
            case .success(let page):
                var seen = Set<Int>()
                let uniqueItems = page.items.filter { seen.insert($0.id).inserted }
                self.page = 1
                self.items = uniqueItems
                if !searchQuery.trimmedSearch.isEmpty {
                    self.suggestions = uniqueItems
                }
                self.remember(uniqueItems)
                self.hasNextPage = page.hasNextPage
                self.phase = uniqueItems.isEmpty ? .empty : .loaded
            case .failure(let error):
                self.phase = .failed((error as? APIError)?.userMessage ?? "Не удалось загрузить каталог.")
            }
        }
    }

    /// Немедленный поиск (например, при нажатии Return на клавиатуре или выборе «Все результаты»).
    func submitSearch(catalog: CatalogService) {
        runner.cancel()
        isSearchingLive = false
        reload(catalog: catalog, debounce: 0)
    }

    /// Постраничная подгрузка при прокрутке к концу списка.
    func loadMoreIfNeeded(current anime: Anime, catalog: CatalogService) {
        guard hasNextPage, !isReloading, !isLoadingMore, phase == .loaded,
              let index = items.firstIndex(where: { $0.id == anime.id }), index >= items.count - 6 else { return }
        isLoadingMore = true
        let requestID = UUID()
        loadMoreRequestID = requestID
        var q = query.withPage(page + 1)
        if !q.trimmedSearch.isEmpty && q.sort == .popularity { q.sort = .relevance }
        let searchQuery = q
        loadMoreTask = Task { [weak self] in
            defer {
                // An old cancelled page must never clear a newer page's loading flag.
                if let self, self.loadMoreRequestID == requestID {
                    self.loadMoreRequestID = nil
                    self.loadMoreTask = nil
                    self.isLoadingMore = false
                }
            }
            do {
                let next = try await catalog.search(searchQuery)
                guard !Task.isCancelled, let self, self.loadMoreRequestID == requestID else { return }
                var known = Set(self.items.map(\.id))
                let newItems = next.items.filter { known.insert($0.id).inserted }
                self.items.append(contentsOf: newItems)
                self.remember(newItems)
                self.page = next.page
                self.hasNextPage = next.hasNextPage
            } catch {
                // Ошибку подгрузки не показываем на весь экран — можно прокрутить ещё раз.
            }
        }
    }

    func cancelRequests() {
        runner.cancel()
        reloadRequestID = nil
        isReloading = false
        loadMoreRequestID = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        isSearchingLive = false
        if items.isEmpty, phase == .loading { phase = .idle }
        // needsReload remains true when a pending new query was interrupted.
    }

    func loadGenres(catalog: CatalogService) async {
        guard genres.isEmpty else { return }
        genres = (try? await catalog.genres()) ?? []
    }

    /// Загружает локально сохранённые тайтлы для мгновенного поиска по мере ввода.
    func loadCachedAnime(cache: MetadataCache) async {
        guard knownAnimePool.isEmpty else { return }
        guard let data = await cache.data(for: "russian-name-index"), !Task.isCancelled else { return }
        // A large name index used to be decoded on MainActor during screen presentation.
        let cached = await Task.detached(priority: .utility) {
            try? JSONDecoder().decode([Anime].self, from: data)
        }.value
        guard !Task.isCancelled, let cached else { return }
        remember(cached)
    }

    func resetFilters() {
        query.genres = []
        query.year = nil
        query.status = nil
        query.formats = []
        query.season = nil
    }

    private func remember(_ newItems: [Anime]) {
        var seen = Set(knownAnimePool.map(\.id))
        for anime in newItems where seen.insert(anime.id).inserted {
            knownAnimePool.append(anime)
        }
        if knownAnimePool.count > 1000 {
            knownAnimePool.removeFirst(knownAnimePool.count - 1000)
        }
    }
}
