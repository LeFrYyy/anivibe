import SwiftUI
import AnivibeCore

/// Постер с кэшированием, плейсхолдером и плавным появлением.
struct PosterImage: View {
    let url: URL?
    var placeholderColorHex: String?
    var cornerRadius: CGFloat = Theme.Radius.card

    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    private struct LoadRequest: Hashable, Sendable {
        let url: URL?
        let size: ImageDecodeSize
    }

    var body: some View {
        // Размер задаёт только плейсхолдер (он ровно равен предложенному месту),
        // а картинка лежит в overlay. Иначе `scaledToFill()` у широкого баннера
        // (AniList отдаёт ~1900×400) сообщает родителю ширину ~950pt — и вся
        // страница аниме становится шире экрана и уезжает в сторону.
        placeholder
            .overlay {
                if loadedURL == url, let image {
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
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                GeometryReader { geometry in
                    let request = LoadRequest(
                        url: url,
                        size: ImageDownsampling.targetSize(
                            width: Double(geometry.size.width), height: Double(geometry.size.height),
                            scale: Double(displayScale)
                        )
                    )
                    Color.clear.task(id: request) { await load(request) }
                }
            }
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        let base = placeholderColorHex.flatMap(UIColor.init(hexString:)).map(Color.init(uiColor:)) ?? Theme.surfaceElevated
        return Rectangle().fill(base.opacity(placeholderColorHex == nil ? 1 : 0.35))
    }

    @MainActor private func load(_ request: LoadRequest) async {
        guard !Task.isCancelled, self.url == request.url else { return }
        // Retain the current image during a rotation/resize; don't flash a placeholder.
        if loadedURL != request.url { image = nil; loadedURL = request.url }
        failed = false
        guard !Task.isCancelled, let url = request.url else { return }
        if let hit = ImagePipeline.shared.cached(url, size: request.size) { image = hit; return }
        do {
            let loaded = try await ImagePipeline.shared.image(for: url, size: request.size)
            try Task.checkCancellation()
            guard self.url == url else { return }
            withAnimation(AppMotion.fade(reduceMotion: reduceMotion)) { image = loaded }
        } catch {
            if !Task.isCancelled, self.url == url, image == nil {
                failed = true
            }
        }
    }
}
