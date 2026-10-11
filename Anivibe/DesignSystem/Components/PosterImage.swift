import SwiftUI

/// Постер с кэшированием, плейсхолдером и плавным появлением.
struct PosterImage: View {
    let url: URL?
    var placeholderColorHex: String?
    var cornerRadius: CGFloat = Theme.Radius.card

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if failed || url == nil {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.6))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: url) { await load() }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        let base = placeholderColorHex.flatMap(UIColor.init(hexString:)).map(Color.init(uiColor:)) ?? Theme.surfaceElevated
        return Rectangle().fill(base.opacity(placeholderColorHex == nil ? 1 : 0.35))
    }

    private func load() async {
        guard let url else { return }
        if let hit = ImagePipeline.shared.cached(url) { image = hit; return }
        image = nil
        failed = false
        do {
            let loaded = try await ImagePipeline.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
