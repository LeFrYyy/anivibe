import SwiftUI
import AnivibeCore

/// Reference-inspired profile. All counters come from real local/account data.
struct ProfileView: View {
    let openCollections: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @State private var social = SocialStore()
    @State private var editProfile = false
    @State private var confirmSignOut = false
    @State private var confirmImportFolders = false

    private var currentProfile: UserProfile? {
        guard let profile = social.profile, profile.userID == session.user?.id else { return nil }
        return profile
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xl) {
                    identity
                    if session.user != nil { socialState }
                    quickStats
                    libraryStats
                    if !session.isBackendConfigured { localMode }
                    else if session.user == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Ваш Anivibe — на всех устройствах").font(.headline)
                            Text("Войдите, чтобы синхронизировать библиотеку и прогресс.")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            AuthFormView()
                        }.profilePanel()
                    } else { accountDetails }
                    NavigationLink { AboutView() } label: {
                        HStack {
                            Label("О приложении", systemImage: "info.circle")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        }.foregroundStyle(Theme.textSecondary).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .screenBackground()
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let user = session.user {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { FriendsView(store: social, userID: user.id) } label: {
                            Image(systemName: "person.crop.circle.badge.magnifyingglass")
                        }.accessibilityLabel("Поиск пользователей и друзья")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Настройки")
                }
            }
            .navigationDestination(for: Anime.self) { AnimeDetailsView(anime: $0) }
            .navigationDestination(for: AnimeSnapshot.self) { AnimeDetailsView(snapshot: $0) }
            .task(id: session.user?.id) { await reloadProfile() }
            .refreshable { await reloadProfile() }
            .sheet(isPresented: $editProfile) {
                if let profile = currentProfile { ProfileEditorView(store: social, profile: profile) }
            }
            .onChange(of: session.user?.id) { _, _ in editProfile = false }
            .confirmationDialog("Скопировать локальные папки?", isPresented: $confirmImportFolders, titleVisibility: .visible) {
                Button("Скопировать") { env.collections.importGuestFolders() }
                Button("Отмена", role: .cancel) {}
            } message: { Text("Папки будут добавлены к аккаунту и синхронизированы. Повторное копирование создаст дубликаты.") }
            .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { Task { await session.signOut() } }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private func reloadProfile() async {
        await social.load(service: env.socialService, userID: session.user?.id)
    }

    private var identity: some View {
        VStack(spacing: 20) {
            ProfileIdentityView(profile: currentProfile,
                fallbackName: session.user == nil ? "Мой Anivibe" : "Мой профиль",
                fallbackSubtitle: session.user == nil ? "Ваша личная история аниме" : "Настройте профиль под себя")
            if currentProfile != nil {
                Button { editProfile = true } label: {
                    Label("Редактировать профиль", systemImage: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered).tint(Theme.accent)
                .clipShape(Capsule())
            }
        }.padding(.vertical, 8)
    }

    @ViewBuilder private var socialState: some View {
        if social.isLoading { ProgressView("Обновляем профиль…").font(.subheadline) }
        if let error = social.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(Theme.danger)
                Button("Повторить") { Task { await reloadProfile() } }.frame(minHeight: 44)
            }.profilePanel()
        }
    }

    private var quickStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            NavigationLink { LibraryView(initialSection: .favorites, embedded: true) } label: {
                ProfileMetric(value: library.snapshot.favorites.count, title: "Избранное", icon: "heart", tint: Theme.accent)
            }.buttonStyle(.plain)
            NavigationLink { LibraryView(initialSection: .history, embedded: true) } label: {
                ProfileMetric(value: library.snapshot.history.count, title: "Серий в истории", icon: "play.rectangle", tint: Theme.secondaryAccent)
            }.buttonStyle(.plain)
            Button(action: openCollections) {
                ProfileMetric(value: env.collections.collections.count, title: "Коллекции", icon: "square.stack", tint: Theme.accent)
            }.buttonStyle(.plain)
            if let user = session.user {
                NavigationLink { FriendsView(store: social, userID: user.id) } label: {
                    ProfileMetric(value: social.friendships.filter { $0.status == "accepted" }.count,
                                  title: "Друзья", icon: "person.2", tint: Theme.secondaryAccent,
                                  isLoading: social.isLoading || social.errorMessage != nil)
                }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "person.2").foregroundStyle(Theme.textSecondary)
                    Text("После входа").font(.headline)
                    Text("Друзья").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading).profilePanel()
            }
        }
    }

    private var libraryStats: some View {
        // Single unsorted pass, rather than filtering and sorting for each counter.
        let counts = library.snapshot.entries.reduce(into: [LibraryStatus: Int]()) { counts, entry in
            if !entry.isDeleted, !entry.isEmpty, let status = entry.status { counts[status, default: 0] += 1 }
        }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Статистика").font(.title3.bold())
                Spacer()
                NavigationLink { LibraryView(embedded: true) } label: {
                    Text("Все списки").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
            }
            if counts.values.reduce(0, +) == 0 {
                Text("Ваша история начинается здесь. Добавьте первый тайтл в библиотеку.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            ForEach(LibraryStatus.allCases, id: \.self) { status in
                NavigationLink { LibraryView(initialSection: .list(status), embedded: true) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: status.systemImage).font(.title3)
                            .foregroundStyle(statusColor(status)).frame(width: 28)
                        Text(status.localizedName).foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        Text((counts[status] ?? 0).formatted()).font(.headline).monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if let error = library.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger)
            }
        }.profilePanel()
    }

    private func statusColor(_ status: LibraryStatus) -> Color {
        switch status {
        case .watching: return Theme.success
        case .completed: return Theme.secondaryAccent
        case .planned: return Theme.accent
        case .onHold: return Theme.textSecondary
        }
    }

    private var localMode: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("На этом устройстве", systemImage: "iphone").font(.headline)
            Text("Библиотека, история и прогресс сохраняются локально. Вход и синхронизация появятся после настройки Supabase.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
        }.profilePanel()
    }

    private var accountDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Синхронизация", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                Spacer()
                if session.isSyncing { ProgressView() }
            }
            if let date = session.lastSync {
                Text("Обновлено " + date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            if let message = session.lastSyncMessage {
                Text(message).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            if let error = env.collections.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(Theme.danger)
            }
            if let message = env.collections.importMessage {
                Text(message).font(.subheadline).foregroundStyle(Theme.success)
            }
            Button("Скопировать локальные папки в аккаунт") { confirmImportFolders = true }.frame(minHeight: 44)
            Text("Папки аккаунта синхронизируются вместе с библиотекой. Локальные папки можно перенести отдельно — оригинал останется на устройстве.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
            Button("Синхронизировать сейчас") { Task { await session.syncIfNeeded(reason: .manual) } }
                .frame(minHeight: 44).disabled(session.isSyncing)
            Divider()
            DisclosureGroup("Данные аккаунта · только вам") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(session.user?.email ?? "Почта не указана").textSelection(.enabled)
                    if let profile = currentProfile {
                        Text("ID: " + profile.userID).textSelection(.enabled)
                        Text("Регистрация: " + String(profile.createdAt.prefix(10)))
                    }
                    Button("Выйти из аккаунта", role: .destructive) { confirmSignOut = true }.frame(minHeight: 44)
                }.font(.subheadline).padding(.top, 12)
            }.font(.subheadline)
        }.profilePanel()
    }
}

