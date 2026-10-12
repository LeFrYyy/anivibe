import Foundation

public struct ProviderID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public enum StreamKind: String, Codable, Sendable {
    case hls
    case progressiveFile
}

/// Объявленная источником дорожка (аудио или субтитры).
public struct MediaTrackInfo: Hashable, Codable, Sendable {
    public let name: String
    public let language: String?
    public let isDefault: Bool
    public let isForced: Bool
    public init(name: String, language: String?, isDefault: Bool = false, isForced: Bool = false) {
        self.name = name
        self.language = language
        self.isDefault = isDefault
        self.isForced = isForced
    }
}

/// Готовый к воспроизведению источник, полученный от провайдера.
public struct PlaybackSource: Hashable, Sendable {
    public let providerID: ProviderID
    public let providerName: String
    public let url: URL
    public let kind: StreamKind
    /// Ссылка временная — её нельзя кэшировать дольше этого момента.
    public let expiresAt: Date?
    public let audioTracks: [MediaTrackInfo]
    public let subtitleTracks: [MediaTrackInfo]
    /// Тестовый поток, а не серия аниме. UI обязан это показывать.
    public let isTestContent: Bool
    public let attribution: String?
    /// Отдельные потоки разного качества (если источник отдаёт их раздельно, как Kodik).
    public let qualities: [PlaybackQuality]
    /// Доступные озвучки для этой серии (названия студий) и выбранная.
    public let voices: [String]
    public let selectedVoice: String?

    public init(providerID: ProviderID, providerName: String, url: URL, kind: StreamKind, expiresAt: Date? = nil,
                audioTracks: [MediaTrackInfo] = [], subtitleTracks: [MediaTrackInfo] = [],
                isTestContent: Bool = false, attribution: String? = nil,
                qualities: [PlaybackQuality] = [], voices: [String] = [], selectedVoice: String? = nil) {
        self.qualities = qualities
        self.voices = voices
        self.selectedVoice = selectedVoice
        self.providerID = providerID
        self.providerName = providerName
        self.url = url
        self.kind = kind
        self.expiresAt = expiresAt
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.isTestContent = isTestContent
        self.attribution = attribution
    }

    /// Тот же источник, но с другим потоком (смена качества).
    public func with(url newURL: URL) -> PlaybackSource {
        PlaybackSource(providerID: providerID, providerName: providerName, url: newURL, kind: kind, expiresAt: expiresAt,
                       audioTracks: audioTracks, subtitleTracks: subtitleTracks, isTestContent: isTestContent,
                       attribution: attribution, qualities: qualities, voices: voices, selectedVoice: selectedVoice)
    }

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

/// Поток определённого качества.
public struct PlaybackQuality: Hashable, Sendable, Identifiable {
    public var id: Int { height }
    public let height: Int
    public let url: URL
    public init(height: Int, url: URL) {
        self.height = height
        self.url = url
    }
    public var label: String { "\(height)p" }
}
