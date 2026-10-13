import SwiftUI
import AnivibeCore

/// Decoded avatars live only in memory, scoped to viewer + target + revision.
/// No durable cache of private avatars or signed URLs. 40 s TTL < server's 60 s.
@MainActor
final class AvatarImageLoader {
    static let shared = AvatarImageLoader()
    private final class Entry: NSObject {
        let image: UIImage
        let expires = Date().addingTimeInterval(40)
        init(_ image: UIImage) { self.image = image }
    }
    private let cache = NSCache<NSString, Entry>()
    private var flights: [String: Task<UIImage?, Error>] = [:]
    private var generation = UUID()
    private let network: URLSession
    init() {
        cache.totalCostLimit = 16 * 1024 * 1024; cache.countLimit = 64
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 20
        network = URLSession(configuration: config)
    }
    static func key(viewer: String, target: String, revision: String) -> String { viewer + "/" + target + "/" + revision }
    func cached(key: String) -> UIImage? {
        guard let entry = cache.object(forKey: key as NSString) else { return nil }
        guard entry.expires > Date() else { cache.removeObject(forKey: key as NSString); return nil }
        return entry.image
    }
    func reset() {
        generation = UUID(); cache.removeAllObjects()
        flights.values.forEach { $0.cancel() }; flights.removeAll()
    }
    func image(service: SupabaseSocialService, viewer: String, target: String, revision: String) async throws -> UIImage? {
        let key = Self.key(viewer: viewer, target: target, revision: revision)
        if let hit = cached(key: key) { return hit }
        if let pending = flights[key] { return try await pending.value }
        let operation = generation
        let pending = Task<UIImage?, Error> { [self] in
            guard let url = try await service.avatarURL(userID: target, expectedUserID: viewer, revision: revision) else { return nil }
            try Task.checkCancellation()
            let (data, response) = try await network.data(from: url)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
                  data.count <= 1_048_576, let decoded = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            return await decoded.byPreparingForDisplay() ?? decoded
        }
        flights[key] = pending
        defer { if generation == operation { flights[key] = nil } }
        let image = try await pending.value
        try Task.checkCancellation()
        guard generation == operation else { throw CancellationError() }
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 512 * 512 * 4
            cache.setObject(Entry(image), forKey: key as NSString, cost: cost)
        }
        return image
    }
}

struct ProfileAvatarView: View {
    let userID: String
    var revision: String = ""
    var size: CGFloat = 40
    var avatarAvailable = true
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @State private var image: UIImage?
    @State private var loadedKey = ""
    private var key: String { AvatarImageLoader.key(viewer: session.user?.id ?? "guest", target: userID, revision: revision) }
    var body: some View {
        let hit = avatarAvailable ? ((loadedKey == key ? image : nil) ?? AvatarImageLoader.shared.cached(key: key)) : nil
        Circle().fill(Theme.accent.opacity(0.12))
            .overlay {
                if let hit { Image(uiImage: hit).resizable().scaledToFill() }
                else {
                    Image(systemName: "person.fill").resizable().scaledToFit()
                        .foregroundStyle(Theme.textSecondary).padding(size * 0.24)
                }
            }
            .frame(width: size, height: size).clipShape(Circle())
            .task(id: key + String(avatarAvailable)) {
                let requestKey = key
                image = nil; loadedKey = requestKey
                guard avatarAvailable, let viewer = session.user?.id, let service = env.socialService else { return }
                do {
                    let result = try await AvatarImageLoader.shared.image(service: service, viewer: viewer, target: userID, revision: revision)
                    guard !Task.isCancelled, session.user?.id == viewer, key == requestKey else { return }
                    image = result
                } catch { /* A failed avatar must not block profile actions. */ }
            }
            .accessibilityLabel("Аватар")
    }
}
