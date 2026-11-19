import WidgetKit
import SwiftUI

/// Точка входа виджета Anivibe. Данные берутся из общего App Group-файла,
/// который приложение обновляет при изменении библиотеки.
@main
struct AnivibeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueWatchingWidget()
    }
}
