import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import AnivibeCore

/// Hold-for-2×, progressive source search, idempotent retries and the shared date codec.
final class Update20261025Tests: XCTestCase {
    private func conditions(ready: Bool = true, playing: Bool = true, buffering: Bool = false, scrubbing: Bool = false,
                            shared: Bool = false, blocked: Bool = false) -> PlaybackSpeedBoost.Conditions {
        .init(isReady: ready, isPlaying: playing, isBuffering: buffering, isScrubbing: scrubbing,
              isSharedWatch: shared, isBlockedByUI: blocked)
    }

    // MARK: Hold for 2×

    func testBoostStartsOnlyWhilePlaybackIsReadyAndPlaying() {
        var boost = PlaybackSpeedBoost()
        XCTAssertEqual(boost.begin(conditions()), 2)
        XCTAssertTrue(boost.isActive)
        XCTAssertNil(boost.begin(conditions()), "a second hold must not stack")
    }

    func testBoostIsRefusedWhenPausedLoadingBufferingSeekingSharedOrCovered() {
        let refused = [conditions(playing: false), conditions(ready: false), conditions(buffering: true),
                       conditions(scrubbing: true), conditions(shared: true), conditions(blocked: true)]
        for condition in refused {
            var boost = PlaybackSpeedBoost()
            XCTAssertNil(boost.begin(condition), "\(condition)")
            XCTAssertFalse(boost.isActive)
        }
    }

    func testReleaseRestoresTheUsersOwnSpeedNotOneX() {
        var boost = PlaybackSpeedBoost()
        _ = boost.begin(conditions())
        XCTAssertEqual(boost.end(restoring: 1.5), 1.5)
        XCTAssertFalse(boost.isActive)
        XCTAssertNil(boost.end(restoring: 1.5), "release without an active boost changes nothing")
    }

    func testResetForgetsBoostWithoutRestoringAndBadRatesFallBackToOneX() {
        var boost = PlaybackSpeedBoost()
        _ = boost.begin(conditions())
        boost.reset()
        XCTAssertNil(boost.end(restoring: 1.25))
        _ = boost.begin(conditions())
        XCTAssertEqual(boost.end(restoring: .nan), 1)
        XCTAssertGreaterThanOrEqual(PlaybackSpeedBoost.activationDelay, 0.3)
        XCTAssertLessThanOrEqual(PlaybackSpeedBoost.activationDelay, 0.5)
    }

    func testReleaseRestoresEverySupportedSpeedIncludingTwoX() {
        for rate: Float in [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2] {
            var boost = PlaybackSpeedBoost()
            XCTAssertEqual(boost.begin(conditions()), 2)
            XCTAssertEqual(boost.end(restoring: rate), rate)
            XCTAssertFalse(boost.isActive)
        }
    }

    func testSpeedLabelsAreShortAndConsistent() {
        XCTAssertEqual(PlaybackSpeedLabel.text(2), "2×")
        XCTAssertEqual(PlaybackSpeedLabel.text(1), "1×")
        XCTAssertEqual(PlaybackSpeedLabel.text(1.25), "1.25×")
        XCTAssertEqual(PlaybackSpeedLabel.text(1.5), "1.5×")
        XCTAssertEqual(PlaybackSpeedLabel.text(0.75), "0.75×")
        XCTAssertEqual(PlaybackSpeedLabel.text(0.5), "0.5×")
        XCTAssertEqual(PlaybackSpeedLabel.text(.nan), "1×")
        XCTAssertEqual(PlaybackSpeedLabel.text(.infinity), "1×")
        XCTAssertFalse(PlaybackSpeedLabel.text(.greatestFiniteMagnitude).isEmpty)
    }

    func testControlsCanBeHiddenImmediately() {
        var controls = PlaybackControlsState()
        controls.interact(at: Date(), blocked: false)
        controls.hide()
        XCTAssertFalse(controls.isVisible)
        XCTAssertNil(controls.deadline)
    }

    // MARK: Progressive source search

