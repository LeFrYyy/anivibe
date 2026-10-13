import SwiftUI
import AnivibeCore

struct CatalogView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = CatalogViewModel()
    @State private var showFilters = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: Theme.Spacing.m, alignment: .top)]

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            content
                .screenBackground()
                .navigationTitle("Каталог")
                .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
                .searchable(text: $model.query.search, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Название, в т.ч. альтернативное")
                .onChange(of: model.query.search) { _, _ in model.reload(catalog: env.catalog, debounce: 0.4) }
                .onSubmit(of: .search) { model.reload(catalog: env.catalog) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showFilters = true } label: {
                            Image(systemName: model.query.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel("Фильтры и сортировка")
                    }
                }
                .sheet(isPresented: $showFilters) {
                    FilterSheet(query: $model.query, genres: model.genres) {
                        model.reload(catalog: env.catalog)
                    }
                    .presentationDetents([.medium, .large])
                }
                .task {
                    if model.phase == .idle { model.reload(catalog: env.catalog) }
                    await model.loadGenres(catalog: env.catalog)
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            if model.items.isEmpty { LoadingStateView(message: "Загружаем каталог…").frame(maxHeight: .infinity) } else { grid }
        case .empty:
            EmptyStateView(systemImage: "magnifyingglass", title: "Ничего не найдено",
                           message: "Попробуйте другое название или ослабьте фильтры.",
                           actionTitle: model.query.hasActiveFilters ? "Сбросить фильтры" : nil) {
                model.resetFilters()
                model.reload(catalog: env.catalog)
            }
        case .failed(let message):
            ErrorStateView(message: message) { model.reload(catalog: env.catalog) }
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            if model.query.hasActiveFilters {
                ActiveFiltersSummary(query: model.query).padding(.horizontal, Theme.Spacing.l)
            }
            LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                ForEach(model.items) { anime in
                    NavigationLink(value: anime) { PosterCard(anime: anime) }
                        .buttonStyle(.plain)
                        .folderMenu(anime.snapshot)
                        .onAppear { model.loadMoreIfNeeded(current: anime, catalog: env.catalog) }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)
            if model.isLoadingMore {
                ProgressView().padding()
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

private struct ActiveFiltersSummary: View {
    let query: CatalogQuery
    var body: some View {
        FlowLayout {
            ForEach(query.genres.sorted(), id: \.self) { Chip(text: CatalogLocalization.genre($0), tint: Theme.accent) }
            if let y = query.year { Chip(text: String(y), tint: Theme.accent) }
            if let s = query.status { Chip(text: s.localizedName, tint: Theme.accent) }
            ForEach(query.formats.sorted { $0.rawValue < $1.rawValue }, id: \.self) { Chip(text: $0.localizedName, tint: Theme.accent) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
