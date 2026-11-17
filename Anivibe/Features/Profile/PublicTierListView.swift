import SwiftUI
import AnivibeCore

/// Просмотр чужого публичного тир-листа в `PublicProfileView` (только чтение).
struct PublicTierListSection: View {
    var name: String = "Тир-лист"
    let tierList: TierList

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(name).font(.title3.bold()).lineLimit(1)
                TierBetaBadge()
                Spacer()
                Text("\(tierList.totalAssignedCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(tierList.tiers.filter { !$0.items.isEmpty }) { row in
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 2) {
                        Text(row.key.rawValue).font(.headline.weight(.heavy)).foregroundStyle(.white)
                        Text(row.title).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.92))
                            .lineLimit(2).multilineTextAlignment(.center)
                    }
                    .frame(width: 62)
                    .frame(minHeight: 72)
                    .padding(.horizontal, 4)
                    .background(tierColor(row.colorHex), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 8) {
                            ForEach(row.items, id: \.id) { anime in
                                NavigationLink(value: anime) {
                                    VStack(spacing: 4) {
                                        PosterImage(url: anime.coverURL, cornerRadius: 8)
                                            .frame(width: 48, height: 72)
                                        Text(anime.title)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(2)
                                            .frame(width: 52)
                                    }
                                }
                                .buttonStyle(PosterPressStyle())
                            }
                        }
                    }
                }
                .padding(8)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .profilePanel()
    }
}
