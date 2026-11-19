import SwiftUI
import AnivibeCore

/// Карточка тайтла: постер 2:3, название, краткая мета-строка, опциональный прогресс.
struct PosterCard: View {
    let title: String
    let coverURL: URL?
    var colorHex: String?
    var subtitle: String?
    var progress: Double?
    var badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            PosterImage(url: coverURL, placeholderColorHex: colorHex)
                .aspectRatio(Theme.posterAspect, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let progress {
                        ProgressBar(value: progress)
                            .frame(height: 4)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                    }
                }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension PosterCard {
    init(anime: Anime, progress: Double? = nil) {
        self.init(title: anime.title.preferred, coverURL: anime.coverURL, colorHex: anime.coverColorHex,
                  subtitle: anime.metaLine, progress: progress,
                  badge: anime.averageScore.map(Anime.scoreText))
    }
}

extension Anime {
    /// Оценка AniList 0–100 → «★ 8.5».
    static func scoreText(_ score: Int) -> String {
        "★ " + String(format: "%.1f", Double(score) / 10)
    }

    /// «2019 · ТВ · 26 эп.» (для онгоинга — «2026 · ТВ · 2/? эп.») — только известные значения.
    var metaLine: String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if let format { parts.append(format.localizedName) }
        if let aired = airedEpisodesText {
            parts.append("\(aired) эп.")          // онгоинг: «2/11 эп.» или «2/? эп.»
        } else if let episodeCount {
            parts.append("\(episodeCount) эп.")
        } else if status == .releasing {
            parts.append("онгоинг")
        }
        return parts.joined(separator: " · ")
    }
}

struct ProgressBar: View {
    let value: Double
    private var safeValue: Double { value.isFinite ? min(1, max(0, value)) : 0 }
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.45))
                Capsule().fill(Theme.secondaryAccent)
                    .frame(width: max(4, geo.size.width * safeValue))
            }
        }
        .accessibilityLabel("Просмотрено \(Int(safeValue * 100))%")
    }
}

/// Quiet visual press feedback; no vibration for routine navigation.
struct PosterPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(AppMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
