import SwiftUI
import AnivibeCore

struct AnimeDetailsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(LibraryStore.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var model: AnimeDetailsViewModel
    @State private var playback: PlaybackRequest?
    @State private var descriptionExpanded = false
    @State private var showEpisodes = false
    @State private var showFolders = false
    @State private var showSources = false
    @State private var pendingPlayback: PlaybackRequest?
    @State private var kodikModel = KodikOnlineViewModel()

    init(anime: Anime) {
        _model = State(initialValue: AnimeDetailsViewModel(anime: anime))
    }

    init(snapshot: AnimeSnapshot) {
        let placeholder = Anime(id: snapshot.id, title: AnimeTitle(english: snapshot.title), coverURL: snapshot.coverURL,
                                episodeCount: snapshot.episodeCount)
        _model = State(initialValue: AnimeDetailsViewModel(anime: placeholder))
    }

    private var anime: Anime { model.anime }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    header
                    actions
                    switch model.phase {
                    case .loading:
                        LoadingStateView(message: "Загружаем информацию…")
                    case .failed(let message):
                        ErrorStateView(message: message) { Task { await model.retry(catalog: env.catalog) } }
                    case .loaded:
                        loadedContent
                    }
                }
                // Жёсткая страховка: контент страницы никогда не шире экрана,
                // иначе ScrollView начинает скроллиться горизонтально.
                .frame(width: proxy.size.width, alignment: .leading)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .sheet(isPresented: $showEpisodes, onDismiss: {
            if let request = pendingPlayback { playback = request; pendingPlayback = nil }
        }) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        if let voice = kodikModel.selectedVoice {
                            Text("Серии источника · " + voice.translation.title).font(.headline)
                            Text("Нумерация источника может отличаться от каталога. Здесь показаны его фактические элементы.").font(.footnote)
                            ForEach(KodikProvider.sourceEpisodes(for: voice, animeID: anime.id)) { episode in
                                Button(episode.displayTitle) { playSourceEpisode(episode, voice: voice) }
                            }
                        }
                        episodesSection
                    }.padding(.vertical)
                }.navigationTitle("Серии").toolbar { Button("Готово") { showEpisodes = false } }
            }
        }
        .sheet(isPresented: $showSources) {
            NavigationStack {
                if let kodik = env.kodik {
                    ScrollView { OnlineSourcesSection(anime: anime, client: kodik, model: kodikModel) }
                        .navigationTitle("Озвучки и серии")
                        .toolbar { Button("Готово") { showSources = false } }
                }
            }
        }
        .sheet(isPresented: $showFolders) { FolderSelectionSheet(anime: anime.snapshot) }
        .screenBackground()
        .navigationTitle(anime.title.preferred)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(catalog: env.catalog) }
        .fullScreenCover(item: $playback) { request in
            PlayerScreen(request: request)
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            PosterImage(url: anime.bannerURL ?? anime.coverURL, placeholderColorHex: anime.coverColorHex, cornerRadius: 0)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 200, maxHeight: 200)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom))
            HStack(alignment: .bottom, spacing: Theme.Spacing.l) {
                PosterImage(url: anime.coverURL, placeholderColorHex: anime.coverColorHex)
                    .frame(width: 110, height: 110 / Theme.posterAspect)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(anime.title.preferred)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    let alts = anime.allTitles.filter { $0 != anime.title.preferred }
                    if !alts.isEmpty {
                        Text(alts.prefix(3).joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(.bottom, Theme.Spacing.s)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .offset(y: 70)
        }
        .padding(.bottom, 70)
    }

    // MARK: Actions

    private var resume: ResumePoint? { library.resumePoint(for: anime) }
    private var episodes: [Episode] { model.episodeList?.episodes ?? [] }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.m) {
            // Озвучка выбирается до просмотра; ждём полные данные тайтла (нужен ID Shikimori).
            if case .loaded = model.phase, let kodik = env.kodik {
                KodikVoicePicker(anime: anime, client: kodik, model: kodikModel)
            }
            Button {
                if let key = resume?.sourceKey {
                    if let voice = kodikModel.selectedVoice,
                       let exact = KodikProvider.sourceEpisodes(for: voice, animeID: anime.id).first(where: { $0.sourceKey == key }) {
                        playSourceEpisode(exact, voice: voice)
                    } else { showEpisodes = true }
                } else { startPlayback(episode: resume?.episode ?? 1, position: resume?.position ?? 0) }
            } label: {
                Label(resumeTitle, systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)
            .disabled(episodes.isEmpty && kodikModel.selectedVoice == nil)

            HStack(spacing: Theme.Spacing.m) {
                Button {
                    Task { await library.toggleFavorite(anime.snapshot) }
                } label: {
                    Label(library.isFavorite(anime.id) ? "В избранном" : "В избранное",
                          systemImage: library.isFavorite(anime.id) ? "heart.fill" : "heart")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Menu {
                    ForEach(LibraryStatus.allCases, id: \.self) { status in
                        Button {
                            Task { await library.setStatus(status, for: anime.snapshot) }
                        } label: {
                            if library.status(of: anime.id) == status { Label(status.localizedName, systemImage: "checkmark") } else { Text(status.localizedName) }
                        }
                    }
                    if library.status(of: anime.id) != nil {
                        Divider()
                        Button("Убрать из списков", role: .destructive) {
                            Task { await library.setStatus(nil, for: anime.snapshot) }
                        }
                    }
                } label: {
                    Label(library.status(of: anime.id)?.localizedName ?? "В список",
                          systemImage: library.status(of: anime.id)?.systemImage ?? "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button { showFolders = true } label: { Label("Добавить в папку", systemImage: "folder.badge.plus") }.buttonStyle(.bordered)

            if library.status(of: anime.id) != .completed {
                Button {
                    Task { await library.markCompleted(anime.snapshot) }
                } label: {
                    Label("Отметить как просмотренное", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    private var resumeTitle: String {
        guard let resume else { return episodes.isEmpty ? "Нет серий" : "Смотреть" }
        if resume.sourceKey != nil { return "Продолжить серию источника" }
        return resume.isNextEpisode ? "Смотреть серию \(resume.episode)" : "Продолжить: серия \(resume.episode)"
    }

    private func startPlayback(episode: Int, position: Double) {
        guard !episodes.isEmpty else { return }
        let request = PlaybackRequest(anime: anime, episodes: episodes, episode: episode, startPosition: position)
        if showEpisodes { pendingPlayback = request; showEpisodes = false }
        else { playback = request }
    }

    private func playSourceEpisode(_ episode: Episode, voice: KodikVoiceOption) {
        let list = KodikProvider.sourceEpisodes(for: voice, animeID: anime.id)
        let progress = library.progress(anime.id, episode: episode.progressNumber, sourceKey: episode.sourceKey)
        let position = (progress?.isFinished ?? true) ? 0 : progress?.position ?? 0
        let request = PlaybackRequest(anime: anime, episodes: list, episode: episode.number, startPosition: position)
        if showEpisodes { pendingPlayback = request; showEpisodes = false }
        else { playback = request }
    }

    // MARK: Content

    @ViewBuilder private var loadedContent: some View {
        info
        if let synopsis = anime.synopsis {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(title: "Описание")
                Text(synopsis)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary.opacity(0.9))
                    .lineLimit(descriptionExpanded ? nil : 5)
                    .padding(.horizontal, Theme.Spacing.l)
                Button(descriptionExpanded ? "Свернуть" : "Читать полностью") {
                    withAnimation(.easeInOut(duration: 0.2)) { descriptionExpanded.toggle() }
                }
                .font(.subheadline)
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
        seasons
        Button("Выбрать серию") { showEpisodes = true }
            .buttonStyle(.bordered).padding(.horizontal, Theme.Spacing.l)
        // Все озвучки Kodik списком (основной просмотр — кнопкой «Смотреть»).
        if env.kodik != nil {
            Button("Озвучки и серии источника") { showSources = true }
                .buttonStyle(.bordered).padding(.horizontal, Theme.Spacing.l)
        }
        officialLinks
        if let recs = model.details?.recommendations, !recs.isEmpty {
            PosterRow(title: "Похожие", items: recs)
        }
        Text("Метаданные: AniList. Наличие тайтла в каталоге не означает наличие видео.")
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Spacing.l)
    }

    private var info: some View {
        FlowLayout(spacing: 6) {
            if let year = anime.year {
                Chip(text: anime.season.map { "\($0.localizedName) \(year)" } ?? String(year), systemImage: "calendar")
            }
            Chip(text: anime.status.localizedName, systemImage: "dot.radiowaves.left.and.right",
                 tint: anime.status == .releasing ? Theme.secondaryAccent : Theme.textSecondary)
            if let format = anime.format { Chip(text: format.localizedName, systemImage: "tv") }
            if let score = anime.averageScore { Chip(text: Anime.scoreText(score) + " AniList", tint: Theme.accent) }
            if let aired = anime.airedEpisodesText {
                Chip(text: "Вышло \(aired) эп." + (anime.episodeDurationMinutes.map { " по \($0) мин" } ?? ""),
                     systemImage: "list.number", tint: Theme.secondaryAccent)
            } else if let count = anime.episodeCount {
                Chip(text: "\(count) эп." + (anime.episodeDurationMinutes.map { " по \($0) мин" } ?? ""), systemImage: "list.number")
            }
            ForEach(model.details?.studios ?? [], id: \.self) { Chip(text: $0, systemImage: "building.2") }
            ForEach(anime.genres, id: \.self) { Chip(text: CatalogLocalization.genre($0)) }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    @ViewBuilder private var seasons: some View {
        if let d = model.details, !(d.otherSeasons.isEmpty && d.otherRelations.isEmpty) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Сезоны и связанное")
                Text("В каталоге каждый сезон — отдельный тайтл.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.Spacing.l)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Theme.Spacing.m) {
                        ForEach(d.otherSeasons + d.otherRelations) { rel in
                            NavigationLink(value: rel.anime) {
                                PosterCard(title: rel.anime.title.preferred, coverURL: rel.anime.coverURL,
                                           colorHex: rel.anime.coverColorHex, subtitle: rel.relation.localizedName)
                                .frame(width: 110)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                }
            }
        }
    }

    @ViewBuilder private var episodesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: anime.airedEpisodesText.map { "Серии · \($0)" } ?? "Серии")
            if let note = model.episodeList?.note {
                Label(note, systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, Theme.Spacing.l)
            }
            if episodes.isEmpty {
                Text("Список серий недоступен.").foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.Spacing.l)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(episodes) { ep in
                        EpisodeRow(episode: ep, progress: library.progress(anime.id, episode: ep.number)) {
                            let p = library.progress(anime.id, episode: ep.number)
                            startPlayback(episode: ep.number, position: (p?.isFinished ?? true) ? 0 : p?.position ?? 0)
                        } toggleWatched: { watched in
                            Task { await library.setEpisodeWatched(anime.snapshot, episode: ep.number, watched: watched) }
                        }
                        Divider().padding(.leading, Theme.Spacing.l)
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }

    @ViewBuilder private var officialLinks: some View {
        if let links = model.details?.externalStreamingLinks, !links.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Официальные площадки")
                Text("Откроются в браузере или приложении сервиса. Доступность зависит от региона и подписки.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.Spacing.l)
                FlowLayout(spacing: 8) {
                    ForEach(links) { link in
                        Button { openURL(link.url) } label: {
                            Label(link.site + (link.language.map { " (\($0))" } ?? ""), systemImage: "arrow.up.right.square")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let progress: WatchProgress?
    let play: () -> Void
    let toggleWatched: (Bool) -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack {
                    Circle().fill(Theme.surfaceElevated).frame(width: 36, height: 36)
                    if progress?.isFinished == true {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.success)
                    } else {
                        Text("\(episode.number)").font(.footnote.weight(.semibold).monospacedDigit())
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title ?? "Серия \(episode.number)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let progress, !progress.isFinished, progress.fraction > 0 {
                        HStack(spacing: 6) {
                            ProgressBar(value: progress.fraction).frame(width: 80, height: 3)
                            Text("\(progress.percent)%").font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "play.circle").font(.title3).foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if progress?.isFinished == true {
                Button("Отметить как непросмотренную") { toggleWatched(false) }
            } else {
                Button("Отметить как просмотренную") { toggleWatched(true) }
            }
        }
        .accessibilityLabel("Серия \(episode.number)\(episode.title.map { ", \($0)" } ?? "")\(progress?.isFinished == true ? ", просмотрено" : "")")
        .accessibilityHint("Воспроизвести")
    }
}
