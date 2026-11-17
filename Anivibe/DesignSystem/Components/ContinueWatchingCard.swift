import SwiftUI
import AnivibeCore

/// Крупная карточка «Продолжить просмотр»: обложка, название, серия и кнопка.
/// Одна такая карточка на главной вместо ряда мелких обложек — это главное
/// действие экрана, и оно должно читаться с первого взгляда.
struct ContinueWatchingCard: View {
    let title: String
    let subtitle: String
    let artworkURL: URL?
    let progress: Double?
    let action: () -> Void

    /// NaN и выход за диапазон из плеера не должны ломать ширину шкалы.
    private var safeProgress: Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(1, max(0, progress))
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                artwork
                details
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            }
        }
        .buttonStyle(PosterPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint("Открыть тайтл")
    }

    private var artwork: some View {
        PosterImage(url: artworkURL, cornerRadius: 0)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(alignment: .bottom) {
                if let safeProgress {
                    GeometryReader { geo in
                        let width = geo.size.width.isFinite ? max(0, geo.size.width) : 0
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.black.opacity(0.35))
                            Rectangle().fill(Theme.accent).frame(width: width * safeProgress)
                        }
                    }
                    .frame(height: 4)
                }
            }
    }

    private var details: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.accent))
                .accessibilityHidden(true)
        }
        .padding(Theme.Spacing.l)
    }
}
