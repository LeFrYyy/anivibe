import SwiftUI
import UniformTypeIdentifiers

struct CollectionDropDelegate: DropDelegate {
    let targetID: String
    @Binding var draggedID: String?
    let move: (String, String) -> Void
    func validateDrop(info: DropInfo) -> Bool { draggedID != nil }
    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { move(draggedID, targetID) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { draggedID = nil; return true }
}
