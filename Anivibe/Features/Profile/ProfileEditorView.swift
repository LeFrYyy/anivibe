import SwiftUI
import PhotosUI
import ImageIO
import UIKit
import AnivibeCore

struct ProfileEditorView: View {
    @Bindable var store: SocialStore
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session
    @State private var photo: PhotosPickerItem?
    @State private var photoError: String?
    @State private var preparingPhoto = false
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
                Section("Аватар") {
                    ProfileAvatarView(userID: profile.userID, revision: store.profile?.updatedAt ?? profile.updatedAt, size: 80)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Выбрать из галереи", systemImage: "photo") }
                        .disabled(store.isSaving || preparingPhoto)
                    if store.profile?.avatarPath != nil {
                        Button("Удалить аватар", role: .destructive) { Task { await store.setAvatar(nil) } }.disabled(store.isSaving || preparingPhoto)
                    }
                    if preparingPhoto || store.isSaving { ProgressView() }
                    if let photoError { Text(photoError).foregroundStyle(Theme.danger) }
                    Text("Фото сохраняется сразу, отдельно от остальных полей. JPEG до 512 px; сервер повторно проверяет и перекодирует файл.").font(.footnote)
                }
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
                    }.disabled(store.isSaving || store.isLoading || preparingPhoto)
                }
            }
            .navigationTitle("Редактировать профиль")
            .task(id: photo) {
                guard let photo else { return }
                preparingPhoto = true; photoError = nil
                defer { preparingPhoto = false }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 25 * 1024 * 1024,
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 512,
                            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
                          let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else {
                        photoError = "Фото не удалось прочитать (до 25 МБ)."; return
                    }
                    try Task.checkCancellation()
                    guard session.user?.id == profile.userID else { return }
                    await store.setAvatar(jpeg)
                } catch { if !Task.isCancelled { photoError = "Не удалось загрузить выбранное фото." } }
            }
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
                HStack { ProfileAvatarView(userID: profile.userID, revision: profile.updatedAt, size: 64); Text(profile.displayName) }
                if let username = profile.username { Text("@" + username).foregroundStyle(Theme.textSecondary) }
                if !profile.bio.isEmpty { Text(verbatim: profile.bio) }
            }
        }.navigationTitle("Профиль")
    }
}
