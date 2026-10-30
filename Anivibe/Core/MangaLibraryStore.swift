import Foundation
import AnivibeCore

/// Локальное отслеживание чтения манги: статус + прочитанные главы.
/// Хранится в UserDefaults (ключ `mangaLibrary.v1`), отдельно от аниме-библиотеки,
/// которая считает эпизоды и синхронизируется с аккаунтом.
@Observable
@MainActor
final class MangaLibraryStore {
    /// Статус чтения — аналог `LibraryStatus`, но для манги.
    enum ReadStatus: String, Codable, CaseIterable, Sendable {
        case reading, completed, planned, onHold, dropped

        var localizedName: String {
            switch self {
            case .reading: return "Читаю"
            case .completed: return "Прочитано"
            case .planned: return "Запланировано"
            case .onHold: return "Отложено"
            case .dropped: return "Брошено"
            }
        }
    }

    struct Record: Codable, Hashable, Sendable {
        var status: ReadStatus?
        var readChapterIDs: [String] = []
        var lastChapterID: String?
    }

    private(set) var records: [Int: Record] = [:]
    private let storageKey = "mangaLibrary.v1"

    init(defaults: UserDefaults = .standard, storageKey: String = "mangaLibrary.v1") {
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Int: Record].self, from: data) {
            records = decoded
        }
        self.defaults = defaults
    }

    private let defaults: UserDefaults

    func record(for mangaID: Int) -> Record { records[mangaID] ?? Record() }
    func status(for mangaID: Int) -> ReadStatus? { records[mangaID]?.status }
    func readCount(for mangaID: Int) -> Int { records[mangaID]?.readChapterIDs.count ?? 0 }
    func lastChapterID(for mangaID: Int) -> String? { records[mangaID]?.lastChapterID }
    func isRead(_ mangaID: Int, chapterID: String) -> Bool {
        records[mangaID]?.readChapterIDs.contains(chapterID) ?? false
    }

    func setStatus(_ status: ReadStatus?, for mangaID: Int) {
        var record = self.record(for: mangaID)
        record.status = status
        if status == .completed, record.lastChapterID == nil {
            record.lastChapterID = record.readChapterIDs.last
        }
        records[mangaID] = record
        save()
    }

    /// Отмечает главу прочитанной и запоминает её как последнюю; пустой статус → «Читаю».
    func markChapterRead(_ mangaID: Int, chapter: MangaChapter) {
        var record = self.record(for: mangaID)
        if !record.readChapterIDs.contains(chapter.id) {
            record.readChapterIDs.append(chapter.id)
        }
        record.lastChapterID = chapter.id
        if record.status == nil { record.status = .reading }
        records[mangaID] = record
        save()
    }

    /// Отмечает все переданные главы прочитанными (статус «Прочитано»).
    func markAllRead(_ mangaID: Int, chapters: [MangaChapter]) {
        var record = self.record(for: mangaID)
        record.readChapterIDs = chapters.map(\.id)
        record.lastChapterID = chapters.last?.id
        record.status = .completed
        records[mangaID] = record
        save()
    }

    /// Первая непрочитанная глава в отсортированном списке, иначе первая.
    func resumeChapter(_ mangaID: Int, in chapters: [MangaChapter]) -> MangaChapter? {
        let record = records[mangaID]
        return chapters.first { !(record?.readChapterIDs.contains($0.id) ?? false) && $0.externalURL == nil }
            ?? chapters.first { $0.externalURL == nil }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
