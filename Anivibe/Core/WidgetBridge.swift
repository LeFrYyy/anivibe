import Foundation
import WidgetKit
import AnivibeCore

/// Мост между приложением и виджетом.
///
/// Приложение пишет снимок «Продолжить просмотр» в общий App Group-файл и просит
/// WidgetKit перестроить таймлайн. Виджет только читает этот файл — сеть ему не нужна.
enum WidgetBridge {
    /// Публикует текущее состояние библиотеки и обновляет виджеты.
    @MainActor
    static func publish(continueWatching: [ContinueWatchingItem], libraryCount: Int) {
        let snapshot = WidgetSnapshotStore.make(from: continueWatching, libraryCount: libraryCount)
        guard WidgetSnapshotStore.write(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
