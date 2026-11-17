import Foundation
import XCTest
@testable import AnivibeCore

final class FeatureUpdate202611Tests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testStrictLibraryStatusFilteringAndLabels() {
        XCTAssertEqual(LibraryStatus.planned.localizedName, "В планах")
        let entries = [
            LibraryEntry(anime: AnimeSnapshot(id: 1, title: "Watching"), status: .watching, updatedAt: baseDate),
            LibraryEntry(anime: AnimeSnapshot(id: 2, title: "Completed"), status: .completed, updatedAt: baseDate.addingTimeInterval(10)),
            LibraryEntry(anime: AnimeSnapshot(id: 3, title: "Planned"), status: .planned, updatedAt: baseDate.addingTimeInterval(20)),
            LibraryEntry(anime: AnimeSnapshot(id: 4, title: "OnHold"), status: .onHold, updatedAt: baseDate.addingTimeInterval(30)),
            LibraryEntry(anime: AnimeSnapshot(id: 5, title: "Dropped"), status: .dropped, updatedAt: baseDate.addingTimeInterval(40)),
            LibraryEntry(anime: AnimeSnapshot(id: 6, title: "FavOnly"), status: nil, isFavorite: true, updatedAt: baseDate.addingTimeInterval(50)),
            LibraryEntry(anime: AnimeSnapshot(id: 7, title: "Deleted"), status: .watching, updatedAt: baseDate.addingTimeInterval(60), isDeleted: true),
            LibraryEntry(anime: AnimeSnapshot(id: 8, title: "Empty"), status: nil, isFavorite: false, updatedAt: baseDate.addingTimeInterval(70))
        ]
        let snapshot = LibrarySnapshot(entries: entries)

        XCTAssertEqual(snapshot.entries(in: .watching).map(\.id), [1])
        XCTAssertEqual(snapshot.entries(in: .completed).map(\.id), [2])
        XCTAssertEqual(snapshot.entries(in: .planned).map(\.id), [3])
        XCTAssertEqual(snapshot.entries(in: .onHold).map(\.id), [4])
        XCTAssertEqual(snapshot.entries(in: .dropped).map(\.id), [5])
        XCTAssertEqual(snapshot.allListEntries.map(\.id), [6, 5, 4, 3, 2, 1])

