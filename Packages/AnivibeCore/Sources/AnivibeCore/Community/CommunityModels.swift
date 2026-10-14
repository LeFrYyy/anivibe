import Foundation

public struct FriendshipLevel: Codable, Sendable, Equatable {
    public let level: Int
    public let xp: String
    public let inLevel: String
    public let needed: String
    public let progress: Double
}
public struct CommunityFriend: Decodable, Sendable, Identifiable {
    public var id: String { peerId }
    public let peerId: String
    public let name: String
    public let username: String?
    public let avatarPath: String?
    public let level: FriendshipLevel
    public let episodes: Int
    public let startedAt: String
    public let lastWatchAt: String?
    public let dailyCompleted: Int
    public let dailyRewarded: Bool
    public let watching: Bool?
}
public struct CommunityItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let category: String
    public let price: Int
    public let cap: Int?
    public let prerequisite: String?
    public let assetKey: String?
    public let mime: String?
    public let posterKey: String?
    public let available: Bool
    public let owned: Bool
    public let equipped: Bool
    public var slot: String? {
        switch category { case "avatar": return "avatar"; case "banner", "animated_banner": return "banner"; default: return nil }
    }
}
public struct CommunityNotice: Decodable, Sendable, Identifiable {
    public struct Payload: Decodable, Sendable {
        public let peerId: String?
        public let sessionId: String?
        public let level: Int?
        public let xp: Int?
        public let coins: Int?
        public let state: String?
        public let reason: String?
    }
    public let id: String
    public let kind: String
    public let createdAt: String
    public let read: Bool
    public let payload: Payload
    public var title: String {
        switch kind {
        case "friend_request": return "Новая заявка в друзья"
        case "friend_accepted": return "Заявка в друзья принята"
        case "watch_invite": return "Приглашение смотреть вместе"
        case "episode_reward": return "Серия засчитана · +\(payload.xp ?? 0) XP · +\(payload.coins ?? 0) монет"
        case "daily_reward": return "Задание выполнено · +\(payload.xp ?? 0) XP · +\(payload.coins ?? 0) монет"
        case "level_up": return "Дружба достигла уровня \(payload.level ?? 1)"
        case "comment_moderated": return payload.state == "hidden" ? "Комментарий скрыт модератором" : "Комментарий восстановлен"
        default: return "Обновление Anivibe"
        }
    }
}
public struct CommunityHub: Decodable, Sendable {
    public let userId: String
    public let balance: Int
    public let friendCap: Int
    public let day: String
    public let dailyGoal: Int
    public let dailyXp: Int
    public let dailyCoins: Int
    public let invitePolicy: String
    public let hideWatching: Bool
    public let uniqueEpisodes: Int
    public let friends: [CommunityFriend]
    public let items: [CommunityItem]
    public let sessions: [WatchRoom]
    public let notifications: [CommunityNotice]
}
public struct CanonicalWatchEpisode: Decodable, Sendable, Identifiable {
    public let id: String
    public let animeId: String
    public let anilistId: Int?
    public let animeTitle: String
    public let label: String
    public let kind: String
    public let sortOrder: Int
    public let duration: Double?
    public let verified: Bool
    public let sources: [WatchSourceMapping]
}
public struct WatchSourceMapping: Decodable, Sendable, Identifiable {
    public let id: String
    public let providerId: String
    public let voice: String
    public let sourceOffset: Double
    public let sourceEpisode: ProviderEpisode
    public let verified: Bool
    enum CodingKeys: String, CodingKey { case id, providerId, voice, sourceOffset, sourceEpisode, verified }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); providerId = try c.decode(String.self, forKey: .providerId)
        voice = try c.decode(String.self, forKey: .voice); sourceOffset = try c.decode(Double.self, forKey: .sourceOffset)
        verified = try c.decode(Bool.self, forKey: .verified)
        let wire = try c.decode(WatchProviderDescriptor.self, forKey: .sourceEpisode)
        guard wire.providerID.rawValue == providerId else {
            throw DecodingError.dataCorruptedError(forKey: .sourceEpisode, in: c, debugDescription: "Provider identity mismatch")
        }
        sourceEpisode = ProviderEpisode(providerID: ProviderID(rawValue: wire.providerID.rawValue), titleID: wire.titleID,
            season: wire.season, number: wire.number, title: wire.title, payload: wire.payload)
    }
}
private struct WatchProviderDescriptor: Decodable {
    struct ProviderWire: Decodable {
        let rawValue: String
        enum CodingKeys: String, CodingKey { case rawValue }
        init(from decoder: Decoder) throws {
            if let scalar = try? decoder.singleValueContainer().decode(String.self) { rawValue = scalar }
            else { let c = try decoder.container(keyedBy: CodingKeys.self); rawValue = try c.decode(String.self, forKey: .rawValue) }
        }
    }
    let providerID: ProviderWire
    let titleID: String
    let season: Int?
    let number: Int
    let title: String?
    let payload: String
}
public struct WatchRoom: Decodable, Sendable, Identifiable {
    public struct Member: Decodable, Sendable, Identifiable {
        public var id: String { userId }
        public let userId: String
        public let mappingId: String?
        public let state: String
        public let online: Bool?
        public let watchedProgress: Double
    }
    public let id: String
    public let hostId: String
    public let guestId: String
    public let status: String
    public let episodeId: String
    public let animeId: String
    public let anilistId: Int?
    public let animeTitle: String
    public let episodeLabel: String
    public let episodeOrder: Int
    public let playback: String
    public let wantsPlay: Bool
    public let position: Double
    public let serverTime: Double
    public let revision: Int
    public let duration: Double?
    public let rewardsEligible: Bool
    public let rewardBlockReason: String?
    public let overlapProgress: Double
    public let completionRatio: Double
    public let overlapRatio: Double
    public let rewarded: Bool
    public let members: [Member]
    public var rewardStatus: String {
        if rewarded { return "Награда подтверждена сервером" }
        switch rewardBlockReason {
        case "untrusted_duration": return "Награды отключены: нет проверенной продолжительности"
        case "untrusted_source": return "Для наград оба источника должны быть подтверждены"
        case "awaiting_duration": return "Проверяем продолжительность видео у обоих участников"
        default: return "Награда появится после подтверждения просмотра обоих участников"
        }
    }
    public var isClosed: Bool { status == "closed" }
    public func member(_ userId: String) -> Member? { members.first { $0.userId.lowercased() == userId.lowercased() } }
}
public struct PurchaseReceipt: Decodable, Sendable {
    public let itemId: String
    public let balance: Int
    public let charged: Int
    public let replayed: Bool
}
public struct CosmeticPresentation: Decodable, Sendable {
    public struct Media: Decodable, Sendable { public let assetKey: String; public let posterKey: String?; public let mime: String }
    public let avatar: Media?
    public let banner: Media?
}
public enum CommunityError: Error, Sendable, Equatable {
    case server(String), unavailable, wrongAccount
    public var userMessage: String {
        switch self {
        case .wrongAccount: return "Аккаунт изменился. Откройте раздел заново."
        case .unavailable: return "Социальная система пока не настроена на сервере."
        case .server(let code):
            switch code {
            case "insufficient_coins": return "Недостаточно монет. Баланс не изменён."
            case "prerequisite_required": return "Сначала купите улучшение до 15 друзей."
            case "already_in_session": return "Один из участников уже в другой комнате. Сначала выйдите из неё."
            case "mapping_missing", "episode_invalid": return "Для этой серии нет подтверждённого сопоставления источника. Выберите другой источник."
            case "invites_disabled": return "Друг запретил приглашения или вы больше не друзья."
            case "request_rate_limited": return "Слишком много запросов. Попробуйте немного позже."
            case "session_expired": return "Комната закрыта из-за неактивности. Создайте новую."
            case "item_unavailable": return "Предмет сейчас недоступен. Монеты не списаны."
            case "request_conflict": return "Этот запрос уже использован для другой операции."
            case "request_not_allowed": return "Недостаточно прав для этого действия."
            default: return "Сервер не подтвердил действие. Обновите данные и повторите попытку."
            }
        }
    }
}
/// Pure reconciliation, independent of the device's wall clock.
public enum WatchReconciliation {
    public static let seekTolerance: Double = 1.5
    public static func target(anchor: Double, elapsed: TimeInterval, playing: Bool, duration: Double?) -> Double {
        let safeAnchor = anchor.isFinite ? max(0, anchor) : 0
        let safeElapsed = elapsed.isFinite ? min(30, max(0, elapsed)) : 0
        let result = safeAnchor + (playing ? safeElapsed : 0)
        return duration.map { $0.isFinite && $0 > 0 ? min($0, result) : result } ?? result
    }
    public static func needsSeek(local: Double, target: Double) -> Bool {
        local.isFinite && target.isFinite && abs(local - target) > seekTolerance
    }
}
