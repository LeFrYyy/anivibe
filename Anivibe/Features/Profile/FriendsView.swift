import SwiftUI
import AnivibeCore

struct FriendsView: View {
    enum Tab: String, CaseIterable { case friends = "Друзья", requests = "Заявки", search = "Поиск" }
    @Bindable var store: SocialStore
    let userID: String
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .friends
    @State private var username = ""
    @State private var lastSearch = ""
    @State private var removeTarget: String?
    private var accepted: [Friendship] { store.friendships.filter { $0.status == "accepted" } }
    private var incoming: [Friendship] { store.friendships.filter { $0.status == "pending" && $0.requesterID != userID } }
    private var outgoing: [Friendship] { store.friendships.filter { $0.status == "pending" && $0.requesterID == userID } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Смотрите. Делитесь. Обсуждайте.").font(.title2.bold())
                    Text("Ваши люди и их аниме — в одном месте.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Picker("Раздел", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0 == .requests && !incoming.isEmpty ? "Заявки · \(incoming.count)" : $0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                if store.isLoading || store.isSaving { ProgressView("Обновляем…").frame(maxWidth: .infinity) }
                if let error = store.errorMessage {
                    SocialErrorPanel(message: error) { Task { await reload() } }
                }
                switch tab {
                case .friends:
                    Text("Друзья · \(accepted.count)/10").font(.headline)
                    if accepted.isEmpty && !store.isLoading {
                        SocialEmptyPanel(icon: "person.2", title: "Хорошие истории лучше вместе", message: "Найдите друга по username и отправьте приглашение.")
                        Button("Найти друзей") { tab = .search }.buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(Theme.onAccent)
                    }
                    ForEach(accepted) { edge in friendCard(edge) }
                case .requests:
                    Text("Входящие · \(incoming.count)").font(.headline)
                    if incoming.isEmpty { SocialEmptyPanel(icon: "tray", title: "Новых заявок нет", message: "Приглашения в друзья появятся здесь.") }
                    ForEach(incoming) { edge in friendCard(edge) }
                    Text("Отправленные · \(outgoing.count)").font(.headline)
                    if outgoing.isEmpty { Text("Вы пока не отправляли приглашений.").foregroundStyle(Theme.textSecondary).font(.subheadline) }
                    ForEach(outgoing) { edge in friendCard(edge) }
                case .search:
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                            TextField("Username друга", text: $username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .submitLabel(.search).onSubmit { Task { await runSearch() } }
                            if store.isSearching { ProgressView() }
                        }.frame(minHeight: 44)
                        Text("Минимум 3 символа. В поиске — публичные профили и ваши друзья.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }.profilePanel()
                    if let error = store.searchError { SocialErrorPanel(message: error) { lastSearch = ""; Task { await runSearch() } } }
                    ForEach(store.searchResults) { profile in
                        VStack(alignment: .leading, spacing: 12) {
                            NavigationLink { PublicProfileView(profile: profile) } label: { SocialPersonRow(profile: profile) }.buttonStyle(.plain)
                            relationAction(profile.userID)
                        }.profilePanel()
                    }
                    if store.searchResults.isEmpty && !store.isSearching {
                        SocialEmptyPanel(icon: "person.crop.circle.badge.magnifyingglass",
                            title: lastSearch.isEmpty ? "Найдите своих" : "Ничего не найдено",
                            message: "Введите username без @. Приватные профили могут быть недоступны в поиске.")
                    }
                }
            }.padding(16).padding(.bottom, 16)
        }
        .screenBackground().navigationTitle("Друзья").navigationBarTitleDisplayMode(.inline)
        .task(id: userID) { await reload() }
        .task(id: username) {
            if tab == .search {
                let term = normalizedSearch
                if term.count < 3 { lastSearch = ""; store.clearSearch(); return }
                do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                await runSearch()
            }
        }
        .onChange(of: session.user?.id) { _, id in if id != userID { store.clearSearch(); dismiss() } }
        .toolbar { Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Обновить друзей").disabled(store.isLoading || store.isSaving) }
        .refreshable { await reload() }
        .confirmationDialog("Удалить из друзей?", isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let id = removeTarget { Task { await store.act(targetID: id, action: .remove) } }; removeTarget = nil }
            Button("Отмена", role: .cancel) { removeTarget = nil }
        }
    }
    private var normalizedSearch: String { username.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased() }
    private func runSearch() async {
        let term = normalizedSearch
        guard term.count >= 3, lastSearch != term, session.user?.id == userID else { return }
        lastSearch = term; await store.search(term)
        if Task.isCancelled { lastSearch = "" }
    }
    private func reload() async {
        guard session.user?.id == userID else { return }
        await store.load(service: env.socialService, userID: userID)
    }
    @ViewBuilder private func friendCard(_ edge: Friendship) -> some View {
        let id = edge.peerID(for: userID)
        VStack(alignment: .leading, spacing: 12) {
            if let profile = store.peers[id] {
                NavigationLink { PublicProfileView(profile: profile) } label: { SocialPersonRow(profile: profile) }.buttonStyle(.plain)
            } else { Label("Профиль недоступен", systemImage: "lock").foregroundStyle(Theme.textSecondary) }
            relationAction(id)
        }.profilePanel()
    }
    @ViewBuilder private func relationAction(_ target: String) -> some View {
        if let edge = store.edge(with: target) {
            if edge.status == "accepted" {
                HStack {
                    Label("В друзьях", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(Theme.success)
                    Spacer()
                    Button { removeTarget = target } label: { Image(systemName: "person.badge.minus").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Удалить из друзей").disabled(store.isSaving)
                }
            } else if edge.requesterID != userID {
                HStack {
                    Button("Принять") { Task { await store.act(targetID: target, action: .accept) } }.buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(Theme.onAccent)
                    Button("Отклонить") { Task { await store.act(targetID: target, action: .decline) } }.buttonStyle(.bordered).controlSize(.large)
                }.disabled(store.isSaving)
            } else {
                Button("Отменить приглашение") { Task { await store.act(targetID: target, action: .cancel) } }.buttonStyle(.bordered).controlSize(.large).disabled(store.isSaving)
            }
        } else {
            Button { Task { await store.act(targetID: target, action: .send) } } label: { Label("Добавить в друзья", systemImage: "person.badge.plus") }
                .buttonStyle(.bordered).controlSize(.large).disabled(store.isSaving || store.isLoading)
        }
    }
}

struct PublicProfileView: View {
    let profile: UserProfile
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var data: SocialProfileStore
    @State private var relationships = SocialStore()
    @State private var viewerID: String?
    @State private var confirmRemove = false
    init(profile: UserProfile) { self.profile = profile; _data = State(initialValue: SocialProfileStore(targetID: profile.userID)) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if let details = data.details {
                    ProfileIdentityView(profile: details.profile, fallbackSubtitle: "Пока ничего о себе")
                        .padding(.vertical, 12)
                    if details.profile.userID != session.user?.id { friendshipActions }
                    counters(details)
                    friendPreview(details)
                    historyPreview(details)
                    libraryPreview(details)
                } else if data.isLoading {
                    ProgressView("Загружаем профиль…").frame(maxWidth: .infinity, minHeight: 240)
                }
                if let error = data.errorMessage { SocialErrorPanel(message: error) { Task { await reload() } } }
                if let error = relationships.errorMessage { Text(error).font(.subheadline).foregroundStyle(Theme.danger) }
            }.padding(16).padding(.bottom, 24)
        }
        .screenBackground().navigationTitle(profile.userID == session.user?.id ? "Мой профиль" : "Профиль друга").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AnimeSnapshot.self) { AnimeDetailsView(snapshot: $0) }
        .task { viewerID = session.user?.id; await reload() }
        .refreshable { await reload() }
        .onChange(of: session.user?.id) { _, id in if id != viewerID { data.clear(); dismiss() } }
        .confirmationDialog("Удалить из друзей?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await act(.remove) } }
            Button("Отмена", role: .cancel) {}
        }
    }
    private func reload() async {
        let viewer = session.user?.id
        await data.load(service: env.socialService, viewerID: viewer)
        guard session.user?.id == viewer else { return }
        await relationships.load(service: env.socialService, userID: viewer)
    }
    private func act(_ action: FriendAction) async {
        await relationships.act(targetID: profile.userID, action: action)
        await data.load(service: env.socialService, viewerID: session.user?.id)
    }
    @ViewBuilder private var friendshipActions: some View {
        if relationships.isLoading { ProgressView("Проверяем приглашение…") }
        else if let edge = relationships.edge(with: profile.userID) {
            if edge.status == "accepted" {
                HStack {
                    Label("Вы друзья", systemImage: "checkmark.circle").foregroundStyle(Theme.success)
                    Spacer()
                    Button { confirmRemove = true } label: { Image(systemName: "person.badge.minus").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Удалить из друзей").disabled(relationships.isSaving)
                }.profilePanel()
            } else if edge.requesterID == session.user?.id {
                Button("Отменить приглашение") { Task { await act(.cancel) } }.buttonStyle(.bordered).controlSize(.large).disabled(relationships.isSaving)
            } else {
                HStack {
                    Button("Принять приглашение") { Task { await act(.accept) } }.buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(Theme.onAccent)
                    Button("Отклонить") { Task { await act(.decline) } }.buttonStyle(.bordered).controlSize(.large)
                }.disabled(relationships.isSaving)
            }
        } else {
            Button { Task { await act(.send) } } label: {
                Label("Добавить в друзья", systemImage: "person.badge.plus").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(Theme.onAccent)
                .disabled(relationships.isSaving || relationships.errorMessage != nil)
        }
    }
    private func counters(_ details: SocialProfileDetails) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: details.friendsAllowed ? "person.2" : "lock").foregroundStyle(Theme.accent)
                Text(details.friendsCount.map { $0.formatted() } ?? "Закрыто").font(.title2.bold())
                Text("Друзья").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading).profilePanel()
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: details.libraryAllowed ? "checkmark.circle" : "lock").foregroundStyle(Theme.secondaryAccent)
                Text(details.stats?["completed"].map { $0.formatted() } ?? "Закрыто").font(.title2.bold())
                Text("Просмотрено").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading).profilePanel()
        }
    }
    private func friendPreview(_ details: SocialProfileDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Друзья").font(.title3.bold()); Spacer()
                if details.friendsAllowed {
                    NavigationLink { SocialFriendsList(data: data) } label: { Text("Все").frame(minHeight: 44) }
                }
            }
            if !details.friendsAllowed { SocialPrivacyNote(text: "Владелец закрыл список друзей.") }
            else if details.friends.isEmpty { Text("Нет доступных вам профилей друзей.").font(.subheadline).foregroundStyle(Theme.textSecondary) }
            else {
                ForEach(details.friends.prefix(3)) { peer in
                    NavigationLink { PublicProfileView(profile: peer) } label: { SocialPersonRow(profile: peer) }.buttonStyle(.plain)
                }
            }
        }.profilePanel()
    }
    private func historyPreview(_ details: SocialProfileDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Недавно смотрел").font(.title3.bold()); Spacer()
                if details.historyAllowed { NavigationLink { SocialActivityList(data: data, kind: .history) } label: { Text("Все").frame(minHeight: 44) } }
            }
            if !details.historyAllowed { SocialPrivacyNote(text: "История просмотра доступна только с разрешения владельца.") }
            else if data.history.isEmpty { Text("История пока пуста.").font(.subheadline).foregroundStyle(Theme.textSecondary) }
            else {
                ForEach(data.history.prefix(3)) { item in
                    NavigationLink { AnimeDetailsView(snapshot: item.anime) } label: { SocialAnimeRow(anime: item.anime, subtitle: "Серия \(item.episode) · " + item.watchedAt.formatted(date: .abbreviated, time: .omitted)) }.buttonStyle(.plain)
                }
            }
        }.profilePanel()
    }
    private func libraryPreview(_ details: SocialProfileDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Библиотека").font(.title3.bold()); Spacer()
                if details.libraryAllowed { NavigationLink { SocialActivityList(data: data, kind: .library) } label: { Text("Все").frame(minHeight: 44) } }
            }
            if !details.libraryAllowed { SocialPrivacyNote(text: "Списки и избранное закрыты владельцем.") }
            else {
                ForEach(LibraryStatus.allCases, id: \.self) { status in
                    HStack {
                        Label(status.localizedName, systemImage: status.systemImage).foregroundStyle(Theme.textSecondary)
                        Spacer(); Text((details.stats?[status.rawValue] ?? 0).formatted()).fontWeight(.semibold).monospacedDigit()
                    }.font(.subheadline).frame(minHeight: 32)
                }
                if data.entries.isEmpty { Text("В библиотеке пока нет тайтлов.").font(.subheadline).foregroundStyle(Theme.textSecondary) }
            }
        }.profilePanel()
    }
}

