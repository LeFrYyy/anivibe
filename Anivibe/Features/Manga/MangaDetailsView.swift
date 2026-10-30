import SwiftUI
import AnivibeCore

/// Карточка манги по референсу: затемнённая размытая обложка на фоне, рейтинг Shikimori,
/// акцентная кнопка чтения, статус чтения с прогрессом, «О сюжете», теги, главы.
struct MangaDetailsView: View {
    let link: MangaLink
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = MangaDetailsViewModel()
    @State private var readerChapter: MangaChapter?
    @State private var descriptionExpanded = false

    init(link: MangaLink) { self.link = link }

    private var coverURL: URL? { model.manga?.coverURL ?? link.coverURL }
    private var readCount: Int { env.mangaLibrary.readCount(for: link.id) }
    private var totalChapters: Int? {
        if !model.chapters.isEmpty { return model.chapters.count }
        return model.manga?.chapters
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.ignoresSafeArea()
            backdrop
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    readButton
                    statusCard
                    if let error = model.error {
                        ErrorStateView(message: error) { Task { await reload() } }
                    } else if model.manga != nil {
                        synopsisSection
                        tagsSection
                        adaptationSection
                        chaptersSection
                    }
                }
                .padding(.vertical, Theme.Spacing.l)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let url = shikimoriURL {
                        Button { openURL(url) } label: { Label("Открыть на Shikimori", systemImage: "safari") }
                    }
                    if !model.chapters.isEmpty {
                        Button { env.mangaLibrary.markAllRead(link.id, chapters: model.chapters) } label: {
                            Label("Отметить всё прочитанным", systemImage: "checkmark.circle")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Theme.textPrimary).padding(6)
                }
            }
        }
        .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
        .navigationDestination(item: $readerChapter) { MangaReaderView(chapter: $0, allChapters: model.chapters, mangaID: link.id) }
        .task(id: link.id) { await reload() }
    }

    private func reload() async {
        await model.load(id: link.id, service: env.manga, catalog: env.catalog)
    }

    // MARK: - Фон: размытая затемнённая обложка с переходом в фон страницы

    private var backdrop: some View {
        VStack(spacing: 0) {
            PosterImage(url: coverURL)
                .frame(maxWidth: .infinity)
                .frame(height: 430)
                .saturation(0.55)
                .blur(radius: 45)
                .overlay(LinearGradient(colors: [
                    Theme.background.opacity(0.55),
                    Theme.background.opacity(0.88),
                    Theme.background
                ], startPoint: .top, endPoint: .bottom))
                .clipped()
                .ignoresSafeArea(edges: .top)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Шапка: обложка, название, мета, рейтинг

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            PosterImage(url: coverURL)
                .aspectRatio(Theme.posterAspect, contentMode: .fit)
                .frame(width: 136)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.manga?.title.preferred ?? link.title ?? "Загрузка…")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                if let original = model.manga?.title.romaji?.nilIfBlank ?? model.manga?.title.english?.nilIfBlank {
                    Text(original)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                if let manga = model.manga {
                    Text([manga.format?.localizedName, manga.year.map(String.init), manga.status?.localizedName]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let manga = model.manga, let score = manga.score {
                    ratingRow(score: score, votes: manga.scoreVotes)
                }
                if let manga = model.manga, manga.title.isRussianAutomatic {
                    Text("Название переведено автоматически")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    /// Рейтинг Shikimori: звезда, оценка, число голосов; тап открывает страницу на Shikimori.
    private func ratingRow(score: Double, votes: Int?) -> some View {
        Button {
            if let url = shikimoriURL { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").foregroundStyle(Theme.mangaAccent)
                    Text(String(format: "%.2f", score)).font(.headline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                    if let votes, votes > 0 {
                        Text("(\(votes.formatted(.number)))").font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                Text("Shikimori").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var shikimoriURL: URL? { URL(string: "https://shikimori.one/mangas/\(link.id)") }

    // MARK: - Кнопка чтения и статус

    private var readButtonTitle: String {
        switch env.mangaLibrary.status(for: link.id) {
        case .completed: return "Прочитано"
        case .reading where readCount > 0: return "Продолжить чтение"
        default: return readCount > 0 ? "Продолжить чтение" : "Начать читать"
        }
    }

    private var readButton: some View {
        Button {
            if let chapter = env.mangaLibrary.resumeChapter(link.id, in: model.chapters) {
                readerChapter = chapter
            }
        } label: {
            HStack(spacing: 10) {
                if model.chaptersState == .loading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(readButtonTitle).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(.white)
            .background(Theme.mangaAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PosterPressStyle())
        .disabled(model.chapters.isEmpty)
        .opacity(model.chapters.isEmpty && model.chaptersState == .loaded ? 0.6 : 1)
        .padding(.horizontal, Theme.Spacing.l)
    }

    /// Блок статуса чтения: меню статуса слева, прогресс глав справа.
    private var statusCard: some View {
        HStack(spacing: Theme.Spacing.m) {
            Menu {
                Button { env.mangaLibrary.setStatus(nil, for: link.id) } label: {
                    if env.mangaLibrary.status(for: link.id) == nil {
                        Label("Не читал", systemImage: "checkmark")
                    } else {
                        Text("Не читал")
                    }
                }
                ForEach(MangaLibraryStore.ReadStatus.allCases, id: \.self) { status in
                    Button { env.mangaLibrary.setStatus(status, for: link.id) } label: {
                        if env.mangaLibrary.status(for: link.id) == status {
                            Label(status.localizedName, systemImage: "checkmark")
                        } else {
                            Text(status.localizedName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book").foregroundStyle(Theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Статус").font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(env.mangaLibrary.status(for: link.id)?.localizedName ?? (readCount > 0 ? "Начал читать" : "Не читал"))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    }
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
                .contentShape(Rectangle())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text("Глава \(readCount) / \(totalChapters.map(String.init) ?? "?")")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                ProgressView(value: Double(readCount), total: Double(max(totalChapters ?? 0, 1)))
                    .tint(Theme.mangaAccent)
                    .frame(width: 110)
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.surfaceElevated.opacity(0.75), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .padding(.horizontal, Theme.Spacing.l)
    }

    // MARK: - Сюжет и теги

    private func sectionTitle(_ text: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.mangaAccent)
                .frame(width: 4, height: 18)
            Text(text).font(.headline)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var synopsisSection: some View {
        if let synopsis = model.manga?.synopsis?.nilIfBlank {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                sectionTitle("О сюжете")
                VStack(alignment: .leading, spacing: 8) {
                    Text(synopsis)
                        .font(.subheadline)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(descriptionExpanded ? nil : 5)
                    Button(descriptionExpanded ? "Свернуть" : "Показать полностью") {
                        withAnimation(AppMotion.selection(reduceMotion: reduceMotion)) { descriptionExpanded.toggle() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.mangaAccent)
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }

    @ViewBuilder private var tagsSection: some View {
        if let manga = model.manga, !manga.genres.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                sectionTitle("Теги")
                FlowLayout(spacing: 8) {
                    ForEach(manga.genres, id: \.self) { genre in
                        Text(genre)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }

    // MARK: - Адаптация и главы

    @ViewBuilder private var adaptationSection: some View {
        if !model.adaptations.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                sectionTitle("Аниме-адаптация")
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
            sectionTitle("Главы на русском")
            switch model.chaptersState {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, Theme.Spacing.l)
            case .empty:
                Text("Главы с русским переводом не найдены (MangaLib и MangaDex).")
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
        let read = env.mangaLibrary.isRead(link.id, chapterID: chapter.id)
        let label = HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(read ? Theme.textSecondary : Theme.textPrimary)
                Text([chapter.volumeText, chapter.group, chapter.pageCount > 0 ? "\(chapter.pageCount) стр." : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if read {
                Image(systemName: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(Theme.mangaAccent)
            } else {
                Image(systemName: chapter.externalURL == nil ? "book.pages" : "safari")
                    .foregroundStyle(Theme.textSecondary)
            }
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
