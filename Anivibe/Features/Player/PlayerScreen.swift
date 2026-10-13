import SwiftUI
import AnivibeCore

/// Полноэкранный плеер. Открывается через `fullScreenCover` со страницы тайтла.
struct PlayerScreen: View {
    let request: PlaybackRequest
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayerViewModel?
    @State private var pip = PictureInPictureModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                PlayerContent(model: model, pip: pip, close: close)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if model == nil {
                let settings = env.settings
                let vm = PlayerViewModel(request: request, registry: env.registry, library: env.library,
                                         accountID: env.session.user?.id, autoplayNext: { settings.autoplayNextEpisode })
                model = vm
                vm.start()
            }
        }
        .onDisappear {
            model?.teardown()
            pip.detach()
        }
    }

    private func close() {
        model?.teardown()
        pip.detach()
        OrientationHelper.request(.portrait)
        dismiss()
    }
}

private struct PlayerContent: View {
    @Bindable var model: PlayerViewModel
    let pip: PictureInPictureModel
    let close: () -> Void

    @State private var controls = PlaybackControlsState()
    @State private var showSettings = false
    @State private var webPlayback: WebPlaybackRequest?
    private var controlsVisible: Bool { controls.isVisible }
    private var interactionBlocked: Bool {
        webPlayback != nil || showSettings || showSources || showEpisodes || model.isScrubbing || model.isBuffering || model.phase != .ready
    }
    @State private var hideTask: Task<Void, Never>?
    @State private var showSources = false
    @State private var showEpisodes = false

    var body: some View {
        ZStack {
            PlayerLayerView(player: model.player, pip: pip)
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }
                .accessibilityLabel("Видео")
                .accessibilityAddTraits(.allowsDirectInteraction)

            phaseOverlay

            if controlsVisible || model.phase != .ready {
                PlayerControlsView(model: model, pip: pip, close: close,
                                   showSources: { showSources = true },
                                   showEpisodes: { showEpisodes = true },
                                   showSettings: { showSettings = true },
                                   interacted: scheduleHide)
                    .transition(.opacity)
            }

            if let countdown = model.nextEpisodeCountdown {
                NextEpisodeCard(countdown: countdown, next: model.episodeNumber + 1,
                                playNow: model.playNextEpisode, cancel: model.cancelCountdown)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(Theme.Spacing.xl)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
        .sheet(item: $webPlayback) { request in
            NavigationStack {
                WebPlayerView(url: request.url).background(Color.black)
                    .navigationTitle("Kodik · веб-плеер").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Закрыть") { webPlayback = nil } } }
                    .safeAreaInset(edge: .bottom) {
                        Text("Прогресс и настройки веб-плеера управляются Kodik; Anivibe не сохраняет их автоматически.")
                            .font(.footnote).padding(12).background(.regularMaterial)
                    }
            }.preferredColorScheme(.dark).presentationDetents([.large])
        }
        .sheet(isPresented: $showSettings) {
            VideoSettingsSheet(model: model).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSources) {
            SourcesSheet(model: model).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showEpisodes) {
            EpisodesSheet(model: model).presentationDetents([.medium, .large])
        }
        .onChange(of: model.isPlaying) { _, _ in scheduleHide() }
        .onChange(of: interactionBlocked) { _, _ in scheduleHide() }
        .onAppear { scheduleHide() }
        .onDisappear { hideTask?.cancel() }
    }

    @ViewBuilder private var phaseOverlay: some View {
        switch model.phase {
        case .searchingSources:
            PlayerStatusView(systemImage: nil, title: "Ищем источники…", message: "Серия \(model.episodeNumber)")
        case .preparing:
            PlayerStatusView(systemImage: nil, title: "Подготовка видео…", message: model.activeCandidate?.providerName)
        case .noSources:
            NoSourcesView(model: model, close: close)
        case .failed(let message):
            PlayerStatusView(systemImage: "exclamationmark.triangle", title: "Не удалось воспроизвести", message: message) {
                VStack(spacing: Theme.Spacing.m) {
                    if let url = model.kodikWebURL {
                        Button("Открыть веб-плеер Kodik") {
                            model.pauseForWebPlayer()
                            webPlayback = WebPlaybackRequest(url: url, title: model.anime.title.preferred, subtitle: model.selectedVoice)
                        }.buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
                    }
                    Button("Повторить", action: model.retry).buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
                    if !model.otherAvailableCandidates.isEmpty {
                        Button("Другой источник") { showSources = true }.buttonStyle(.bordered)
                    }
                }
            }
        case .ready:
            if model.isBuffering {
                ProgressView().controlSize(.large).tint(.white)
                    .accessibilityLabel("Буферизация")
            }
        }
    }

    private func toggleControls() {
        hideTask?.cancel()
        controls.toggle(at: Date(), blocked: interactionBlocked)
        if controlsVisible { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        controls.interact(at: Date(), blocked: interactionBlocked || !model.isPlaying)
        guard !interactionBlocked, model.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            controls.tick(at: Date(), playing: model.isPlaying, blocked: interactionBlocked)
        }
    }
}

private struct PlayerStatusView<Actions: View>: View {
    let systemImage: String?
    let title: String
    let message: String?
    @ViewBuilder var actions: () -> Actions

    init(systemImage: String?, title: String, message: String?, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            if let systemImage {
                Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.white.opacity(0.8))
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
            Text(title).font(.headline).foregroundStyle(.white)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            }
            actions()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 420)
    }
}

private struct NoSourcesView: View {
    let model: PlayerViewModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: "film.stack").font(.largeTitle).foregroundStyle(.white.opacity(0.8))
            Text("Нет доступных источников").font(.headline).foregroundStyle(.white)
            Text("Для серии \(model.episodeNumber) ни один подключённый источник не подтвердил доступность видео.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(model.candidates) { c in
                    SourceStatusRow(candidate: c)
                }
                if model.candidates.isEmpty {
                    Text("Все источники отключены. Включите тестовые потоки или настройте свой источник в README.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                }
            }
            HStack {
                Button("Повторить", action: model.findSources).buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
                Button("Закрыть", action: close).buttonStyle(.bordered).tint(.white)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 460)
    }
}

struct SourceStatusRow: View {
    let candidate: SourceCandidate

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: candidate.availability.isAvailable ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(candidate.availability.isAvailable ? Theme.success : Theme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.providerName).font(.subheadline.weight(.semibold))
                if case .unavailable(let error) = candidate.availability {
                    Text(error.userMessage).font(.caption).foregroundStyle(.secondary)
                } else if candidate.isTestContent {
                    Text("Тестовое видео — не является серией аниме").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NextEpisodeCard: View {
    let countdown: Int
    let next: Int
    let playNow: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Серия \(next) через \(countdown) с").font(.headline)
            HStack {
                Button("Смотреть", action: playNow).buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
                Button("Отмена", action: cancel).buttonStyle(.bordered)
            }
        }
        .padding(Theme.Spacing.l)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
        .environment(\.colorScheme, .dark)
    }
}

enum OrientationHelper {
    @MainActor
    static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    @MainActor
    static func toggle() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        request(scene.interfaceOrientation.isLandscape ? .portrait : .landscapeRight)
    }
}
