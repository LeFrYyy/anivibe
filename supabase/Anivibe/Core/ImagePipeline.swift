import UIKit

/// Загрузка постеров с кэшем в памяти (NSCache) и на диске (URLCache).
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init() {
        memory.countLimit = 300
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 30 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(for url: URL) async throws -> UIImage {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
        let prepared = await image.byPreparingForDisplay() ?? image
        memory.setObject(prepared, forKey: url as NSURL)
        return prepared
    }
}
