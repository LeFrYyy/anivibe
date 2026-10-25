import SwiftUI
import AnivibeCore

struct PlayerControlsView: View {
    @Bindable var model: PlayerViewModel
    let pip: PictureInPictureModel
    let close: () -> Void
    let showSources: () -> Void
    let showEpisodes: () -> Void
    let showSettings: () -> Void
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
            if model.phase == .ready { HStack { videoMenu; Spacer() } }
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
                ZStack {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 44))
                        .opacity(model.isBuffering ? 0.35 : 1)
                    if model.isBuffering {
                        ProgressView().controlSize(.large).tint(.white)
                    }
                }
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
                VideoTimelineSlider(model: model, interacted: interacted)
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

    /// Озвучка (Kodik), качество и скорость воспроизведения.
    private var videoMenu: some View {
        Button(action: showSettings) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                Text(videoSummary)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.secondaryAccent.opacity(0.35)],
                                                           startPoint: .leading, endPoint: .trailing)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }
            .shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 2)
        }
        .accessibilityLabel("Настройки видео: озвучка, качество и скорость")
    }

    /// Явная кнопка качества; скорость и озвучка доступны в том же окне.
    private var videoSummary: String {
        if let quality = model.currentQualityHeight { return "Качество: \(quality)p" }
        return "Качество: авто"
    }

    private var tracksMenu: some View {
        Button(action: showSettings) {
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
                    if model.pendingSourceCount > 0 {
                        Text("Проверяем ещё источников: \(model.pendingSourceCount). Уже найденные доступны для выбора.")
                    } else {
                        Text("Подключённые источники. Доступность окончательно проверяется при загрузке видеопотока.")
                    }
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
                            if let p = library.progress(model.anime.id, episode: ep.progressNumber, sourceKey: ep.sourceKey) {
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

private struct VideoTimelineSlider: View {
    @Bindable var model: PlayerViewModel
    let interacted: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragPosition: Double?

    private var displayTime: Double {
        dragPosition ?? model.currentTime
    }

    private var duration: Double {
        max(model.duration, 1)
    }

    private var playedFraction: Double {
        min(1.0, max(0.0, displayTime / duration))
    }

    private var bufferedFraction: Double {
        min(1.0, max(0.0, model.bufferedTime / duration))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height: CGFloat = 6
            let thumbRadius: CGFloat = 7

            ZStack(alignment: .leading) {
                // Фоновая дорожка
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: height)

                // Буферизация (прогруженная часть потока)
                Capsule()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: max(0, min(width, width * bufferedFraction)), height: height)
                    .animation(AppMotion.fade(reduceMotion: reduceMotion), value: bufferedFraction)

                // Воспроизведённая часть
                Capsule()
                    .fill(
                        LinearGradient(colors: [Theme.accent, Theme.secondaryAccent],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(0, min(width, width * playedFraction)), height: height)

                // Ползунок текущей позиции
                Circle()
                    .fill(.white)
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                    .offset(x: max(0, min(width - thumbRadius * 2, (width * playedFraction) - thumbRadius)))
            }
            .frame(height: max(geo.size.height, 32))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard width.isFinite, width > 0 else { return }
                        if dragPosition == nil {
                            model.isScrubbing = true
                            interacted()
                        }
                        let fraction = max(0, min(1, gesture.location.x / width))
                        let targetTime = fraction * duration
                        dragPosition = targetTime
                        model.currentTime = targetTime
                    }
                    .onEnded { gesture in
                        guard width.isFinite, width > 0 else {
                            dragPosition = nil
                            model.isScrubbing = false
                            return
                        }
                        let fraction = max(0, min(1, gesture.location.x / width))
                        let targetTime = fraction * duration
                        dragPosition = nil
                        model.seek(to: targetTime)
                        interacted()
                    }
            )
        }
        .frame(height: 32)
        .disabled(model.duration <= 0)
        .onDisappear {
            dragPosition = nil
            model.isScrubbing = false
        }
        .accessibilityLabel("Позиция воспроизведения")
        .accessibilityValue("\(TimeFormat.string(model.currentTime)) из \(TimeFormat.string(model.duration)), прогружено \(Int(bufferedFraction * 100))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.skip(by: 10)
            case .decrement: model.skip(by: -10)
            @unknown default: break
            }
            interacted()
        }
    }
}