    func testFastTopPriorityProviderIsDecisiveBeforeSlowBackupFinishes() async {
        let registry = ProviderRegistry(providers: [
            ProviderTests.FakeProvider(id: KodikProvider.providerID, displayName: "Kodik"),
            ProviderTests.FakeProvider(id: "anilibria", displayName: "Anilibria", delay: 1.5)
        ])
        let started = Date()
        var decisiveAfter: TimeInterval?
        var last: CandidateSearchUpdate?
        for await update in await registry.candidateUpdates(for: makeAnime(), episode: 1) {
            if decisiveAfter == nil, update.decisive != nil { decisiveAfter = Date().timeIntervalSince(started) }
            last = update
        }
        XCTAssertLessThan(decisiveAfter ?? .infinity, 1, "playback must not wait for the slow backup")
        XCTAssertEqual(last?.decisive?.providerID, KodikProvider.providerID)
        XCTAssertEqual(last?.candidates.count, 2, "the full list still arrives for the sources sheet")
        XCTAssertEqual(last?.isComplete, true)
    }

    func testLowerPriorityResultWaitsWhileBetterProviderIsPending() async {
        let registry = ProviderRegistry(providers: [
            ProviderTests.FakeProvider(id: KodikProvider.providerID, displayName: "Kodik", delay: 0.4),
            ProviderTests.FakeProvider(id: "anilibria", displayName: "Anilibria"),
            ProviderTests.FakeProvider(id: "test", displayName: "Test", providesTestContent: true)
        ])
        var updates: [CandidateSearchUpdate] = []
        for await update in await registry.candidateUpdates(for: makeAnime(), episode: 1) { updates.append(update) }
        for update in updates where update.pendingProviderIDs.contains(KodikProvider.providerID) {
            XCTAssertNil(update.decisive, "Anilibria/test must not start while Kodik may still answer")
        }
        XCTAssertEqual(updates.last?.decisive?.providerID, KodikProvider.providerID)
        XCTAssertEqual(updates.first?.candidates, [], "first snapshot reports pending providers only")
        XCTAssertEqual(updates.first?.pendingProviderIDs.count, 3)
    }

    func testUnavailableTopProviderLetsBackupBecomeDecisive() async {
        let registry = ProviderRegistry(providers: [
            ProviderTests.FakeProvider(id: KodikProvider.providerID, displayName: "Kodik", result: .failure(.unauthorized)),
            ProviderTests.FakeProvider(id: "anilibria", displayName: "Anilibria")
        ])
        var last: CandidateSearchUpdate?
        for await update in await registry.candidateUpdates(for: makeAnime(), episode: 1) { last = update }
        XCTAssertEqual(last?.decisive?.providerID.rawValue, "anilibria")
        let all = await registry.candidates(for: makeAnime(), episode: 1)
        XCTAssertEqual(all.map(\.providerID.rawValue), ["anilibria", KodikProvider.providerID.rawValue])
    }

    func testEmptyRegistryFinishesWithoutCandidates() async {
        let registry = ProviderRegistry(providers: [])
        var updates: [CandidateSearchUpdate] = []
        for await update in await registry.candidateUpdates(for: makeAnime(), episode: 1) { updates.append(update) }
        XCTAssertEqual(updates.count, 1)
        XCTAssertTrue(updates[0].isComplete)
        XCTAssertNil(updates[0].decisive)
    }

    // MARK: Retries

