import SwiftUI
import AVFoundation
import AnivibeCore

struct SharedWatchPlayback {
    let roomId: String
    let episode: CanonicalWatchEpisode
    let mapping: WatchSourceMapping
    let userId: String
}

/// The player reports observations; only RPC responses can authorize playback/rewards.
@Observable @MainActor
final class SharedWatchCoordinator {
    private(set) var room: WatchRoom?
    private(set) var connected = false
    private(set) var message = "Подключаемся к комнате…"
    private(set) var isCommandPending = false
    @ObservationIgnored private weak var model: PlayerViewModel?
    @ObservationIgnored private let service: SupabaseCommunityService
    @ObservationIgnored private let session: SessionStore
    @ObservationIgnored private var context: SharedWatchPlayback
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var realtime: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var commandTask: Task<Void, Never>?
    @ObservationIgnored private let clientId = UUID()
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var switching = false
    @ObservationIgnored private var lastSnapshotUptime: TimeInterval = 0
    @ObservationIgnored private var fetchPending = false
    @ObservationIgnored private var telemetryPending = false
    @ObservationIgnored private var isForeground = true

    init(model: PlayerViewModel, context: SharedWatchPlayback, service: SupabaseCommunityService, session: SessionStore) {
        self.model = model; self.context = context; self.service = service; self.session = session
    }
    func start() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.validAccount else { break }
                await self.heartbeat()
                do { try await Task.sleep(nanoseconds: 12_000_000_000) } catch { break }
            }
        }
        realtime = Task { [weak self] in
            guard let self else { return }
            let stream = await service.invalidations(userId: context.userId, roomId: context.roomId)
            for await _ in stream {
                guard !Task.isCancelled, validAccount else { break }
                await fetch()
            }
        }
    }
    private var validAccount: Bool { !stopped && session.user?.id.lowercased() == context.userId.lowercased() }
    private func accept(_ value: WatchRoom) async {
        guard validAccount else { return }
        guard room == nil || value.revision > (room?.revision ?? 0) ||
            (value.revision == room?.revision && value.serverTime >= (room?.serverTime ?? 0)) else { return }
        room = value; connected = true; lastSnapshotUptime = ProcessInfo.processInfo.systemUptime
        if value.isClosed { model?.sharedPause(); message = "Комната закрыта. Вернитесь к выбору серии."; return }
        if value.episodeId != context.episode.id {
            model?.sharedPause()
            await switchEpisode(value)
            return
        }
        message = value.rewarded ? "Награда за эту серию уже подтверждена" :
            (!value.rewardsEligible || !context.mapping.verified ? value.rewardStatus :
                (value.playback == "waiting" ? "Ждём друга или загрузки источника…" : "Совместный просмотр · данные подтверждены сервером"))
        apply()
    }
    private func apply() {
        guard validAccount, isForeground, connected, let room, room.episodeId == context.episode.id, !switching else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - lastSnapshotUptime
        let target = WatchReconciliation.target(anchor: room.position, elapsed: elapsed, playing: room.playback == "playing", duration: room.duration)
        model?.applySharedPlayback(position: target + context.mapping.sourceOffset, playing: room.playback == "playing" && !room.isClosed)
    }
    func setActive(_ active: Bool) {
        isForeground = active
        if !active { model?.sharedPause() }
        playerStateChanged()
    }
    func playerStateChanged() {
        guard validAccount else { model?.sharedPause(); return }
        if !connected { model?.sharedPause() }
        apply()
        guard eventTask == nil else { return }
        eventTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard let self else { return }; defer { eventTask = nil }
            guard validAccount else { return }
            await heartbeat()
        }
    }
    private func fetch() async {
        guard validAccount, !fetchPending else { return }
        fetchPending = true
        defer { fetchPending = false }
        do { let value = try await service.room(context.roomId, userId: context.userId); await accept(value) }
        catch { disconnected(error) }
    }
    private func heartbeat() async {
        guard validAccount, let model, !telemetryPending, !switching else { return }
        guard model.phase == .ready else { await fetch(); return }
        telemetryPending = true; sequence += 1
        defer { telemetryPending = false }
        let state: String = !isForeground ? "unavailable" : (model.isScrubbing ? "ready" : (model.isBuffering ? "buffering" :
            (model.duration > 0 && model.currentTime >= model.duration - 0.3 ? "ended" : (model.isPlaying ? "playing" : "paused"))))
        let observedEpisode = context.episode.id
        do {
            let value = try await service.heartbeat(roomId: context.roomId, episodeId: observedEpisode, mappingId: context.mapping.id,
                eventId: UUID(), clientId: clientId, sequence: sequence, position: model.currentTime, duration: model.duration, state: state, userId: context.userId)
            guard context.episode.id == observedEpisode else { return }
            await accept(value)
        } catch { disconnected(error) }
    }
    func togglePlay() { command(room?.wantsPlay == true ? "pause" : "play") }
    func seek(to position: Double) {
        guard position.isFinite else { return }
        command("seek", position: max(0, position - context.mapping.sourceOffset))
    }
    func nextEpisode() {
        guard validAccount, room?.hostId.lowercased() == context.userId.lowercased(), !isCommandPending else { return }
        commandTask = Task { [weak self] in
            guard let self else { return }; isCommandPending = true
            defer { isCommandPending = false }
            do {
                let episodes = try await service.episodes(anilistId: context.episode.anilistId, after: context.episode.sortOrder, userId: context.userId)
                guard validAccount, let next = episodes.filter({ $0.animeId == context.episode.animeId && $0.sortOrder > context.episode.sortOrder }).min(by: { $0.sortOrder < $1.sortOrder }) else {
                    message = "Следующей подтверждённой серии нет в каталоге."; return
                }
                let value = try await service.action(roomId: context.roomId, action: "next", episodeId: next.id, userId: context.userId)
                await accept(value)
            } catch { disconnected(error) }
        }
    }
    private func command(_ action: String, position: Double? = nil) {
        guard validAccount, !isCommandPending, !switching else { return }
        if action == "pause" { model?.sharedPause() }
        isCommandPending = true
        commandTask = Task { [weak self] in
            guard let self else { return }
            defer { isCommandPending = false }
            do { let value = try await service.action(roomId: context.roomId, action: action, position: position, userId: context.userId); await accept(value) }
            catch { disconnected(error) }
        }
    }
    private func switchEpisode(_ value: WatchRoom) async {
        guard !switching else { return }
        switching = true; message = "Готовим следующую серию…"
        defer { switching = false }
        do {
            let episodes = try await service.episodes(anilistId: value.anilistId, after: max(0, value.episodeOrder - 1), userId: context.userId)
            guard validAccount, let episode = episodes.first(where: { $0.id == value.episodeId }),
                  let mapping = episode.sources.first(where: { $0.providerId == context.mapping.providerId && $0.voice == context.mapping.voice }) else {
                message = "Выберите источник новой серии в комнате. Плеер поставлен на паузу."; return
            }
            let updated = try await service.action(roomId: context.roomId, action: "source", mappingId: mapping.id, userId: context.userId)
            guard validAccount, updated.episodeId == episode.id else { return }
            context = SharedWatchPlayback(roomId: context.roomId, episode: episode, mapping: mapping, userId: context.userId)
            room = updated; lastSnapshotUptime = ProcessInfo.processInfo.systemUptime
            model?.configureSharedEpisode(episode, mapping: mapping, position: updated.position + mapping.sourceOffset)
            message = "Новая серия готовится. Нажмите Play, когда оба источника загрузятся."
        } catch { disconnected(error) }
    }
    private func disconnected(_ error: Error) {
        guard !stopped else { return }
        connected = false; model?.sharedPause(); message = CommunityStore.message(error)
    }
    func stop() {
        guard !stopped else { return }
        let shouldPause = validAccount
        let service = service, roomId = context.roomId, userId = context.userId
        stopped = true
        if shouldPause {
            Task { _ = try? await service.action(roomId: roomId, action: "pause", userId: userId) }
        }
        monitor?.cancel(); realtime?.cancel(); eventTask?.cancel(); commandTask?.cancel()
        monitor = nil; realtime = nil; eventTask = nil; commandTask = nil
        // No optimistic award and no unsafe offline queue. The peer waits; TTL closes an abandoned room.
    }
}
