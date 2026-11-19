import Foundation
import AnivibeCore

/// Маршрут, открытый по deep link (`anivibe://anime/<id>`).
///
/// Держится в `AppEnvironment`: `RootView` переключает вкладку, а `CatalogView`
/// с собственной навигацией выполняет переход к деталям тайтла.
@Observable
@MainActor
final class DeepLinkRouter {
    /// ID тайтла, который нужно открыть. Сбрасывается после обработки.
    private(set) var pendingAnimeID: Int?

    /// Разбирает внешний URL. `true`, если URL — наш deep link.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let id = WidgetSnapshot.animeID(from: url) else { return false }
        pendingAnimeID = id
        return true
    }

    /// Атомарно забирает ожидающий ID (nil, если открывать нечего).
    func take() -> Int? {
        defer { pendingAnimeID = nil }
        return pendingAnimeID
    }
}
