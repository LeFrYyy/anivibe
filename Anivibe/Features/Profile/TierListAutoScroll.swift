import SwiftUI
import UIKit

/// Плавный автоскролл конструктора тир-листов при перетаскивании карточки.
/// Зоны срабатывания ~110pt сверху и снизу видимой области; скорость растёт к краю;
/// цикл — таймер ~30 Гц, скроллит через UIScrollView.setContentOffset (пиксельная точность).
@Observable
final class TierListAutoScroller {
    private(set) var isDragging = false

    /// Ширина краевой зоны срабатывания, pt (соответствует ~12–15% типичной высоты).
    static let edgeZone: CGFloat = 110
    /// Максимальное смещение за тик, pt (~16pt * 30 Гц ≈ 480 pt/с).
    static let maxDeltaPerTick: CGFloat = 16
    static let tickInterval: TimeInterval = 1.0 / 30.0

    @ObservationIgnored private var dragLocation: CGPoint = .zero
    @ObservationIgnored private weak var scrollView: UIScrollView?
    @ObservationIgnored private var timer: Timer?

    /// Пробник внутри ScrollView нашёл родительский UIScrollView.
    func attach(_ scrollView: UIScrollView) {
        self.scrollView = scrollView
    }

    func dragStarted(at location: CGPoint) {
        isDragging = true
        dragLocation = location
        startTimerIfNeeded()
    }

    func dragMoved(to location: CGPoint) {
        dragLocation = location
        if !isDragging {
            isDragging = true
        }
        startTimerIfNeeded()
    }

    /// Дроп, выход за пределы, отмена — в любом случае гасим таймер.
    func dragEnded() {
        isDragging = false
        stopTimer()
    }

    func cancel() {
        dragEnded()
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        // .common — таймер не должен останавливаться во время drag-tracking.
        // RunLoop.main гарантирует исполнение tick() на главном потоке.
        let t = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isDragging, let sv = scrollView else { return }
        let height = sv.bounds.height
        guard height > 0 else { return }
        let zone = Self.edgeZone
        let y = dragLocation.y
        var delta: CGFloat = 0

        if y < zone {
            // progress 0→1: на границе зоны — 0, у самого края — 1.
            delta = -Self.maxDeltaPerTick * ease(progress(distanceFromEdge: max(0, y), zone: zone))
        } else if y > height - zone {
            delta = Self.maxDeltaPerTick * ease(progress(distanceFromEdge: max(0, height - y), zone: zone))
        }

        guard delta != 0 else { return }
        let maxY = max(0, sv.contentSize.height - height + sv.adjustedContentInset.bottom + sv.adjustedContentInset.top)
        let minY = -sv.adjustedContentInset.top
        let newY = min(maxY, max(minY, sv.contentOffset.y + delta))
        guard newY != sv.contentOffset.y else { return }
        sv.setContentOffset(CGPoint(x: sv.contentOffset.x, y: newY), animated: false)
    }

    /// 0 у внешней границы зоны → 1 у самого края экрана.
    private func progress(distanceFromEdge: CGFloat, zone: CGFloat) -> CGFloat {
        min(1, max(0, (zone - distanceFromEdge) / zone))
    }

    /// Квадратичное нарастание — плавный старт, быстрая прокрутка у края.
    private func ease(_ t: CGFloat) -> CGFloat { t * t }
}

/// DropDelegate, который вешается на весь ScrollView конструктора и читает
/// координату перетаскивания (`info.location` — в системе координат ScrollView).
/// `performDrop` возвращает `false`, чтобы дроп уходил во внутренние `.dropDestination`.
struct TierListAutoScrollDelegate: DropDelegate {
    let scroller: TierListAutoScroller

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        scroller.dragStarted(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal {
        scroller.dragMoved(to: info.location)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        scroller.dragEnded()
        return false
    }

    func dropExited(info: DropInfo) {
        scroller.dragEnded()
    }
}

/// Невидимый UIView-пробник: находится внутри контента ScrollView и при появлении
/// в окне поднимается по superview-цепочке до родительского UIScrollView.
struct TierScrollViewProbe: UIViewRepresentable {
    let onResolve: (UIScrollView) -> Void

    func makeUIView(context: Context) -> TierScrollProbeView {
        TierScrollProbeView(onResolve: onResolve)
    }

    func updateUIView(_ uiView: TierScrollProbeView, context: Context) {
        uiView.onResolve = onResolve
    }
}

final class TierScrollProbeView: UIView {
    var onResolve: (UIScrollView) -> Void
    private var resolved = false

    init(onResolve: @escaping (UIScrollView) -> Void) {
        self.onResolve = onResolve
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !resolved else { return }
        resolved = true
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                onResolve(scrollView)
                return
            }
            view = current.superview
        }
        // ScrollView мог ещё не смонтироваться — пробуем на следующем цикле.
        resolved = false
        DispatchQueue.main.async { [weak self] in self?.didMoveToWindow() }
    }
}
