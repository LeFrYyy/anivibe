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

/// Именованный тир-лист: у пользователя может быть несколько (максимум `TierListSet.maxLists`).
public struct NamedTierList: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var list: TierList

    public init(id: UUID = UUID(), name: String, list: TierList = .empty) {
        self.id = id
        self.name = name
        self.list = list
    }
}

/// Набор персональных тир-листов пользователя (Beta).
/// Ограничение — не более `maxLists` списков; дублируется CHECK-ограничением на сервере.
public struct TierListSet: Hashable, Codable, Sendable {
    public static let maxLists = 5
    public static let maxNameLength = 40

    public var lists: [NamedTierList]
    public var activeListID: UUID?
    public var updatedAt: Date
    public var mutationID: UUID

    public init(
        lists: [NamedTierList] = [],
        activeListID: UUID? = nil,
        updatedAt: Date = Date(),
        mutationID: UUID = UUID()
    ) {
        self.lists = Array(lists.prefix(Self.maxLists))
        self.activeListID = activeListID
        self.updatedAt = Date(timeIntervalSince1970: floor(updatedAt.timeIntervalSince1970 * 1000) / 1000)
        self.mutationID = mutationID
        if self.lists.isEmpty {
            self.activeListID = nil
        } else if self.activeListID == nil || !self.lists.contains(where: { $0.id == self.activeListID }) {
            self.activeListID = self.lists.first?.id
        }
    }

    /// Обратная совместимость: старый формат — одиночный `TierList`, оборачивается в именованный список.
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let decoded = try container.decodeIfPresent([NamedTierList].self, forKey: .lists) {
            self.init(lists: decoded,
                      activeListID: try container.decodeIfPresent(UUID.self, forKey: .activeListID),
                      updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(),
                      mutationID: try container.decodeIfPresent(UUID.self, forKey: .mutationID) ?? UUID())
            return
        }
        let legacy = try TierList(from: decoder)
        let named = NamedTierList(name: Self.defaultListName(for: 1), list: legacy)
        self.init(lists: [named], activeListID: named.id, updatedAt: legacy.updatedAt, mutationID: legacy.mutationID)
    }

    public static func defaultListName(for index: Int) -> String {
        "Тир-лист \(index)"
    }

    public static func normalizedName(_ raw: String, fallbackIndex: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return defaultListName(for: fallbackIndex) }
        return String(trimmed.prefix(maxNameLength))
    }

    public static let empty = TierListSet()

    public var activeList: NamedTierList? {
        if let id = activeListID, let found = lists.first(where: { $0.id == id }) { return found }
        return lists.first
    }

    /// Содержимое активного списка — для обратной совместимости UI.
    public var tierList: TierList { activeList?.list ?? .empty }

    public func list(id: UUID) -> NamedTierList? {
        lists.first { $0.id == id }
    }

    /// Создаёт новый именованный список и делает его активным. `nil`, если достигнут лимит.
    @discardableResult
    public mutating func createList(name: String = "", at date: Date = Date()) -> NamedTierList? {
        guard lists.count < Self.maxLists else { return nil }
        let named = NamedTierList(name: Self.normalizedName(name, fallbackIndex: lists.count + 1))
        lists.append(named)
        activeListID = named.id
        touch(at: date)
        return named
    }

    public mutating func renameList(_ id: UUID, name: String, at date: Date = Date()) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        let fallback = lists.indices.contains(index) ? index + 1 : 1
        let normalized = Self.normalizedName(name, fallbackIndex: fallback)
        guard lists[index].name != normalized else { return }
        lists[index].name = normalized
        touch(at: date)
    }

    public mutating func deleteList(_ id: UUID, at date: Date = Date()) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists.remove(at: index)
        if activeListID == id { activeListID = lists.first?.id }
        touch(at: date)
    }

    /// Переключение активного списка — локальное действие, не требует выгрузки.
    public mutating func selectList(_ id: UUID) {
        guard lists.contains(where: { $0.id == id }) else { return }
        activeListID = id
    }

    /// Мутация содержимого активного списка (assign/remove/updateTier/setVisibility).
    public mutating func mutateActive(at date: Date = Date(), _ work: (inout TierList) -> Void) {
        guard let id = activeList?.id, let index = lists.firstIndex(where: { $0.id == id }) else { return }
        work(&lists[index].list)
        touch(at: date)
    }

    public func isNewer(than other: TierListSet) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        return mutationID.uuidString > other.mutationID.uuidString
    }

    private mutating func touch(at date: Date) {
        let rounded = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1000) / 1000)
        updatedAt = max(rounded, updatedAt.addingTimeInterval(0.002))
        mutationID = UUID()
    }
}

public struct TierListSyncDocument: Codable, Hashable, Sendable {
    public var set: TierListSet
    public var acknowledgedMutationID: UUID?

    public init(set: TierListSet = .empty, acknowledgedMutationID: UUID? = nil) {
        self.set = set
        self.acknowledgedMutationID = acknowledgedMutationID
    }

    private enum CodingKeys: String, CodingKey {
        case set
        case tierList // legacy-ключ старого формата (одиночный TierList)
        case acknowledgedMutationID
    }

    /// Обратная совместимость файла: старый формат хранил `tierList` (одиночный TierList).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decoded = try container.decodeIfPresent(TierListSet.self, forKey: .set) {
            set = decoded
        } else if let legacy = try container.decodeIfPresent(TierListSet.self, forKey: .tierList) {
            set = legacy
        } else {
            set = .empty
        }
        acknowledgedMutationID = try container.decodeIfPresent(UUID.self, forKey: .acknowledgedMutationID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(set, forKey: .set)
        try container.encodeIfPresent(acknowledgedMutationID, forKey: .acknowledgedMutationID)
    }

    public var needsUpload: Bool {
        acknowledgedMutationID != set.mutationID
    }

    public mutating func merge(_ remote: TierListSet?) {
        guard let remote else { return }
        acknowledgedMutationID = remote.mutationID
        if remote.mutationID == set.mutationID || remote.isNewer(than: set) {
            set = remote
        }
    }
}
