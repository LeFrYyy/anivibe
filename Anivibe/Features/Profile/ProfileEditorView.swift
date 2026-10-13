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
    @State private var friendsVisibility: SharingVisibility
    @State private var historyVisibility: SharingVisibility
    @State private var libraryVisibility: SharingVisibility
    init(store: SocialStore, profile: UserProfile) {
        self.store = store; self.profile = profile
        _username = State(initialValue: profile.username ?? "")
        _displayName = State(initialValue: profile.displayName)
        _bio = State(initialValue: profile.bio)
        _visibility = State(initialValue: profile.visibility)
        _friendsVisibility = State(initialValue: profile.friendsVisibility)
        _historyVisibility = State(initialValue: profile.historyVisibility)
        _libraryVisibility = State(initialValue: profile.libraryVisibility)
    }
    private var validationMessage: String? {
        do {
            _ = try ProfileDraft(username: username, displayName: displayName, bio: bio, visibility: visibility, friendsVisibility: friendsVisibility, historyVisibility: historyVisibility, libraryVisibility: libraryVisibility).validated()
            return nil
        } catch let error as SocialError { return error.userMessage }
        catch { return "Проверьте поля профиля." }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Аватар") {
                    VStack(spacing: 12) {
                        ProfileAvatarView(userID: profile.userID, revision: store.profile?.avatarPath ?? store.profile?.updatedAt ?? profile.updatedAt, size: 112, avatarAvailable: store.profile?.avatarPath != nil)
                        Text("Ваш образ в Anivibe").font(.headline)
                    }.frame(maxWidth: .infinity).padding(.vertical, 16)
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
                    Picker("Список друзей", selection: $friendsVisibility) {
                        ForEach(SharingVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("История просмотра", selection: $historyVisibility) {
                        ForEach(SharingVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Библиотека и избранное", selection: $libraryVisibility) {
                        ForEach(SharingVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Друзья, история и библиотека изначально закрыты. Разрешения работают только для пользователей, которым доступен ваш профиль. Почта, точная позиция плеера и папки остаются личными.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if let validationMessage { Text(validationMessage).font(.footnote).foregroundStyle(Theme.danger) }
                if let error = store.errorMessage { Text(error).foregroundStyle(Theme.danger) }
                Section {
                    Button {
                        let draft = ProfileDraft(username: username, displayName: displayName, bio: bio, visibility: visibility, friendsVisibility: friendsVisibility, historyVisibility: historyVisibility, libraryVisibility: libraryVisibility)
                        Task { if await store.save(draft) { dismiss() } }
                    } label: {
                        HStack { Text("Сохранить"); Spacer(); if store.isSaving { ProgressView() } }
                    }.disabled(store.isSaving || store.isLoading || preparingPhoto || validationMessage != nil)
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Редактировать профиль")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(store.isSaving || preparingPhoto)
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

