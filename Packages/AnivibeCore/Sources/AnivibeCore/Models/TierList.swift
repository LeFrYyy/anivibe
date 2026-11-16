import Foundation

/// Стандартные ранги персонального тир-листа.
public enum TierKey: String, Codable, CaseIterable, Hashable, Sendable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"

    public var defaultTitle: String {
        switch self {
        case .s: return "Шедевр"
        case .a: return "Отлично"
        case .b: return "Хорошо"
        case .c: return "Нормально"
        case .d: return "На любителя"
        }
    }

    public var defaultColorHex: String {
        switch self {
        case .s: return "E5534B"
        case .a: return "E0823D"
        case .b: return "C9A227"
        case .c: return "2E9B63"
        case .d: return "6E7687"
        }
    }
}

public enum TierListVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case privateOnly = "private"
    case publicList = "public"

    public var title: String {
        switch self {
        case .privateOnly: return "Приватный"
        case .publicList: return "Публичный тир-лист"
        }
    }

    public var shortTitle: String {
        switch self {
        case .privateOnly: return "Приватный"
        case .publicList: return "Публичный"
        }
    }
}

public struct TierRowData: Identifiable, Hashable, Codable, Sendable {
    public var id: TierKey { key }
    public let key: TierKey
    public var title: String
    public var colorHex: String
    public var items: [AnimeSnapshot]

    public init(key: TierKey, title: String? = nil, colorHex: String? = nil, items: [AnimeSnapshot] = []) {
        self.key = key
        self.title = title ?? key.defaultTitle
        self.colorHex = Self.normalizedHex(colorHex ?? key.defaultColorHex) ?? key.defaultColorHex
        self.items = items
    }

    public static func normalizedHex(_ raw: String) -> String? {
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "# \n\t")).uppercased()
        guard cleaned.count == 6, UInt32(cleaned, radix: 16) != nil else { return nil }
        return cleaned
    }
}

/// Персональный тир-лист пользователя (Beta).
public struct TierList: Hashable, Codable, Sendable {
    public var tiers: [TierRowData]
    public var visibility: TierListVisibility
    public var updatedAt: Date
    public var mutationID: UUID

    public init(
        tiers: [TierRowData] = TierList.defaultTiers(),
        visibility: TierListVisibility = .privateOnly,
        updatedAt: Date = Date(),
        mutationID: UUID = UUID()
    ) {
        self.tiers = Self.normalizedTiers(tiers)
        self.visibility = visibility
        self.updatedAt = Date(timeIntervalSince1970: floor(updatedAt.timeIntervalSince1970 * 1000) / 1000)
        self.mutationID = mutationID
    }

    public static func defaultTiers() -> [TierRowData] {
        TierKey.allCases.map { TierRowData(key: $0) }
    }

    public static let empty = TierList()

    public var assignedIDs: Set<Int> {
        Set(tiers.flatMap { $0.items.map(\.id) })
    }

    public var totalAssignedCount: Int {
        tiers.reduce(0) { $0 + $1.items.count }
    }

    public var isEmpty: Bool { totalAssignedCount == 0 }

    public func tier(for animeID: Int) -> TierKey? {
        tiers.first { $0.items.contains { $0.id == animeID } }?.key
    }

    public func row(for key: TierKey) -> TierRowData {
        tiers.first { $0.key == key } ?? TierRowData(key: key)
    }

    /// Перемещает тайтл в выбранный тир (удаляя из остальных, чтобы не было дубликатов).
    public mutating func assign(_ anime: AnimeSnapshot, to key: TierKey, at date: Date = Date()) {
        for index in tiers.indices {
            tiers[index].items.removeAll { $0.id == anime.id }
        }
        if let targetIndex = tiers.firstIndex(where: { $0.key == key }) {
            tiers[targetIndex].items.append(anime)
        }
        touch(at: date)
    }

    /// Убирает тайтл из тир-листа обратно в пул нераспределённых.
    public mutating func remove(_ animeID: Int, at date: Date = Date()) {
        var removed = false
        for index in tiers.indices {
            let before = tiers[index].items.count
            tiers[index].items.removeAll { $0.id == animeID }
            if tiers[index].items.count != before { removed = true }
        }
        if removed { touch(at: date) }
    }

    public mutating func updateTier(_ key: TierKey, title: String, colorHex: String, at date: Date = Date()) {
        guard let index = tiers.firstIndex(where: { $0.key == key }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        tiers[index].title = trimmed.isEmpty ? key.defaultTitle : String(trimmed.prefix(32))
        if let validHex = TierRowData.normalizedHex(colorHex) {
            tiers[index].colorHex = validHex
        }
        touch(at: date)
    }

    public mutating func setVisibility(_ newVisibility: TierListVisibility, at date: Date = Date()) {
        guard visibility != newVisibility else { return }
        visibility = newVisibility
        touch(at: date)
    }

    public func isNewer(than other: TierList) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        return mutationID.uuidString > other.mutationID.uuidString
    }

    /// Пул нераспределённых тайтлов из библиотеки пользователя.
    /// По умолчанию приоритетно подтягивает «Просмотрено» и «Смотрю», исключая уже распределённые.
    public func unassignedPool(from snapshot: LibrarySnapshot, includeAllStatuses: Bool = false) -> [LibraryEntry] {
        let assigned = assignedIDs
        if includeAllStatuses {
            return snapshot.allListEntries.filter { !assigned.contains($0.id) }
        }
        let completed = snapshot.entries(in: .completed).filter { !assigned.contains($0.id) }
        let watching = snapshot.entries(in: .watching).filter { !assigned.contains($0.id) }
        return completed + watching
    }

    private mutating func touch(at date: Date) {
        let rounded = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1000) / 1000)
        updatedAt = max(rounded, updatedAt.addingTimeInterval(0.002))
        mutationID = UUID()
    }

    private static func normalizedTiers(_ input: [TierRowData]) -> [TierRowData] {
        var seen = Set<Int>()
        return TierKey.allCases.map { key in
            let existing = input.first { $0.key == key } ?? TierRowData(key: key)
            let uniqueItems = existing.items.filter { seen.insert($0.id).inserted }
            return TierRowData(key: key, title: existing.title, colorHex: existing.colorHex, items: uniqueItems)
        }
    }
}

public struct TierListSyncDocument: Codable, Hashable, Sendable {
    public var tierList: TierList
    public var acknowledgedMutationID: UUID?

    public init(tierList: TierList = .empty, acknowledgedMutationID: UUID? = nil) {
        self.tierList = tierList
        self.acknowledgedMutationID = acknowledgedMutationID
    }

    public var needsUpload: Bool {
        acknowledgedMutationID != tierList.mutationID
    }

    public mutating func merge(_ remote: TierList?) {
        guard let remote else { return }
        acknowledgedMutationID = remote.mutationID
        if remote.mutationID == tierList.mutationID || remote.isNewer(than: tierList) {
            tierList = remote
        }
    }
}
