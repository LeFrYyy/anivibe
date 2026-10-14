import SwiftUI
import AnivibeCore

struct WatchInviteView: View {
    var peerId: String? = nil
    var anilistId: Int? = nil
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var owner: String?
    @State private var selectedPeer = ""
    @State private var selectedAnime: Int?
    @State private var search = ""
    @State private var animeResults: [Anime] = []
    @State private var episodes: [CanonicalWatchEpisode] = []
    @State private var selectedEpisode = ""
    @State private var hasMoreEpisodes = false
    @State private var selectedMapping = ""
    @State private var createdRoom: String?
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var requestId = UUID()
    private var episode: CanonicalWatchEpisode? { episodes.first { $0.id == selectedEpisode } }
    var body: some View {
        Form {
            Section("Друг") {
                Picker("С кем смотрим", selection: $selectedPeer) {
                    Text("Выберите друга").tag("")
                    ForEach(env.community.hub?.friends ?? []) { friend in Text(friend.name).tag(friend.peerId) }
                }
                if env.community.hub?.friends.isEmpty != false { Text("Сначала добавьте друга и дождитесь принятия заявки.").font(.footnote) }
            }
            if anilistId == nil {
                Section("Аниме") {
                    TextField("Найти в каталоге", text: $search).autocorrectionDisabled()
                    ForEach(animeResults) { anime in
                        Button { selectedAnime = anime.id; animeResults = [] } label: {
                            HStack { Text(anime.title.preferred).lineLimit(2); Spacer(); if selectedAnime == anime.id { Image(systemName: "checkmark") } }
                        }
                    }
                    if let selectedAnime { Text("ID выбранного аниме: \(selectedAnime)").font(.caption) }
                }
            }
            Section("Каноническая серия") {
                if loading { ProgressView("Проверяем сопоставления…") }
                if !episodes.isEmpty {
                    Picker("Серия", selection: $selectedEpisode) {
                        Text("Выберите серию").tag("")
                        ForEach(episodes) { item in Text(item.label).tag(item.id) }
                    }
                } else if !loading, selectedAnime != nil {
                    Text("Для этого аниме сервер ещё не содержит явных сопоставлений серий. Это не ошибка источника; обычный просмотр работает как раньше.").font(.footnote)
                }
                if hasMoreEpisodes { Button("Загрузить следующие серии") { Task { await loadMoreEpisodes() } }.disabled(loading) }
                if let episode {
                    Picker("Ваш источник", selection: $selectedMapping) {
                        Text("Выберите источник").tag("")
                        ForEach(episode.sources) { source in Text(source.providerId + (source.voice.isEmpty ? "" : " · " + source.voice)).tag(source.id) }
                    }
                    Text(episode.verified ? "Продолжительность проверена. Награды потребуют подтверждённого просмотра обоих участников." : "Продолжительность не подтверждена: синхронизация доступна, награды отключены.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            Section {
                Button { Task { await invite() } } label: { Label(busy ? "Отправляем…" : "Отправить приглашение", systemImage: "paperplane").frame(minHeight: 32) }
                    .disabled(busy || loading || selectedPeer.isEmpty || selectedEpisode.isEmpty || selectedMapping.isEmpty)
                if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
            }
        }.navigationTitle("Смотреть вместе").navigationBarTitleDisplayMode(.inline)
        .task(id: session.user?.id) {
            owner = session.user?.id; selectedPeer = peerId ?? ""; selectedAnime = anilistId
            await env.community.refresh(service: env.communityService, userId: owner)
        }
        .task(id: selectedAnime) { await loadEpisodes() }
        .task(id: search) { await searchAnime() }
        .onChange(of: selectedEpisode) { _, _ in selectedMapping = ""; requestId = UUID() }
        .onChange(of: selectedPeer) { _, _ in requestId = UUID() }
        .onChange(of: selectedMapping) { _, _ in requestId = UUID() }
        .onChange(of: session.user?.id) { _, value in if owner != nil, value != owner { createdRoom = nil; dismiss() } }
        .navigationDestination(item: $createdRoom) { id in WatchRoomView(roomId: id) }
    }
    private func searchAnime() async {
        guard anilistId == nil, search.trimmingCharacters(in: .whitespaces).count >= 2 else { animeResults = []; return }
        let term = search
        do {
            try await Task.sleep(nanoseconds: 350_000_000)
            let page = try await env.catalog.search(CatalogQuery(search: term, sort: .relevance, perPage: 10))
            guard !Task.isCancelled, search == term else { return }; animeResults = page.items
        } catch { if !Task.isCancelled { self.error = CommunityStore.message(error) } }
    }
    private func loadEpisodes() async {
        episodes = []; selectedEpisode = ""; selectedMapping = ""; loading = false; hasMoreEpisodes = false
        guard let id = selectedAnime, let user = session.user?.id, let service = env.communityService else { return }
        loading = true
        defer { if selectedAnime == id { loading = false } }
        do {
            let result = try await service.episodes(anilistId: id, userId: user)
            guard !Task.isCancelled, session.user?.id == user, selectedAnime == id else { return }
            episodes = result; hasMoreEpisodes = result.count == 100; error = nil
        } catch { if !Task.isCancelled { self.error = CommunityStore.message(error) } }
    }
    private func loadMoreEpisodes() async {
        guard !loading, let id = selectedAnime, let user = session.user?.id, let service = env.communityService else { return }
        loading = true; let after = episodes.last?.sortOrder ?? 0
        defer { if selectedAnime == id { loading = false } }
        do {
            let result = try await service.episodes(anilistId: id, after: after, userId: user)
            guard !Task.isCancelled, session.user?.id == user, selectedAnime == id else { return }
            let known = Set(episodes.map(\.id)); episodes += result.filter { !known.contains($0.id) }
            hasMoreEpisodes = result.count == 100
        } catch { if !Task.isCancelled { self.error = CommunityStore.message(error) } }
    }
    private func invite() async {
        guard let user = session.user?.id, user == owner, let service = env.communityService, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let room = try await service.invite(peerId: selectedPeer, episodeId: selectedEpisode, mappingId: selectedMapping, requestId: requestId, userId: user)
            guard session.user?.id == user else { return }; createdRoom = room.id
            await env.community.refresh(service: service, userId: user)
        } catch { self.error = CommunityStore.message(error) }
    }
}

struct WatchRoomView: View {
    let roomId: String
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var room: WatchRoom?
    @State private var episodes: [CanonicalWatchEpisode] = []
    @State private var selectedMapping = ""
    @State private var playback: PlaybackRequest?
    @State private var owner: String?
    @State private var busy = false
    @State private var error: String?
    @State private var refreshPending = false
    private var episode: CanonicalWatchEpisode? { episodes.first { $0.id == room?.episodeId } }
    private var mapping: WatchSourceMapping? { episode?.sources.first { $0.id == selectedMapping } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let room {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Одна история, два экрана", systemImage: "play.rectangle.on.rectangle").font(.subheadline).foregroundStyle(Theme.accent)
                        Text(room.animeTitle).font(.title2.bold())
                        Text(room.episodeLabel).foregroundStyle(Theme.textSecondary)
                        Label(room.isClosed ? "Комната закрыта" : room.status == "invited" ? "Ждём принятия приглашения" : "Комната активна", systemImage: room.isClosed ? "xmark.circle" : "person.2")
                    }.profilePanel()
                    if !room.isClosed {
                        if let episode {
                            Picker("Ваш источник", selection: $selectedMapping) {
                                Text("Выберите источник").tag("")
                                ForEach(episode.sources) { source in Text(source.providerId + (source.voice.isEmpty ? "" : " · " + source.voice)).tag(source.id) }
                            }.pickerStyle(.menu)
                        }
                        if room.status == "invited" && room.guestId == session.user?.id {
                            Button("Принять приглашение") { Task { await act("accept") } }.buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent).disabled(mapping == nil || busy)
                            Button("Отклонить", role: .destructive) { Task { await act("decline") } }.disabled(busy)
                        } else if room.status == "active" {
                            Button { Task { await openPlayer() } } label: { Label("Открыть совместный плеер", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44) }
                                .buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent).disabled(mapping == nil || busy)
                            Button("Выйти из комнаты", role: .destructive) { Task { await act("leave") } }.disabled(busy)
                        } else { Text("Друг может выбрать свою озвучку после принятия приглашения.").font(.subheadline).foregroundStyle(Theme.textSecondary) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Подтверждённый прогресс").font(.headline)
                        ForEach(room.members) { member in
                            HStack { Text(member.userId == session.user?.id ? "Вы" : "Друг"); Spacer(); Text("\(Int(member.watchedProgress * 100))%").monospacedDigit() }
                            ProgressView(value: member.watchedProgress).tint(Theme.accent)
                        }
                        Text("Одновременно: \(Int(room.overlapProgress * 100))% / \(Int(room.overlapRatio * 100))%").font(.caption).foregroundStyle(Theme.textSecondary)
                        if room.rewarded { Label("Награда подтверждена сервером", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.success) }
                        Text("Каждому нужно подтвердить \(Int(room.completionRatio * 100))% серии. Перемотка, буферизация и повторные участки не добавляют время.").font(.footnote).foregroundStyle(Theme.textSecondary)
                        if !room.rewardsEligible { Label(room.rewardStatus, systemImage: "info.circle").font(.footnote) }
                    }.profilePanel()
                } else { ProgressView("Подключаемся к комнате…").frame(maxWidth: .infinity, minHeight: 180) }
                if busy { ProgressView("Ожидаем сервер…") }
                if let error { Text(error).font(.subheadline).foregroundStyle(Theme.danger); Button("Обновить") { Task { await refresh() } }.buttonStyle(.bordered) }
            }.padding(20)
        }.screenBackground().navigationTitle("Совместный просмотр").navigationBarTitleDisplayMode(.inline)
        .task(id: session.user?.id) {
            owner = session.user?.id; await refresh()
            guard let service = env.communityService, let user = session.user?.id else { return }
            let stream = await service.invalidations(userId: user, roomId: roomId)
            for await _ in stream { guard !Task.isCancelled, session.user?.id == user else { break }; if scenePhase == .active, playback == nil { await refresh() } }
        }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { break }
                if scenePhase == .active, playback == nil { await refresh() }
            }
        }
        .onChange(of: session.user?.id) { _, id in if owner != nil, owner != id { playback = nil; room = nil; dismiss() } }
        .fullScreenCover(item: $playback, onDismiss: { Task { await refresh() } }) { request in PlayerScreen(request: request) }
    }
    private func refresh() async {
        guard !refreshPending, let service = env.communityService, let user = session.user?.id else { return }
        refreshPending = true; defer { refreshPending = false }
        do {
            let latest = try await service.room(roomId, userId: user)
            guard !Task.isCancelled, session.user?.id == user else { return }
            let changed = room?.episodeId != latest.episodeId; room = latest
            if episodes.isEmpty || changed {
                let result = try await service.episodes(anilistId: latest.anilistId, after: max(0, latest.episodeOrder - 1), userId: user)
                guard !Task.isCancelled, session.user?.id == user else { return }; episodes = result
                selectedMapping = latest.member(user)?.mappingId ?? ""
            }
            error = nil
        } catch { if !Task.isCancelled { self.error = CommunityStore.message(error) } }
    }
    private func act(_ action: String) async {
        guard let service = env.communityService, let user = session.user?.id, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await service.action(roomId: roomId, action: action, mappingId: selectedMapping.isEmpty ? nil : selectedMapping, userId: user)
            guard session.user?.id == user else { return }; room = value; error = nil
            await env.community.refresh(service: service, userId: user)
        } catch { self.error = CommunityStore.message(error) }
    }
    private func openPlayer() async {
        guard let service = env.communityService, let user = session.user?.id, let episode, let mapping, let animeId = episode.anilistId, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await service.action(roomId: roomId, action: "source", mappingId: mapping.id, userId: user)
            guard session.user?.id == user, !value.isClosed else { return }; room = value
            let source = mapping.sourceEpisode
            let anime = Anime(id: animeId, title: AnimeTitle(russian: episode.animeTitle))
            let localEpisode = Episode(animeId: animeId, season: source.season ?? 1, number: source.number, title: episode.label, sourceEpisode: source)
            playback = PlaybackRequest(anime: anime, episodes: [localEpisode], episode: localEpisode.number,
                startPosition: max(0, value.position + mapping.sourceOffset), sharedWatch: SharedWatchPlayback(roomId: roomId, episode: episode, mapping: mapping, userId: user))
        } catch { self.error = CommunityStore.message(error) }
    }
}