struct ProfileIdentityView: View {
    let profile: UserProfile?
    var fallbackName = "Мой профиль"
    var fallbackSubtitle = "Ваша личная история аниме"
    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let profile {
                    ProfileAvatarView(userID: profile.userID, revision: profile.avatarPath ?? profile.updatedAt, size: 112, avatarAvailable: profile.avatarPath != nil)
                } else {
                    Image(systemName: "person.crop.circle.fill").resizable().scaledToFit()
                        .foregroundStyle(Theme.accent).frame(width: 112, height: 112)
                }
            }
            .padding(6)
            .background(Theme.accent.opacity(0.12), in: Circle())
            .overlay { Circle().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1) }
            Text(profile?.displayName ?? fallbackName)
                .font(.title.bold()).multilineTextAlignment(.center).textSelection(.enabled)
            if let username = profile?.username {
                Text("@" + username).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Text(profile.flatMap { $0.bio.isEmpty ? nil : $0.bio } ?? fallbackSubtitle)
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let profile {
                Label(profile.visibility.title,
                      systemImage: profile.visibility == .publicProfile ? "globe" : "lock")
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.surfaceElevated, in: Capsule())
            }
        }.frame(maxWidth: .infinity)
    }
}

private struct ProfileMetric: View {
    let value: Int
    let title: String
    let icon: String
    let tint: Color
    var isLoading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint).accessibilityHidden(true)
            Text(isLoading ? "—" : value.formatted()).font(.title2.bold()).monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).profilePanel()
            .accessibilityElement(children: .combine)
    }
}

struct AuthFormView: View {
    enum Mode: String, CaseIterable { case signIn = "Вход", signUp = "Регистрация", recover = "Восстановление" }

    @Environment(SessionStore.self) private var session
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationCode = ""
    @State private var resendAfter = Date.distantPast

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Picker("Режим", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            TextField("Электронная почта", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))

            if mode != .recover {
                SecureField(mode == .signUp ? "Пароль (от 8 символов)" : "Пароль", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .padding(10)
                    .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
            }

            if let pending = session.pendingConfirmationEmail {
                Text("Подтверждение: \(pending)").font(.footnote)
                TextField("Код из письма (6 цифр)", text: $confirmationCode)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                Button("Подтвердить код") { Task { await session.verifySignupCode(code: confirmationCode); confirmationCode = "" } }
                    .disabled(session.isBusy || confirmationCode.count != 6)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Button(context.date < resendAfter ? "Повторить через \(max(1, Int(resendAfter.timeIntervalSince(context.date)))) с" : "Отправить код повторно") {
                        resendAfter = Date().addingTimeInterval(60)
                        Task { await session.resendSignupCode() }
                    }.disabled(session.isBusy || context.date < resendAfter)
                }
            }
            Button("Войти через Google") { Task { await session.signInGoogle() } }.disabled(session.isBusy)

            if let error = session.errorMessage {
                Text(error).font(.footnote).foregroundStyle(Theme.danger)
            }
            if let info = session.infoMessage {
                Text(info).font(.footnote).foregroundStyle(Theme.success)
            }

            Button {
                Task {
                    switch mode {
                    case .signIn: await session.signIn(email: email, password: password)
                    case .signUp: await session.signUp(email: email, password: password)
                    case .recover: await session.recover(email: email)
                    }
                    password = ""
                }
            } label: {
                HStack {
                    Spacer()
                    if session.isBusy { ProgressView() } else { Text(buttonTitle).fontWeight(.semibold) }
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent).foregroundStyle(Theme.onAccent)
            .disabled(session.isBusy || email.isEmpty || (mode != .recover && password.isEmpty))
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    private var buttonTitle: String {
        switch mode {
        case .signIn: return "Войти"
        case .signUp: return "Создать аккаунт"
        case .recover: return "Отправить письмо"
        }
    }
}