    private final class SleepLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [TimeInterval] = []
        func add(_ value: TimeInterval) { lock.lock(); values.append(value); lock.unlock() }
        var all: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return values }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
    }

    private func request(_ method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://example.org/x")!)
        request.httpMethod = method
        return request
    }

    func testGetIsRetriedAfterDroppedConnectionWithBackoff() async throws {
        let calls = Counter()
        let stub = StubTransport { _ in
            if calls.next() == 1 { throw APIError.network("lost", code: URLError.networkConnectionLost.rawValue) }
            return (200, Data("ok".utf8), [:])
        }
        let sleeps = SleepLog()
        let transport = RetryingTransport(base: stub, maxRetries: 2, baseDelay: 0.4) { sleeps.add($0) }
        let (data, response) = try await transport.send(request("GET"))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        XCTAssertEqual(stub.requests.count, 2)
        XCTAssertEqual(sleeps.all, [0.4])
    }

    func testWritesOfflineAndTimeoutsAreNeverRetried() async {
        let offline = StubTransport { _ in throw APIError.network("offline", code: URLError.notConnectedToInternet.rawValue) }
        let lost = StubTransport { _ in throw APIError.network("lost", code: URLError.networkConnectionLost.rawValue) }
        let slow = StubTransport { _ in throw APIError.network("slow", code: URLError.timedOut.rawValue) }
        for (stub, method) in [(offline, "GET"), (lost, "POST"), (lost, "PATCH"), (slow, "GET")] {
            let transport = RetryingTransport(base: stub, maxRetries: 2, baseDelay: 0) { _ in }
            let before = stub.requests.count
            do { _ = try await transport.send(request(method)); XCTFail("must throw") } catch {}
            XCTAssertEqual(stub.requests.count - before, 1, method)
        }
    }

    func testGatewayErrorsAreRetriedBoundedAndLongRetryAfterIsRespected() async throws {
        let stub = StubTransport { _ in (503, Data(), [:]) }
        let sleeps = SleepLog()
        let transport = RetryingTransport(base: stub, maxRetries: 2, baseDelay: 0.25) { sleeps.add($0) }
        let (_, response) = try await transport.send(request("GET"))
        XCTAssertEqual(response.statusCode, 503)
        XCTAssertEqual(stub.requests.count, 3)
        XCTAssertEqual(sleeps.all, [0.25, 0.5])

        let polite = StubTransport { _ in (503, Data(), ["Retry-After": "60"]) }
        _ = try await RetryingTransport(base: polite, baseDelay: 0) { _ in }.send(request("GET"))
        XCTAssertEqual(polite.requests.count, 1)

        let notFound = StubTransport { _ in (404, Data(), [:]) }
        _ = try await RetryingTransport(base: notFound, baseDelay: 0) { _ in }.send(request("GET"))
        XCTAssertEqual(notFound.requests.count, 1)
    }

    func testHeadHonoursShortRetryAfter() async throws {
        let calls = Counter()
        let stub = StubTransport { _ in
            calls.next() == 1 ? (503, Data(), ["Retry-After": "0.8"]) : (200, Data(), [:])
        }
        let sleeps = SleepLog()
        let transport = RetryingTransport(base: stub) { sleeps.add($0) }
        let (_, response) = try await transport.send(request("HEAD"))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(stub.requests.count, 2)
        XCTAssertEqual(sleeps.all, [0.8])
    }

    func testInvalidOrHTTPDateRetryAfterNeverRetriesEarly() async throws {
        for header in ["nan", "-1", "Wed, 21 Oct 2030 07:28:00 GMT"] {
            let stub = StubTransport { _ in (503, Data(), ["Retry-After": header]) }
            _ = try await RetryingTransport(base: stub) { _ in XCTFail("must not sleep") }.send(request("GET"))
            XCTAssertEqual(stub.requests.count, 1, header)
        }
    }

    func testCancelledBackoffSurfacesAsCancelled() async {
        let stub = StubTransport { _ in throw APIError.network("lost", code: URLError.networkConnectionLost.rawValue) }
        let transport = RetryingTransport(base: stub, maxRetries: 2, baseDelay: 0) { _ in throw CancellationError() }
        do { _ = try await transport.send(request("GET")); XCTFail("must throw") }
        catch { XCTAssertEqual(error as? APIError, .cancelled) }
        XCTAssertEqual(stub.requests.count, 1)
    }

    // MARK: Library dates

    func testSharedDateCodecSupportsConcurrentReadAndWriteFormatting() async {
        let valid = await withTaskGroup(of: Bool.self) { group in
            for offset in 0..<64 {
                group.addTask {
                    let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(offset))
                    let codec = LibraryDateCodec.shared
                    return codec.date(from: codec.string(from: date)) == date
                }
            }
            var result = true
            for await value in group { result = result && value }
            return result
        }
        XCTAssertTrue(valid)
    }

    func testSharedDateCodecKeepsFractionsAndReadsLegacyDates() throws {
        let codec = LibraryDateCodec.shared
        let date = Date(timeIntervalSince1970: 1_800_000_000.123)
        let restored = try XCTUnwrap(codec.date(from: codec.string(from: date)))
        XCTAssertEqual(restored.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(codec.date(from: "2027-01-15T08:00:00Z")?.timeIntervalSince1970, 1_800_000_000)
        XCTAssertNil(codec.date(from: "not a date"))
    }
}
