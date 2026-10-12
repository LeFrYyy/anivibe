import SwiftUI
import AnivibeCore

struct HomeView: View {
    let openCatalog: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(LibraryStore.self) private var library
    @State private var model = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    if env.catalog.isDemo {
                        DemoBanner()
                    }
                    continueSection
                    recentEpisodesSection
                    feedSections
                    favoritesSection
                    catalogShortcut
                }
                .padding(.vertical, Theme.Spacing.l)
            }
            .screenBackground()
            .navigationTitle("Anivibe")
            .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
            .navigationDestination(for: AnimeSnapshot.self) { AnimeDetailsView(snapshot: $0) }
            .refreshable {
                await model.load(catalog: env.catalog, force: true)
                await model.loadRecentEpisodes(catalog: env.catalog)
            }
            .task { await model.load(catalog: env.catalog) }
            .task { await model.loadRecentEpisodes(catalog: env.catalog) }
            .task(id: library.continueWatching.first?.anime.id) {
                await model.loadRecommendations(catalog: env.catalog, basedOn: library.continueWatching.first)
            }
        }
    }

    @ViewBuilder private var continueSection: some View {
        if !library.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Продолжить просмотр")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(library.continueWatching) { item in
                            NavigationLink(value: item.anime) {
                                PosterCard(title: item.anime.title, coverURL: item.anime.coverURL,
                                           subtitle: item.resume.isNextEpisode ? "Далее: серия \(item.resume.episode)" : "Серия \(item.resume.episode) · \(Int(item.resume.fraction * 100))%",
                                           progress: item.resume.isNextEpisode ? nil : item.resume.fraction)
                                .frame(width: 130)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }

    @ViewBuilder private var recentEpisodesSection: some View {
        if !model.recentEpisodes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    SectionHeader(title: "Недавно вышедшие")
                    Spacer()
                    NavigationLink {
                        RecentEpisodesView(items: model.recentEpisodes)
                    } label: {
                        Text("Все").font(.subheadline.weight(.medium))
                    }
                    .padding(.trailing, Theme.Spacing.l)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(model.recentEpisodes.prefix(20)) { item in
                            NavigationLink(value: item.anime) {
                                PosterCard(title: item.anime.title.preferred, coverURL: item.anime.coverURL,
                                           colorHex: item.anime.coverColorHex,
                                           subtitle: "Серия \(item.episode) · \(RecentEpisodesView.relative(item.airedAt))")
                                    .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }

    @ViewBuilder private var feedSections: some View {
        switch model.state {
        case .idle, .loading:
            ForEach(["Популярное", "Новинки сезона"], id: \.self) { title in
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: title)
                    PosterRowSkeleton()
                }
            }
        case .failed(let message):
            ErrorStateView(message: message) { Task { await model.load(catalog: env.catalog, force: true) } }
        case .loaded(let feed):
            PosterRow(title: "Популярное", items: feed.popular)
            PosterRow(title: "Новинки · \(feed.seasonLabel)", items: feed.seasonal)
            if !model.recommendations.isEmpty, let basis = model.recommendationsBasis {
                PosterRow(title: "Рекомендации", subtitle: "Похоже на «\(basis)»", items: model.recommendations)
            } else {
                PosterRow(title: "Рекомендации", subtitle: "Сейчас в тренде", items: feed.trending)
            }
            PosterRow(title: "Недавно добавленные", items: feed.recentlyAdded)
        }
    }

    @ViewBuilder private var favoritesSection: some View {
        let favorites = library.snapshot.favorites
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Избранное")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(favorites) { entry in
                            NavigationLink(value: entry.anime) {
                                PosterCard(title: entry.anime.title, coverURL: entry.anime.coverURL).frame(width: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }

    private var catalogShortcut: some View {
        Button(action: openCatalog) {
            HStack {
                Image(systemName: "square.grid.2x2")
                Text("Открыть каталог").fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Spacing.l)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Spacing.l)
    }
}

struct PosterRow: View {
    let title: String
    var subtitle: String?
    let items: [Anime]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionHeader(title: title)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.Spacing.l)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(items) { anime in
                            NavigationLink(value: anime) {
                                PosterCard(anime: anime).frame(width: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Демо-каталог: вымышленные данные режима разработки", systemImage: "hammer")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.secondaryAccent)
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .padding(.horizontal, Theme.Spacing.l)
    }
}

/// Полный список недавно вышедших серий.
struct RecentEpisodesView: View {
    let items: [AiredEpisode]

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        List(items) { item in
            NavigationLink(value: item.anime) {
                HStack(spacing: Theme.Spacing.m) {
                    PosterImage(url: item.anime.coverURL, placeholderColorHex: item.anime.coverColorHex)
                        .frame(width: 50, height: 50 / Theme.posterAspect)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.anime.title.preferred)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                        Text("Серия \(item.episode)")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                        Text(Self.relative(item.airedAt))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Недавно вышедшие")
        .navigationBarTitleDisplayMode(.inline)
    }
}
