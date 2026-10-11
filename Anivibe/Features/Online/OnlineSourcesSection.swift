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

    var voices: [KodikVoiceOption] { match?.voices ?? [] }

    var selectedVoice: KodikVoiceOption? {
        if let selectedVoiceID, let voice = voices.first(where: { $0.id == selectedVoiceID }) { return voice }
        return voices.first
    }

    var availableSeasons: [Int] {
        guard let voice = selectedVoice else { return [] }
        return Set(voice.episodes.map(\.season)).sorted()
    }

    var visibleEpisodes: [KodikEpisode] {
        guard let voice = selectedVoice else { return [] }
        let inSeason = voice.episodes(season: selectedSeason)
        return inSeason.isEmpty ? voice.episodes : inSeason
    }

    func load(anime: Anime, client: KodikClient) async {
        phase = .loading
        do {
            if let match = try await client.search(titles: anime.allTitles, year: anime.year) {
                self.match = match
                selectedVoiceID = match.voices.first?.id
                selectedSeason = match.voices.first?.seasons.first ?? 1
                phase = .loaded
            } else {
                phase = .notFound
            }
        } catch let error as APIError {
            phase = .failed(error.userMessage)
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}

/// Раздел «Смотреть с озвучкой» на странице аниме: поиск по Kodik,
/// выбор озвучки и серии, воспроизведение во встроенном веб-плеере сервиса.
struct OnlineSourcesSection: View {
    let anime: Anime
    let client: KodikClient

    @State private var model = KodikOnlineViewModel()
    @State private var webPlayback: WebPlaybackRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Смотреть с русской озвучкой")
            Text("Видео, озвучки и плеер предоставлены Kodik. Просмотр идёт во встроенном веб-плеере сервиса: выбор серии, озвучки и качества — внутри него; реклама в плеере — со стороны Kodik.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.l)

            content
        }
        .fullScreenCover(item: $webPlayback) { request in
            KodikPlayerScreen(request: request)
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
                        webPlayback = WebPlaybackRequest(url: voice.playerURL, title: anime.title.preferred,
                                                         subtitle: voice.translation.title)
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
                    model.selectedVoiceID = voice.id
                    model.selectedSeason = voice.seasons.first ?? 1
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
                    webPlayback = WebPlaybackRequest(url: episode.playerURL,
                                                     title: "\(anime.title.preferred) — серия \(episode.number)",
                                                     subtitle: model.selectedVoice?.translation.title)
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
