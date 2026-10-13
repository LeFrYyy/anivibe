import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

final class ProviderTests: XCTestCase {
    func testHLSInspector() {
        let info = HLSManifestInspector.inspect(Fixtures.bipbopMaster)
        XCTAssertTrue(info.isValid)
        XCTAssertTrue(info.isMaster)
        XCTAssertEqual(info.variantCount, 2)
        XCTAssertEqual(info.audio.map(\.name), ["BipBop Audio 1", "BipBop Audio 2"])
        XCTAssertEqual(info.subtitles.map(\.name), ["English", "English (Forced)"])
        XCTAssertTrue(info.subtitles[1].isForced)
        XCTAssertTrue(info.audio[0].isDefault)
        XCTAssertFalse(HLSManifestInspector.inspect("<html>").isValid)
        XCTAssertEqual(HLSManifestInspector.attributes(#"A=1,B="x,y",C=z"#), ["A": "1", "B": "x,y", "C": "z"])
    }

    func testTestStreamProviderResolvesAndMarksAsTest() async throws {
        let t = StubTransport { _ in (200, Data(Fixtures.bipbopMaster.utf8), [:]) }
        let p = TestStreamProvider(transport: t)
        let title = try await p.match(anime: makeAnime())
        let eps = try await p.episodes(for: try XCTUnwrap(title))
        let ep = try XCTUnwrap(EpisodeMatcher.match(season: 1, number: 1, in: eps))
        let src = try await p.resolve(ep)
        XCTAssertTrue(src.isTestContent)
        XCTAssertEqual(src.kind, .hls)
        XCTAssertEqual(src.audioTracks.count, 2)
        XCTAssertEqual(src.subtitleTracks.count, 2)
        XCTAssertEqual(t.requests.first?.url, TestStreamProvider.streams[0].url)
    }

    func testTestStreamProviderReportsUnavailable() async throws {
        let t = StubTransport { _ in (404, Data(), [:]) }
        let p = TestStreamProvider(transport: t)
        let eps = try await p.episodes(for: ProviderTitle(id: "x", providerID: p.id, titles: []))
        let a = await p.checkAvailability(eps[0])
        XCTAssertFalse(a.isAvailable)
        let html = StubTransport { _ in (200, Data("<html></html>".utf8), [:]) }
        let a2 = await TestStreamProvider(transport: html).checkAvailability(eps[0])
        XCTAssertEqual(a2, .unavailable(.unsupportedFormat("ответ не является плейлистом HLS")))
    }

    // MARK: Manifest provider

    private func manifest(expires: String? = nil, url: String = "https://cdn.example.com/aot/1.m3u8") -> String {
        let exp = expires.map { "\"\($0)\"" } ?? "null"
        return """
        {"version": 1, "providerName": "Мой CDN", "titles": [
          {"id": "aot", "anilistId": 1, "titles": ["Attack on Titan"], "episodes": [
            {"season": 1, "number": 1, "title": "Pilot", "url": "\(url)", "expiresAt": \(exp)},
            {"season": 1, "number": 2, "title": null, "url": "https://cdn.example.com/aot/2.mp4", "expiresAt": null}
          ]},
          {"id": "other", "anilistId": 777, "titles": ["Attack on Titan"], "episodes": []},
          {"id": "nameonly", "anilistId": null, "titles": ["Frieren: Beyond Journey's End"], "episodes": []}
        ]}
        """
    }

    private func manifestTransport(_ json: String, playlist: String = Fixtures.bipbopMaster) -> StubTransport {
        StubTransport { req in
            if req.url?.path == "/manifest.json" { return (200, Data(json.utf8), [:]) }
            if req.httpMethod == "HEAD" { return (200, Data(), [:]) }
            return (200, Data(playlist.utf8), [:])
        }
    }

    func testManifestProviderMatchesByAniListIDThenTitle() async throws {
        let t = manifestTransport(manifest())
        let p = ManifestProvider(manifestURL: URL(string: "https://example.com/manifest.json")!, transport: t)
        let byID = try await p.match(anime: makeAnime(id: 1))
        XCTAssertEqual(byID?.id, "aot")
        // Другой ID с тем же названием не должен совпасть с записью, у которой указан чужой anilistId.
        let wrong = try await p.match(anime: makeAnime(id: 2))
        XCTAssertNil(wrong)
        let frieren = Anime(id: 154587, title: AnimeTitle(romaji: "Sousou no Frieren", english: "Frieren: Beyond Journey’s End"))
        let byName = try await p.match(anime: frieren)
        XCTAssertEqual(byName?.id, "nameonly")
        XCTAssertEqual(t.requests.filter { $0.url?.path == "/manifest.json" }.count, 1, "манифест кэшируется")
    }

    func testManifestProviderResolve() async throws {
        let p = ManifestProvider(manifestURL: URL(string: "https://example.com/manifest.json")!, transport: manifestTransport(manifest()))
        let eps = try await p.episodes(for: ProviderTitle(id: "aot", providerID: p.id, titles: []))
        XCTAssertEqual(eps.count, 2)
        let hls = try await p.resolve(eps[0])
        XCTAssertEqual(hls.kind, .hls)
        XCTAssertEqual(hls.providerName, "Мой CDN")
        XCTAssertFalse(hls.isTestContent)
        XCTAssertEqual(hls.audioTracks.count, 2)
        let mp4 = try await p.resolve(eps[1])
        XCTAssertEqual(mp4.kind, .progressiveFile)
    }

    func testManifestProviderRejectsExpiredAndInsecureLinks() async throws {
        let clock = Clock(Date(timeIntervalSince1970: 1_800_000_000))
        let past = ISO8601DateFormatter().string(from: clock.now.addingTimeInterval(-10))
        let p = ManifestProvider(manifestURL: URL(string: "https://example.com/manifest.json")!,
                                 transport: manifestTransport(manifest(expires: past)), now: { clock.now })
        let eps = try await p.episodes(for: ProviderTitle(id: "aot", providerID: p.id, titles: []))
        do { _ = try await p.resolve(eps[0]); XCTFail() } catch { XCTAssertEqual(error as? VideoSourceError, .linkExpired) }

        let insecure = ManifestProvider(manifestURL: URL(string: "https://example.com/manifest.json")!,
                                        transport: manifestTransport(manifest(url: "http://cdn.example.com/1.m3u8")))
        let eps2 = try await insecure.episodes(for: ProviderTitle(id: "aot", providerID: insecure.id, titles: []))
        do { _ = try await insecure.resolve(eps2[0]); XCTFail() } catch {
            XCTAssertEqual(error as? VideoSourceError, .unsupportedFormat("разрешены только https-ссылки"))
        }
    }

    func testManifestCacheNeverOutlivesTemporaryLinks() async throws {
        let clock = Clock()
        let soon = ISO8601DateFormatter().string(from: clock.now.addingTimeInterval(30))
        let t = manifestTransport(manifest(expires: soon))
        let p = ManifestProvider(manifestURL: URL(string: "https://example.com/manifest.json")!, transport: t, cacheTTL: 600, now: { clock.now })
        _ = try await p.loadManifest()
        clock.advance(31)
        _ = try await p.loadManifest()
        XCTAssertEqual(t.requests.count, 2)
    }

    func testManifestErrors() async {
        let bad = StubTransport { _ in (200, Data(#"{"version": 2, "titles": []}"#.utf8), [:]) }
        let p = ManifestProvider(manifestURL: URL(string: "https://example.com/manifest.json")!, transport: bad)
        do { _ = try await p.loadManifest(); XCTFail() } catch {
            XCTAssertEqual(error as? VideoSourceError, .invalidResponse("неподдерживаемая версия манифеста 2"))
        }
        let unauthorized = StubTransport { _ in (401, Data(), [:]) }
        let p2 = ManifestProvider(manifestURL: URL(string: "https://example.com/manifest.json")!, transport: unauthorized)
        do { _ = try await p2.loadManifest(); XCTFail() } catch { XCTAssertEqual(error as? VideoSourceError, .unauthorized) }
    }

    // MARK: Registry

    struct FakeProvider: VideoSourceProvider {
        let id: ProviderID
        let displayName: String
        let capabilities: ProviderCapabilities = [.search]
        var providesTestContent = false
        var result: Result<Bool, VideoSourceError> = .success(true)
        var delay: TimeInterval = 0
        var episodeCount = 10

        func search(title: String) async throws -> [ProviderTitle] {
            [ProviderTitle(id: "t", providerID: id, titles: [title])]
        }
        func episodes(for title: ProviderTitle) async throws -> [ProviderEpisode] {
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            return (0..<episodeCount).map { ProviderEpisode(providerID: id, titleID: "t", season: nil, number: $0 + 1, payload: "") }
        }
        func resolve(_ episode: ProviderEpisode) async throws -> PlaybackSource {
            switch result {
            case .success: return PlaybackSource(providerID: id, providerName: displayName, url: URL(string: "https://x/\(episode.number).m3u8")!, kind: .hls)
            case .failure(let e): throw e
            }
        }
    }

    func testRegistryOrdersRealBeforeTestAndAvailableFirst() async {
        let registry = ProviderRegistry(providers: [
            FakeProvider(id: "test", displayName: "Test", providesTestContent: true),
            FakeProvider(id: "broken", displayName: "Broken", result: .failure(.unauthorized)),
            FakeProvider(id: "good", displayName: "Good")
        ])
        let c = await registry.candidates(for: makeAnime(), episode: 3)
        XCTAssertEqual(c.map(\.providerID.rawValue), ["good", "broken", "test"])
        XCTAssertTrue(c[0].availability.isAvailable)
        XCTAssertEqual(c[1].availability, .unavailable(.unauthorized))
        XCTAssertEqual(c[0].episode?.number, 3)
    }

    func testKodikWinsRegardlessOfRegistrationOrder() async {
        let registry = ProviderRegistry(providers: [
            FakeProvider(id: "anilibria", displayName: "Anilibria"),
            FakeProvider(id: KodikProvider.providerID, displayName: "Kodik")
        ])
        let candidates = await registry.candidates(for: makeAnime(), episode: 1)
        XCTAssertEqual(candidates.first?.providerID, KodikProvider.providerID)
    }
    func testUnavailableKodikDoesNotBlockWorkingBackup() async {
        let registry = ProviderRegistry(providers: [
            FakeProvider(id: KodikProvider.providerID, displayName: "Kodik", result: .failure(.unauthorized)),
            FakeProvider(id: "anilibria", displayName: "Anilibria")
        ])
        let candidates = await registry.candidates(for: makeAnime(), episode: 1)
        XCTAssertEqual(candidates.first?.providerID.rawValue, "anilibria")
        XCTAssertTrue(candidates.contains { $0.providerID == KodikProvider.providerID })
    }
    func testDisabledKodikDoesNotOverrideExplicitSetting() async {
        let registry = ProviderRegistry(providers: [
            FakeProvider(id: "anilibria", displayName: "Anilibria"),
            FakeProvider(id: KodikProvider.providerID, displayName: "Kodik")
        ])
        await registry.setEnabled(false, for: KodikProvider.providerID)
        let candidates = await registry.candidates(for: makeAnime(), episode: 1)
        XCTAssertFalse(candidates.contains { $0.providerID == KodikProvider.providerID })
    }

    func testRegistryDisabledProvidersAndMissingEpisodes() async {
        let registry = ProviderRegistry(providers: [FakeProvider(id: "a", displayName: "A", episodeCount: 2), FakeProvider(id: "b", displayName: "B")])
        await registry.setEnabled(false, for: "b")
        let c = await registry.candidates(for: makeAnime(), episode: 5)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].availability, .unavailable(.episodeNotFound(5)))
        await registry.setEnabled(true, for: "b")
        let c2 = await registry.candidates(for: makeAnime(), episode: 5)
        XCTAssertEqual(c2.count, 2)
    }

    func testRegistryTimeout() async {
        let registry = ProviderRegistry(providers: [FakeProvider(id: "slow", displayName: "Slow", delay: 5)], timeout: 0.2)
        let started = Date()
        let c = await registry.candidates(for: makeAnime(), episode: 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertEqual(c.first?.availability, .unavailable(.timeout))
    }

    func testDefaultMatchUsesTitles() async throws {
        let p = FakeProvider(id: "f", displayName: "F")
        let m = try await p.match(anime: makeAnime())
        XCTAssertNotNil(m)
    }

    func testErrorMapping() {
        XCTAssertEqual(VideoSourceError.from(APIError.forbidden), .unauthorized)
        XCTAssertEqual(VideoSourceError.from(APIError.rateLimited(retryAfter: 5)), .rateLimited(retryAfter: 5))
        XCTAssertFalse(VideoSourceError.timeout.userMessage.isEmpty)
    }
}

final class RegistryInfoTests: XCTestCase {
    func testProviderInfoReflectsEnabledState() async {
        let registry = ProviderRegistry(providers: [ProviderTests.FakeProvider(id: "a", displayName: "A", providesTestContent: true)])
        await registry.setEnabled(false, for: "a")
        let info = await registry.allProviders()
        XCTAssertEqual(info, [ProviderInfo(id: "a", name: "A", isEnabled: false, isTestContent: true)])
    }
}
