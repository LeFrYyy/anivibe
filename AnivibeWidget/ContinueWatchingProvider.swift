import WidgetKit
import SwiftUI
import AnivibeCore

/// Одна точка входа таймлайна: снимок «Продолжить просмотр» из App Group.
struct ContinueWatchingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Провайдер таймлайна. Данные локальные, поэтому сеть не нужна:
/// таймлайн перестраивается при обновлении снимка приложением (`WidgetCenter.reloadAllTimelines`)
/// и раз в 30 минут как страховка.
struct ContinueWatchingProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> ContinueWatchingEntry {
        ContinueWatchingEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueWatchingEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : WidgetSnapshotStore.read()
        completion(ContinueWatchingEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueWatchingEntry>) -> Void) {
        let now = Date()
        let entry = ContinueWatchingEntry(date: now, snapshot: WidgetSnapshotStore.read())
        let next = now.addingTimeInterval(Self.refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension WidgetSnapshot {
    /// Демонстрационные данные для галереи виджетов и превью — без реальной библиотеки.
    static var preview: WidgetSnapshot {
        WidgetSnapshot(continueWatching: [
            Item(id: 16498, title: "Атака титанов", episode: 5, progress: 0.62),
            Item(id: 21, title: "Ван-Пис", episode: 1042, progress: 0.18),
            Item(id: 1, title: "Ковбой Бибоп", episode: 3, progress: 0.9)
        ], libraryCount: 12, updatedAt: Date())
    }
}
