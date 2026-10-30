import SwiftUI
import UIKit

/// Лента страниц манги на UIScrollView: нативный pinch-зум (1–4x) с якорем под пальцами,
/// панорамирование по обеим осям при зуме, двойной тап — приблизить / сбросить.
/// Страницы раскладываются вручную (без Auto Layout и без SwiftUI-высоты внутри
/// UIHostingController), поэтому у контента всегда реальный размер.
struct MangaPagesZoomView: UIViewRepresentable {
    let pages: [URL]
    let footer: AnyView

    func makeCoordinator() -> MangaPagesController { MangaPagesController(footer: footer) }

    func makeUIView(context: Context) -> MangaZoomScrollView {
        let scrollView = MangaZoomScrollView()
        context.coordinator.attach(to: scrollView)
        context.coordinator.setPages(pages)
        return scrollView
    }

    func updateUIView(_ scrollView: MangaZoomScrollView, context: Context) {
        context.coordinator.footerHost.rootView = footer
        context.coordinator.setPages(pages)
    }
}

final class MangaZoomScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

@MainActor
final class MangaPagesController: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private static let maxZoom: CGFloat = 4
    private static let doubleTapZoom: CGFloat = 2.5
    private static let footerHeight: CGFloat = 84

    let footerHost: UIHostingController<AnyView>
    private weak var scrollView: MangaZoomScrollView?
    private let content = UIView()
    private var pageViews: [MangaPageView] = []
    private var pages: [URL] = []
    private var layoutWidth: CGFloat = 0

    init(footer: AnyView) {
        footerHost = UIHostingController(rootView: footer)
        super.init()
        footerHost.view.backgroundColor = .clear
        footerHost.safeAreaRegions = []
    }

    func attach(to scrollView: MangaZoomScrollView) {
        self.scrollView = scrollView
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = Self.maxZoom
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.addSubview(content)
        content.addSubview(footerHost.view)
        scrollView.onLayout = { [weak self] in self?.boundsDidChange() }

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        scrollView.addGestureRecognizer(doubleTap)
    }

    func setPages(_ newPages: [URL]) {
        guard newPages != pages else { return }
        pages = newPages
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews = newPages.enumerated().map { index, url in
            let page = MangaPageView(url: url, index: index)
            page.onResize = { [weak self] page in self?.pageDidResize(page) }
            content.insertSubview(page, belowSubview: footerHost.view)
            return page
        }
        scrollView?.setZoomScale(1, animated: false)
        scrollView?.contentOffset = .zero
        relayout()
    }

    private func boundsDidChange() {
        guard let scrollView, scrollView.bounds.width > 0, scrollView.bounds.width != layoutWidth else { return }
        // Поворот / смена ширины: раскладываем заново в масштабе 1x.
        layoutWidth = scrollView.bounds.width
        scrollView.setZoomScale(1, animated: false)
        relayout()
    }

    private func relayout() {
        guard let scrollView, scrollView.bounds.width > 0 else { return }
        let width = scrollView.bounds.width
        layoutWidth = width
        var y: CGFloat = 0
        for page in pageViews {
            let height = (width * page.aspectRatio).rounded()
            page.frame = CGRect(x: 0, y: y, width: width, height: height)
            y += height
        }
        footerHost.view.frame = CGRect(x: 0, y: y, width: width, height: Self.footerHeight)
        y += Self.footerHeight

        // Зум-вью трансформирована, поэтому меняем bounds/center, а не frame.
        let zoom = scrollView.zoomScale
        content.bounds = CGRect(x: 0, y: 0, width: width, height: y)
        content.center = CGPoint(x: width * zoom / 2, y: y * zoom / 2)
        scrollView.contentSize = CGSize(width: width * zoom, height: y * zoom)
        updateVisiblePages()
    }

    /// Страница узнала реальные пропорции. Если она выше видимой области —
    /// сдвигаем offset, чтобы читаемая страница не «прыгала».
    private func pageDidResize(_ page: MangaPageView) {
        guard let scrollView else { return }
        let zoom = scrollView.zoomScale
        let oldHeight = page.frame.height
        let isAbove = page.frame.maxY <= scrollView.contentOffset.y / zoom
        relayout()
        if isAbove {
            scrollView.contentOffset.y += (page.frame.height - oldHeight) * zoom
        }
    }

    /// Грузим страницы рядом с экраном, далёкие выгружаем из памяти.
    private func updateVisiblePages() {
        guard let scrollView, scrollView.bounds.height > 0 else { return }
        let zoom = scrollView.zoomScale
        let screen = scrollView.bounds.height / zoom
        let visible = CGRect(x: 0, y: scrollView.contentOffset.y / zoom, width: layoutWidth, height: screen)
        let preload = visible.insetBy(dx: 0, dy: -screen * 1.5)
        let keep = visible.insetBy(dx: 0, dy: -screen * 5)
        for page in pageViews {
            if page.frame.intersects(preload) {
                page.load()
            } else if !page.frame.intersects(keep) {
                page.unload()
            }
        }
    }

    @objc private func didDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let scrollView else { return }
        let animated = !UIAccessibility.isReduceMotionEnabled
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: animated)
        } else {
            let point = gesture.location(in: content)
            let size = CGSize(width: scrollView.bounds.width / Self.doubleTapZoom,
                              height: scrollView.bounds.height / Self.doubleTapZoom)
            let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                              width: size.width, height: size.height)
            scrollView.zoom(to: rect, animated: animated)
        }
    }

    // Двойной тап не должен перехватывать кнопки глав внизу ленты.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !footerHost.view.bounds.contains(touch.location(in: footerHost.view))
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { updateVisiblePages() }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateVisiblePages() }
}