private struct SocialFriendsList: View {
    @Bindable var data: SocialProfileStore
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var viewerID: String?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Показаны только профили, доступные вам. Приватные профили других пользователей не раскрываются.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                if data.details?.friendsAllowed == true {
                    ForEach(data.details?.friends ?? []) { profile in
                        NavigationLink { PublicProfileView(profile: profile) } label: { SocialPersonRow(profile: profile).profilePanel() }.buttonStyle(.plain)
                    }
                    if data.details?.friends.isEmpty == true { SocialEmptyPanel(icon: "person.2", title: "Нет доступных профилей", message: "Список может быть пустым или содержать закрытые профили.") }
                } else { SocialPrivacyNote(text: "Владелец закрыл список друзей.").profilePanel() }
                if let error = data.errorMessage { SocialErrorPanel(message: error) { Task { await reload() } } }
            }.padding(16)
        }
        .screenBackground().navigationTitle("Друзья пользователя")
        .onAppear { viewerID = session.user?.id }
        .onChange(of: session.user?.id) { _, id in if id != viewerID { data.clear(); dismiss() } }
        .refreshable { await reload() }
    }
    private func reload() async { await data.load(service: env.socialService, viewerID: session.user?.id) }
}

private struct SocialActivityList: View {
    enum Kind: Equatable { case history, library }
    @Bindable var data: SocialProfileStore
    let kind: Kind
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var viewerID: String?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if kind == .history {
                    if data.details?.historyAllowed != true { SocialPrivacyNote(text: "История закрыта владельцем.").profilePanel() }
                    else if data.history.isEmpty { SocialEmptyPanel(icon: "clock", title: "История пока пуста", message: "Новые просмотры появятся после синхронизации владельца.") }
                    else {
                        ForEach(data.history) { item in
                            NavigationLink { AnimeDetailsView(snapshot: item.anime) } label: { SocialAnimeRow(anime: item.anime, subtitle: "Серия \(item.episode) · " + item.watchedAt.formatted(date: .abbreviated, time: .shortened)).profilePanel() }.buttonStyle(.plain)
                        }
                    }
                    if data.historyHasMore { Button("Загрузить ещё") { Task { await data.moreHistory(service: env.socialService) } }.frame(minHeight: 44).disabled(data.isPaging || data.isLoading) }
                } else {
                    if data.details?.libraryAllowed != true { SocialPrivacyNote(text: "Библиотека закрыта владельцем.").profilePanel() }
                    else if data.entries.isEmpty { SocialEmptyPanel(icon: "books.vertical", title: "Библиотека пока пуста", message: "Здесь будут списки и избранное пользователя.") }
                    else {
                        ForEach(data.entries) { entry in
                            NavigationLink { AnimeDetailsView(snapshot: entry.anime) } label: { SocialAnimeRow(anime: entry.anime, subtitle: (entry.status?.localizedName ?? "Без списка") + (entry.isFavorite ? " · Избранное" : "")).profilePanel() }.buttonStyle(.plain)
                        }
                    }
                    if data.libraryHasMore { Button("Загрузить ещё") { Task { await data.moreLibrary(service: env.socialService) } }.frame(minHeight: 44).disabled(data.isPaging || data.isLoading) }
                }
                if data.isPaging || data.isLoading { ProgressView() }
                if let error = data.errorMessage { SocialErrorPanel(message: error) { Task { await reload() } } }
                Text("Общие данные · только просмотр").font(.footnote).foregroundStyle(Theme.textSecondary)
            }.padding(16)
        }
        .screenBackground().navigationTitle(kind == .history ? "История просмотра" : "Библиотека пользователя")
        .navigationDestination(for: AnimeSnapshot.self) { AnimeDetailsView(snapshot: $0) }
        .onAppear { viewerID = session.user?.id }
        .onChange(of: session.user?.id) { _, id in if id != viewerID { data.clear(); dismiss() } }
        .refreshable { await reload() }
    }
    private func reload() async { await data.load(service: env.socialService, viewerID: session.user?.id) }
}

private struct SocialPersonRow: View {
    let profile: UserProfile
    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatarView(userID: profile.userID, revision: profile.avatarPath ?? profile.updatedAt, size: 52, avatarAvailable: profile.avatarPath != nil)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName).font(.headline).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Text(profile.username.map { "@" + $0 } ?? "Без username").font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textSecondary)
        }.frame(minHeight: 52).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}
private struct SocialAnimeRow: View {
    let anime: AnimeSnapshot
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            PosterImage(url: anime.coverURL, cornerRadius: 8).frame(width: 48, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(anime.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Theme.textSecondary)
        }.contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}
private struct SocialPrivacyNote: View {
    let text: String
    var body: some View { Label(text, systemImage: "lock").font(.subheadline).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
}
private struct SocialEmptyPanel: View {
    let icon: String; let title: String; let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.accent)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).profilePanel()
    }
}
private struct SocialErrorPanel: View {
    let message: String; let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Theme.danger)
            Button("Повторить", action: retry).frame(minHeight: 44)
        }.frame(maxWidth: .infinity, alignment: .leading).profilePanel()
    }
}
