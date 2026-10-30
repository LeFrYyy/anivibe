import UIKit
import ImageIO
import AnivibeCore

/// Bounded decoded-image cache + HTTP disk cache. Downloads are shared by URL;
/// decoded variants are shared by display size. One cell never cancels another.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()
    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession
    private let lock = NSLock()
    private struct Request: Hashable, Sendable {
        let url: URL
        let size: ImageDecodeSize
        var cacheKey: NSString { "\(size.width)x\(size.height)|\(url.absoluteString)" as NSString }
    }
    private struct Flight: Sendable {
        let id: UUID
        let task: Task<UIImage, Error>
        var subscribers: Set<UUID>
    }
    private struct Download: Sendable {
        let id: UUID
        let task: Task<Data, Error>
        var subscribers: Set<UUID>
    }
    private var flights: [Request: Flight] = [:]
    private var downloads: [URL: Download] = [:]
    private var memoryWarningObserver: NSObjectProtocol?

    private init() {
        memory.countLimit = 180
        memory.totalCostLimit = 64 * 1024 * 1024
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.memory.removeAllObjects()
        }
    }

    deinit {
        if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
    }

    func cached(_ url: URL, size: ImageDecodeSize = .full) -> UIImage? {
        memory.object(forKey: Request(url: url, size: size).cacheKey)
    }

    func image(for url: URL, size: ImageDecodeSize = .full) async throws -> UIImage {
        try Task.checkCancellation()
        let request = Request(url: url, size: size)
        if let hit = cached(url, size: size) { return hit }
        let subscriber = UUID()
        let flight: Flight = lock.withLock {
            if var existing = flights[request] {
                existing.subscribers.insert(subscriber)
                flights[request] = existing
                return existing
            }
            let id = UUID()
            let task = Task.detached(priority: .userInitiated) { [self] () async throws -> UIImage in
                // Another request may have completed between the first lookup and lock.
                if let hit = cached(url, size: size) { return hit }
                // A header and a small card can need different decodes of one URL,
                // but must not start two simultaneous HTTP downloads.
                let data = try await self.data(for: url)
                try Task.checkCancellation()
                guard let source = CGImageSourceCreateWithData(data as CFData, [
                        kCGImageSourceShouldCache: false
                      ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                var width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
                var height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
                let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
                if (5...8).contains(orientation) { swap(&width, &height) }
                let pixelSize = ImageDownsampling.thumbnailPixelSize(
                    sourceWidth: width, sourceHeight: height, target: size
                )
                guard
                      let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
                let image = UIImage(cgImage: bitmap)
                let prepared = await image.byPreparingForDisplay() ?? image
                try Task.checkCancellation()
                let cost = prepared.cgImage.map { $0.bytesPerRow * $0.height } ?? bitmap.bytesPerRow * bitmap.height
                memory.setObject(prepared, forKey: request.cacheKey, cost: cost)
                return prepared
            }
            let created = Flight(id: id, task: task, subscribers: [subscriber])
            flights[request] = created
            return created
        }
        let flightID = flight.id
        defer { release(request, flightID: flightID, subscriber: subscriber) }
        return try await withTaskCancellationHandler(operation: {
            let image = try await flight.task.value
            try Task.checkCancellation()
            return image
        }, onCancel: { [self] in
            // Cancel a download only when *all* visible consumers have left.
            release(request, flightID: flightID, subscriber: subscriber)
        })
    }

    private func release(_ request: Request, flightID: UUID, subscriber: UUID) {
        let abandoned: Task<UIImage, Error>? = lock.withLock {
            guard var flight = flights[request], flight.id == flightID,
                  flight.subscribers.remove(subscriber) != nil else { return nil }
            if flight.subscribers.isEmpty {
                flights[request] = nil
                return flight.task
            }
            flights[request] = flight
            return nil
        }
        // Do not call cancellation handlers while holding the dictionary lock.
        abandoned?.cancel()
    }

    private func data(for url: URL) async throws -> Data {
        try Task.checkCancellation()
        let subscriber = UUID()
        let download: Download = lock.withLock {
            if var existing = downloads[url] {
                existing.subscribers.insert(subscriber)
                downloads[url] = existing
                return existing
            }
            let task = Task.detached(priority: .userInitiated) { [session] () async throws -> Data in
                var request = URLRequest(url: url)
                // MangaDex CDN требует Referer, остальные хосты его игнорируют.
                if url.host == "uploads.mangadex.org" { request.setValue("https://mangadex.org", forHTTPHeaderField: "Referer") }
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
                guard data.count <= 40 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
                return data
            }
            let created = Download(id: UUID(), task: task, subscribers: [subscriber])
            downloads[url] = created
            return created
        }
        let downloadID = download.id
        defer { releaseDownload(url, downloadID: downloadID, subscriber: subscriber) }
        return try await withTaskCancellationHandler(operation: {
            let data = try await download.task.value
            try Task.checkCancellation()
            return data
        }, onCancel: { [self] in
            releaseDownload(url, downloadID: downloadID, subscriber: subscriber)
        })
    }

    private func releaseDownload(_ url: URL, downloadID: UUID, subscriber: UUID) {
        let abandoned: Task<Data, Error>? = lock.withLock {
            guard var download = downloads[url], download.id == downloadID,
                  download.subscribers.remove(subscriber) != nil else { return nil }
            if download.subscribers.isEmpty {
                downloads[url] = nil
                return download.task
            }
            downloads[url] = download
            return nil
        }
        abandoned?.cancel()
    }
}