/// Одна страница: картинка на всю ширину, высота по пропорциям картинки.
@MainActor
final class MangaPageView: UIView {
    let url: URL
    private(set) var aspectRatio: CGFloat = 1.5
    var onResize: ((MangaPageView) -> Void)?
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let failedIcon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
    private var task: Task<Void, Never>?
    private var failed = false

    init(url: URL, index: Int) {
        self.url = url
        super.init(frame: .zero)
        backgroundColor = UIColor(Theme.surfaceElevated)
        imageView.contentMode = .scaleAspectFit
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
        spinner.color = UIColor(Theme.textSecondary)
        addSubview(spinner)
        failedIcon.tintColor = UIColor(Theme.textSecondary)
        failedIcon.isHidden = true
        addSubview(failedIcon)
        isAccessibilityElement = true
        accessibilityLabel = "Страница \(index + 1)"
        accessibilityTraits = .image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        failedIcon.center = spinner.center
    }

    func load() {
        guard imageView.image == nil, task == nil, !failed else { return }
        if let cached = ImagePipeline.shared.cached(url) {
            show(cached)
            return
        }
        spinner.startAnimating()
        task = Task { [weak self, url] in
            do {
                let image = try await ImagePipeline.shared.image(for: url)
                guard !Task.isCancelled else { return }
                self?.task = nil
                self?.show(image)
            } catch {
                guard !Task.isCancelled else { return }
                self?.task = nil
                self?.showFailure()
            }
        }
    }

    func unload() {
        task?.cancel()
        task = nil
        spinner.stopAnimating()
        guard imageView.image != nil else { return }
        imageView.image = nil
        backgroundColor = UIColor(Theme.surfaceElevated)
    }

    private func show(_ image: UIImage) {
        spinner.stopAnimating()
        imageView.image = image
        backgroundColor = .clear
        guard image.size.width > 0, image.size.height > 0 else { return }
        let ratio = image.size.height / image.size.width
        if abs(ratio - aspectRatio) > 0.001 {
            aspectRatio = ratio
            onResize?(self)
        }
    }

    private func showFailure() {
        spinner.stopAnimating()
        failed = true
        failedIcon.isHidden = false
    }
}
