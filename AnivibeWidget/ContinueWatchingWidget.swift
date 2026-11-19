import WidgetKit
import SwiftUI
import AnivibeCore

/// Виджет «Продолжить просмотр». Тап открывает deep link `anivibe://anime/<id>`.
struct ContinueWatchingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AnivibeContinueWatching", provider: ContinueWatchingProvider()) { entry in
            ContinueWatchingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Продолжить просмотр")
        .description("Последние тайтлы из вашей библиотеки — тап открывает тайтл в приложении.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ContinueWatchingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ContinueWatchingEntry

    var body: some View {
        let items = Array(entry.snapshot.continueWatching.prefix(limit))
        if items.isEmpty {
            EmptyWidgetView()
        } else {
            switch family {
            case .systemSmall: SmallWidgetView(item: items[0])
            default: ListWidgetView(items: items)
            }
        }
    }

    private var limit: Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 2
        default: return 4
        }
    }
}

/// Пустое состояние: библиотека ещё ничего не смотрит.
private struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.circle")
                .font(.title)
                .foregroundStyle(WidgetTheme.secondaryText)
            Text("Продолжить нечего")
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
            Text("Начните смотреть аниме в приложении")
                .font(.caption2)
                .foregroundStyle(WidgetTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small: один тайтл с постером и прогрессом.
private struct SmallWidgetView: View {
    let item: WidgetSnapshot.Item

    var body: some View {
        if let url = WidgetSnapshot.deepLink(for: item.id) {
            Link(destination: url) { content }
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            WidgetPoster(url: item.coverURL, cornerRadius: 10)
                .frame(width: 58)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                Text("Серия \(item.episode)")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.secondaryText)
                WidgetProgressBar(value: item.safeProgress)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Medium и Large: список тайтлов.
private struct ListWidgetView: View {
    let items: [WidgetSnapshot.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Продолжить просмотр")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.secondaryText)
            ForEach(items) { item in
                row(item)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func row(_ item: WidgetSnapshot.Item) -> some View {
        if let url = WidgetSnapshot.deepLink(for: item.id) {
            Link(destination: url) { rowContent(item) }
        } else {
            rowContent(item)
        }
    }

    private func rowContent(_ item: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 10) {
            WidgetPoster(url: item.coverURL, cornerRadius: 6)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                WidgetProgressBar(value: item.safeProgress, height: 3)
            }
            Spacer(minLength: 0)
            Text("\(item.episode)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(WidgetTheme.secondaryText)
        }
    }
}

/// Постер тайтла. `AsyncImage` в виджете отдаёт уже закэшированную картинку,
/// а при промахе показывает плоский плейсхолдер — виджет не должен ждать сеть
/// в момент отрисовки таймлайна.
private struct WidgetPoster: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .aspectRatio(WidgetTheme.posterAspect, contentMode: .fit)
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Rectangle().fill(WidgetTheme.progressTrack)
    }
}

/// Плоский индикатор прогресса: без градиентов и теней.
private struct WidgetProgressBar: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetTheme.progressTrack)
                Capsule().fill(WidgetTheme.accent)
                    .frame(width: max(height, geo.size.width * value))
            }
        }
        .frame(height: height)
        .accessibilityLabel("Просмотрено \(Int((value * 100).rounded()))%")
    }
}
