import SwiftUI
import AnivibeCore

/// Small, isolated HUD: no timers or invalidation of the video/controls hierarchy.
struct SpeedBoostIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            Text(PlaybackSpeedLabel.text(PlaybackSpeedBoost.boostRate))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            if reduceMotion {
                arrows(active: true)
            } else {
                PhaseAnimator([false, true]) { phase in
                    arrows(active: phase)
                } animation: { _ in AppMotion.hudPulseStep }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background {
            if reduceTransparency { Capsule().fill(Color(white: 0.12)) }
            else { Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(.black.opacity(0.55))) }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Временная скорость 2×")
    }

    private func arrows(active: Bool) -> some View {
        HStack(spacing: 1) {
            Image(systemName: "play.fill").opacity(active ? 0.55 : 1)
            Image(systemName: "play.fill").opacity(active ? 1 : 0.55)
        }
        .font(.system(size: 10, weight: .bold))
        .offset(x: active ? 1 : 0)
    }
}
