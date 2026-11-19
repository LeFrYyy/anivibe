import SwiftUI

/// Мини-палитра виджета. Намеренно независима от `Theme` приложения:
/// у виджета свой таргет и он не должен тянуть UIKit-зависимый дизайн-код.
enum WidgetTheme {
    /// Акцент совпадает с базовым акцентом приложения (`Theme.accent`).
    static let accent = Color(red: 0x84 / 255, green: 0x67 / 255, blue: 0xFF / 255)
    static let secondaryText = Color.secondary
    static let progressTrack = Color.primary.opacity(0.15)

    static let posterAspect: CGFloat = 2.0 / 3.0
}
