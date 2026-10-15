/// Временно скрытые незавершённые функции. Данные и серверная логика сохранены.
enum AppFeatures {
    static let sharedWatchingEnabled = false
    static let friendshipShopEnabled = false

    static var communityEnabled: Bool {
        sharedWatchingEnabled || friendshipShopEnabled
    }
}