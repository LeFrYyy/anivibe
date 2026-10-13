import SwiftUI
import WebKit
import AVKit
import AnivibeCore

/// Веб-плеер для embed-ссылок Kodik (iframe).
///
/// Это осознанно отдельный путь воспроизведения, а не наш AVPlayer-плеер:
/// Kodik отдаёт только HTML-плеер, поэтому выбор серий/озвучки/качества происходит
/// ВНУТРИ веб-плеера, а PiP, сохранение прогресса и жесты Anivibe здесь недоступны.
struct WebPlayerView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url?.absoluteString != url.absoluteString, context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            uiView.load(URLRequest(url: url))
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: URL?

        /// Держим пользователя внутри плеера: переходы по рекламе/внешним ссылкам
        /// открываем в браузере, а не подменяем плеер.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                // Навигация самого плеера (kodik-и др. его домены) разрешена.
                if let host = url.host(), host.contains("kodik") || host.contains("aniqit") || host.contains("kodikplayer") || host.contains("kodikres") {
                    return .allow
                }
                await UIApplication.shared.open(url)
                return .cancel
            }
            return .allow
        }
    }
}

/// Запрос на открытие веб-плеера (для fullScreenCover(item:)).
struct WebPlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let subtitle: String?
}

/// Полноэкранный плеер Kodik.
///
/// По умолчанию — нативный AVPlayer: прямые HLS-потоки Kodik с выбором качества
/// и скорости воспроизведения, PiP и без рекламы веб-плеера. Если получить потоки
/// не удалось, можно открыть встроенный веб-плеер Kodik.
struct KodikPlayerScreen: View {
    let request: WebPlaybackRequest
    let client: KodikClient

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
        case web
    }

    static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    @Environment(\.dismiss) private var dismiss
    @AppStorage("kodik.preferredQuality") private var preferredQuality: Int = 1080
    @AppStorage("kodik.playbackSpeed") private var storedSpeed: Double = 1.0

    @State private var phase: Phase = .loading
    @State private var streams: [KodikStream] = []
    @State private var currentQuality: Int?
    @State private var player = AVPlayer()

    private var speed: Float { Float(storedSpeed) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                Color.black
                switch phase {
                case .loading:
                    VStack(spacing: Theme.Spacing.m) {
                        ProgressView().tint(.white)
                        Text("Получаем видеопоток…")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                case .ready:
                    NativeVideoPlayer(player: player, speeds: Self.speeds)
                case .failed(let message):
                    failedView(message)
                case .web:
                    WebPlayerView(url: request.url)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task { await load() }
        .onDisappear {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    // MARK: - Верхняя панель

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
        HStack(alignment: .center, spacing: Theme.Spacing.s) {
            // Настройки видео — в левом верхнем углу.
            VStack(alignment: .leading, spacing: 2) {
                Text(request.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle = request.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Spacing.s)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("Закрыть плеер")
        }
        if phase == .ready { HStack { qualityMenu; speedMenu; Spacer() } }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .background(Color.black)
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(streams) { stream in
                Button {
                    switchQuality(to: stream)
                } label: {
                    if stream.quality == currentQuality {
                        Label(stream.label, systemImage: "checkmark")
                    } else {
                        Text(stream.label)
                    }
                }
            }
        } label: {
            pill(icon: "sparkles.tv", text: currentQuality.map { "Качество: \($0)p" } ?? "Качество: авто")
        }
        .accessibilityLabel("Качество видео")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(Self.speeds, id: \.self) { value in
                Button {
                    setSpeed(value)
                } label: {
                    if value == speed {
                        Label(Self.speedLabel(value), systemImage: "checkmark")
                    } else {
                        Text(Self.speedLabel(value))
                    }
                }
            }
        } label: {
            pill(icon: "gauge.with.dots.needle.67percent", text: Self.speedLabel(speed))
        }
        .accessibilityLabel("Скорость воспроизведения")
    }

    private func pill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text).monospacedDigit()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.white.opacity(0.15), in: Capsule())
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.8))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.m) {
                Button("Повторить") { Task { await load() } }
                    .buttonStyle(.bordered)
                    .tint(.white)
                Button("Веб-плеер Kodik") { phase = .web }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.xl)
    }

    static func speedLabel(_ value: Float) -> String {
        let text = value == value.rounded() ? String(format: "%.0f", value) : String(format: "%g", value)
        return text + "×"
    }

    // MARK: - Воспроизведение

    private func load() async {
        phase = .loading
        do {
            let found = try await client.streams(for: request.url)
            guard !found.isEmpty else { throw APIError.notFound }
            streams = found
            // Лучшее качество, не выше выбранного ранее; иначе — самое низкое доступное.
            let stream = found.first { $0.quality <= preferredQuality } ?? found.last!
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            play(stream, at: nil, autoplay: true)
            phase = .ready
        } catch is CancellationError {
            return
        } catch {
            phase = .failed("Не удалось получить видеопоток Kodik. Попробуйте ещё раз или откройте веб-плеер.")
        }
    }

    private func play(_ stream: KodikStream, at time: CMTime?, autoplay: Bool) {
        let item = AVPlayerItem(url: stream.url)
        item.preferredForwardBufferDuration = 10
        player.replaceCurrentItem(with: item)
        currentQuality = stream.quality
        let needsSeek = time.map { $0.isValid && $0.seconds > 0 } ?? false
        if let time, needsSeek {
            player.pause()
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { completed in
                Task { @MainActor in
                    guard completed, player.currentItem === item else { return }
                    if autoplay { player.playImmediately(atRate: speed) }
                }
            }
        }
        player.defaultRate = speed
        if autoplay && !needsSeek { player.playImmediately(atRate: speed) }
    }

    private func switchQuality(to stream: KodikStream) {
        guard stream.quality != currentQuality else { return }
        preferredQuality = stream.quality
        let wasPlaying = player.timeControlStatus != .paused
        play(stream, at: player.currentTime(), autoplay: wasPlaying)
    }

    private func setSpeed(_ value: Float) {
        storedSpeed = Double(value)
        player.defaultRate = value
        if player.rate > 0 { player.rate = value }
    }
}

/// Системный плеер (AVPlayerViewController): перемотка, PiP, полноэкранный режим.
struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    let speeds: [Float]

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.videoGravity = .resizeAspect
        controller.speeds = speeds.map { AVPlaybackSpeed(rate: $0, localizedName: KodikPlayerScreen.speedLabel($0)) }
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
