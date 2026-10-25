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
        context.coordinator.loadedURL = url
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
