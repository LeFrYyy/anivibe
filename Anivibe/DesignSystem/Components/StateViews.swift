import SwiftUI

struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }
}

struct LoadingStateView: View {
    var message = "Загрузка…"
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
            }
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Не удалось загрузить", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Повторить", action: retry).buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
        }
    }
}

/// Скелетон горизонтальной подборки.
struct PosterRowSkeleton: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.m) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        RoundedRectangle(cornerRadius: Theme.Radius.card).fill(Theme.surfaceElevated)
                            .aspectRatio(Theme.posterAspect, contentMode: .fit)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceElevated).frame(height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.surfaceElevated).frame(width: 60, height: 10)
                    }
                    .frame(width: 120)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Загрузка подборки")
    }
}

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}

/// Простая раскладка «перенос по строкам» для чипов жанров.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sv in subviews {
            let size = Self.size(of: sv, maxWidth: width)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        // Никогда не сообщаем ширину больше предложенной: иначе при промежуточных
        // замерах (proposal без ширины) одна строка чипов растягивает весь экран.
        let finalWidth = proposal.width.map { min(maxX, $0) } ?? maxX
        return CGSize(width: finalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = Self.size(of: sv, maxWidth: bounds.width)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    /// Чип не может быть шире строки: очень длинное название студии/площадки
    /// переносится внутри чипа, а не вылезает за край экрана.
    private static func size(of subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard maxWidth.isFinite, ideal.width > maxWidth else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}
