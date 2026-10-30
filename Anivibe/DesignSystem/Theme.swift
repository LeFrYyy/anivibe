import SwiftUI
import UIKit

/// Палитра и метрики Anivibe. Тёмная тема — основная; светлая поддерживается.
@Observable
final class AccentPalette {
    var hex: String? = UserDefaults.standard.string(forKey: "settings.accentHex")
}

enum Theme {
    static let palette = AccentPalette()
    // Графитовый фон, глубокий фиолетовый акцент, холодный голубой второстепенный акцент.
    static let background = Color(light: 0xF5F5F8, dark: 0x111114)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1B1B20)
    static let surfaceElevated = Color(light: 0xECECF1, dark: 0x25252C)
    static let separator = Color(light: 0xDADAE2, dark: 0x2E2E36)
    static let textPrimary = Color(light: 0x15151A, dark: 0xF2F2F5)
    static let textSecondary = Color(light: 0x5E5E6B, dark: 0xA0A0AE)
    static var accent: Color {
        if let hex = palette.hex, let color = UIColor(hexString: hex) { return Color(color) }
        return Color(light: 0x5B3FE0, dark: 0x8467FF)
    }
    static var onAccent: Color {
        guard let hex = palette.hex, let color = UIColor(hexString: hex) else { return Color(light: 0xFFFFFF, dark: 0x000000) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ v: CGFloat) -> Double { let x = Double(v); return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        return luminance > 0.179 ? .black : .white
    }
    static let secondaryAccent = Color(light: 0x0E8FC2, dark: 0x5CC8F2)
    static let danger = Color(light: 0xC62E3A, dark: 0xFF6B6B)
    /// Кораллово-красный акцент экранов манги (по референсу дизайна).
    static let mangaAccent = Color(light: 0xD9433E, dark: 0xF0564D)
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
        static let card: CGFloat = 16
        static let panel: CGFloat = 24
        static let chip: CGFloat = 10
    }

    /// Flat folder surfaces share the app palette in both system themes.
    enum Folder {
        static let tileSize: CGFloat = 104
        static let tileRadius: CGFloat = 22
        static let tileInset: CGFloat = 12
        static let slotSpacing: CGFloat = 6
        static let slotRadius: CGFloat = 6
        static let posterRadius: CGFloat = 14
        static let panelRadius: CGFloat = 28
        static let panelMaxHeight: CGFloat = 460
        static let panelMaxWidth: CGFloat = 520
        static let borderWidth: CGFloat = 1
        static let scrim = Color.black.opacity(0.55)
        static let background = Theme.surface
        static let placeholder = Theme.surfaceElevated
        static let border = Theme.separator
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

/// Material only on panels, never repeated across every scrolling poster.
/// Opaque fallback respects Reduce Transparency and custom background readability.
private struct ProfilePanelModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.padding(Theme.Spacing.l)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                if reduceTransparency { shape.fill(Theme.surface) }
                else { shape.fill(.regularMaterial) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.7), lineWidth: 0.5)
            }
    }
}

extension View {
    func profilePanel() -> some View { modifier(ProfilePanelModifier()) }
}
