import SwiftUI
import AnivibeCore

/// Состояние загрузки раздела «Озвучки онлайн».
@Observable
@MainActor
final class KodikOnlineViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case notFound
        case failed(String)
        case loaded
    }

    private(set) var phase: Phase = .idle
    private(set) var match: KodikMatch?
    var selectedVoiceID: KodikVoiceOption.ID?
    var selectedSeason: Int = 1
    @ObservationIgnored private var lookup: Task<KodikMatch?, Error>?
    @ObservationIgnored private var lookupID = UUID()
    @ObservationIgnored private var animeID: Int?

    /// В том же порядке, что использует плеер по умолчанию.
    var voices: [KodikVoiceOption] { KodikProvider.rankedVoices(match?.voices ?? []) }

    var selectedVoice: KodikVoiceOption? {
        if let selectedVoiceID, let voice = voices.first(where: { $0.id == selectedVoiceID }) { return voice }
        return voices.first
    }

    var availableSeasons: [Int] {
        guard let voice = selectedVoice else { return [] }
        let fromEpisodes = Set(voice.episodes.map(\.season)).sorted()
        return fromEpisodes.isEmpty ? voice.seasons : fromEpisodes
    }

    var visibleEpisodes: [KodikEpisode] {
        guard let voice = selectedVoice else { return [] }
        let inSeason = voice.episodes(season: selectedSeason)
        if !inSeason.isEmpty { return inSeason }
        if let firstSeason = availableSeasons.first {
            let firstInSeason = voice.episodes(season: firstSeason)
            if !firstInSeason.isEmpty { return firstInSeason }
        }
        return voice.episodes
    }

    func selectVoice(_ voice: KodikVoiceOption) {
        selectedVoiceID = voice.id
        // Запоминаем — кнопка «Смотреть» и плеер приложения возьмут эту же озвучку.
        UserDefaults.standard.set(voice.translation.title, forKey: KodikPreferences.voiceKey)
        let seasons = Set(voice.episodes.map(\.season)).sorted()
        if !seasons.isEmpty && !seasons.contains(selectedSeason) {
            selectedSeason = seasons.first(where: { $0 >= 1 }) ?? seasons.first ?? 1
        }
    }

    func load(anime: Anime, client: KodikClient) async {
        if animeID == anime.id, phase == .loaded { return }
        if animeID != anime.id {
            lookup?.cancel(); lookup = nil; lookupID = UUID()
            match = nil; selectedVoiceID = nil
        }
        animeID = anime.id
        let task: Task<KodikMatch?, Error>
        if let pending = lookup { task = pending }
        else {
            lookupID = UUID(); phase = .loading
            let created = Task<KodikMatch?, Error> {
                try await client.search(titles: anime.allTitles, year: anime.year, shikimoriID: anime.malID)
            }
            lookup = created; task = created
        }
        let request = lookupID
        defer { if lookupID == request, phase != .loading { lookup = nil } }
        do {
            let result = try await task.value
            guard !Task.isCancelled, lookupID == request, animeID == anime.id else { return }
            // Another waiter may already have applied it and user may have picked a voice.
            if phase == .loaded { return }
            if let result {
                match = result
                let ranked = KodikProvider.rankedVoices(result.voices)
                let saved = UserDefaults.standard.string(forKey: KodikPreferences.voiceKey)
                let firstVoice = ranked.first { $0.translation.title == saved } ?? ranked.first
                selectedVoiceID = firstVoice?.id
                let seasons = firstVoice.map { Set($0.episodes.map(\.season)).sorted() } ?? []
                selectedSeason = seasons.first(where: { $0 >= 1 }) ?? seasons.first ?? 1
                phase = .loaded
            } else { match = nil; phase = .notFound }
        } catch {
            guard lookupID == request, !Task.isCancelled else { return }
            if error is CancellationError || (error as? APIError) == .cancelled { phase = .idle }
            else if let error = error as? APIError { phase = .failed(error.userMessage) }
            else { phase = .failed("Не удалось загрузить озвучки Kodik.") }
        }
    }

}

