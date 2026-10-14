import SwiftUI
import AnivibeCore

struct CatalogView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismissSearch) private var dismissSearch
    @State private var model = CatalogViewModel()
    @State private var showFilters = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: Theme.Spacing.m, alignment: .top)]

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            content
                .animation(.easeInOut(duration: 0.25), value: model.phase)
                .screenBackground()
                .navigationTitle("Каталог")
                .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
                .searchable(text: $model.query.search, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "Название, в т.ч. альтернативное")
                .onChange(of: model.query.search) { _, _ in
                    model.handleSearchTextChange(catalog: env.catalog)
                }
                .onSubmit(of: .search) {
                    model.submitSearch(catalog: env.catalog)
                }
                .searchSuggestions {
                    if !model.query.trimmedSearch.isEmpty {
                        suggestionsContent
                    }
                }
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
                    await model.loadCachedAnime(cache: env.cache)
                }
        }
    }

    @ViewBuilder private var suggestionsContent: some View {
        if model.isSearchingLive && model.suggestions.isEmpty {
            HStack(spacing: Theme.Spacing.m) {
                ProgressView()
                    .controlSize(.small)
                Text("Ищем «\(model.query.trimmedSearch)»…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 4)
        } else if model.suggestions.isEmpty && !model.isSearchingLive {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                Text("Ничего не найдено по запросу «\(model.query.trimmedSearch)»")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 4)
        } else {
            if model.isSearchingLive {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Обновляем варианты…")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 2)
            }

            ForEach(model.suggestions.prefix(8)) { anime in
                NavigationLink(value: anime) {
                    SuggestionRow(anime: anime)
                }
                .buttonStyle(PosterPressStyle())
                .searchCompletion(anime.title.preferred)
            }

            Button {
                dismissSearch()
                model.submitSearch(catalog: env.catalog)
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.accent)
                    Text("Все результаты в каталоге («\(model.query.trimmedSearch)»)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .loading:
            if model.items.isEmpty {
                LoadingStateView(message: model.query.trimmedSearch.isEmpty ? "Загружаем каталог…" : "Ищем «\(model.query.trimmedSearch)»…")
                    .frame(maxHeight: .infinity)
            } else {
                grid
            }
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
                        .buttonStyle(PosterPressStyle())
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

private struct SuggestionRow: View {
    let anime: Anime

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            PosterImage(url: anime.coverURL, placeholderColorHex: anime.coverColorHex, cornerRadius: 6)
                .frame(width: 40, height: 40 / Theme.posterAspect)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(anime.title.preferred)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                if let secondary = secondaryTitle, secondary != anime.title.preferred {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let score = anime.averageScore {
                        Text(Anime.scoreText(score))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    let meta = anime.metaLine
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .folderMenu(anime.snapshot)
    }

    private var secondaryTitle: String? {
        if anime.title.russian != nil {
            return anime.title.romaji ?? anime.title.english
        } else {
            return anime.title.english ?? anime.title.romaji
        }
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
