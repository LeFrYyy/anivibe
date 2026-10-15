import Foundation

/// Постоянное хранилище состояния библиотеки.
public protocol LibraryPersistence: Sendable {
    func load() throws -> LibrarySnapshot
    func save(_ snapshot: LibrarySnapshot) throws
}

/// JSON-файл в Application Support с атомарной записью.
/// Выбран вместо SwiftData, чтобы одна и та же проверенная тестами логика
/// работала на всех платформах и легко сериализовалась для синхронизации.
public struct FileLibraryPersistence: LibraryPersistence {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultLocation(fileManager: FileManager = .default) throws -> FileLibraryPersistence {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Anivibe", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return FileLibraryPersistence(fileURL: dir.appendingPathComponent("library.json"))
    }

    public func load() throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        let data = try Data(contentsOf: fileURL)
        let snapshot = try Self.decoder.decode(LibrarySnapshot.self, from: data)
        return snapshot
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        e.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(formatter.string(from: date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let legacy = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: value) ?? legacy.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid library date: \(value)"))
        }
        return d
    }
}

/// Хранилище в памяти (тесты и превью).
public final class InMemoryLibraryPersistence: LibraryPersistence, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LibrarySnapshot
    public private(set) var saveCount = 0

    public init(_ snapshot: LibrarySnapshot = .empty) {
        stored = snapshot
    }

    public func load() throws -> LibrarySnapshot {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ snapshot: LibrarySnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        stored = snapshot
        saveCount += 1
    }
}
