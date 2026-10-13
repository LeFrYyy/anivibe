import XCTest
@testable import AnivibeCore
final class CollectionOrderTests: XCTestCase {
    func testMoveFoldersAndItemsPersistAndRejectInvalidOffsets() throws {
        var state = AnimeCollections()
        let a = state.create(name: "A"), b = state.create(name: "B"), c = state.create(name: "C")
        state.moveCollection(a, to: c)
        XCTAssertEqual(state.collections.map(\.id), [b, c, a])
        for id in [1, 2, 3] { state.add(.init(id: id, title: "T\(id)"), to: a) }
        state.moveItem(3, in: a, to: 1)
        XCTAssertEqual(state.collection(a)?.items.map(\.id), [2, 1, 3])
        let saved = try JSONDecoder().decode(AnimeCollections.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(saved, state)
        state.moveItems(in: a, from: IndexSet(integer: 999), to: 0)
        XCTAssertEqual(state, saved)
        state.remove(1, from: a)
        XCTAssertEqual(state.collection(a)?.items.map(\.id), [2, 3])
        state.moveCollection(UUID(), to: a)
        XCTAssertEqual(state.collections.map(\.id), [b, c, a])
    }
}
