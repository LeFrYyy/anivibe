import Foundation

/// Пользовательская папка с аниме на главной (как папки приложений в iOS).
public struct AnimeCollection: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var items: [AnimeSnapshot]
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, items: [AnimeSnapshot] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = createdAt
    }

    public func contains(_ animeID: Int) -> Bool { items.contains { $0.id == animeID } }
}

/// Чистая логика папок: создание, переименование, добавление/удаление/перестановка аниме.
public struct AnimeCollections: Hashable, Codable, Sendable {
    public private(set) var collections: [AnimeCollection]

    public init(collections: [AnimeCollection] = []) {
        self.collections = collections
    }

    /// Пустое имя превращается в «Новая папка», повтор имени — в «Имя 2», «Имя 3»…
    public mutating func create(name: String, with first: AnimeSnapshot? = nil) -> UUID {
        let collection = AnimeCollection(name: uniqueName(for: name), items: first.map { [$0] } ?? [])
        collections.append(collection)
        return collection.id
    }

    public mutating func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = index(id) else { return }
        collections[i].name = trimmed
    }

    public mutating func delete(_ id: UUID) {
        collections.removeAll { $0.id == id }
    }

    /// Добавляет аниме в начало папки (если его там ещё нет).
    public mutating func add(_ anime: AnimeSnapshot, to id: UUID) {
        guard let i = index(id), !collections[i].contains(anime.id) else { return }
        collections[i].items.insert(anime, at: 0)
    }

    public mutating func remove(_ animeID: Int, from id: UUID) {
        guard let i = index(id) else { return }
        collections[i].items.removeAll { $0.id == animeID }
    }

    /// Добавить, если нет; убрать, если есть.
    public mutating func toggle(_ anime: AnimeSnapshot, in id: UUID) {
        guard let i = index(id) else { return }
        if collections[i].contains(anime.id) { remove(anime.id, from: id) } else { add(anime, to: id) }
    }

    public mutating func moveItems(in id: UUID, from source: IndexSet, to destination: Int) {
        guard let i = index(id) else { return }
        var items = collections[i].items
        guard source.allSatisfy({ items.indices.contains($0) }), (0...items.count).contains(destination) else { return }
        let moving = source.sorted().map { items[$0] }
        for offset in source.sorted(by: >) { items.remove(at: offset) }
        let shift = source.filter { $0 < destination }.count
        items.insert(contentsOf: moving, at: max(0, min(items.count, destination - shift)))
        collections[i].items = items
    }

    public mutating func moveCollection(_ id: UUID, to targetID: UUID) {
        guard id != targetID, let from = index(id), let to = index(targetID) else { return }
        let folder = collections.remove(at: from)
        collections.insert(folder, at: to)
    }
    public mutating func moveItem(_ animeID: Int, in id: UUID, to targetID: Int) {
        guard let i = index(id), animeID != targetID,
              let from = collections[i].items.firstIndex(where: { $0.id == animeID }),
              let to = collections[i].items.firstIndex(where: { $0.id == targetID }) else { return }
        let anime = collections[i].items.remove(at: from)
        collections[i].items.insert(anime, at: to)
    }

    public func collection(_ id: UUID) -> AnimeCollection? { collections.first { $0.id == id } }

    private func index(_ id: UUID) -> Int? { collections.firstIndex { $0.id == id } }

    private func uniqueName(for raw: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Новая папка" : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = Set(collections.map { $0.name.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        var n = 2
        while names.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}

/// Sync unit is one whole folder (name + ordered items). Concurrent edits of the
/// same folder use timestamp/mutation-ID LWW; different folders merge independently.
public struct CollectionSyncRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { folder.id }
    public var folder: AnimeCollection
    public var rank: Int
    public var updatedAt: Date
    public var mutationID: UUID
    public var isDeleted: Bool
    public init(folder: AnimeCollection, rank: Int, updatedAt: Date = Date(), mutationID: UUID = UUID(), isDeleted: Bool = false) {
        self.folder = folder; self.rank = rank; self.updatedAt = Date(timeIntervalSince1970: floor(updatedAt.timeIntervalSince1970 * 1000) / 1000); self.mutationID = mutationID; self.isDeleted = isDeleted
    }
    public func isNewer(than other: Self) -> Bool {
        updatedAt != other.updatedAt ? updatedAt > other.updatedAt : mutationID.uuidString > other.mutationID.uuidString
    }
}
public struct CollectionsSyncState: Codable, Hashable, Sendable {
    public var records: [CollectionSyncRecord]
    public var acknowledgedMutations: [String: UUID]?
    public init(records: [CollectionSyncRecord] = []) { self.records = records; self.acknowledgedMutations = nil }
    public var recordsToUpload: [CollectionSyncRecord] {
        records.filter { acknowledgedMutations?[$0.id.uuidString] != $0.mutationID }
    }
    public var visible: AnimeCollections {
        AnimeCollections(collections: records.filter { !$0.isDeleted }.sorted {
            $0.rank != $1.rank ? $0.rank < $1.rank : $0.id.uuidString < $1.id.uuidString
        }.map(\.folder))
    }
    public mutating func capture(_ state: AnimeCollections, at date: Date = Date()) {
        let time = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1000) / 1000)
        let live = Set(state.collections.map(\.id))
        for i in records.indices where !records[i].isDeleted && !live.contains(records[i].id) {
            records[i].isDeleted = true; records[i].updatedAt = max(time, records[i].updatedAt.addingTimeInterval(0.002)); records[i].mutationID = UUID()
        }
        for (rank, folder) in state.collections.enumerated() {
            if let i = records.firstIndex(where: { $0.id == folder.id }) {
                if records[i].folder != folder || records[i].rank != rank || records[i].isDeleted {
                    records[i] = CollectionSyncRecord(folder: folder, rank: rank, updatedAt: max(time, records[i].updatedAt.addingTimeInterval(0.002)))
                }
            } else { records.append(CollectionSyncRecord(folder: folder, rank: rank, updatedAt: date)) }
        }
    }
    public mutating func merge(_ remote: [CollectionSyncRecord]) {
        var acknowledged = acknowledgedMutations ?? [:]
        for record in remote {
            acknowledged[record.id.uuidString] = record.mutationID
            if let i = records.firstIndex(where: { $0.id == record.id }) {
                if record.mutationID == records[i].mutationID || record.isNewer(than: records[i]) { records[i] = record }
            } else { records.append(record) }
        }
        acknowledgedMutations = acknowledged
    }
}
