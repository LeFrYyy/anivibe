import Foundation

/// Auto-hide deadline. Menus, sheets, seeking, loading and buffering are blockers.
public struct PlaybackControlsState: Equatable, Sendable {
    public private(set) var isVisible = true
    public private(set) var deadline: Date?
    public let delay: TimeInterval
    public init(delay: TimeInterval = 3.5) { self.delay = delay }
    public mutating func interact(at now: Date, blocked: Bool) {
        isVisible = true
        deadline = blocked ? nil : now.addingTimeInterval(delay)
    }
    public mutating func toggle(at now: Date, blocked: Bool) {
        if blocked { interact(at: now, blocked: true); return }
        isVisible.toggle()
        deadline = isVisible ? now.addingTimeInterval(delay) : nil
    }
    public mutating func tick(at now: Date, playing: Bool, blocked: Bool) {
        guard playing, !blocked, let deadline, now >= deadline else { return }
        isVisible = false
        self.deadline = nil
    }
}
