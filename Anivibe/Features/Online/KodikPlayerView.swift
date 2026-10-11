import SwiftUI
import WebKit

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
                if let host = url.host(), host.contains("kodik") || host.contains("aniqit") {
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

/// Полноэкранный веб-плеер Kodik.
struct KodikPlayerScreen: View {
    let request: WebPlaybackRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            WebPlayerView(url: request.url)
                .ignoresSafeArea()

            // Верхняя панель поверх плеера.
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
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
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .accessibilityLabel("Закрыть плеер")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .background(
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}