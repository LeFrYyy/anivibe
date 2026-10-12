import XCTest
@testable import AnivibeCore

final class CollectionsTests: XCTestCase {
    private let a = AnimeSnapshot(id: 1, title: "A")
    private let b = AnimeSnapshot(id: 2, title: "B")
    private let c = AnimeSnapshot(id: 3, title: "C")

    func testCreateUniqueNamesAndDefault() {
        var s = AnimeCollections()
        _ = s.create(name: "  ")
        _ = s.create(name: "Новая папка")
        _ = s.create(name: "Новая папка")
        XCTAssertEqual(s.collections.map(\.name), ["Новая папка", "Новая папка 2", "Новая папка 3"])
    }

    func testAddRemoveToggleNoDuplicates() {
        var s = AnimeCollections()
        let id = s.create(name: "Топ", with: a)
        s.add(b, to: id)
        s.add(b, to: id)
        XCTAssertEqual(s.collection(id)?.items.map(\.id), [2, 1])
        s.toggle(a, in: id)
        XCTAssertEqual(s.collection(id)?.items.map(\.id), [2])
        s.toggle(a, in: id)
        XCTAssertTrue(s.collection(id)?.contains(1) ?? false)
        s.remove(2, from: id)
        XCTAssertEqual(s.collection(id)?.items.map(\.id), [1])
    }

    func testRenameDeleteMoveAndCodable() throws {
        var s = AnimeCollections()
        let id = s.create(name: "X")
        s.add(c, to: id); s.add(b, to: id); s.add(a, to: id) // [1,2,3]
        s.moveItems(in: id, from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(s.collection(id)?.items.map(\.id), [2, 3, 1])
        s.rename(id, to: "  Любимое ")
        s.rename(id, to: "   ")
        XCTAssertEqual(s.collection(id)?.name, "Любимое")
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(AnimeCollections.self, from: data), s)
        s.delete(id)
        XCTAssertTrue(s.collections.isEmpty)
    }
}
