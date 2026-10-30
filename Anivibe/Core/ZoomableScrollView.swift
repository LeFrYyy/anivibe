import SwiftUI
import UIKit

/// UIScrollView с pinch-зумом и двойным тапом поверх SwiftUI-контента.
/// Используется в читалке манги: вертикальный скролл по страницам + приближение.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let maxZoom: CGFloat
    let content: Content

    init(maxZoom: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.maxZoom = maxZoom
        self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = maxZoom
        scrollView.showsVerticalScrollIndicator = true
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear

        let hosted = context.coordinator.hostingController
        // Иначе контент внутри UIScrollView сообщает нулевую высоту и не рендерится.
        hosted.sizingOptions = .intrinsicContentSize
        hosted.view.translatesAutoresizingMaskIntoConstraints = false
        hosted.view.backgroundColor = .clear
        scrollView.addSubview(hosted.view)
        NSLayoutConstraint.activate([
            hosted.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hosted.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hosted.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hosted.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hosted.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let hosted = context.coordinator.hostingController
        hosted.rootView = content
        // Контент меняет высоту при догрузке страниц — сообщаем UIScrollView.
        hosted.view.invalidateIntrinsicContentSize()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private let parent: ZoomableScrollView
        let hostingController: UIHostingController<Content>

        init(_ parent: ZoomableScrollView) {
            self.parent = parent
            hostingController = UIHostingController(rootView: parent.content)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { hostingController.view }

        @objc func didDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: hostingController.view)
                let size = scrollView.bounds.size
                let rect = CGRect(x: point.x - size.width / 4, y: point.y - size.height / 4,
                                  width: size.width / 2, height: size.height / 2)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}
