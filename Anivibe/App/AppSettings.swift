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

    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var autoplayNextEpisode: Bool { didSet { defaults.set(autoplayNextEpisode, forKey: Keys.autoplay) } }
    var testStreamsEnabled: Bool { didSet { defaults.set(testStreamsEnabled, forKey: Keys.testStreams) } }

    private enum Keys {
        static let appearance = "settings.appearance"
        static let autoplay = "settings.autoplayNext"
        static let testStreams = "settings.testStreams"
    }

    init(defaults: UserDefaults = .standard, testStreamsDefault: Bool) {
        self.defaults = defaults
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .dark
        autoplayNextEpisode = defaults.object(forKey: Keys.autoplay) as? Bool ?? true
        testStreamsEnabled = defaults.object(forKey: Keys.testStreams) as? Bool ?? testStreamsDefault
    }
}