        let counts = snapshot.statusCounts
        XCTAssertEqual(counts[.watching], 1)
        XCTAssertEqual(counts[.completed], 1)
        XCTAssertEqual(counts[.planned], 1)
        XCTAssertEqual(counts[.onHold], 1)
        XCTAssertEqual(counts[.dropped], 1)
    }

    func testRecentEpisodesCoversSevenDaysPaginatesAndSortsNewestFirst() async throws {
        let nowStamp = 1_800_000_000 / 600 * 600
        let sixDaysAgo = nowStamp - 6 * 24 * 3600
        let eightDaysAgo = nowStamp - 8 * 24 * 3600
        let oneHourAgo = nowStamp - 3600

        let transport = StubTransport { request in
            let vars = request.bodyJSON["variables"] as? [String: Any] ?? [:]
            let page = vars["page"] as? Int ?? 1
            let from = vars["from"] as? Int ?? 0
            XCTAssertEqual(from, nowStamp - 7 * 24 * 3600, "Окно должно быть ровно 7 дней (168 часов)")

            let body: String
            if page == 1 {
                body = """
                {"data": {"Page": {
                  "pageInfo": {"currentPage": 1, "hasNextPage": true},
                  "airingSchedules": [
                    {"episode": 4, "airingAt": \(oneHourAgo), "media": \(Fixtures.mediaJSON(id: 10, english: "Fresh", romaji: "Fresh", extra: ", \"popularity\": 1200"))},
                    {"episode": 2, "airingAt": \(oneHourAgo - 7200), "media": \(Fixtures.mediaJSON(id: 11, english: "LowPop", romaji: "LowPop", extra: ", \"popularity\": 100"))}
                  ]
                }}}
                """
            } else {
                body = """
                {"data": {"Page": {
                  "pageInfo": {"currentPage": 2, "hasNextPage": false},
                  "airingSchedules": [
                    {"episode": 7, "airingAt": \(sixDaysAgo), "media": \(Fixtures.mediaJSON(id: 12, english: "WeekOld", romaji: "WeekOld", extra: ", \"popularity\": 900"))},
                    {"episode": 3, "airingAt": \(sixDaysAgo), "media": \(Fixtures.mediaJSON(id: 10, english: "Fresh", romaji: "Fresh", extra: ", \"popularity\": 1200"))},
                    {"episode": 1, "airingAt": \(eightDaysAgo), "media": \(Fixtures.mediaJSON(id: 13, english: "TooOld", romaji: "TooOld", extra: ", \"popularity\": 2000"))}
                  ]
                }}}
                """
            }
            return (200, Data(body.utf8), [:])
        }

        let service = AniListCatalogService(
            transport: transport,
            cache: MetadataCache(directory: nil, ttl: 3600),
            limiter: RateLimiter(limit: 100, per: 60),
            now: { Date(timeIntervalSince1970: TimeInterval(nowStamp)) }
        )
        let list = try await service.recentEpisodes()

        XCTAssertEqual(transport.requests.count, 2, "Должна загрузиться 2-я страница по hasNextPage")
        XCTAssertEqual(list.map(\.anime.id), [10, 12])
        XCTAssertEqual(list.first?.episode, 4, "Для одного тайтла сохраняется самая свежая серия")
        XCTAssertGreaterThan(list[0].airedAt, list[1].airedAt)
    }

    func testTierListAssignMovePoolAndSyncMerge() throws {
        let a = AnimeSnapshot(id: 101, title: "Frieren")
        let b = AnimeSnapshot(id: 102, title: "Dandadan")
        let c = AnimeSnapshot(id: 103, title: "PlanTitle")

        var list = TierList.empty
        XCTAssertEqual(list.tiers.map(\.key), [.s, .a, .b, .c, .d])
        XCTAssertEqual(list.visibility, .privateOnly)

        list.assign(a, to: .s, at: baseDate)
        list.assign(b, to: .a, at: baseDate.addingTimeInterval(1))
        // Перенос в другой тир не создаёт дублей
        list.assign(a, to: .b, at: baseDate.addingTimeInterval(2))
        XCTAssertTrue(list.row(for: .s).items.isEmpty)
        XCTAssertEqual(list.row(for: .b).items.map(\.id), [101])
        XCTAssertEqual(list.totalAssignedCount, 2)

        list.updateTier(.s, title: "Легенды", colorHex: "#112233", at: baseDate.addingTimeInterval(3))
        XCTAssertEqual(list.row(for: .s).title, "Легенды")
        XCTAssertEqual(list.row(for: .s).colorHex, "112233")

        list.setVisibility(.publicList, at: baseDate.addingTimeInterval(4))
        XCTAssertEqual(list.visibility, .publicList)

        let snapshot = LibrarySnapshot(entries: [
            LibraryEntry(anime: a, status: .completed),
            LibraryEntry(anime: b, status: .watching),
            LibraryEntry(anime: c, status: .planned)
        ])
        // Оба (a, b) уже распределены — основной пул пуст, расширенный содержит c
        XCTAssertTrue(list.unassignedPool(from: snapshot, includeAllStatuses: false).isEmpty)
        XCTAssertEqual(list.unassignedPool(from: snapshot, includeAllStatuses: true).map(\.id), [103])

        list.remove(b.id, at: baseDate.addingTimeInterval(5))
        XCTAssertEqual(list.unassignedPool(from: snapshot, includeAllStatuses: false).map(\.id), [102])

        // LWW sync roundtrip
        let data = try SupabaseSyncService.encoder.encode(list)
        let decoded = try SupabaseSyncService.decoder.decode(TierList.self, from: data)
        XCTAssertEqual(decoded.row(for: .s).title, "Легенды")
        XCTAssertEqual(decoded.visibility, .publicList)
        XCTAssertEqual(decoded.row(for: .b).items.map(\.id), [101])

        var syncDoc = TierListSyncDocument(set: .empty)
        syncDoc.merge(TierListSet(lists: [NamedTierList(name: "A", list: decoded)],
                                updatedAt: decoded.updatedAt, mutationID: decoded.mutationID))
        XCTAssertEqual(syncDoc.set.tierList.row(for: .b).items.map(\.id), [101])
        XCTAssertFalse(syncDoc.needsUpload)
    }

    func testTierListSetCrudLimitAndLegacyDecode() throws {
        // Legacy: одиночный TierList оборачивается в именованный список.
        var legacy = TierList.empty
        legacy.assign(AnimeSnapshot(id: 55, title: "Legacy"), to: .s, at: baseDate)
        let legacyData = try SupabaseSyncService.encoder.encode(legacy)
        let migrated = try SupabaseSyncService.decoder.decode(TierListSet.self, from: legacyData)
        XCTAssertEqual(migrated.lists.count, 1)
        XCTAssertEqual(migrated.lists[0].name, "Тир-лист 1")
        XCTAssertEqual(migrated.lists[0].list.row(for: .s).items.map(\.id), [55])
        XCTAssertEqual(migrated.activeList?.id, migrated.lists[0].id)

        // CRUD + лимит 5.
        var set = TierListSet.empty
        XCTAssertNil(set.activeList)
        for i in 1...TierListSet.maxLists {
            XCTAssertNotNil(set.createList(name: "Список \(i)", at: baseDate.addingTimeInterval(TimeInterval(i))))
        }
        XCTAssertEqual(set.lists.count, TierListSet.maxLists)
        XCTAssertNil(set.createList(name: "Лишний", at: baseDate.addingTimeInterval(9)), "Шестой список не создаётся")

        let first = set.lists[0]
        set.renameList(first.id, name: "  Сёнэны  ", at: baseDate.addingTimeInterval(10))
        XCTAssertEqual(set.list(id: first.id)?.name, "Сёнэны")

        // Пустое имя → дефолтное по индексу.
        set.renameList(first.id, name: "   ", at: baseDate.addingTimeInterval(11))
        XCTAssertEqual(set.list(id: first.id)?.name, "Тир-лист 1")

        // Переключение активного — локально, без смены updatedAt.
        let before = set.updatedAt
        set.selectList(set.lists[2].id)
        XCTAssertEqual(set.activeList?.id, set.lists[2].id)
        XCTAssertEqual(set.updatedAt, before)

        // Удаление активного → активным становится первый из оставшихся.
        let activeID = set.activeList!.id
        set.deleteList(activeID, at: baseDate.addingTimeInterval(12))
        XCTAssertEqual(set.lists.count, TierListSet.maxLists - 1)
        XCTAssertEqual(set.activeList?.id, set.lists[0].id)

        // Мутации идут в активный список.
        set.mutateActive(at: baseDate.addingTimeInterval(13)) { $0.assign(AnimeSnapshot(id: 77, title: "X"), to: .a) }
        XCTAssertEqual(set.tierList.row(for: .a).items.map(\.id), [77])

        // Roundtrip нового формата.
        let data = try SupabaseSyncService.encoder.encode(set)
        let decoded = try SupabaseSyncService.decoder.decode(TierListSet.self, from: data)
        XCTAssertEqual(decoded.lists.count, set.lists.count)
        XCTAssertEqual(decoded.activeList?.id, set.activeList?.id)
        XCTAssertEqual(decoded.tierList.row(for: .a).items.map(\.id), [77])

        // Legacy-формат sync-документа: { tierList: {...} } читается как список.
        struct LegacyDoc: Encodable { let tierList: TierList; let acknowledgedMutationID: UUID? }
        let docData = try SupabaseSyncService.encoder.encode(LegacyDoc(tierList: legacy, acknowledgedMutationID: nil))
        let doc = try SupabaseSyncService.decoder.decode(TierListSyncDocument.self, from: docData)
        XCTAssertEqual(doc.set.lists.count, 1)
        XCTAssertEqual(doc.set.tierList.row(for: .s).items.map(\.id), [55])
        XCTAssertTrue(doc.needsUpload)
    }
}
