import SwiftUI
import UIKit

/// Палитра и метрики Anivibe. Тёмная тема — основная; светлая поддерживается.
@Observable
final class AccentPalette {
    var hex: String? = UserDefaults.standard.string(forKey: "settings.accentHex")
}

enum Theme {
    static let palette = AccentPalette()
    // Нейтральные непрозрачные поверхности и один спокойный цвет действия.
    static let background = Color(light: 0xF4F4F2, dark: 0x141415)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surfaceElevated = Color(light: 0xEBEBE8, dark: 0x28282B)
    static let separator = Color(light: 0xD6D6D1, dark: 0x39393D)
    static let textPrimary = Color(light: 0x202020, dark: 0xF2F2EF)
    static let textSecondary = Color(light: 0x5F5F5A, dark: 0xA8A8A2)
    /// Затемнение под панелями и модальными слоями.
    static let scrim = Color(light: 0x101014, dark: 0x000000).opacity(0.55)
    static var accent: Color {
        if let hex = palette.hex, let color = UIColor(hexString: hex) { return Color(color) }
        return Color(light: 0x275D8C, dark: 0x9CBADD)
    }
    static var onAccent: Color {
        guard let hex = palette.hex, let color = UIColor(hexString: hex) else { return Color(light: 0xFFFFFF, dark: 0x000000) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return luminance > 0.179 ? .black : .white
    }
    /// Второстепенный акцент — тот же цвет действия: одна палитра на всё приложение.
    static var secondaryAccent: Color { accent }
    static let danger = Color(light: 0xC62E3A, dark: 0xFF6B6B)
    static let success = Color(light: 0x1D7049, dark: 0x4CD18F)

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 12
        static let panel: CGFloat = 16
        static let chip: CGFloat = 8
    }

    /// Папки используют общие поверхности темы — своего набора цветов у них нет.
    enum Folder {
        static let tileSize: CGFloat = 104
        static let tileRadius: CGFloat = 20
        static let posterRadius: CGFloat = 14
        static let panelRadius: CGFloat = 20
        static let panelMaxHeight: CGFloat = 460
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
        background(AppScreenBackground().ignoresSafeArea())
    }
}

/// Непрозрачная панель: текст читается и поверх стандартного, и поверх пользовательского фона.
private struct ProfilePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(Theme.Spacing.l)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).fill(Theme.surface))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            }
    }
}

extension View {
    func profilePanel() -> some View { modifier(ProfilePanelModifier()) }
}
