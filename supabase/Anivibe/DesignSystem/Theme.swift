import SwiftUI
import UIKit

/// Палитра и метрики Anivibe. Тёмная тема — основная; светлая поддерживается.
enum Theme {
    // Графитовый фон, глубокий фиолетовый акцент, холодный голубой второстепенный акцент.
    static let background = Color(light: 0xF5F5F8, dark: 0x111114)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1B1B20)
    static let surfaceElevated = Color(light: 0xECECF1, dark: 0x25252C)
    static let separator = Color(light: 0xDADAE2, dark: 0x2E2E36)
    static let textPrimary = Color(light: 0x15151A, dark: 0xF2F2F5)
    static let textSecondary = Color(light: 0x5E5E6B, dark: 0xA0A0AE)
    static let accent = Color(light: 0x5B3FE0, dark: 0x8467FF)
    static let secondaryAccent = Color(light: 0x0E8FC2, dark: 0x5CC8F2)
    static let danger = Color(light: 0xC62E3A, dark: 0xFF6B6B)
    static let success = Color(light: 0x1E8E5A, dark: 0x4CD18F)

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 10
        static let panel: CGFloat = 14
        static let chip: CGFloat = 8
    }

    /// Пропорция постера (2:3).
    static let posterAspect: CGFloat = 2.0 / 3.0
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self = Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    convenience init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

extension View {
    /// Стандартный фон экранов.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
