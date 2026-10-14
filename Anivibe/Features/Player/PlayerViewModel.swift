import AVFoundation
import SwiftUI
import AnivibeCore

/// Состояние и логика плеера на AVPlayer: источники, воспроизведение, дорожки, прогресс.
@Observable
@MainActor
final class PlayerViewModel {
    enum Phase: Equatable {
        case searchingSources
        case preparing
        case ready
        case failed(String)
        case noSources
    }

    struct TrackOption: Identifiable, Hashable {
        let id: String
        let name: String
        /// Индекс в `AVMediaSelectionGroup.options`; `nil` — «выключено».
        let index: Int?
    }

    let anime: Anime
    private(set) var episodes: [Episode]
    private(set) var episodeNumber: Int
    private(set) var phase: Phase = .searchingSources
    private(set) var candidates: [SourceCandidate] = []
    private(set) var activeCandidate: SourceCandidate?
    private(set) var source: PlaybackSource?
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var duration: Double = 0
    private(set) var bufferedTime: Double = 0
    var currentTime: Double = 0
    var isScrubbing = false

    var bufferedFraction: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, max(0.0, bufferedTime / duration))
    }
    private(set) var audioOptions: [TrackOption] = []
    private(set) var subtitleOptions: [TrackOption] = []
    private(set) var selectedAudioID: String?
    private(set) var selectedSubtitleID: String?
    private(set) var nextEpisodeCountdown: Int?

    var sharedWatch: SharedWatchCoordinator?
    let player = AVPlayer()
    private let registry: ProviderRegistry
    private let library: LibraryStore
    private let progressAccountID: String?
    private let autoplayNext: () -> Bool
    @ObservationIgnored private var startPosition: Double
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var playerObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var appTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var audioGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var subtitleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var preparationTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var progressSaveTask: Task<Void, Never>?
    @ObservationIgnored private var seekGeneration = UUID()
    @ObservationIgnored private var lastSavedProgress: SavedProgress?
    @ObservationIgnored private var lastSaveDate = Date.distantPast
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var isTornDown = false
    @ObservationIgnored private var restoringPosition = false
    @ObservationIgnored private var resumeAfterLoad = true
    @ObservationIgnored private var hasActuallyPlayed = false

    static let saveInterval: TimeInterval = 5

    private struct SavedProgress: Equatable {
        let episode: Int
        let position: Double
        let duration: Double
        let sourceKey: String?
    }

    init(request: PlaybackRequest, registry: ProviderRegistry, library: LibraryStore, accountID: String?, autoplayNext: @escaping () -> Bool) {
        anime = request.anime
        episodes = request.episodes
        episodeNumber = request.episode
        startPosition = request.startPosition
        self.registry = registry
        self.library = library
        progressAccountID = accountID
        self.autoplayNext = autoplayNext
    }

    var currentEpisode: Episode? { episodes.first { $0.number == episodeNumber } }
    var hasNextEpisode: Bool { sharedWatch != nil || episodes.contains { $0.number == episodeNumber + 1 } }
    var hasPreviousEpisode: Bool { episodes.contains { $0.number == episodeNumber - 1 } }
    var otherAvailableCandidates: [SourceCandidate] {
        candidates.filter { $0.availability.isAvailable && $0.providerID != activeCandidate?.providerID }
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true
        player.defaultRate = playbackSpeed
        configureAudioSession()
        observePlayer()
        observeApp()
        findSources()
    }

    /// Освобождает ресурсы: сохраняет прогресс, снимает всех наблюдателей, останавливает плеер.
    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        sharedWatch?.stop()
        saveProgress(force: true)
        loadTask?.cancel()
        countdownTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        playerObservations.forEach { $0.invalidate() }
        playerObservations.removeAll()
        clearItemObservers()
        appTokens.forEach { NotificationCenter.default.removeObserver($0) }
        appTokens.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var kodikWebURL: URL? {
        guard let episode = activeCandidate?.episode else { return nil }
        return KodikProvider.playerURL(for: episode)
    }
    func pauseForWebPlayer() { saveProgress(force: true); sharedWatch?.setActive(false); player.pause() }

    // MARK: - Sources

    func findSources() {
        guard !isTornDown else { return }
        loadTask?.cancel()
        cancelCountdown()
        phase = .searchingSources
        candidates = []
        let episode = episodeNumber
        loadTask = Task { [weak self] in
            guard let self else { return }
            let found: [SourceCandidate]
            if let exact = self.currentEpisode?.sourceEpisode, let provider = await registry.provider(exact.providerID) {
                let availability = await provider.checkAvailability(exact)
                found = [SourceCandidate(providerID: provider.id, providerName: provider.displayName,
                    isTestContent: provider.providesTestContent, episode: exact, availability: availability)]
            } else {
                found = await registry.candidates(for: anime, season: self.currentEpisode?.season ?? 1, episode: episode)
            }
            guard !Task.isCancelled, !self.isTornDown, episode == self.episodeNumber else { return }
            self.candidates = found
            if let first = found.first(where: { $0.availability.isAvailable }) {
                await self.play(candidate: first)
            } else {
                self.phase = .noSources
            }
        }
    }

    func select(candidate: SourceCandidate) {
        guard !isTornDown, candidate.availability.isAvailable else { return }
        saveProgress(force: true)
        resumeAfterLoad = isPlaying || isBuffering
        startPosition = currentTime > 1 ? currentTime : startPosition
        loadTask?.cancel()
        loadTask = Task { [weak self] in await self?.play(candidate: candidate) }
    }

    /// Повтор: заново получаем ссылку (временные ссылки не переиспользуются).
    func retry() {
        guard !isTornDown else { return }
        if let activeCandidate {
            startPosition = max(startPosition, currentTime)
            loadTask?.cancel()
            loadTask = Task { [weak self] in await self?.play(candidate: activeCandidate) }
        } else {
            findSources()
        }
    }

    private func play(candidate: SourceCandidate) async {
        guard !Task.isCancelled, !isTornDown else { return }
        player.pause()
        source = nil
        hasActuallyPlayed = false
        activeCandidate = candidate
        phase = .preparing
        guard let episode = candidate.episode, let provider = await registry.provider(candidate.providerID) else {
            if !Task.isCancelled, !isTornDown { phase = .failed("Источник недоступен.") }
            return
        }
        guard !Task.isCancelled, !isTornDown else { return }
        do {
            let resolved = try await provider.resolve(episode)
            guard !Task.isCancelled, !isTornDown else { return }
            guard !resolved.isExpired() else { throw VideoSourceError.linkExpired }
            source = resolved
            load(resolved)
        } catch let error as VideoSourceError {
            if !Task.isCancelled { phase = .failed(error.userMessage) }
        } catch {
            if !Task.isCancelled { phase = .failed(VideoSourceError.network(error.localizedDescription).userMessage) }
        }
    }

    private func load(_ source: PlaybackSource) {
        clearItemObservers()
        hasActuallyPlayed = false
        audioOptions = []
        subtitleOptions = []
        duration = 0
        currentTime = startPosition
        restoringPosition = true
        phase = .preparing
        let item = AVPlayerItem(url: source.url)
        observe(item: item)
        player.replaceCurrentItem(with: item)
        preparationTask = Task { [weak self, weak item] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) }
            catch { return }
            guard !Task.isCancelled, let self, let item, !self.isTornDown,
                  self.player.currentItem === item, self.phase == .preparing else { return }
            // A stalled asset/track/initial-seek load must offer Retry, not spin forever.
            self.player.pause()
            self.clearItemObservers()
            self.player.replaceCurrentItem(with: nil)
            self.restoringPosition = false
            self.phase = .failed("Видео не удалось подготовить за 30 секунд. Проверьте сеть или выберите другой источник.")
        }
    }

    // MARK: - Observers

    private func observePlayer() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, !self.isTornDown, !self.isScrubbing, !self.restoringPosition, self.phase == .ready else { return }
                let seconds = time.seconds
                if seconds.isFinite, seconds >= 0, self.currentTime != seconds { self.currentTime = seconds }
                if self.isPlaying && seconds > 0 { self.hasActuallyPlayed = true }
                self.saveProgress(force: false)
            }
        }
        playerObservations.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isTornDown else { return }
                // Read the latest status instead of applying a queued, stale KVO value.
                let status = self.player.timeControlStatus
                self.isPlaying = status == .playing
                switch status {
                case .playing:
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                case .paused:
                    if let item = self.player.currentItem {
                        self.isBuffering = item.isPlaybackBufferEmpty && !item.isPlaybackLikelyToKeepUp && !item.isPlaybackBufferFull
                    } else {
                        self.isBuffering = false
                    }
                @unknown default:
                    break
                }
            }
        })
    }

    private func observe(item: AVPlayerItem) {
        itemObservations.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error.map(Self.describe)
            Task { @MainActor [weak self] in
                guard let self, !self.isTornDown, self.player.currentItem === item else { return }
                switch status {
                case .readyToPlay: await self.itemBecameReady(item)
                case .failed:
                    self.preparationTask?.cancel()
                    self.preparationTask = nil
                    self.phase = .failed(message ?? "Не удалось воспроизвести поток.")
                default: break
                }
            }
        })
        itemObservations.append(item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            let empty = item.isPlaybackBufferEmpty
            Task { @MainActor [weak self] in
                guard let self, !self.isTornDown, self.player.currentItem === item else { return }
                if empty {
                    self.isBuffering = true
                } else if item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull {
                    self.isBuffering = false
                }
            }
        })
        itemObservations.append(item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            let likely = item.isPlaybackLikelyToKeepUp
            Task { @MainActor [weak self] in
                guard let self, !self.isTornDown, self.player.currentItem === item else { return }
                if likely {
                    self.isBuffering = false
                }
            }
        })
        itemObservations.append(item.observe(\.isPlaybackBufferFull, options: [.new]) { [weak self] item, _ in
            let full = item.isPlaybackBufferFull
            Task { @MainActor [weak self] in
                guard let self, !self.isTornDown, self.player.currentItem === item else { return }
                if full {
                    self.isBuffering = false
                }
            }
        })
        itemObservations.append(item.observe(\.loadedTimeRanges, options: [.initial, .new]) { [weak self] item, _ in
            let ranges = item.loadedTimeRanges
            Task { @MainActor [weak self] in
                guard let self, !self.isTornDown, self.player.currentItem === item else { return }
                self.updateLoadedTimeRanges(ranges)
            }
        })
        let center = NotificationCenter.default
        itemTokens.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isTornDown, self.player.currentItem === item else { return }
                self.playbackEnded()
            }
        })
        itemTokens.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated {
                guard let self, !self.isTornDown, self.player.currentItem === item else { return }
                self.saveProgress(force: true)
                self.phase = .failed(error.map(Self.describe) ?? "Воспроизведение прервано.")
            }
        })
    }

    private func observeApp() {
        let center = NotificationCenter.default
        appTokens.append(center.addObserver(forName: .anivibeWillResignActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveProgress(force: true) }
        })
        appTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                if type == .began { self?.saveProgress(force: true) }
            }
        })
    }

    private func clearItemObservers() {
        preparationTask?.cancel()
        preparationTask = nil
        seekGeneration = UUID()
        isScrubbing = false
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
        itemTokens.forEach { NotificationCenter.default.removeObserver($0) }
        itemTokens.removeAll()
        player.currentItem?.cancelPendingSeeks()
        player.currentItem?.asset.cancelLoading()
        bufferedTime = 0
    }

    private func updateLoadedTimeRanges(_ ranges: [NSValue]) {
        var maxLoaded: Double = 0
        for val in ranges {
            let r = val.timeRangeValue
            let start = r.start.seconds
            let dur = r.duration.seconds
            if start.isFinite && dur.isFinite {
                let end = start + dur
                if end > maxLoaded { maxLoaded = end }
            }
        }
        if bufferedTime != maxLoaded { bufferedTime = maxLoaded }
        if let item = player.currentItem, (item.isPlaybackLikelyToKeepUp || item.isPlaybackBufferFull) {
            self.isBuffering = false
        }
    }

    private func itemBecameReady(_ item: AVPlayerItem) async {
        let loadedDuration = try? await item.asset.load(.duration)
        guard player.currentItem === item, !isTornDown else { return }
        if let d = loadedDuration, d.seconds.isFinite { duration = d.seconds }
        await loadTracks(for: item)
        guard player.currentItem === item, !isTornDown else { return }
        if startPosition > 0 {
            let target = duration > 0 ? min(startPosition, max(0, duration - 0.1)) : startPosition
            let succeeded = await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            guard player.currentItem === item, !isTornDown else { return }
            guard succeeded else { phase = .failed("Не удалось восстановить позицию. Повторите загрузку."); return }
            currentTime = target
        }
        startPosition = 0
        restoringPosition = false
        preparationTask?.cancel()
        preparationTask = nil
        phase = .ready
        if sharedWatch != nil { player.pause(); sharedWatch?.playerStateChanged() }
        else if resumeAfterLoad { player.playImmediately(atRate: playbackSpeed) } else { player.pause() }
    }

    // MARK: - Tracks

    private func loadTracks(for item: AVPlayerItem) async {
        let asset = item.asset
        let loadedAudio = try? await asset.loadMediaSelectionGroup(for: .audible)
        guard player.currentItem === item, !isTornDown else { return }
        if let group = loadedAudio, !group.options.isEmpty {
            audioGroup = group
            audioOptions = group.options.enumerated().map { TrackOption(id: "audio-\($0.offset)", name: Self.trackName($0.element), index: $0.offset) }
            if let selected = item.currentMediaSelection.selectedMediaOption(in: group), let i = group.options.firstIndex(of: selected) {
                selectedAudioID = "audio-\(i)"
            }
        } else {
            audioGroup = nil
        }
        let loadedSubtitles = try? await asset.loadMediaSelectionGroup(for: .legible)
        guard player.currentItem === item, !isTornDown else { return }
        if let group = loadedSubtitles, !group.options.isEmpty {
            subtitleGroup = group
            var options = group.options.enumerated().map { TrackOption(id: "sub-\($0.offset)", name: Self.trackName($0.element), index: $0.offset) }
            if group.allowsEmptySelection { options.insert(TrackOption(id: "sub-off", name: "Выключены", index: nil), at: 0) }
            subtitleOptions = options
            if let selected = item.currentMediaSelection.selectedMediaOption(in: group), let i = group.options.firstIndex(of: selected) {
                selectedSubtitleID = "sub-\(i)"
            } else {
                selectedSubtitleID = "sub-off"
            }
        } else {
            subtitleGroup = nil
        }
    }

    func selectAudio(_ option: TrackOption) {
        guard let group = audioGroup, let index = option.index, group.options.indices.contains(index), let item = player.currentItem else { return }
        item.select(group.options[index], in: group)
        selectedAudioID = option.id
    }

    func selectSubtitle(_ option: TrackOption) {
        guard let group = subtitleGroup, let item = player.currentItem else { return }
        if let index = option.index, group.options.indices.contains(index) {
            item.select(group.options[index], in: group)
        } else {
            item.select(nil, in: group)
        }
        selectedSubtitleID = option.id
    }

    // MARK: - Качество, скорость, озвучка (Kodik)

    static let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private(set) var playbackSpeed: Float = PlayerViewModel.storedSpeed()

    var qualities: [PlaybackQuality] { source?.qualities ?? [] }
    var currentQualityHeight: Int? {
        guard let source else { return nil }
        return source.qualities.first { $0.url == source.url }?.height
    }
    var qualityMenuTitle: String {
        "Качество: " + (currentQualityHeight.map { "\($0)p" } ?? "Авто")
    }
    var voices: [String] { source?.voices ?? [] }
    var selectedVoice: String? { source?.selectedVoice }

    nonisolated private static func storedSpeed() -> Float {
        let value = UserDefaults.standard.double(forKey: KodikPreferences.speedKey)
        return value > 0 ? Float(value) : 1.0
    }

    func selectQuality(_ quality: PlaybackQuality) {
        guard phase == .ready, let current = source, current.qualities.contains(where: { $0.url == quality.url && $0.height == quality.height }), quality.url != current.url else { return }
        UserDefaults.standard.set(quality.height, forKey: KodikPreferences.qualityKey)
        saveProgress(force: true)
        resumeAfterLoad = isPlaying || isBuffering
        startPosition = currentTime
        let updated = current.with(url: quality.url)
        source = updated
        load(updated)
    }

    func setSpeed(_ speed: Float) {
        guard sharedWatch == nil else { return }
        playbackSpeed = speed
        UserDefaults.standard.set(Double(speed), forKey: KodikPreferences.speedKey)
        player.defaultRate = speed
        if player.rate > 0 { player.rate = speed }
    }

    func selectVoice(_ voice: String) {
        guard sharedWatch == nil else { return }
        guard voice != selectedVoice, let candidate = activeCandidate, let episode = candidate.episode,
              candidate.providerID == KodikProvider.providerID else { return }
        UserDefaults.standard.set(voice, forKey: KodikPreferences.voiceKey)
        let updated = SourceCandidate(providerID: candidate.providerID, providerName: candidate.providerName,
                                      isTestContent: candidate.isTestContent,
                                      episode: KodikProvider.episode(episode, withVoice: voice),
                                      availability: candidate.availability)
        if let index = candidates.firstIndex(where: { $0.providerID == candidate.providerID }) {
            candidates[index] = updated
        }
        select(candidate: updated)
    }

    private static func trackName(_ option: AVMediaSelectionOption) -> String {
        var name = option.displayName
        if option.hasMediaCharacteristic(.containsOnlyForcedSubtitles) { name += " (только надписи)" }
        return name
    }

    // MARK: - Transport

    func togglePlay() {
        if let sharedWatch { sharedWatch.togglePlay(); return }
        if isPlaying { player.pause(); saveProgress(force: true) } else { cancelCountdown(); player.play() }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: Double) {
        if let sharedWatch { sharedWatch.seek(to: seconds); return }
        performSeek(to: seconds)
    }

    private func performSeek(to seconds: Double) {
        guard !isTornDown, phase == .ready, seconds.isFinite, let item = player.currentItem else { return }
        let upper = duration > 0 ? duration : seconds
        let target = min(max(0, seconds), upper)
        let requestID = UUID()
        seekGeneration = requestID
        item.cancelPendingSeeks()
        isScrubbing = true
        currentTime = target
        if !item.isPlaybackLikelyToKeepUp {
            isBuffering = true
        }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, !self.isTornDown,
                      self.player.currentItem === item, self.seekGeneration == requestID else { return }
                self.isScrubbing = false
                self.isBuffering = item.isPlaybackBufferEmpty && !item.isPlaybackLikelyToKeepUp && !item.isPlaybackBufferFull
                if !finished {
                    let actual = self.player.currentTime().seconds
                    if actual.isFinite, actual >= 0 { self.currentTime = actual }
                    return
                }
                self.saveProgress(force: true)
            }
        }
    }

    func sharedPause() { player.pause() }
    func useSharedSpeed() { playbackSpeed = 1; player.defaultRate = 1 }

    func applySharedPlayback(position: Double, playing: Bool) {
        guard !isTornDown, phase == .ready, position.isFinite else { player.pause(); return }
        if !isScrubbing, WatchReconciliation.needsSeek(local: currentTime, target: position) { performSeek(to: position) }
        let atEnd = duration > 0 && currentTime >= duration - 0.3
        if playing && !atEnd && !isBuffering && !isScrubbing { player.playImmediately(atRate: 1) }
        else { player.pause() }
    }

    func configureSharedEpisode(_ episode: CanonicalWatchEpisode, mapping: WatchSourceMapping, position: Double) {
        guard !isTornDown else { return }
        saveProgress(force: true); player.pause(); clearItemObservers(); player.replaceCurrentItem(with: nil)
        let sourceEpisode = mapping.sourceEpisode
        episodes = [Episode(animeId: anime.id, season: sourceEpisode.season ?? 1, number: sourceEpisode.number,
                            title: episode.label, sourceEpisode: sourceEpisode)]
        episodeNumber = sourceEpisode.number; source = nil; hasActuallyPlayed = false; resumeAfterLoad = false
        startPosition = max(0, position); currentTime = startPosition; findSources()
    }

    // MARK: - Episodes

    func selectEpisode(_ number: Int) {
        guard sharedWatch == nil else { return }
        guard !isTornDown, number != episodeNumber || phase != .ready,
              episodes.contains(where: { $0.number == number }) else { return }
        saveProgress(force: true)
        player.pause()
        clearItemObservers()
        player.replaceCurrentItem(with: nil)
        source = nil
        hasActuallyPlayed = false
        resumeAfterLoad = true
        episodeNumber = number
        let saved = library.progress(anime.id, episode: currentEpisode?.progressNumber ?? number, sourceKey: currentEpisode?.sourceKey)
        startPosition = (saved?.isFinished ?? true) ? 0 : saved?.position ?? 0
        currentTime = startPosition
        findSources()
    }

    func playNextEpisode() {
        if let sharedWatch { sharedWatch.nextEpisode(); return }
        cancelCountdown()
        guard hasNextEpisode else { return }
        selectEpisode(episodeNumber + 1)
    }

    private func playbackEnded() {
        if duration > 0 { currentTime = duration }
        saveProgress(force: true)
        isPlaying = false
        guard hasNextEpisode, autoplayNext() else { return }
        nextEpisodeCountdown = 5
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for remaining in stride(from: 5, through: 1, by: -1) {
                await MainActor.run { self?.nextEpisodeCountdown = remaining }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            await MainActor.run { self?.playNextEpisode() }
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        nextEpisodeCountdown = nil
    }

    // MARK: - Progress

    private func saveProgress(force: Bool) {
        guard source != nil, source?.isTestContent != true, hasActuallyPlayed, !restoringPosition, currentTime > 0 else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSaveDate) >= Self.saveInterval else { return }
        guard force || isPlaying else { return }
        let snapshot = anime.snapshot
        let kodikEpisode = activeCandidate?.providerID == KodikProvider.providerID ? activeCandidate?.episode : nil
        let (episode, position, total) = (kodikEpisode?.number ?? currentEpisode?.progressNumber ?? episodeNumber, currentTime, duration)
        let key = kodikEpisode?.id ?? currentEpisode?.sourceKey
        let sample = SavedProgress(episode: episode, position: position, duration: total, sourceKey: key)
        guard sample != lastSavedProgress || library.errorMessage != nil else { return }
        lastSaveDate = now
        lastSavedProgress = sample
        let previousSave = progressSaveTask
        // Preserve pause/seek/exit ordering. The final save deliberately survives teardown.
        progressSaveTask = Task { [library, progressAccountID] in
            await previousSave?.value
            await library.recordProgress(anime: snapshot, episode: episode, position: position,
                                         duration: total, sourceKey: key, accountID: progressAccountID)
        }
    }

    // MARK: - Helpers

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    nonisolated static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "Нет подключения к интернету."
            case NSURLErrorTimedOut: return "Сервер видео не отвечает."
            case NSURLErrorAppTransportSecurityRequiresSecureConnection: return "Источник использует небезопасное соединение (http). Такие потоки не поддерживаются."
            case NSURLErrorFileDoesNotExist, NSURLErrorResourceUnavailable: return "Видео не найдено у источника."
            default: return "Сетевая ошибка при загрузке видео (\(ns.code))."
            }
        }
        if ns.domain == AVFoundationErrorDomain {
            switch AVError.Code(rawValue: ns.code) {
            case .contentIsProtected?: return "Видео защищено DRM и не может быть воспроизведено в Anivibe."
            case .fileFormatNotRecognized?, .decoderNotFound?: return "Формат потока не поддерживается AVPlayer."
            case .contentIsNotAuthorized?: return "Нет доступа к видео у источника."
            default: break
            }
        }
        return "Ошибка воспроизведения: \(ns.localizedDescription)"
    }
}

enum TimeFormat {
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
