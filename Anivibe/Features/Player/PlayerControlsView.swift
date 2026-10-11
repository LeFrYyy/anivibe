import SwiftUI
import AnivibeCore

struct PlayerControlsView: View {
    @Bindable var model: PlayerViewModel
    let pip: PictureInPictureModel
    let close: () -> Void
    let showSources: () -> Void
    let showEpisodes: () -> Void
    let interacted: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            if model.phase == .ready { centerControls }
            Spacer()
            if model.phase == .ready { bottomBar }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .background {
            LinearGradient(colors: [.black.opacity(0.6), .clear, .clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Top

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Button(action: close) {
                    Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Закрыть плеер")
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.anime.title.preferred).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(model.currentEpisode?.displayTitle ?? "Серия \(model.episodeNumber)")
                        .font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                }
                Spacer()
                if pip.isSupported && model.phase == .ready {
                    Button(action: pip.toggle) {
                        Image(systemName: pip.isActive ? "pip.exit" : "pip.enter").frame(width: 44, height: 44)
                    }
                    .disabled(!pip.isPossible)
                    .accessibilityLabel("Картинка в картинке")
                }
                Button { OrientationHelper.toggle() } label: {
                    Image(systemName: "rotate.right").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Повернуть экран")
            }
            if let source = model.source {
                HStack(spacing: 6) {
                    Image(systemName: source.isTestContent ? "testtube.2" : "antenna.radiowaves.left.and.right")
                    Text(source.isTestContent ? "Тестовый поток — это не серия «\(model.anime.title.preferred)»" : source.providerName)
                        .lineLimit(2)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(source.isTestContent ? Theme.secondaryAccent.opacity(0.25) : Color.white.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 6))
                if let attribution = source.attribution {
                    Text(attribution).font(.caption2).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    // MARK: Center

    private var centerControls: some View {
        HStack(spacing: 44) {
            Button { model.skip(by: -10); interacted() } label: {
                Image(systemName: "gobackward.10").font(.system(size: 30))
            }
            .accessibilityLabel("Назад на 10 секунд")
            Button { model.togglePlay(); interacted() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44))
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel(model.isPlaying ? "Пауза" : "Воспроизвести")
            Button { model.skip(by: 10); interacted() } label: {
                Image(systemName: "goforward.10").font(.system(size: 30))
            }
            .accessibilityLabel("Вперёд на 10 секунд")
        }
    }

    // MARK: Bottom

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Text(TimeFormat.string(model.currentTime)).font(.caption.monospacedDigit())
                Slider(value: Binding(get: { model.currentTime }, set: { model.currentTime = $0 }),
                       in: 0...max(model.duration, 1)) { editing in
                    if editing { model.isScrubbing = true } else { model.seek(to: model.currentTime) }
                    interacted()
                }
                .disabled(model.duration <= 0)
                .accessibilityLabel("Позиция воспроизведения")
                .accessibilityValue("\(TimeFormat.string(model.currentTime)) из \(TimeFormat.string(model.duration))")
                Text(model.duration > 0 ? TimeFormat.string(model.duration) : "--:--").font(.caption.monospacedDigit())
            }
            HStack(spacing: Theme.Spacing.l) {
                tracksMenu
                Button(action: showSources) { Label("Источник", systemImage: "server.rack") }
                Spacer()
                Button(action: showEpisodes) { Label("Серии", systemImage: "list.bullet") }
                if model.hasNextEpisode {
                    Button(action: model.playNextEpisode) { Label("Далее", systemImage: "forward.end.fill") }
                        .accessibilityLabel("Следующая серия")
                }
            }
            .font(.footnote.weight(.medium))
            .labelStyle(.titleAndIcon)
        }
    }

    private var tracksMenu: some View {
        Menu {
            Section("Аудио") {
                if model.audioOptions.count > 1 {
                    ForEach(model.audioOptions) { option in
                        Button { model.selectAudio(option) } label: {
                            if option.id == model.selectedAudioID { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
                        }
                    }
                } else {
                    Text(model.audioOptions.isEmpty ? "Поток не сообщает об аудиодорожках" : "Одна аудиодорожка: \(model.audioOptions[0].name)")
                }
            }
            Section("Субтитры") {
                if model.subtitleOptions.isEmpty {
                    Text("В потоке нет субтитров")
                } else {
                    ForEach(model.subtitleOptions) { option in
                        Button { model.selectSubtitle(option) } label: {
                            if option.id == model.selectedSubtitleID { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
                        }
                    }
                }
            }
        } label: {
            Label("Звук и субтитры", systemImage: "captions.bubble")
        }
    }
}

struct SourcesSheet: View {
    let model: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.candidates) { candidate in
                        Button {
                            model.select(candidate: candidate)
                            dismiss()
                        } label: {
                            HStack {
                                SourceStatusRow(candidate: candidate)
                                Spacer()
                                if candidate.providerID == model.activeCandidate?.providerID {
                                    Image(systemName: "play.fill").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .disabled(!candidate.availability.isAvailable)
                    }
                } footer: {
                    Text("Показаны только подключённые источники. Доступным считается источник, ссылка которого проверена.")
                }
            }
            .navigationTitle("Источники · серия \(model.episodeNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Обновить") { model.findSources(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
    }
}

struct EpisodesSheet: View {
    let model: PlayerViewModel
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(model.episodes) { ep in
                    Button {
                        model.selectEpisode(ep.number)
                        dismiss()
                    } label: {
                        HStack {
                            Text(ep.displayTitle)
                                .fontWeight(ep.number == model.episodeNumber ? .bold : .regular)
                                .foregroundStyle(ep.number == model.episodeNumber ? Theme.accent : Theme.textPrimary)
                            Spacer()
                            if let p = library.progress(model.anime.id, episode: ep.number) {
                                if p.isFinished {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.success)
                                } else if p.percent > 0 {
                                    Text("\(p.percent)%").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .id(ep.number)
                }
                .onAppear { proxy.scrollTo(model.episodeNumber, anchor: .center) }
            }
            .navigationTitle("Серии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}
