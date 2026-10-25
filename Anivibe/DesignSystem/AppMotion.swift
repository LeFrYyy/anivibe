import SwiftUI

/// One motion language: quiet presses, quick fades and a restrained panel spring.
/// Every caller respects Reduce Motion; only the temporary speed HUD pulses while held.
enum AppMotion {
    static func press(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.9)
    }

    static func selection(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)
    }

    static func panel(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9)
    }

    static func fade(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }

    static let hudPulseStep: Animation = .easeInOut(duration: 0.42)

    static func hudTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94))
    }

    static func panelTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.96))
                .combined(with: .offset(x: 0, y: 12)),
            removal: .opacity.combined(with: .scale(scale: 0.98))
                .combined(with: .offset(x: 0, y: 6))
        )
    }
}
