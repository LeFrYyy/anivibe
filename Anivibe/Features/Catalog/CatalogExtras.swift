import SwiftUI
import AnivibeCore

/// Круглая кнопка возврата к началу списка.
struct BackToTopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 44, height: 44)
                .background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .accessibilityLabel("Наверх")
        .buttonStyle(PosterPressStyle())
    }
}

/// Шит рандомайзера: «мне нечего смотреть» — карточка случайного тайтла.
struct RandomPickSheet: View {
    let anime: Anime
    let reroll: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Text("Может, это?")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            HStack(alignment: .top, spacing: Theme.Spacing.l) {
                PosterImage(url: anime.coverURL, placeholderColorHex: anime.coverColorHex)
                    .aspectRatio(Theme.posterAspect, contentMode: .fit)
                    .frame(width: 110)

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(anime.title.preferred)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                    if let score = anime.averageScore {
                        Text(Anime.scoreText(score))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    let meta = anime.metaLine
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: Theme.Spacing.m) {
                Button("Ещё раз", action: reroll)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("К тайтлу", action: open)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .screenBackground()
    }
}

/// Зум-превью постера по удержанию живёт внутри `FolderMenuModifier`:
/// SwiftUI оставляет только одно контекстное меню на view, поэтому вторым
/// модификатором его навесить нельзя — пункты «В папку» и действия превью
/// должны быть в одном `.contextMenu`.

