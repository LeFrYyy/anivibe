import SwiftUI
import AnivibeCore

struct ProfileEditorView: View {
    @Bindable var store: SocialStore
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var username: String
    @State private var displayName: String
    @State private var bio: String
    @State private var visibility: ProfileVisibility
    init(store: SocialStore, profile: UserProfile) {
        self.store = store; self.profile = profile
        _username = State(initialValue: profile.username ?? "")
        _displayName = State(initialValue: profile.displayName)
        _bio = State(initialValue: profile.bio)
        _visibility = State(initialValue: profile.visibility)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Публичные данные") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("3–24 символа: латиница, цифры и _. Username уникален.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    TextField("Отображаемое имя", text: $displayName)
                    TextField("О себе", text: $bio, axis: .vertical).lineLimit(3...6)
                    Text("Описание: до 500 символов").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                Section("Приватность") {
                    Picker("Профиль", selection: $visibility) {
                        ForEach(ProfileVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Публичный профиль доступен авторизованным пользователям и поиску по username. Приватный виден вам, вашим друзьям и адресатам ваших запросов в друзья. Почта, библиотека и история не публикуются.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(Theme.danger) }
                Section {
                    Button {
                        let draft = ProfileDraft(username: username, displayName: displayName, bio: bio, visibility: visibility)
                        Task { if await store.save(draft) { dismiss() } }
                    } label: {
                        HStack { Text("Сохранить"); Spacer(); if store.isSaving { ProgressView() } }
                    }.disabled(store.isSaving || store.isLoading)
                }
            }
            .navigationTitle("Редактировать профиль")
            .onChange(of: session.user?.id) { _, id in if id != profile.userID { dismiss() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() }.disabled(store.isSaving) } }
        }
    }
}

struct PublicProfileView: View {
    let profile: UserProfile
    var body: some View {
        Form {
            Section {
                Label(profile.displayName, systemImage: "person.crop.circle")
                if let username = profile.username { Text("@" + username).foregroundStyle(Theme.textSecondary) }
                if !profile.bio.isEmpty { Text(verbatim: profile.bio) }
            }
        }.navigationTitle("Профиль")
    }
}
