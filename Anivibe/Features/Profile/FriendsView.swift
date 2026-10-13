import SwiftUI
import AnivibeCore

struct FriendsView: View {
    @Bindable var store: SocialStore
    let userID: String
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var removeTarget: String?
    private var accepted: [Friendship] { store.friendships.filter { $0.status == "accepted" } }
    private var incoming: [Friendship] { store.friendships.filter { $0.status == "pending" && $0.requesterID != userID } }
    private var outgoing: [Friendship] { store.friendships.filter { $0.status == "pending" && $0.requesterID == userID } }
    var body: some View {
        List {
            Section("Поиск по username") {
                TextField("Минимум 3 символа", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { Task { await store.search(username) } }
                Button { Task { await store.search(username) } } label: {
                    HStack { Text("Найти"); Spacer(); if store.isSearching { ProgressView() } }
                }.disabled(store.isSearching || username.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                if let error = store.searchError { Text(error).foregroundStyle(Theme.danger) }
                ForEach(store.searchResults) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink { PublicProfileView(profile: profile) } label: {
                            VStack(alignment: .leading) { Text(profile.displayName); Text("@" + (profile.username ?? "")).font(.caption).foregroundStyle(Theme.textSecondary) }
                        }
                        if let edge = store.edge(with: profile.userID) {
                            Text(edge.status == "accepted" ? "Уже в друзьях" : "Запрос уже отправлен").font(.caption)
                        } else {
                            Button("Добавить в друзья") { Task { await store.act(targetID: profile.userID, action: .send) } }.disabled(store.isSaving)
                        }
                    }
                }
                if !store.isSearching, store.searchResults.isEmpty, store.searchError == nil {
                    Text("В поиске видны публичные профили и ваши друзья.").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            Section("Друзья · \(accepted.count)/10") {
                if accepted.isEmpty { Text("Пока нет друзей").foregroundStyle(Theme.textSecondary) }
                ForEach(accepted) { edge in
                    peerRow(edge)
                        .swipeActions { Button("Удалить", role: .destructive) { removeTarget = edge.peerID(for: userID) }.disabled(store.isSaving) }
                }
            }
            Section("Входящие запросы") {
                if incoming.isEmpty { Text("Новых запросов нет").foregroundStyle(Theme.textSecondary) }
                ForEach(incoming) { edge in
                    VStack(alignment: .leading, spacing: 8) {
                        peerRow(edge)
                        HStack {
                            Button("Принять") { Task { await store.act(targetID: edge.peerID(for: userID), action: .accept) } }
                            Spacer()
                            Button("Отклонить", role: .destructive) { Task { await store.act(targetID: edge.peerID(for: userID), action: .decline) } }
                        }.disabled(store.isSaving)
                    }
                }
            }
            Section("Исходящие запросы") {
                if outgoing.isEmpty { Text("Нет отправленных запросов").foregroundStyle(Theme.textSecondary) }
                ForEach(outgoing) { edge in
                    VStack(alignment: .leading, spacing: 8) {
                        peerRow(edge)
                        Button("Отменить запрос") { Task { await store.act(targetID: edge.peerID(for: userID), action: .cancel) } }.disabled(store.isSaving)
                    }
                }
            }
            if store.isLoading || store.isSaving { ProgressView("Обновляем…") }
            if let error = store.errorMessage { Text(error).foregroundStyle(Theme.danger) }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Друзья")
        .onChange(of: session.user?.id) { _, id in if id != userID { dismiss() } }
        .toolbar { Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }.disabled(store.isLoading || store.isSaving) }
        .refreshable { await reload() }
        .confirmationDialog("Удалить из друзей?", isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let id = removeTarget { Task { await store.act(targetID: id, action: .remove) } }; removeTarget = nil }
        }
    }
    @Environment(AppEnvironment.self) private var env
    private func reload() async { await store.load(service: env.socialService, userID: userID) }
    @ViewBuilder private func peerRow(_ edge: Friendship) -> some View {
        let id = edge.peerID(for: userID)
        if let profile = store.peers[id] {
            NavigationLink { PublicProfileView(profile: profile) } label: {
                VStack(alignment: .leading) {
                    Text(profile.displayName)
                    if let username = profile.username { Text("@" + username).font(.caption).foregroundStyle(Theme.textSecondary) }
                }
            }
        } else { Text("Приватный профиль · " + String(id.prefix(8))) }
    }
}
