import SwiftUI

/// Плавный автоскролл конструктора тир-листов при перетаскивании карточки.
/// Зоны срабатывания ~110pt сверху и снизу контейнера; скорость растёт к краю;
/// цикл — таймер ~30 Гц, применяет смещение через `applyScroll` (ScrollPosition.scrollTo(y:)).
@Observable
final class TierListAutoScroller {
    private(set) var isDragging = false

    /// Ширина краевой зоны срабатывания, pt (соответствует ~12–15% типичной высоты).
    static let edgeZone: CGFloat = 110
    /// Максимальное смещение за тик, pt (~16pt * 30 Гц ≈ 480 pt/с).
    static let maxDeltaPerTick: CGFloat = 16
    static let tickInterval: TimeInterval = 1.0 / 30.0

    private var dragLocation: CGPoint = .zero
    private var containerHeight: CGFloat = 0
    private var currentOffset: CGFloat = 0
    private var timer: Timer?

    /// Замыкание прокрутки: получает новое вертикальное смещение в pt.
    var applyScroll: (CGFloat) -> Void = { _ in }

    func updateContainer(height: CGFloat) {
        containerHeight = height
    }

    /// Текущий вертикальный offset контента — обновляется из GeometryReader.
    func updateOffset(_ y: CGFloat) {
        currentOffset = max(0, y)
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
        guard isDragging, containerHeight > 0 else { return }
        let zone = Self.edgeZone
        let y = dragLocation.y
        var delta: CGFloat = 0

        if y < zone {
            // progress 0→1: на границе зоны — 0, у самого края — 1.
            delta = -Self.maxDeltaPerTick * ease(progress(distanceFromEdge: max(0, y), zone: zone))
        } else if y > containerHeight - zone {
            delta = Self.maxDeltaPerTick * ease(progress(distanceFromEdge: max(0, containerHeight - y), zone: zone))
        }

        guard delta != 0 else { return }
        let newY = max(0, currentOffset + delta)
        currentOffset = newY
        applyScroll(newY)
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

/// Отслеживание вертикального смещения контента внутри именованного coordinateSpace.
struct TierScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
