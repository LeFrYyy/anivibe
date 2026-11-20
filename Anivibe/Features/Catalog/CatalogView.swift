import SwiftUI
import AnivibeCore

struct CatalogView: View {
    /// ID тайтла для перехода из deep link (виджет). Каталог открывает его и сбрасывает.
    var openAnimeID: Binding<Int?> = .constant(nil)
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = CatalogViewModel()
    @State private var showFilters = false
    @State private var path = NavigationPath()
    @State private var randomPick: Anime?
    @State private var scrollAnchor = UUID()
    @State private var showBackToTop = false

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 180), spacing: Theme.Spacing.m, alignment: .top)]
    /// Имя координатного пространства списка — для отслеживания прокрутки (iOS 17).
    private let scrollSpace = "catalog.scroll"

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            content
                .animation(AppMotion.fade(reduceMotion: reduceMotion), value: model.phase)
                .screenBackground()
                .navigationTitle("Каталог")
                .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
                .navigationDestination(for: DeepLinkedAnime.self) { AnimeDetailsView(snapshot: AnimeSnapshot(id: $0.id, title: "Загрузка…")) }
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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            randomPick = model.randomTitle()
                        } label: {
                            Image(systemName: "shuffle")
                        }
                        .disabled(model.items.isEmpty && model.genres.isEmpty)
                        .accessibilityLabel("Случайный тайтл")
                    }
                }
                .sheet(item: $randomPick) { anime in
                    RandomPickSheet(anime: anime,
                                    reroll: { randomPick = model.randomTitle() },
                                    open: {
                                        randomPick = nil
                                        path.append(anime)
                                    })
                    .presentationDetents([.height(360)])
                }
                .sheet(isPresented: $showFilters) {
                    FilterSheet(query: $model.query, genres: model.genres) {
                        model.reload(catalog: env.catalog)
                    }
                    .presentationDetents([.medium, .large])
                }
                .task {
                    if model.phase == .idle || model.needsReload { model.reload(catalog: env.catalog) }
                    await model.loadGenres(catalog: env.catalog)
                    await model.loadCachedAnime(cache: env.cache)
                    openDeepLinkedAnime()
                }
                .onChange(of: openAnimeID.wrappedValue) { _, _ in
                    openDeepLinkedAnime()
                }
        }
        .onDisappear { model.cancelRequests() }
    }

    /// Открывает тайтл из deep link, если он ожидает, и сбрасывает запрос.
    private func openDeepLinkedAnime() {
        guard let id = openAnimeID.wrappedValue else { return }
        // Виджет знает только ID. AnimeDetailsView(snapshot:) сам догрузит детали,
        // поэтому заголовок-заглушка виден лишь до окончания загрузки.
        path.append(DeepLinkedAnime(id: id))
        openAnimeID.wrappedValue = nil
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
                // Скелетон вместо спиннера: повторяет сетку постеров, поэтому
                // выдача «проявляется» на месте, без скачка раскладки.
                ScrollView {
                    PosterGridSkeleton(columns: columns, count: 12)
                }
                .scrollDisabled(true)
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
        ScrollViewReader { proxy in
            ScrollView {
                // Якорь начала списка: к нему возвращает кнопка «наверх», и по его
                // видимости решается, показывать ли кнопку (iOS 17, без scroll APIs 18).
                Color.clear
                    .frame(height: 0)
                    .id(scrollAnchor)
                    .background {
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: geo.frame(in: .named(scrollSpace)).minY, initial: true) { _, minY in
                                    withAnimation(AppMotion.fade(reduceMotion: reduceMotion)) {
                                        showBackToTop = minY < -240
                                    }
                                }
                        }
                    }
                if model.query.hasActiveFilters {
                    ActiveFiltersSummary(query: model.query).padding(.horizontal, Theme.Spacing.l)
                }
                LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                    ForEach(model.items) { anime in
                        NavigationLink(value: anime) { PosterCard(anime: anime) }
                            .buttonStyle(PosterPressStyle())
                            .folderMenu(anime.snapshot, preview: true)
                            .onAppear { model.loadMoreIfNeeded(current: anime, catalog: env.catalog) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                if model.isLoadingMore {
                    ProgressView().padding()
                }
            }
            .coordinateSpace(name: scrollSpace)
            .scrollDismissesKeyboard(.immediately)
            .refreshable {
                model.reload(catalog: env.catalog)
                await model.awaitReload()
            }
            .overlay(alignment: .bottomTrailing) {
                if showBackToTop {
                    BackToTopButton {
                        withAnimation(AppMotion.panel(reduceMotion: reduceMotion)) {
                            proxy.scrollTo(scrollAnchor, anchor: .top)
                        }
                    }
                    .padding(Theme.Spacing.l)
                    .transition(AppMotion.panelTransition(reduceMotion: reduceMotion))
                }
            }
        }
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
                        // Токен темы, а не белая линия: на светлом фоне она пропадала.
                        .strokeBorder(Theme.separator.opacity(0.7), lineWidth: 0.5)
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
            if let years = query.yearRange {
                Chip(text: years.lowerBound == years.upperBound ? String(years.lowerBound) : "\(years.lowerBound)–\(years.upperBound)", tint: Theme.accent)
            } else if let from = query.yearFrom {
                Chip(text: "от \(from)", tint: Theme.accent)
            } else if let to = query.yearTo {
                Chip(text: "до \(to)", tint: Theme.accent)
            }
            if let s = query.status { Chip(text: s.localizedName, tint: Theme.accent) }
            ForEach(query.formats.sorted { $0.rawValue < $1.rawValue }, id: \.self) { Chip(text: $0.localizedName, tint: Theme.accent) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Маршрут deep link из виджета: известен только ID тайтла.
/// `AnimeDetailsView(snapshot:)` догружает детали по этому ID.
struct DeepLinkedAnime: Hashable {
    let id: Int
}
