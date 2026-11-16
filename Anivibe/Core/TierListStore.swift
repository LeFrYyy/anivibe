import Foundation
import AnivibeCore

/// Локальное хранилище персонального тир-листа (отдельно для гостя и каждого аккаунта).
@Observable
@MainActor
final class TierListStore {
    private(set) var tierList: TierList = .empty
    private(set) var activeAccountID: String?
    private(set) var errorMessage: String?
    @ObservationIgnored var onLocalChange: (@MainActor () -> Void)?
    @ObservationIgnored private var document = TierListSyncDocument()
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private let directory: URL?

    struct Prepared {
        let document: TierListSyncDocument
        let url: URL
    }

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Anivibe", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        do {
            activate(try prepareAccount(nil), userID: nil)
        } catch {
            canSave = false
            errorMessage = "Файл тир-листа не удалось открыть. Исходный файл сохранён."
        }
    }

    func prepareAccount(_ userID: String?) throws -> Prepared {
        guard let directory else { throw APIError.badRequest("Хранилище тир-листа недоступно") }
        let filename: String
        if let userID {
            guard UUID(uuidString: userID) != nil else { throw APIError.badRequest("Некорректный ID аккаунта") }
            filename = "tierlist-user-" + userID.lowercased() + ".json"
        } else {
            filename = "tierlist.json"
        }
        let url = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Prepared(document: TierListSyncDocument(), url: url)
        }
        let data = try Data(contentsOf: url)
        let doc = try JSONDecoder().decode(TierListSyncDocument.self, from: data)
        return Prepared(document: doc, url: url)
    }

    func activate(_ prepared: Prepared, userID: String?) {
        activeAccountID = userID
        fileURL = prepared.url
        document = prepared.document
        tierList = prepared.document.tierList
        canSave = true
        errorMessage = nil
    }

    func clearVisibleOnAccountFailure() {
        activeAccountID = nil
        tierList = .empty
        document = TierListSyncDocument()
        canSave = false
        errorMessage = "Тир-лист не удалось открыть. Исходные файлы сохранены."
    }

    // MARK: - Mutations

    func assign(_ anime: AnimeSnapshot, to key: TierKey) {
        mutate { $0.assign(anime, to: key) }
    }

    func remove(_ animeID: Int) {
        mutate { $0.remove(animeID) }
    }

    func updateTier(_ key: TierKey, title: String, colorHex: String) {
        mutate { $0.updateTier(key, title: title, colorHex: colorHex) }
    }

    func setVisibility(_ visibility: TierListVisibility) {
        mutate { $0.setVisibility(visibility) }
    }

    private func mutate(_ work: (inout TierList) -> Void) {
        guard canSave else { return }
        var next = tierList
        work(&next)
        guard next != tierList || errorMessage != nil else { return }
        tierList = next
        document.tierList = next
        do {
            try persist()
            onLocalChange?()
        } catch {
            errorMessage = "Не удалось сохранить тир-лист на устройство."
        }
    }

    private func persist() throws {
        guard canSave, let fileURL else { throw APIError.badRequest("Хранилище тир-листа недоступно") }
        let data = try JSONEncoder().encode(document)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        errorMessage = nil
    }

    // MARK: - Sync

    func payloadForSync(accountID: String) throws -> TierList? {
        guard activeAccountID == accountID, canSave, errorMessage == nil else { return nil }
        return document.needsUpload ? document.tierList : nil
    }

    func mergeRemote(_ remote: TierList?, accountID: String) throws {
        guard activeAccountID == accountID, canSave else { throw AuthError.notSignedIn }
        guard let remote else { return }
        let previous = document
        document.merge(remote)
        do {
            try persist()
            tierList = document.tierList
        } catch {
            document = previous
            errorMessage = "Не удалось сохранить тир-лист после синхронизации."
            throw error
        }
    }
}
