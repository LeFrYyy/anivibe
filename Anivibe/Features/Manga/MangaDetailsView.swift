import SwiftUI
import AnivibeCore

/// Карточка манги: русское название, обложка, статус, тома/главы, аниме-адаптация и список глав.
struct MangaDetailsView: View {
    let link: MangaLink
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = MangaDetailsViewModel()
    @State private var readerChapter: MangaChapter?

    init(link: MangaLink) { self.link = link }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                if let error = model.error {
                    ErrorStateView(message: error) { Task { await reload() } }
                } else if model.manga != nil {
                    chips
                    synopsisSection
                    adaptationSection
                    chaptersSection
                }
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .screenBackground()
        .navigationTitle(model.manga?.title.preferred ?? link.title ?? "Манга")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
        .navigationDestination(item: $readerChapter) { MangaReaderView(chapter: $0, allChapters: model.chapters) }
        .task(id: link.id) { await reload() }
    }

    private func reload() async {
        await model.load(id: link.id, service: env.manga, catalog: env.catalog)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            PosterImage(url: model.manga?.coverURL ?? link.coverURL)
                .frame(width: 128)
                .aspectRatio(Theme.posterAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Манга")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.16), in: Capsule())
                    .foregroundStyle(Theme.accent)
                Text(model.manga?.title.preferred ?? link.title ?? "Загрузка…")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let original = model.manga?.title.romaji ?? model.manga?.title.english {
                    Text(original)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let manga = model.manga, manga.title.isRussianAutomatic {
                    Text("Название переведено автоматически")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityLabel("Русское название переведено автоматически, официального перевода нет")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                if let manga = model.manga {
                    if let format = manga.format { Chip(text: format.localizedName, systemImage: "book") }
                    if let status = manga.status { Chip(text: status.localizedName) }
                    if let score = manga.scoreText { Chip(text: score + " Shikimori", tint: Theme.accent) }
                    if let volumes = manga.volumes { Chip(text: "\(volumes) т.", systemImage: "books.vertical") }
                    if let chapters = manga.chapters { Chip(text: "\(chapters) гл.", systemImage: "doc.text") }
                    ForEach(manga.genres.prefix(6), id: \.self) { Chip(text: $0) }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
    }

    @ViewBuilder private var synopsisSection: some View {
        if let synopsis = model.manga?.synopsis?.nilIfBlank {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Описание")
                Text(synopsis)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }

    @ViewBuilder private var adaptationSection: some View {
        if !model.adaptations.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Аниме-адаптация")
                Text("По этой манге снято аниме — она здесь первоисточник.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(model.adaptations) { anime in
                            NavigationLink(value: anime) {
                                PosterCard(title: anime.title.preferred, coverURL: anime.coverURL,
                                           colorHex: anime.coverColorHex, subtitle: anime.metaLine, badge: "Аниме")
                                .frame(width: 110)
                            }
                            .buttonStyle(PosterPressStyle())
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }

    @ViewBuilder private var chaptersSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Главы на русском")
            switch model.chaptersState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.l)
            case .empty:
                Text("Главы с русским переводом пока не найдены на MangaDex.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.l)
            case .failed:
                ErrorStateView(message: "Не удалось загрузить главы.") {
                    Task { await model.loadChapters(service: env.manga) }
                }
            case .loaded:
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.chapters.enumerated()), id: \.element.id) { index, chapter in
                        chapterRow(chapter, index: index)
                    }
                }
            }
        }
    }

    @ViewBuilder private func chapterRow(_ chapter: MangaChapter, index: Int) -> some View {
        let label = HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text([chapter.volumeText, chapter.group, chapter.pageCount > 0 ? "\(chapter.pageCount) стр." : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: chapter.externalURL == nil ? "book.pages" : "safari")
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        if let external = chapter.externalURL {
            Link(destination: external) { label }
        } else {
            Button { readerChapter = chapter } label: { label }
                .buttonStyle(.plain)
        }
        if index < model.chapters.count - 1 {
            Divider().padding(.leading, Theme.Spacing.l)
        }
    }
}