/// Раздел «Смотреть с озвучкой» на странице аниме: поиск по Kodik,
/// выбор озвучки и серии, запуск единого плеера Anivibe с точной серией Kodik.
struct OnlineSourcesSection: View {
    let anime: Anime
    let client: KodikClient
    /// Общая модель со страницей аниме (её же использует выбор озвучки над кнопкой «Смотреть»).
    let model: KodikOnlineViewModel
    let playEpisode: (Episode, KodikVoiceOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Смотреть с русской озвучкой")
            Text("Видео и озвучки предоставлены Kodik. Видео открывается в плеере приложения: можно выбрать качество и скорость воспроизведения.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.l)

            content
        }

        .task {
            if model.phase == .idle {
                await model.load(anime: anime, client: client)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            Button {
                Task { await model.load(anime: anime, client: client) }
            } label: {
                Label("Найти озвучки", systemImage: "mic.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, Theme.Spacing.l)

        case .loading:
            HStack(spacing: Theme.Spacing.m) {
                ProgressView()
                Text("Ищем озвучки у Kodik…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.l)

        case .notFound:
            Text("Kodik не нашёл этот тайтл (по всем известным названиям).")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.l)

        case .failed(let message):
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button("Повторить") {
                    Task { await model.load(anime: anime, client: client) }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, Theme.Spacing.l)

        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder private var loadedContent: some View {
        if let match = model.match {
            if TitleMatcher.normalize(match.matchedTitle) != TitleMatcher.normalize(anime.title.preferred) {
                Text("Найдено у Kodik: «\(match.matchedTitle)»\(match.year.map { " (\($0))" } ?? ""). Проверьте, что это тот же тайтл.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryAccent)
                    .padding(.horizontal, Theme.Spacing.l)
            }

            voicePicker

            if let voice = model.selectedVoice {
                if voice.isSingleVideo {
                    Button {
                        if let episode = KodikProvider.sourceEpisodes(for: voice, animeID: anime.id).first {
                            playEpisode(episode, voice)
                        }
                    } label: {
                        Label("Смотреть" + (voice.quality.map { " · \($0)" } ?? ""), systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, Theme.Spacing.l)
                } else {
                    seasonPicker(voice: voice)
                    episodeList
                }
            }
        }
    }

    private var voicePicker: some View {
        Menu {
            ForEach(model.voices) { voice in
                Button {
                    model.selectVoice(voice)
                } label: {
                    let kind = voice.translation.isVoice ? "Озвучка" : (voice.translation.kind == .subtitles ? "Субтитры" : "Перевод")
                    if model.selectedVoice?.id == voice.id {
                        Label("\(voice.translation.title) — \(kind)", systemImage: "checkmark")
                    } else {
                        Text("\(voice.translation.title) — \(kind)")
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: model.selectedVoice?.translation.isVoice == true ? "mic" : "captions.bubble")
                Text(model.selectedVoice?.translation.title ?? "Выберите озвучку")
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.m)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .padding(.horizontal, Theme.Spacing.l)
        .accessibilityLabel("Выбор озвучки")
    }

    @ViewBuilder private func seasonPicker(voice: KodikVoiceOption) -> some View {
        let seasons = model.availableSeasons
        if seasons.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(seasons, id: \.self) { season in
                        Chip(text: "Сезон \(season)", tint: model.selectedSeason == season ? Theme.accent : Theme.textSecondary)
                            .onTapGesture { model.selectedSeason = season }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }

    private var episodeList: some View {
        let episodes = model.visibleEpisodes
        return LazyVStack(spacing: 0) {
            ForEach(episodes) { episode in
                Button {
                    if let voice = model.selectedVoice,
                       let exact = KodikProvider.sourceEpisodes(for: voice, animeID: anime.id).first(where: {
                           $0.sourceEpisode?.season == episode.season && $0.sourceEpisode?.number == episode.number
                       }) {
                        playEpisode(exact, voice)
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Text("\(episode.number)")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .frame(width: 36, height: 36)
                            .background(Theme.surfaceElevated, in: Circle())
                        Text(episode.title ?? "Серия \(episode.number)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "play.circle")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if episode.id != episodes.last?.id {
                    Divider().padding(.leading, Theme.Spacing.l)
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .padding(.horizontal, Theme.Spacing.l)
    }
}

/// Выбор озвучки прямо над кнопкой «Смотреть» — плеер включит выбранную.
struct KodikVoicePicker: View {
    let anime: Anime
    let client: KodikClient
    let model: KodikOnlineViewModel

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text("Ищем озвучки…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, Theme.Spacing.s)
            case .notFound:
                Label("У Kodik нет озвучек этого тайтла", systemImage: "mic.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed:
                Button {
                    Task { await model.load(anime: anime, client: client) }
                } label: {
                    Label("Не удалось загрузить озвучки — повторить", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .loaded:
                menu
            }
        }
        .task {
            if model.phase == .idle { await model.load(anime: anime, client: client) }
        }
    }

    private var menu: some View {
        Menu {
            ForEach(model.voices) { voice in
                Button {
                    model.selectVoice(voice)
                } label: {
                    let suffix = voice.translation.isVoice ? "" : " (субтитры)"
                    let count = voice.isSingleVideo ? "" : " · \(voice.episodes.count) сер."
                    if model.selectedVoice?.id == voice.id {
                        Label(voice.translation.title + suffix + count, systemImage: "checkmark")
                    } else {
                        Text(voice.translation.title + suffix + count)
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "mic.fill")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Источник: Kodik · озвучка")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(model.selectedVoice?.translation.title ?? "Выберите озвучку")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(model.voices.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        }
        .accessibilityLabel("Выбор озвучки")
    }
}
