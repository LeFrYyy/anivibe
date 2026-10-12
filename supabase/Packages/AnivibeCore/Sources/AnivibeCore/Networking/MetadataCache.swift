import Foundation

/// Кэш метаданных каталога с ограниченным сроком жизни (память + диск).
/// Срок жизни короткий — AniList запрещает использовать API как хранилище/архив.
public actor MetadataCache {
    private struct Item { let storedAt: Date; let data: Data }
    private var memory: [String: Item] = [:]
    private let directory: URL?
    private let ttl: TimeInterval
    private let maxMemoryItems: Int
    private let now: @Sendable () -> Date

    public init(directory: URL?, ttl: TimeInterval = 6 * 3600, maxMemoryItems: Int = 200, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.ttl = ttl
        self.maxMemoryItems = maxMemoryItems
        self.now = now
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }

    public func data(for key: String) -> Data? {
        let current = now()
        if let item = memory[key] {
            if current.timeIntervalSince(item.storedAt) < ttl { return item.data }
            memory[key] = nil
        }
        guard let url = fileURL(for: key),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        guard current.timeIntervalSince(modified) < ttl, let data = try? Data(contentsOf: url) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        memory[key] = Item(storedAt: modified, data: data)
        return data
    }

    public func store(_ data: Data, for key: String) {
        if memory.count >= maxMemoryItems, let oldest = memory.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            memory[oldest] = nil
        }
        let current = now()
        memory[key] = Item(storedAt: current, data: data)
        if let url = fileURL(for: key) {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.modificationDate: current], ofItemAtPath: url.path)
        }
    }

    public func removeAll() {
        memory.removeAll()
        if let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            files.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    private func fileURL(for key: String) -> URL? {
        directory?.appendingPathComponent("\(StableHash.fnv1a(key)).json")
    }
}
