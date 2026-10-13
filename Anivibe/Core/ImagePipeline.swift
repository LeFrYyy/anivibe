import UIKit
import ImageIO

/// Bounded decoded-image cache + HTTP disk cache. A shared task coalesces requests
/// for the same URL; scrolling one cell away does not cancel other subscribers.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private let lock = NSLock()
    private struct Flight {
        let id: UUID
        let task: Task<UIImage, Error>
    }
    private var flights: [URL: Flight] = [:]

    private init() {
        memory.countLimit = 160
        memory.totalCostLimit = 96 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(for url: URL) async throws -> UIImage {
        try Task.checkCancellation()
        if let hit = cached(url) { return hit }
        let flight: Flight = lock.withLock {
            if let existing = flights[url] { return existing }
            let id = UUID()
            let task = Task.detached(priority: .userInitiated) { [self] () throws -> UIImage in
                // Another request may have completed between the first lookup and lock.
                if let hit = cached(url) { return hit }
                let (data, response) = try await session.data(from: url)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
                guard data.count <= 40 * 1024 * 1024,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1600,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
                let image = UIImage(cgImage: bitmap)
                let prepared = await image.byPreparingForDisplay() ?? image
                let cost = prepared.cgImage.map { $0.bytesPerRow * $0.height } ?? bitmap.bytesPerRow * bitmap.height
                memory.setObject(prepared, forKey: url as NSURL, cost: cost)
                return prepared
            }
            let created = Flight(id: id, task: task)
            flights[url] = created
            return created
        }
        defer {
            lock.withLock { if flights[url]?.id == flight.id { flights[url] = nil } }
        }
        let image = try await flight.task.value
        try Task.checkCancellation()
        return image
    }
}
