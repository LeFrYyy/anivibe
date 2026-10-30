import SwiftUI
import AnivibeCore

/// Каталог манги: популярное + поиск (Shikimori + MangaDex). Экспериментальная функция.
struct MangaCatalogView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = MangaCatalogViewModel()
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 105, maximum: 150), spacing: Theme.Spacing.m)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Манга на русском: метаданные — Shikimori, главы — MangaDex.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Spacing.l)
                    grid
                }
                .padding(.vertical, Theme.Spacing.l)
            }
            .screenBackground()
            .navigationTitle("Манга")
            .searchable(text: $searchText, placement: .navigationBarDrawer, prompt: "Название манги")
            .task(id: searchText) { await model.search(text: searchText, service: env.manga) }
            .task { await model.load(service: env.manga) }
            .navigationDestination(for: MangaLink.self) { MangaDetailsView(link: $0) }
            .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
        }
    }

    @ViewBuilder private var grid: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if model.searching && model.searchResults.isEmpty {
                PosterRowSkeleton().padding(.top, Theme.Spacing.m)
            } else if model.searchResults.isEmpty {
                ContentUnavailableView("Ничего не найдено", systemImage: "magnifyingglass",
                                       description: Text("Попробуйте название на русском, английском или ромадзи."))
                    .padding(.top, 40)
            } else {
                mangaGrid(model.searchResults)
            }
        } else {
            switch model.feed {
            case .idle, .loading:
                PosterRowSkeleton().padding(.top, Theme.Spacing.m)
            case .failed(let message):
                ErrorStateView(message: message) { Task { await model.load(service: env.manga, force: true) } }
            case .loaded(let items):
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: "Популярная манга")
                    mangaGrid(items)
                }
            }
        }
    }

    private func mangaGrid(_ items: [Manga]) -> some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
            ForEach(items) { manga in
                NavigationLink(value: MangaLink(manga)) {
                    PosterCard(title: manga.title.preferred, coverURL: manga.coverURL,
                               subtitle: manga.metaLine, badge: "Манга")
                }
                .buttonStyle(PosterPressStyle())
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }
}
