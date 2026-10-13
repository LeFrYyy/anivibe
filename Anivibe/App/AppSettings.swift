import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: return "Тёмная"
        case .light: return "Светлая"
        case .system: return "Как в системе"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

/// Пользовательские настройки (UserDefaults).
@Observable
@MainActor
final class AppSettings {
    private let defaults: UserDefaults

    var accentHex: String? {
        didSet { defaults.set(accentHex, forKey: "settings.accentHex"); Theme.palette.hex = accentHex }
    }
    var libraryPinned: Bool { didSet { defaults.set(libraryPinned, forKey: "settings.libraryPinned") } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var autoplayNextEpisode: Bool { didSet { defaults.set(autoplayNextEpisode, forKey: Keys.autoplay) } }
    var testStreamsEnabled: Bool { didSet { defaults.set(testStreamsEnabled, forKey: Keys.testStreams) } }
    var anilibriaEnabled: Bool { didSet { defaults.set(anilibriaEnabled, forKey: Keys.anilibria) } }

    private enum Keys {
        static let appearance = "settings.appearance"
        static let autoplay = "settings.autoplayNext"
        static let testStreams = "settings.testStreams"
        static let anilibria = "settings.anilibria"
    }

    init(defaults: UserDefaults = .standard, testStreamsDefault: Bool) {
        self.defaults = defaults
        accentHex = defaults.string(forKey: "settings.accentHex")
        libraryPinned = defaults.bool(forKey: "settings.libraryPinned")
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .dark
        autoplayNextEpisode = defaults.object(forKey: Keys.autoplay) as? Bool ?? true
        testStreamsEnabled = defaults.object(forKey: Keys.testStreams) as? Bool ?? testStreamsDefault
        anilibriaEnabled = defaults.object(forKey: Keys.anilibria) as? Bool ?? true
        // Read observable properties only after all stored properties are initialized.
        Theme.palette.hex = accentHex
    }
}
