import Foundation

/// Temporary "hold to play at 2×" boost. Pure state, no UIKit/AVFoundation:
/// the player applies the returned rates, the UI only reports gesture start/end.
///
/// The user's own speed (settings) is never overwritten: `end` always hands back
/// the rate that was selected before the hold, even if it is not 1×.
public struct PlaybackSpeedBoost: Equatable, Sendable {
    /// Speed while the finger is held.
    public static let boostRate: Float = 2
    /// Long-press threshold (product requirement: 300–500 ms).
    public static let activationDelay: TimeInterval = 0.4
    /// Movement (pt) tolerated *before* activation. Larger travel is a swipe, not a hold.
    public static let allowableMovement: Double = 12

    /// Everything that can forbid a boost at the moment the hold is recognised.
    public struct Conditions: Equatable, Sendable {
        public var isReady: Bool
        public var isPlaying: Bool
        public var isBuffering: Bool
        public var isScrubbing: Bool
        public var isSharedWatch: Bool
        public var isBlockedByUI: Bool

        public init(isReady: Bool, isPlaying: Bool, isBuffering: Bool, isScrubbing: Bool,
                    isSharedWatch: Bool, isBlockedByUI: Bool) {
            self.isReady = isReady
            self.isPlaying = isPlaying
            self.isBuffering = isBuffering
            self.isScrubbing = isScrubbing
            self.isSharedWatch = isSharedWatch
            self.isBlockedByUI = isBlockedByUI
        }

        /// Paused, loading, buffering, seeking, synchronised rooms and open sheets never boost.
        public var allowsBoost: Bool {
            isReady && isPlaying && !isBuffering && !isScrubbing && !isSharedWatch && !isBlockedByUI
        }
    }

    public private(set) var isActive = false
    public let rate: Float

    public init(rate: Float = PlaybackSpeedBoost.boostRate) {
        self.rate = rate
    }

    /// Returns the rate to apply, or `nil` when the boost is refused or already active.
    public mutating func begin(_ conditions: Conditions) -> Float? {
        guard !isActive, conditions.allowsBoost, rate.isFinite, rate > 0 else { return nil }
        isActive = true
        return rate
    }

    /// Returns the user's rate to restore, or `nil` when there is nothing to undo.
    public mutating func end(restoring userRate: Float) -> Float? {
        guard isActive else { return nil }
        isActive = false
        return userRate.isFinite && userRate > 0 ? userRate : 1
    }

    /// Playback stopped or the item was replaced underneath the hold: forget the boost
    /// without touching the player (the new item starts at the user's speed).
    public mutating func reset() {
        isActive = false
    }
}

/// One label format for every speed shown in the app («1×», «1.25×», «2×»).
public enum PlaybackSpeedLabel {
    public static func text(_ value: Float) -> String {
        guard value.isFinite, value > 0 else { return "1×" }
        if value == value.rounded() { return String(format: "%.0f", Double(value)) + "×" }
        var text = String(format: "%.2f", Double(value))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "×"
    }
}
