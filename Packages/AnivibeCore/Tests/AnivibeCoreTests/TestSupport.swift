import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

/// Заглушка сети: отвечает по обработчику и записывает запросы.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data, [String: String])
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private let handler: Handler
    let delay: TimeInterval

    init(delay: TimeInterval = 0, handler: @escaping Handler) {
        self.handler = handler
        self.delay = delay
    }

    private func record(_ r: URLRequest) { lock.withLock { _requests.append(r) } }

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        record(request)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let (status, data, headers) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (data, response)
    }
}

extension URLRequest {
    var bodyJSON: [String: Any] {
        guard let body = httpBody, let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
        return obj
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { _now = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return _now }
    func advance(_ s: TimeInterval) { lock.lock(); _now = _now.addingTimeInterval(s); lock.unlock() }
}

enum Fixtures {
    static let bipbopMaster = """
    #EXTM3U
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="bipbop_audio",LANGUAGE="eng",NAME="BipBop Audio 1",AUTOSELECT=YES,DEFAULT=YES
    #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="bipbop_audio",LANGUAGE="eng",NAME="BipBop Audio 2",AUTOSELECT=NO,DEFAULT=NO,URI="alternate_audio_aac/prog_index.m3u8"
    #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",DEFAULT=YES,AUTOSELECT=YES,FORCED=NO,LANGUAGE="en",CHARACTERISTICS="public.accessibility.transcribes-spoken-dialog, public.accessibility.describes-music-and-sound",URI="subtitles/eng/prog_index.m3u8"
    #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English (Forced)",DEFAULT=NO,AUTOSELECT=NO,FORCED=YES,LANGUAGE="en",URI="subtitles/eng_forced/prog_index.m3u8"
    #EXT-X-STREAM-INF:BANDWIDTH=263851,CODECS="mp4a.40.2, avc1.4d400d",RESOLUTION=416x234,AUDIO="bipbop_audio",SUBTITLES="subs"
    gear1/prog_index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=577610,CODECS="mp4a.40.2, avc1.4d401e",RESOLUTION=640x360,AUDIO="bipbop_audio",SUBTITLES="subs"
    gear2/prog_index.m3u8
    """

    static func mediaJSON(id: Int, english: String?, romaji: String, episodes: Int? = 12, status: String = "FINISHED",
                          format: String = "TV", next: Int? = nil, adult: Bool = false, extra: String = "") -> String {
        let eng = english.map { "\"\($0)\"" } ?? "null"
        let ep = episodes.map(String.init) ?? "null"
        let nx = next.map { "{\"episode\": \($0)}" } ?? "null"
        return """
        {"id": \(id), "title": {"romaji": "\(romaji)", "english": \(eng), "native": null}, "synonyms": ["Alt \(id)"],
         "coverImage": {"large": "https://s4.anilist.co/c/\(id).jpg", "extraLarge": null, "color": "#aabbcc"},
         "bannerImage": "http://s4.anilist.co/b/\(id).jpg", "seasonYear": 2013, "season": "SPRING", "startDate": {"year": 2013},
         "genres": ["Action", "Drama"], "status": "\(status)", "format": "\(format)", "averageScore": 85, "episodes": \(ep),
         "duration": 24, "nextAiringEpisode": \(nx), "isAdult": \(adult)\(extra)}
        """
    }
}

func makeAnime(id: Int = 1, title: String = "Attack on Titan", romaji: String = "Shingeki no Kyojin", episodes: Int? = 25,
               status: AiringStatus = .finished) -> Anime {
    Anime(id: id, title: AnimeTitle(romaji: romaji, english: title), synonyms: ["AoT"], status: status, format: .tv, episodeCount: episodes)
}
